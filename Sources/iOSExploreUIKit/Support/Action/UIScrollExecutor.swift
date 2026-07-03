#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.scroll` 的执行核心。
///
/// 在 `MainActor` 上完成：经 `UIScrollResolver` 解析滚动容器 → `UIScrollGeometry` 计算
/// 距离并单步滚动 → 回传完整 offset/extent/inset 摘要。容器解析、几何计算已下沉到共享
/// 原语（供 `ui.scrollToElement` 复用），本类型只保留 scroll 特有的「amount 缺省 = 可见区
/// 一半」语义与日志/响应组装。所有失败出口通过 `UIKitCommandError` 工厂构造。
///
/// `execute` 为同步方法（`setContentOffset(animated: false)` 同步更新 contentOffset，
/// 立即读 after 即为目标值，语义确定；`animated: true` 仅调试用，此时 after 为动画启动
/// 时的插值快照）。
@MainActor
enum UIScrollExecutor {
    /// 在已定位上下文上执行滚动，返回 container/offset/extent/inset 摘要。
    ///
    /// - Parameters:
    ///   - input: 已通过 typed schema 校验的 scroll 输入。
    ///   - context: 当前 MainActor 查询上下文（window / rootView / topViewController）。
    /// - Returns: 滚动结果 JSON（container 类型名、offsetBefore/offsetAfter、reachedExtent、
    ///   adjustedContentInset 全字段）。
    /// - Throws: 定位失败、陈旧、无 scrollView 祖先等 `UIKitCommandError`。
    static func execute(input: UIScrollInput, context: UIKitContextProvider.Context) throws -> JSON {
        let action = ScrollCommand.actionName
        let resolved = try UIScrollResolver.resolveFromTarget(
            locator: input.locator,
            viewSnapshotID: input.viewSnapshotID,
            context: context,
            action: action
        )
        let scrollView = resolved.scrollView
        let distance = input.amount ?? UIScrollGeometry.defaultDistance(
            scrollView: scrollView, direction: input.direction
        )
        let result = UIScrollGeometry.step(
            scrollView: scrollView,
            direction: input.direction,
            amount: distance,
            animated: input.animated
        )
        let container = String(describing: type(of: scrollView))
        UIKitCommandLogging.info("command", "ui scroll completed container=\(container) beforeX=\(result.offsetBefore.x) beforeY=\(result.offsetBefore.y) afterX=\(result.offsetAfter.x) afterY=\(result.offsetAfter.y) extent=\(result.reachedExtent?.rawValue ?? "nil")")
        return result.toJSON(container: container)
    }
}
#endif
