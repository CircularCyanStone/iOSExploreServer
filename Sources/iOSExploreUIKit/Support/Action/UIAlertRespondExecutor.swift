#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.alert.respond` 的执行核心。
///
/// 在 `MainActor` 上定位当前 `UIAlertController`。`dryRun=true` 只返回标题/消息/按钮/输入框
/// 列表；`dryRun=false` 会按调用方提供的按钮选择条件触发对应 action 的 handler，并请求关闭
/// alert。失败由 command adapter 顶层 catch 转 envelope。
@MainActor
enum UIAlertRespondExecutor {
    /// 执行一次 alert 查询/响应。
    ///
    /// - Parameters:
    ///   - input: 已通过 typed schema 校验的 alert respond 参数。
    ///   - context: 当前 MainActor 查询上下文。
    /// - Returns: dryRun=true 时返回 alert 摘要；dryRun=false 时返回已触发的按钮与关闭请求结果。
    /// - Throws: `UIKitCommandError.alertUnavailable`——无 alert；`.alertButtonRequired`——多按钮未指定；
    ///   `.alertButtonNotFound`——指定按钮不存在；`.alertButtonTriggerFailed`——按钮 handler 无法执行。
    static func execute(input: UIAlertRespondInput, context: UIKitContextProvider.Context) throws -> JSON {
        let action = AlertRespondCommand.actionName
        guard let alert = UIAlertInspector.findAlert(in: context) else {
            throw UIKitCommandError.alertUnavailable(action: action)
        }

        if !input.dryRun {
            #if DEBUG
            return try perform(input: input, alert: alert)
            #else
            throw UIKitCommandError.alertRespondDisabledInRelease(action: action)
            #endif
        }

        let summary = UIAlertInspector.summarize(alert)
        UIKitCommandLogging.info("command", "ui alert respond complete dryRun=true buttons=\(summary.buttons.count) textFields=\(summary.textFields.count)")
        return [
            "dryRun": .bool(true),
            "title": summary.title.map(JSONValue.string) ?? .null,
            "message": summary.message.map(JSONValue.string) ?? .null,
            "buttons": .array(summary.buttons.map { buttonJSON($0) }),
            "textFields": .array(summary.textFields.map { textFieldJSON($0) }),
        ]
    }

    #if DEBUG
    /// 执行一次 alert 按钮响应。
    ///
    /// executor 只负责业务流程：选择按钮、交给 Debug runtime 扩展触发、返回统一结果。真实展示中的
    /// alert 由 `UIAlertController` 扩展接管，让 UIKit 按自己的按钮点击流程关闭弹窗并执行 handler；
    /// 未 present 的 alert（典型是 logic test 构造的对象）没有展示层级可关闭，改由 `UIAlertAction`
    /// 扩展直接执行 handler，并明确返回 `dismissed=false`。runtime 细节集中在扩展文件内，命令层不
    /// 散写私有结构处理逻辑，后续 iOS 版本适配也只需要改扩展。
    private static func perform(input: UIAlertRespondInput, alert: UIAlertController) throws -> JSON {
        let actionName = AlertRespondCommand.actionName
        let selected = try selectAction(input: input, alert: alert)
        let isPresented = alert.presentingViewController != nil
        let dismissed: Bool
        do {
            if isPresented {
                try alert.explore_dismissWithAction(selected.action)
                dismissed = true
            } else {
                try selected.action.explore_performHandler()
                dismissed = false
            }
        } catch {
            throw UIKitCommandError.alertButtonTriggerFailed(action: actionName, reason: "\(error)")
        }
        // dismiss 是 UIKit 动画转场；为防止 alert.respond 返回后 agent 立即 observe 仍看到
        // UIAlertController 残留在 presentedViewController 链上，这里在主线程上 RunLoop
        // 轮询直到顶层 presented chain 真正清空（或最多 ~1500ms）再返回。
        //
        // maxAttempts=95 × 16ms ≈ 1520ms：嵌套 alert（第 1 层 dismiss → 第 2 层 present）
        // 在较复杂 view 层级下可能耗时 800-1200ms 完成转场。此前 T2-AlertDismiss 用 800ms
        // 仍偶现 stale read（见 docs/investigations/mcp-spim-example-e2e-issues.md P6），
        // 提至 ~1500ms 覆盖更多嵌套场景。
        let waitedMs: Int
        if isPresented {
            waitedMs = waitForPresentedViewControllerToClear(on: alert, maxAttempts: 95, intervalMs: 16)
        } else {
            waitedMs = 0
        }
        UIKitCommandLogging.info("command", "ui alert respond complete dryRun=false performed=true dismissed=\(dismissed) viaSystemDismiss=\(isPresented) selector=\(selectorDescription(input)) dismissWaitMs=\(waitedMs)")
        return [
            "performed": .bool(true),
            "dismissed": .bool(dismissed),
            "dismissWaitMs": .double(Double(waitedMs)),
            "presentedAfterDismiss": .bool(rootView?.presentedViewController != nil),
            "button": buttonJSON(selected.button),
        ]
    }

