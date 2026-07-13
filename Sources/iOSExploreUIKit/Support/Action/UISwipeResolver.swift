#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.swipe` 共享的 view 解析逻辑。
///
/// 把「定位目标 → 目标 view」与「无定位 → keyWindow 最前 scrollView」两种
/// 语义收敛到 `resolveTarget`。与 `UIScrollResolver` 不同：swipe 不需要找 scrollView 祖先，
/// 直接定位目标 view（因为 swipe 可能作用于普通 view 上的 gesture recognizer）。
@MainActor
enum UISwipeResolver {
    /// 已解析的滑动目标及定位摘要。
    struct Resolved {
        /// 命中的目标 view。
        let view: UIView
        /// 目标 path（用于响应/日志关联）。
        let path: String
    }

    /// 解析滑动目标。
    ///
    /// locator 缺省时回退到 keyWindow 最前 scrollView（与 ui.scroll 一致的行为，
    /// 因为最常用的 swipe 场景是 scrollView 的 swipe to delete）。`viewSnapshotID` 由调用方
    /// 可选传入，配合 locator（identifier / path 均可）走 `UIKitActionExecutor.validateViewSnapshot`
    /// 同一陈旧校验入口；缺省时跳过陈旧校验。
    ///
    /// - Parameters:
    ///   - locator: 滑动目标定位（identifier/path），nil 表示回退 foremost scrollView。
    ///   - viewSnapshotID: path 或 identifier 定位携带的陈旧校验标识（来自 ui.inspect）。
    ///   - context: 当前 MainActor 查询上下文。
    ///   - action: 触发 action 名（错误工厂日志关联）。
    /// - Returns: 解析到的目标 view 及路径。
    /// - Throws: `UIKitCommandError`——目标未找到/歧义/陈旧。
    static func resolveTarget(locator: UIKitViewLookupTarget?,
                              viewSnapshotID: String?,
                              context: UIKitContextProvider.Context,
                              action: String) throws -> Resolved {
        if let locator = locator {
            let located = try UIKitLocatorResolver.locate(
                locator: locator.locator,
                in: context.rootView,
                notFound: { UIKitCommandError.targetNotFound(action: action,
                                                              message: "swipe target not found",
                                                              logMessage: "ui swipe target not found action=\(action)") },
                ambiguous: { count in
                    UIKitCommandError.invalidData(action: action, message: "swipe target is ambiguous count=\(count)")
                }
            )
            if let viewSnapshotID = viewSnapshotID {
                try UIKitActionExecutor.validateViewSnapshot(
                    located: located,
                    viewSnapshotID: viewSnapshotID,
                    context: context,
                    action: action
                )
            }
            return Resolved(view: located.view, path: located.pathString)
        }
        // 回退到 keyWindow 最前 scrollView
        guard let scrollView = foremostScrollView(in: context.window) else {
            throw UIKitCommandError.scrollContainerUnavailable(action: action, target: "keyWindow")
        }
        let path = UIKitLocatorResolver.locatedView(for: scrollView, in: context.rootView)?.pathString ?? "unknown"
        return Resolved(view: scrollView, path: path)
    }

    /// 深度优先遍历 window 子树，返回第一个 `UIScrollView`（排除 `UITextView`）。
    private static func foremostScrollView(in window: UIWindow?) -> UIScrollView? {
        guard let window else { return nil }
        var found: UIScrollView?
        func walk(_ view: UIView) {
            if found != nil { return }
            if let scrollView = view as? UIScrollView, !(view is UITextView) {
                found = scrollView
                return
            }
            for child in view.subviews {
                walk(child)
                if found != nil { return }
            }
        }
        walk(window)
        return found
    }
}
#endif
