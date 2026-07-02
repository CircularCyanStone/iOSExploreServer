#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.alert.respond` 使用的弹窗检查器。
///
/// 在 `MainActor` 上定位当前 presented 的 `UIAlertController`，并列出其 actions 的
/// index/title/role。不依赖 `present` 转场完成——直接读 `UIAlertController.actions`，
/// 因此在 logic test 里用 `summarize(_:)` 传入构造好的 alert 即可稳定验证。
@MainActor
enum UIAlertInspector {
    /// 一个 alert 按钮的摘要。
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
