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
/// `ui.topViewHierarchy` 提供含按钮路径的扩展摘要，路径通过 `_UIAlertControllerActionView`
/// 视图树公开 subviews DFS 解析（iOS 26 已实测可行）。
@MainActor
enum UIAlertInspector {
    /// 一个 alert 按钮的摘要（供 `ui.alert.respond dryRun=true` 使用）。
    struct Button: Sendable, Equatable {
        /// 在 alert.actions 中的下标。
        let index: Int
        /// 按钮标题（可能为 nil）。
        let title: String?
        /// 按钮角色。
        let role: AlertButtonRole
    }

    /// alert 输入框的摘要。
    ///
    /// 只暴露 placeholder 与 secure 标记——**绝不**回 `text` 原文，密码/验证码等敏感输入
    /// 不应进入响应或日志。供 agent 识别输入型 alert（登录/改密码等需先填输入框再点按钮）。
    struct TextFieldSummary: Sendable, Equatable {
        /// 输入框占位文本。
        let placeholder: String?
        /// 是否为安全（密码）输入。
        let isSecure: Bool
    }

    /// alert 整体摘要。
    struct Summary: Sendable, Equatable {
        /// alert 标题。
        let title: String?
        /// alert 消息。
        let message: String?
        /// 按钮列表。
        let buttons: [Button]
        /// 输入框列表（仅 `addTextField` 过的 alert 非空）。
        let textFields: [TextFieldSummary]
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
        /// 该按钮 `_UIAlertControllerActionView` 的定位路径；未解析到时为 nil。
        let path: String?
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
        let textFields: [TextFieldSummary]
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

    /// 列出 alert 的标题/消息/按钮/输入框（输入框只取 placeholder 与 secure 标记，不取原文）。
    static func summarize(_ alert: UIAlertController) -> Summary {
        let buttons = alert.actions.enumerated().map { index, action in
            Button(index: index, title: action.title, role: AlertButtonRole(style: action.style))
        }
        let textFields = (alert.textFields ?? []).map { textField in
            TextFieldSummary(placeholder: textField.placeholder, isSecure: textField.isSecureTextEntry)
        }
        return Summary(title: alert.title, message: alert.message, buttons: buttons, textFields: textFields)
    }

    /// 给 `ui.inspect` / `ui.topViewHierarchy` 调用的入口。
    ///
    /// 当 `topViewController` 不是 `UIAlertController` 时返回 `available=false`，
    /// `buttons` / `textFields` 为空数组。
    /// 路径解析仅在 DEBUG 构建生效；Release 下 `path` 字段全部 nil
    /// （私有 API 不进 Release，符合项目硬规则）。
    ///
    /// - Parameters:
    ///   - topViewController: 当前顶部控制器。
    ///   - rootView: 当前顶部控制器的根 view（用于按钮路径 DFS）。
    /// - Returns: `InspectAlertSummary`，非 alert 场景下 `available=false`。
    static func summarizeForInspect(topViewController: UIViewController?, rootView: UIView?) -> InspectAlertSummary {
        guard let alert = topViewController as? UIAlertController else {
            return InspectAlertSummary(available: false, title: nil, message: nil, buttons: [], textFields: [])
        }
        let base = summarize(alert)
        let resolved = resolveButtonPaths(alert: alert, rootView: rootView)
        let buttons = base.buttons.enumerated().map { (i, button) in
            InspectButtonSummary(
                index: button.index,
                title: button.title,
                role: button.role,
                path: i < resolved.count ? resolved[i].path : nil
            )
        }
        UIKitCommandLogging.info("command", "ui alert inspect available=true buttonCount=\(buttons.count)")
        return InspectAlertSummary(
            available: true,
            title: base.title,
            message: base.message,
            buttons: buttons,
            textFields: base.textFields
        )
    }

    /// 将 `InspectAlertSummary` 转为命令响应 JSON。
    ///
    /// 格式与 `ui.alert.respond dryRun=true` 的 `buttons` 区块对齐，额外追加 `path`
    /// 字段供 agent 直接用 `ui.inspect` 返回的 path 定位按钮。
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
                    "path": button.path.map(JSONValue.string) ?? .null,
                    "availableActions": .array([.string("ui.alert.respond")]),
                ]))
            }),
            "textFields": .array(summary.textFields.map { textField in
                .object(JSON([
                    "placeholder": textField.placeholder.map(JSONValue.string) ?? .null,
                    "isSecure": .bool(textField.isSecure),
                ]))
            }),
        ]
    }

    // MARK: - Private

    /// 解析 alert 按钮的路径（DEBUG-only），Release 下全返回 nil。
    @MainActor
    private static func resolveButtonPaths(alert: UIAlertController, rootView: UIView?) -> [UIAlertButtonPathResolver.ResolvedButton] {
        guard let rootView else {
            return alert.actions.enumerated().map { (i, action) in
                UIAlertButtonPathResolver.ResolvedButton(index: i, title: action.title, role: AlertButtonRole(style: action.style), path: nil)
            }
        }
        #if DEBUG
        return UIAlertButtonPathResolver.resolveButtons(in: alert, rootView: rootView)
        #else
        return alert.actions.enumerated().map { (i, action) in
            UIAlertButtonPathResolver.ResolvedButton(index: i, title: action.title, role: AlertButtonRole(style: action.style), path: nil)
        }
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
