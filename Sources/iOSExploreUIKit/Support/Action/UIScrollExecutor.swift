#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.scroll` 的执行核心。
///
/// 在 `MainActor` 上完成：定位目标 view → 向上找最近 `UIScrollView`（排除 `UITextView`）
/// → 陈旧校验 → 算 delta → `setContentOffset(animated:)` → 用 `adjustedContentInset` 判断
/// 是否到达边界并回传完整 inset。所有失败出口都通过 `UIKitCommandError` 工厂构造。
///
/// `execute` 为**同步**方法（codex 复审：去掉 async / Task.yield，避免 adapter 用
/// `MainActor.run` 包 async body）。`setContentOffset(animated: false)` 同步更新
/// `contentOffset`，立即读 after 即为目标值，语义确定；`animated: true` 仅调试用，
/// 此时 after 为「动画启动时的插值快照」而非最终值。
@MainActor
enum UIScrollExecutor {
    /// 在已定位上下文上执行滚动，返回 container/offset/extent/inset 摘要。
    ///
    /// - Parameters:
    ///   - input: 已通过 typed schema 校验的 scroll 输入。
    ///   - context: 当前 MainActor 查询上下文（window / rootView / topViewController）。
    /// - Returns: 滚动结果 JSON（container 类型名、offsetBefore/offsetAfter、reachedExtent、
    ///   adjustedContentInset 全 4 字段）。
    /// - Throws: 定位失败、陈旧、无 scrollView 祖先等 `UIKitCommandError`。
    static func execute(input: UIScrollInput, context: UIKitContextProvider.Context) throws -> JSON {
        let action = ScrollCommand.actionName
        let scrollView: UIScrollView

        if let locator = input.locator {
            // 有定位目标：解析 view → 陈旧校验 → 向上找最近 scrollView 祖先。
            let located = try UIKitLocatorResolver.locate(
                locator: locator.locator,
                in: context.rootView,
                notFound: { UIKitCommandError.invalidData(action: action, message: "scroll target not found") },
                ambiguous: { count in
                    UIKitCommandError.invalidData(action: action, message: "scroll target is ambiguous count=\(count)")
                }
            )
            if let snapshotID = input.snapshotID, case .path = locator {
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
                    snapshotID: snapshotID,
                    path: located.pathString,
                    context: snapshotContext,
                    current: current
                ) {
                    throw UIKitCommandError.staleLocator(action: action, snapshotID: snapshotID)
                }
            }
            guard let candidate = nearestScrollView(from: located.view) else {
                throw UIKitCommandError.scrollContainerUnavailable(action: action, target: locator.description)
            }
            scrollView = candidate
        } else {
            // 无定位目标：回退到 keyWindow 最前 scrollView。
            guard let candidate = foremostScrollView(in: context.window) else {
                throw UIKitCommandError.scrollContainerUnavailable(action: action, target: "keyWindow")
            }
            scrollView = candidate
        }

        // 用 adjustedContentInset（含 safe area）计算可见区与边界，而非裸 contentInset。
        let adjusted = scrollView.adjustedContentInset
        let visibleHeight = Double(scrollView.bounds.height) - adjusted.top - adjusted.bottom
        let visibleWidth = Double(scrollView.bounds.width) - adjusted.left - adjusted.right
        let defaultDistance: Double = input.direction.isVertical ? visibleHeight * 0.5 : visibleWidth * 0.5
        let distance: Double = input.amount ?? defaultDistance

        let before = scrollView.contentOffset
        let delta = self.delta(for: input.direction, amount: distance)
        scrollView.setContentOffset(CGPoint(x: before.x + delta.x, y: before.y + delta.y),
                                    animated: input.animated)
        let after = scrollView.contentOffset
        let extent = reachedExtent(scrollView: scrollView)

        UIKitCommandLogging.info("command", "ui scroll completed container=\(String(describing: type(of: scrollView))) beforeY=\(before.y) afterY=\(after.y) extent=\(extent?.rawValue ?? "nil")")

        return [
            "container": .string(String(describing: type(of: scrollView))),
            "offsetBefore": .object(JSON(["x": .double(Double(before.x)), "y": .double(Double(before.y))])),
            "offsetAfter": .object(JSON(["x": .double(Double(after.x)), "y": .double(Double(after.y))])),
            "reachedExtent": extent.map { .string($0.rawValue) } ?? .null,
            "adjustedContentInset": .object(JSON([
                "top": .double(adjusted.top),
                "bottom": .double(adjusted.bottom),
                "left": .double(adjusted.left),
                "right": .double(adjusted.right),
            ])),
        ]
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

    /// 把方向 + 距离转为 contentOffset 的 (dx, dy)。
    private static func delta(for direction: ScrollDirection, amount: Double) -> CGPoint {
        switch direction {
        case .up: return CGPoint(x: 0, y: -amount)
        case .down: return CGPoint(x: 0, y: amount)
        case .left: return CGPoint(x: -amount, y: 0)
        case .right: return CGPoint(x: amount, y: 0)
        }
    }

    /// 用 `adjustedContentInset` 判断 contentOffset 是否已到边界，1pt 容差。
    ///
    /// minY = -adjusted.top（顶部留出 safe area），maxY = max(minY, contentSize.h - bounds.h + adjusted.bottom)。
    /// x 轴同理。先判 top/left（小值边界），再判 bottom/right，保证短内容 scrollView 同时
    /// 满足 top 与 bottom 时优先返回 top。
    private static func reachedExtent(scrollView: UIScrollView) -> ScrollExtent? {
        let inset = scrollView.adjustedContentInset
        let minY = -inset.top
        if Double(scrollView.contentOffset.y) <= minY + 1 { return .top }
        let maxY = max(minY, Double(scrollView.contentSize.height - scrollView.bounds.height) + inset.bottom)
        if Double(scrollView.contentOffset.y) >= maxY - 1 { return .bottom }
        let minX = -inset.left
        if Double(scrollView.contentOffset.x) <= minX + 1 { return .left }
        let maxX = max(minX, Double(scrollView.contentSize.width - scrollView.bounds.width) + inset.right)
        if Double(scrollView.contentOffset.x) >= maxX - 1 { return .right }
        return nil
    }
}
#endif
