#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.longPress` 共享的 view 解析逻辑。
///
/// 把「定位目标 → 目标 view」与「无定位 → keyWindow 第一个可长按的 view」两种
/// 语义收敛到 `resolveTarget`。
@MainActor
enum UILongPressResolver {
    /// 已解析的长按目标及定位摘要。
    struct Resolved {
        /// 命中的目标 view。
        let view: UIView
        /// 目标 path（用于响应/日志关联）。
        let path: String
    }

    /// 解析长按目标。
    ///
    /// locator 缺省时回退到 keyWindow 第一个可长按的 view（通过检查是否有 `UILongPressGestureRecognizer`）。
    /// `viewSnapshotID` 由调用方可选传入，配合 locator（identifier / path 均可）走陈旧校验；缺省时跳过陈旧校验。
    ///
    /// - Parameters:
    ///   - locator: 长按目标定位（identifier/path），nil 表示回退第一个可长按的 view。
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
                                                              message: "longPress target not found",
                                                              logMessage: "ui longPress target not found action=\(action)") },
                ambiguous: { count in
                    UIKitCommandError.invalidData(action: action, message: "longPress target is ambiguous count=\(count)")
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
        // 回退到 keyWindow 第一个有 UILongPressGestureRecognizer 的 view
        guard let view = foremostLongPressView(in: context.window) else {
            throw UIKitCommandError.unsupportedTarget(
                action: action,
                targetDescription: "keyWindow",
                type: "UIWindow (no UILongPressGestureRecognizer found)",
                message: "no UILongPressGestureRecognizer found on target"
            )
        }
        let path = UIKitLocatorResolver.locatedView(for: view, in: context.rootView)?.pathString ?? "unknown"
        return Resolved(view: view, path: path)
    }

    /// 深度优先遍历 window 子树，返回第一个挂载了 `UILongPressGestureRecognizer` 的 view。
    private static func foremostLongPressView(in window: UIWindow?) -> UIView? {
        guard let window else { return nil }
        var found: UIView?
        func walk(_ view: UIView) {
            if found != nil { return }
            if hasLongPressGesture(view) {
                found = view
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

    /// 检查 view 是否挂载了 `UILongPressGestureRecognizer`。
    private static func hasLongPressGesture(_ view: UIView) -> Bool {
        guard let gestures = view.gestureRecognizers else { return false }
        for gesture in gestures {
            if gesture is UILongPressGestureRecognizer {
                return true
            }
        }
        return false
    }
}
#endif