    /// dismiss 后在主线程 RunLoop 上轮询，等待 presented chain 清空。
    ///
    /// - Parameters:
    ///   - alert: 刚执行过 dismiss 的 alert controller。
    ///   - maxAttempts: 最多轮询次数。
    ///   - intervalMs: 每轮让出 runloop 的时长（毫秒）。
    /// - Returns: 实际等待毫秒数（向上取到整轮），供日志和返回。
    private static func waitForPresentedViewControllerToClear(on alert: UIAlertController,
                                                              maxAttempts: Int,
                                                              intervalMs: Int) -> Int {
        let rootView = alert.presentingViewController
        let intervalSec = CFTimeInterval(intervalMs) / 1000.0
        for attempt in 0..<maxAttempts {
            if rootView?.presentedViewController == nil {
                return attempt * intervalMs
            }
            // 用 `CFRunLoopRunInMode` 而非 `RunLoop.run(until:)`：后者每次只跑一次 pass，
            // 不让 UIKit 把 dismiss 转场真正交付到 runloop 上；前者在 default mode 持续
            // service 整个 interval，与真机主 RunLoop 行为一致，dismiss 才能真正落地。
            CFRunLoopRunInMode(.defaultMode, intervalSec, false)
        }
        return maxAttempts * intervalMs
    }

    /// 按请求选择一个 `UIAlertAction` 与对应摘要。
    ///
    /// 没传选择器时只有单按钮 alert 可以默认选择；多按钮 alert 必须显式指定，防止 agent 误点
    /// 取消/删除等破坏性动作。
    private static func selectAction(input: UIAlertRespondInput,
                                     alert: UIAlertController) throws -> (button: UIAlertInspector.Button, action: UIAlertAction) {
        let summary = UIAlertInspector.summarize(alert)
        let selectedIndex: Int?
        if let title = input.buttonTitle {
            selectedIndex = summary.buttons.first { $0.title == title }?.index
        } else if let index = input.buttonIndex {
            selectedIndex = summary.buttons.indices.contains(index) ? index : nil
        } else if let role = input.role {
            guard let parsedRole = AlertButtonRole(rawValue: role) else {
                throw UIKitCommandError.alertButtonNotFound(action: AlertRespondCommand.actionName,
                                                            selector: selectorDescription(input))
            }
            selectedIndex = summary.buttons.first { $0.role == parsedRole }?.index
        } else {
            guard summary.buttons.count == 1 else {
                throw UIKitCommandError.alertButtonRequired(action: AlertRespondCommand.actionName)
            }
            selectedIndex = summary.buttons.first?.index
        }

        guard let index = selectedIndex,
              summary.buttons.indices.contains(index),
              alert.actions.indices.contains(index) else {
            throw UIKitCommandError.alertButtonNotFound(action: AlertRespondCommand.actionName,
                                                        selector: selectorDescription(input))
        }
        return (summary.buttons[index], alert.actions[index])
    }

    /// 构造按钮选择条件摘要，只写入标题长度或短值，避免日志中混入过长输入。
    private static func selectorDescription(_ input: UIAlertRespondInput) -> String {
        if let title = input.buttonTitle {
            return "titleLen=\(title.count)"
        }
        if let index = input.buttonIndex {
            return "index=\(index)"
        }
        if let role = input.role {
            return "role=\(role)"
        }
        return "default"
    }
    #endif

    /// 构造单个按钮的 JSON 值。
    private static func buttonJSON(_ button: UIAlertInspector.Button) -> JSONValue {
        .object(JSON([
            "index": .double(Double(button.index)),
            "title": button.title.map(JSONValue.string) ?? .null,
            "role": .string(button.role.rawValue),
        ]))
    }

    /// 构造单个输入框的 JSON 值，只回 placeholder 与 secure 标记，不回原文（防泄露密码）。
    private static func textFieldJSON(_ textField: UIAlertInspector.TextFieldSummary) -> JSONValue {
        .object(JSON([
            "placeholder": textField.placeholder.map(JSONValue.string) ?? .null,
            "isSecure": .bool(textField.isSecure),
        ]))
    }
}
#endif
