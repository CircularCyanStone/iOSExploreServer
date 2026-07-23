#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// 当前页面 alert 检查器。
///
/// 在 `MainActor` 上定位当前 presented 的 `UIAlertController`，并列出其 actions 的
/// index/title/role。不依赖 `present` 转场完成——直接读 `UIAlertController.actions`，
/// 因此在 logic test 里用 `summarize(_:)` 传入构造好的 alert 即可稳定验证。
///
/// `summarizeForInspect(topViewController:rootView:)` 为 `ui.inspect` /
/// `ui.topViewHierarchy` 提供含按钮与输入框路径的扩展摘要：按钮路径通过 `_UIAlertControllerActionView`
/// 视图树 DFS + UILabel 文本匹配解析，输入框路径用对象身份（`===`）DFS 解析（输入框模型对象
/// 同时在 `alert.textFields` 数组与视图树中，是同一对象，故无需文本/类型名匹配，更抗版本漂移）。
/// 两类路径均在 iOS 26 已实测可行。
@MainActor
enum UIAlertInspector {
    /// 一个 alert 按钮的摘要（供 `ui.alert.respond` 的按钮选择与触发使用）。
    struct Button: Sendable, Equatable {
        /// 在 alert.actions 中的下标。
        let index: Int
        /// 按钮标题（可能为 nil）。
        let title: String?
        /// 按钮角色。
        let role: AlertButtonRole
    }

    /// alert 整体摘要（标题/消息/按钮），供 executor 选按钮与测试用。输入框摘要只在 inspect
    /// 扩展摘要（`InspectTextFieldSummary`）里暴露——`ui.alert.respond` 移除 dryRun 后不再
    /// 返回 alert 结构查询结果，查询统一走 `ui.inspect`。
    struct Summary: Sendable, Equatable {
        /// alert 标题。
        let title: String?
        /// alert 消息。
        let message: String?
        /// 按钮列表。
        let buttons: [Button]
    }

    // MARK: - ui.inspect 扩展摘要（供 ui.inspect / ui.topViewHierarchy 使用）

    /// `ui.inspect` / `ui.topViewHierarchy` 输出里给 agent 暴露的 alert 摘要。
    /// 与 `summarize(alert:)` 不同，此版本额外携带每个按钮的 inspect path
    /// （通过 `_UIAlertControllerActionView` 视图树解析），让 agent 在 inspect
    /// 结果里直接定位按钮，不必另行调用 `ui.alert.respond` 才能拿到按钮清单。
    struct InspectButtonSummary: Sendable, Equatable {
        /// 在 `alert.actions` 中的下标。
        let index: Int
        /// 按钮标题（可能为 nil）。
        let title: String?
        /// 按钮角色。
        let role: AlertButtonRole
    }

    /// `ui.inspect` / `ui.topViewHierarchy` 输出里给 agent 暴露的 alert 输入框摘要。
    ///
    /// 携带 `path` 与 `accessibilityIdentifier`，让 agent 在 inspect 结果里直接拿到输入框定位
    /// 并调 `ui.input`，不必在深层 targets 里翻找 `_UIAlertControllerTextField`（其 path 极深
    /// 且脆弱，如 `root/0/0/1/0/0/4/0/0/0/0/0/0/0/0`）。仍**绝不**回 `text` 原文——密码/验证码
    /// 等敏感输入不应进入响应或日志。
    struct InspectTextFieldSummary: Sendable, Equatable {
        /// 输入框占位文本。
        let placeholder: String?
        /// 是否为安全（密码）输入。
        let isSecure: Bool
        /// 该输入框的定位路径（通过对象身份 DFS 解析）；未解析到或 Release 构建时为 nil。
        let path: String?
        /// 输入框的 accessibilityIdentifier（业务在 `addTextField` 时设置），未设置时为 nil。
        let accessibilityIdentifier: String?
    }

    /// alert 检查结果（供 `ui.inspect` / `ui.topViewHierarchy` 输出使用）。
    struct InspectAlertSummary: Sendable, Equatable {
        /// 当前顶部控制器是否为 `UIAlertController`。
        let available: Bool
        /// alert 标题（无 alert 时为 nil）。
        let title: String?
        /// alert 消息（无 alert 时为 nil）。
        let message: String?
        /// 按钮列表（无 alert 时为空数组）。
        let buttons: [InspectButtonSummary]
        /// 输入框列表（无 alert 时为空数组）。
        let textFields: [InspectTextFieldSummary]
    }

    /// 从查询上下文找当前 presented 的 UIAlertController。
    ///
    /// `UIKitContextProvider` 已沿 presentedViewController 链取到最顶控制器，故 topViewController
    /// 本身是 alert 时直接命中；非 alert 返回 nil（调用方抛 `alertUnavailable`）。
    ///
    /// - Parameter context: 当前 MainActor 查询上下文。
    /// - Returns: 当前 UIAlertController；没有则 nil。
    static func findAlert(in context: UIKitContextProvider.Context) -> UIAlertController? {
        context.topViewController as? UIAlertController
    }

