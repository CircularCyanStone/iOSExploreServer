#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.scrollToElement` 的执行核心。
///
/// 在 `MainActor` 上：经 `UIScrollResolver.resolveContainer` 解析滚动容器 → 在容器内查找
/// 目标 view（文本/identifier）→ 用 `UIScrollView.scrollRectToVisible` 一次性滚到目标可见。
///
/// 目标不在 `visibleCells` 中时分两个阶段搜索：
/// 1. **寻址阶段（progressive find）** — 从当前位置逐页滚动（page down/up 交替），每次滚动后重扫
///    `visibleCells`，直到找到目标或遍历完整个 contentSize。找到目标后记下目标 **绝对坐标**。
/// 2. **对齐阶段（scroll-to-visible）** — 用 `scrollRectToVisible` 把第二阶段找到的目标坐标滚到可见。
///    两阶段分离：寻址阶段只确认坐标，对齐阶段做最终可见化。
///
/// 刻意不要求目标必须是 `UICollectionViewCell`/`UITableViewCell`（可以是 cell 内的 UILabel 等），
/// 边界情况：当目标本身不满足 userInteractionEnabled 时坐标仍然有效，scrollRectToVisible 不会失败。
///
/// 嵌套 scrollView（如外层 UITableView 内嵌 UICollectionView）：`scrollRectToVisible` 是否
/// 联动外层取决于 UIKit 的祖先链转发；若外层未联动而目标仍被裁切，agent 可显式传 `container`
/// 指向外层 scrollView 再调一次。
///
/// 不签发 viewSnapshotID：滚动后画面变化，旧 viewSnapshotID 失效，agent 应重新 `ui.inspect`。
@MainActor
enum UIScrollToElementExecutor {
    /// 最大寻址滚动次数，防止 contentSize 无限循环或估算偏差导致的死循环。
    private static let maxProgressiveScrolls = 50

    /// 执行一次滚动到目标。
    ///
    /// - Parameters:
    ///   - input: 已通过 typed schema 校验的 scroll-to-element 参数。
    ///   - context: 当前 MainActor 查询上下文。
    /// - Returns: found=true 及目标 path/type/container 摘要。
    /// - Throws: `UIKitCommandError`——容器不可用 / 目标未找到。
    static func execute(input: UIScrollToElementInput, context: UIKitContextProvider.Context) throws -> JSON {
        let action = ScrollToElementCommand.actionName
        let resolved = try UIScrollResolver.resolveContainer(locator: input.container,
                                                              context: context,
                                                              action: action)
        let scrollView = resolved.scrollView

        // 容器禁用滚动或已脱离 window 时 scrollRectToVisible 是 no-op
        guard scrollView.isScrollEnabled, scrollView.window != nil else {
            throw UIKitCommandError.scrollContainerNotScrollable(action: action,
                                                                 target: "container disabled or detached")
        }

        let target = try progressiveFindTarget(match: input.match, value: input.value, in: scrollView, action: action)

        // 目标已找到，用 scrollRectToVisible 精细对齐
        // （progressiveFindTarget 已经滚到目标可见，但可能只是部分可见，这里确保可见）
        let targetRect = target.convert(target.bounds, to: scrollView)
        scrollView.scrollRectToVisible(targetRect, animated: input.animated)

        let path = UIKitLocatorResolver.locatedView(for: target, in: context.rootView)?.pathString
        let targetType = String(describing: type(of: target))
        let container = String(describing: type(of: scrollView))
        UIKitCommandLogger.info("command", "ui scroll to element complete match=\(input.match.rawValue) found=true path=\(path ?? "nil") type=\(targetType) container=\(container)")

        return [
            "found": .bool(true),
            "match": .string(input.match.rawValue),
            "targetPath": path.map(JSONValue.string) ?? .null,
            "targetType": .string(targetType),
            "container": .string(container),
        ]
    }

    /// 渐进式搜索目标：先搜当前 `visibleCells`，搜不到则逐页滚动交替方向直到遍历完 content。
    ///
    /// 逐页策略：
    /// - 记录开始时 contentOffset 作为方向原点
    /// - 检测 UICollectionView 的 scrollDirection，决定垂直还是横向滚动
    /// - 先尝试从原点向下/右 page 滚动，每次滚动后检查
    /// - 滚到底/右且未找到时，回到原点尝试向上/左 page 滚动
    /// - 向上/左滚到顶/左仍未找到 → 目标不存在
    ///
    /// - Parameters:
    ///   - match: 匹配方式。
    ///   - value: 匹配值。
    ///   - scrollView: 滚动容器。
    ///   - action: 命令 action 名，用于错误构造。
    /// - Returns: 找到的目标 view。
    /// - Throws: `UIKitCommandError` 目标不存在。
    private static func progressiveFindTarget(
        match: ScrollToElementMatch,
        value: String,
        in scrollView: UIScrollView,
        action: String
    ) throws -> UIView {
        // 1. 先扫 visibleCells
        if let found = findTargetInVisibleCells(match: match, value: value, in: scrollView) {
            UIKitCommandLogger.info("command", "ui scroll to element found in visible cells")
            return found
        }

        UIKitCommandLogger.info("command", "ui scroll to element not in visible cells, starting progressive scroll")

        // 2. 检测滚动方向（UICollectionView 特有）
        let isHorizontal: Bool
        if let collectionView = scrollView as? UICollectionView,
           let flowLayout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            isHorizontal = (flowLayout.scrollDirection == .horizontal)
        } else {
            isHorizontal = false
        }

