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

    /// alert 整体摘要。
    struct Summary: Sendable, Equatable {
        /// alert 标题。
        let title: String?
        /// alert 消息。
        let message: String?
        /// 按钮列表。
        let buttons: [Button]
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

    /// 列出 alert 的标题/消息/按钮。
    static func summarize(_ alert: UIAlertController) -> Summary {
        let buttons = alert.actions.enumerated().map { index, action in
            Button(index: index, title: action.title, role: AlertButtonRole(style: action.style))
        }
        return Summary(title: alert.title, message: alert.message, buttons: buttons)
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