    /// 列出 alert 的标题/消息/按钮（供 executor 选按钮与测试用）。输入框信息不在此摘要——
    /// 查询 alert 结构（含输入框 path/identifier）走 `ui.inspect` 的 alert 区块。
    static func summarize(_ alert: UIAlertController) -> Summary {
        let buttons = alert.actions.enumerated().map { index, action in
            Button(index: index, title: action.title, role: AlertButtonRole(style: action.style))
        }
        return Summary(title: alert.title, message: alert.message, buttons: buttons)
    }

    /// 给 `ui.inspect` / `ui.topViewHierarchy` 调用的入口。
    ///
    /// 当 `topViewController` 不是 `UIAlertController` 时返回 `available=false`，
    /// `buttons` / `textFields` 为空数组。
    /// 输入框的路径解析仅在 DEBUG 构建生效；Release 下 `path` 字段全部 nil
    /// （私有 API 不进 Release，符合项目硬规则）。`accessibilityIdentifier` 是公开 API，
    /// 无论 Debug/Release 都从 `alert.textFields[i]` 直接读取。
    ///
    /// - Parameters:
    ///   - topViewController: 当前顶部控制器。
    ///   - rootView: 当前顶部控制器的根 view（用于按钮/输入框路径 DFS）。
    /// - Returns: `InspectAlertSummary`，非 alert 场景下 `available=false`。
    static func summarizeForInspect(topViewController: UIViewController?, rootView: UIView?) -> InspectAlertSummary {
        guard let alert = topViewController as? UIAlertController else {
            return InspectAlertSummary(available: false, title: nil, message: nil, buttons: [], textFields: [])
        }
        let base = summarize(alert)
        let buttons = base.buttons.map { button in
            InspectButtonSummary(
                index: button.index,
                title: button.title,
                role: button.role
            )
        }
        let resolvedTextFieldPaths = resolveTextFieldPaths(alert: alert, rootView: rootView)
        let alertTextFields = alert.textFields ?? []
        let textFields = alertTextFields.enumerated().map { (i, textField) in
            InspectTextFieldSummary(
                placeholder: textField.placeholder,
                isSecure: textField.isSecureTextEntry,
                path: i < resolvedTextFieldPaths.count ? resolvedTextFieldPaths[i] : nil,
                accessibilityIdentifier: textField.accessibilityIdentifier
            )
        }
        UIKitCommandLogger.info("command", "ui alert inspect available=true buttonCount=\(buttons.count) textFieldCount=\(textFields.count)")
        return InspectAlertSummary(
            available: true,
            title: base.title,
            message: base.message,
            buttons: buttons,
            textFields: textFields
        )
    }

    /// 将 `InspectAlertSummary` 转为命令响应 JSON。
    ///
    /// `buttons` 区块与 `ui.alert.respond` 对齐，追加 `availableActions:["ui.alert.respond"]`
    ///（button 用 `buttonIndex`/`title`/`role` 调 respond，不带 path——alert button 视图无 tap
    /// 激活路由，path 不可操作也无消费者）。`textFields` 区块追加 `path`、`accessibilityIdentifier`
    /// 与 `availableActions:["ui.input"]`，让 agent 直接从 alert 区块拿到输入框定位去调 `ui.input`。
    static func toJSONInspect(_ summary: InspectAlertSummary) -> JSON {
        [
            "available": .bool(summary.available),
            "title": summary.title.map(JSONValue.string) ?? .null,
            "message": summary.message.map(JSONValue.string) ?? .null,
            "buttons": .array(summary.buttons.map { button in
                .object(JSON([
                    "index": .double(Double(button.index)),
                    "title": button.title.map(JSONValue.string) ?? .null,
                    "role": .string(button.role.rawValue),
                    "availableActions": .array([.string("ui.alert.respond")]),
                ]))
            }),
            "textFields": .array(summary.textFields.map { textField in
                .object(JSON([
                    "placeholder": textField.placeholder.map(JSONValue.string) ?? .null,
                    "isSecure": .bool(textField.isSecure),
                    "path": textField.path.map(JSONValue.string) ?? .null,
                    "accessibilityIdentifier": textField.accessibilityIdentifier.map(JSONValue.string) ?? .null,
                    "availableActions": .array([.string("ui.input")]),
                ]))
            }),
        ]
    }

    // MARK: - Private

    /// 解析 alert 输入框的路径（DEBUG-only），返回与 `alert.textFields` 同序的 path 数组。
    ///
    /// 返回 `[String?]` 保证 Release-safe，DEBUG 分支才调用 `#if DEBUG` 保护的
    /// `UIAlertTextFieldPathResolver`。Release 下全返回 nil。
    @MainActor
    private static func resolveTextFieldPaths(alert: UIAlertController, rootView: UIView?) -> [String?] {
        let textFields = alert.textFields ?? []
        guard !textFields.isEmpty else { return [] }
        #if DEBUG
        guard let rootView else {
            return textFields.map { _ in nil }
        }
        return UIAlertTextFieldPathResolver.resolveTextFields(in: alert, rootView: rootView).map { $0.path }
        #else
        return textFields.map { _ in nil }
        #endif
    }
}

extension AlertButtonRole {
    /// 从 `UIAlertAction.Style` 构造角色。
    init(style: UIAlertAction.Style) {
        switch style {
        case .default: self = .default
        case .cancel: self = .cancel
        case .destructive: self = .destructive
        @unknown default: self = .default
        }
    }
}
#endif