        // 3. 渐进滚动
        let startOffset = scrollView.contentOffset
        let contentSize = scrollView.contentSize
        let bounds = scrollView.bounds

        let viewportSize: CGFloat
        let maxOffset: CGFloat
        let offsetKeyPath: WritableKeyPath<CGPoint, CGFloat>

        if isHorizontal {
            viewportSize = bounds.width
            maxOffset = max(0, contentSize.width - viewportSize)
            offsetKeyPath = \.x
        } else {
            viewportSize = bounds.height
            maxOffset = max(0, contentSize.height - viewportSize)
            offsetKeyPath = \.y
        }

        /// 尝试在一个方向上逐页滚动搜索。
        /// - Parameters:
        ///   - forward: true=向下/右滚动, false=向上/左滚动
        ///   - startAt: 起始位置
        /// - Returns: 找到的目标；nil 表示该方向搜完仍未找到。
        func scrollInDirection(forward: Bool, startAt: CGPoint) -> UIView? {
            var current = startAt
            var step = 0

            while step < maxProgressiveScrolls {
                step += 1

                // 计算下一个分页位置
                let currentValue = current[keyPath: offsetKeyPath]
                let nextValue: CGFloat
                if forward {
                    nextValue = min(currentValue + viewportSize, maxOffset)
                } else {
                    nextValue = max(currentValue - viewportSize, 0)
                }

                // 到达边界未移动，退出这个方向
                if nextValue == currentValue {
                    UIKitCommandLogger.info("command", "ui scroll to element progressive reached \(forward ? (isHorizontal ? "right" : "bottom") : (isHorizontal ? "left" : "top")) step=\(step)")
                    return nil
                }

                current[keyPath: offsetKeyPath] = nextValue
                scrollView.setContentOffset(current, animated: false)
                // 强制布局让 visibleCells 更新
                scrollView.layoutIfNeeded()

                if let found = findTargetInVisibleCells(match: match, value: value, in: scrollView) {
                    UIKitCommandLogger.info("command", "ui scroll to element found via progressive scroll direction=\(forward ? (isHorizontal ? "right" : "down") : (isHorizontal ? "left" : "up")) step=\(step)")
                    return found
                }
            }

            UIKitCommandLogger.info("command", "ui scroll to element progressive exceeded maxStep=\(maxProgressiveScrolls) direction=\(forward ? (isHorizontal ? "right" : "down") : (isHorizontal ? "left" : "up"))")
            return nil
        }

        // 先向下/右搜
        if let found = scrollInDirection(forward: true, startAt: startOffset) {
            return found
        }

        // 向下/右搜不到，回到原点向上/左搜
        scrollView.setContentOffset(startOffset, animated: false)
        scrollView.layoutIfNeeded()

        if let found = scrollInDirection(forward: false, startAt: startOffset) {
            return found
        }

        // 双向都没找到，恢复到原位置
        scrollView.setContentOffset(startOffset, animated: false)
        scrollView.layoutIfNeeded()

        throw UIKitCommandError.targetNotFound(
            action: action,
            message: "scroll target not found",
            logMessage: "ui scroll to element target not found after progressive scroll action=\(action) match=\(match.rawValue)"
        )
    }

    /// 在滚动容器的 `visibleCells` 内搜索目标。
    ///
    /// 对 `UITableView` / `UICollectionView` 搜索 `visibleCells` 及其子 view；
    /// 对普通 `UIScrollView` 直接深度优先搜索 subviews。
    private static func findTargetInVisibleCells(match: ScrollToElementMatch, value: String, in root: UIView) -> UIView? {
        if let tableView = root as? UITableView {
            for cell in tableView.visibleCells {
                if let found = findTargetDepthFirst(match: match, value: value, in: cell) {
                    return found
                }
            }
            return nil
        }
        if let collectionView = root as? UICollectionView {
            for cell in collectionView.visibleCells {
                if let found = findTargetDepthFirst(match: match, value: value, in: cell) {
                    return found
                }
            }
            return nil
        }
        return findTargetDepthFirst(match: match, value: value, in: root)
    }

    /// 纯 UIView 深度优先搜索。
    private static func findTargetDepthFirst(match: ScrollToElementMatch, value: String, in root: UIView) -> UIView? {
        var found: UIView?
        func walk(_ view: UIView) {
            if found != nil { return }
            switch match {
            case .text:
                if let label = view as? UILabel, let text = label.text, text.contains(value) {
                    found = view
                    return
                }
            case .accessibilityIdentifier:
                if view.accessibilityIdentifier == value {
                    found = view
                    return
                }
            }
            for child in view.subviews {
                walk(child)
                if found != nil { return }
            }
        }
        walk(root)
        return found
    }
}
#endif
