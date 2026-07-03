#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.scroll` / `ui.scrollToElement` 共享的滚动容器解析。
///
/// 把「定位目标 → 最近 UIScrollView 祖先」与「无定位 → keyWindow 最前 scrollView」两种
/// 语义收敛到 `resolveFromTarget`，复用同一份 `UITextView` 排除规则。`Resolved` 持有真实
/// `UIScrollView`，**仅限 `@MainActor` 域内流转**，不跨隔离边界（故不 conform `Sendable`——
/// `UIScrollView` 非 Sendable，跨边界传递会破坏 Swift 6 并发安全）。
@MainActor
enum UIScrollResolver {
    /// 已解析的滚动容器及定位摘要。
    ///
    /// 仅在 MainActor 域内使用：`scrollView` 是 UIKit 引用类型，不可跨 actor 传递。
    struct Resolved {
        /// 命中的 scrollView。
        let scrollView: UIScrollView
        /// 触发解析的目标描述（用于错误日志，已脱敏）。
        let targetDescription: String
        /// 目标 path（若有，用于响应/日志关联）。
        let targetPath: String?
    }

    /// `ui.scroll` 语义：locator 是触发滚动的目标 view，executor 找其最近 scrollView 祖先。
    ///
    /// locator 缺省时回退到 keyWindow 最前 scrollView。`path + viewSnapshotID` 组合做陈旧校验
    /// （viewSnapshotID 由 `ui.viewTargets` 签发）。全程排除 `UITextView`（其内部滚动语义不同，
    /// 按 spec 不作为滚动容器）。
    ///
    /// - Parameters:
    ///   - locator: 触发滚动的目标定位（identifier/path），nil 表示回退 foremost。
    ///   - viewSnapshotID: path 定位携带的陈旧校验标识（来自 ui.viewTargets）。
    ///   - context: 当前 MainActor 查询上下文。
    ///   - action: 触发 action 名（错误工厂日志关联）。
    /// - Returns: 解析到的 scrollView 容器及摘要。
    /// - Throws: `UIKitCommandError`——目标未找到/歧义/陈旧/无 scrollView 祖先。
    static func resolveFromTarget(locator: UIKitViewLookupTarget?,
                                  viewSnapshotID: String?,
                                  context: UIKitContextProvider.Context,
                                  action: String) throws -> Resolved {
        if let locator = locator {
            let located = try UIKitLocatorResolver.locate(
                locator: locator.locator,
                in: context.rootView,
                notFound: { UIKitCommandError.targetNotFound(action: action,
                                                              message: "scroll target not found",
                                                              logMessage: "ui scroll target not found action=\(action)") },
                ambiguous: { count in
                    UIKitCommandError.invalidData(action: action, message: "scroll target is ambiguous count=\(count)")
                }
            )
            if let viewSnapshotID = viewSnapshotID, case .path = locator {
                let current = UIKitFingerprintCollector.fingerprint(
                    for: located.view,
                    path: located.pathString,
                    rootView: context.rootView,
                    digest: UIKitFingerprintCollector.digest(topViewController: context.topViewController)
                )
                let snapshotContext = UIKitFingerprintCollector.context(
                    window: context.window,
                    topViewController: context.topViewController
                )
                if UIKitSnapshotStore.shared.isStale(
                    viewSnapshotID: viewSnapshotID,
                    path: located.pathString,
                    context: snapshotContext,
                    current: current
                ) {
                    throw UIKitCommandError.staleLocator(action: action, viewSnapshotID: viewSnapshotID)
                }
            }
            guard let candidate = nearestScrollView(from: located.view) else {
                throw UIKitCommandError.scrollContainerUnavailable(action: action, target: locator.description)
            }
            return Resolved(scrollView: candidate,
                            targetDescription: locator.description,
                            targetPath: located.pathString)
        }
        guard let candidate = foremostScrollView(in: context.window) else {
            throw UIKitCommandError.scrollContainerUnavailable(action: action, target: "keyWindow")
        }
        return Resolved(scrollView: candidate, targetDescription: "keyWindow", targetPath: nil)
    }

    /// 从 view 向上查找最近的 `UIScrollView`，排除 `UITextView`。
    ///
    /// `UITextView` 是 `UIScrollView` 子类，但其内部长文滚动语义不同，按 spec 排除。
    private static func nearestScrollView(from view: UIView) -> UIScrollView? {
        var current: UIView? = view
        while let candidate = current {
            if let scrollView = candidate as? UIScrollView, !(candidate is UITextView) {
                return scrollView
            }
            current = candidate.superview
        }
        return nil
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

    /// `ui.scrollToElement` 语义：locator 是滚动容器自身。
    ///
    /// 与 `resolveFromTarget` 不同：locator 非 nil 时，解析出的 view **本身**必须是
    /// `UIScrollView`（排除 `UITextView`），而非其子孙。locator 缺省时回退到 foremost
    /// scrollView。这样 scrollToElement 只在明确限定的容器内查找目标。
    ///
    /// - Parameters:
    ///   - locator: 滚动容器定位（identifier/path），nil 表示 foremost scrollView。
    ///   - context: 当前 MainActor 查询上下文。
    ///   - action: 触发 action 名（错误工厂日志关联）。
    /// - Returns: 解析到的 scrollView 容器及摘要。
    /// - Throws: `UIKitCommandError`——容器未找到/歧义/非 scrollView。
    static func resolveContainer(locator: UIKitViewLookupTarget?,
                                 context: UIKitContextProvider.Context,
                                 action: String) throws -> Resolved {
        guard let locator = locator else {
            guard let candidate = foremostScrollView(in: context.window) else {
                throw UIKitCommandError.scrollContainerUnavailable(action: action, target: "keyWindow")
            }
            return Resolved(scrollView: candidate, targetDescription: "keyWindow", targetPath: nil)
        }
        let located = try UIKitLocatorResolver.locate(
            locator: locator.locator,
            in: context.rootView,
            notFound: { UIKitCommandError.targetNotFound(action: action,
                                                          message: "scroll container not found",
                                                          logMessage: "ui scroll container not found action=\(action)") },
            ambiguous: { count in
                UIKitCommandError.invalidData(action: action, message: "scroll container is ambiguous count=\(count)")
            }
        )
        guard let scrollView = located.view as? UIScrollView, !(located.view is UITextView) else {
            throw UIKitCommandError.scrollContainerUnavailable(action: action, target: locator.description)
        }
        return Resolved(scrollView: scrollView,
                        targetDescription: locator.description,
                        targetPath: located.pathString)
    }
}
#endif
