#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.scroll` 的滚动几何计算（原语抽取自 `UIScrollExecutor`）。
///
/// 把默认距离、方向 → delta、边界判定、单步滚动四个纯几何操作集中到一处。注意：
/// `ui.scrollToElement` 改用 UIKit 原生 `scrollRectToVisible` 后不再调用本类型；
/// step / delta / reachedExtent 当前仅 `ui.scroll` 使用。
/// 全部基于 `adjustedContentInset`（含 safe area），与迁移前的 `ui.scroll` 行为一致。
@MainActor
enum UIScrollGeometry {
    /// 默认滚动距离：可见区尺寸 × ratio（`ui.scroll` 默认 0.5）。
    static func defaultDistance(scrollView: UIScrollView,
                                direction: ScrollDirection,
                                ratio: Double = 0.5) -> Double {
        let adjusted = scrollView.adjustedContentInset
        let visibleHeight = Double(scrollView.bounds.height) - Double(adjusted.top) - Double(adjusted.bottom)
        let visibleWidth = Double(scrollView.bounds.width) - Double(adjusted.left) - Double(adjusted.right)
        return direction.isVertical ? visibleHeight * ratio : visibleWidth * ratio
    }

    /// 把方向 + 距离转为 contentOffset 的 (dx, dy)。
    static func delta(for direction: ScrollDirection, amount: Double) -> CGPoint {
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
    /// x 轴同理。
    ///
    /// **边界检测策略：** 只有当内容尺寸**大于** viewport 时，对应方向的边界才有意义。
    /// 如果内容宽度 ≤ viewport 宽度，不返回 left/right；如果内容高度 ≤ viewport 高度，不返回 top/bottom。
    /// 这避免了垂直滚动时因内容宽度不足而错误返回 `left` 的问题。
    static func reachedExtent(scrollView: UIScrollView) -> ScrollExtent? {
        let inset = scrollView.adjustedContentInset
        let offsetY = Double(scrollView.contentOffset.y)
        let offsetX = Double(scrollView.contentOffset.x)
        let contentHeight = Double(scrollView.contentSize.height)
        let contentWidth = Double(scrollView.contentSize.width)
        let viewportHeight = Double(scrollView.bounds.height)
        let viewportWidth = Double(scrollView.bounds.width)

        // 垂直边界检测（仅当内容高度 > viewport 高度时）
        if contentHeight > viewportHeight {
            let minY = -Double(inset.top)
            if offsetY <= minY + 1 { return .top }
            let maxY = max(minY, contentHeight - viewportHeight + Double(inset.bottom))
            if offsetY >= maxY - 1 { return .bottom }
        }

        // 横向边界检测（仅当内容宽度 > viewport 宽度时）
        if contentWidth > viewportWidth {
            let minX = -Double(inset.left)
            if offsetX <= minX + 1 { return .left }
            let maxX = max(minX, contentWidth - viewportWidth + Double(inset.right))
            if offsetX >= maxX - 1 { return .right }
        }

        return nil
    }

    /// 单步滚动：按方向 + 距离 `setContentOffset`，返回前后 offset 与边界结果。
    ///
    /// **Bug fix (2026-07-12):** 在读取 `offsetAfter` 之前先 `layoutIfNeeded()`，确保 UIKit
    /// 完成布局并将 contentOffset clamp 到有效范围。但某些情况下 UIKit 仍允许负数 offset
    /// （如快速滚动超出边界），所以手动将 offset clamp 到 [min, max] 范围再返回。
    static func step(scrollView: UIScrollView,
                     direction: ScrollDirection,
                     amount: Double,
                     animated: Bool) -> UIScrollStepResult {
        let before = scrollView.contentOffset
        let d = delta(for: direction, amount: amount)
        scrollView.setContentOffset(CGPoint(x: before.x + d.x, y: before.y + d.y), animated: animated)
        // 强制布局，确保 contentOffset 已被 clamp 到有效范围
        scrollView.layoutIfNeeded()

        // 读取并手动 clamp offset 到合法范围（基于 adjustedContentInset）
        let inset = scrollView.adjustedContentInset
        let rawOffset = scrollView.contentOffset
        let minY = -inset.top
        let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
        let minX = -inset.left
        let maxX = max(minX, scrollView.contentSize.width - scrollView.bounds.width + inset.right)

        let clampedOffset = CGPoint(
            x: max(minX, min(maxX, rawOffset.x)),
            y: max(minY, min(maxY, rawOffset.y))
        )

        return UIScrollStepResult(offsetBefore: before,
                                  offsetAfter: clampedOffset,
                                  reachedExtent: reachedExtent(scrollView: scrollView),
                                  adjustedContentInset: inset)
    }
}

/// 单步滚动结果（仅 `ui.scroll` 使用，`ui.scrollToElement` 已改用 `scrollRectToVisible`）。
///
/// 值类型快照：捕获一次 `setContentOffset` 前后的 offset、边界与 inset，便于 executor
/// 统一构造对外 JSON。`animated: false` 时 after 为目标值；`animated: true` 时 after 为
/// 动画启动时的插值快照（仅调试用）。
struct UIScrollStepResult {
    /// 滚动前 contentOffset。
    let offsetBefore: CGPoint
    /// 滚动后 contentOffset。
    let offsetAfter: CGPoint
    /// 滚动后到达的边界（未到边界为 nil）。
    let reachedExtent: ScrollExtent?
    /// 滚动容器的 adjustedContentInset 快照。
    let adjustedContentInset: UIEdgeInsets

    /// 构造对外 JSON 响应（container/offsetBefore/offsetAfter/reachedExtent/adjustedContentInset）。
    func toJSON(container: String) -> JSON {
        JSON([
            "container": .string(container),
            "offsetBefore": .object(JSON(["x": .double(Double(offsetBefore.x)), "y": .double(Double(offsetBefore.y))])),
            "offsetAfter": .object(JSON(["x": .double(Double(offsetAfter.x)), "y": .double(Double(offsetAfter.y))])),
            "reachedExtent": reachedExtent.map { .string($0.rawValue) } ?? .null,
            "adjustedContentInset": .object(JSON([
                "top": .double(Double(adjustedContentInset.top)),
                "bottom": .double(Double(adjustedContentInset.bottom)),
                "left": .double(Double(adjustedContentInset.left)),
                "right": .double(Double(adjustedContentInset.right)),
            ])),
        ])
    }
}
#endif
