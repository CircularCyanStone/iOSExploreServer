#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.alert.respond` 的执行核心。
///
/// 在 `MainActor` 上定位当前 `UIAlertController`，按调用方提供的按钮选择条件触发对应 action
/// 的 handler 并请求关闭 alert。查询 alert 结构（标题/按钮/输入框）请用 `ui.inspect`——其顶层
/// `alert` 区块信息更全（含 path / availableActions），本命令只负责「触发」。失败由 command
/// adapter 顶层 catch 转 envelope。
@MainActor
enum UIAlertRespondExecutor {
    /// 执行一次 alert 按钮响应。
    ///
    /// - Parameters:
    ///   - input: 已通过 typed schema 校验的 alert respond 参数。
    ///   - context: 当前 MainActor 查询上下文。
    /// - Returns: 已触发的按钮与关闭请求结果。dismissWaitMs 和 presentedAfterDismiss 仅为
    ///   启动时标记（dismissWaitMs=0），真正的耗时等待由 `UIAlertRespondCommand.handle` 中的
    ///   async 等待完成。
    /// - Throws: `UIKitCommandError.alertUnavailable`——无 alert；`.alertButtonRequired`——多按钮未指定；
    ///   `.alertButtonNotFound`——指定按钮不存在；`.alertButtonTriggerFailed`——按钮 handler 无法执行；
    ///   `.alertRespondDisabledInRelease`——Release 构建（私有 API 被 `#if DEBUG` 隔离）。
    static func execute(input: UIAlertRespondInput, context: UIKitContextProvider.Context) throws -> JSON {
        let action = AlertRespondCommand.actionName
        guard let alert = UIAlertInspector.findAlert(in: context) else {
            throw UIKitCommandError.alertUnavailable(action: action)
        }
        #if DEBUG
        return try perform(input: input, alert: alert)
        #else
        throw UIKitCommandError.alertRespondDisabledInRelease(action: action)
        #endif
    }

    #if DEBUG
    /// 执行一次 alert 按钮响应（同步部分：选择按钮、触发 dismiss）。
    ///
    /// dismissWaitMs 为启动时的标记（0），真正的转场等待由调用方的 async 路径补齐。
    /// 拆分原因为：Task.sleep 只能在 async 上下文中让出主线程给 UIKit 推进 dismiss 动画，
    /// 而 executor 本身被 `MainActor.run(unsafeSync:)` 约束为同步。调用方 handle 在拿到
    /// 这个返回值后做 async wait，用 write-through 更新 dismissWaitMs。
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
        // dismissWaitMs 和 presentedAfterDismiss 由调用方 async 等待后通过
        // UIAlertRespondCommand.handle 的回填逻辑更新。这里只标记启动值。
        UIKitCommandLogging.info("command", "ui alert respond part1 sync performed=true dismissed=\(dismissed) viaSystemDismiss=\(isPresented) selector=\(selectorDescription(input))")
        return [
            "performed": .bool(true),
            "dismissed": .bool(dismissed),
            "dismissWaitMs": .double(0),
            "presentedAfterDismiss": .bool(false),
            "button": buttonJSON(selected.button),
        ]
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
}
#endif
