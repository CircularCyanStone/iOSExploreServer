#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.scrollToElement` 的执行核心。
///
/// 在 `MainActor` 上：经 `UIScrollResolver.resolveContainer` 解析滚动容器 → 在容器内查找
/// 目标 view（文本/identifier）→ 用 `UIScrollView.scrollRectToVisible` 一次性滚到目标可见。
///
/// 刻意采用 `scrollRectToVisible` 而非「循环小步 scroll + 每轮采集可见候选」：前者是 UIKit
/// 原生方法，自动计算最短滚动让目标进入可见区；后者每轮用 `UIViewTargetsCollector.collect`
/// 会签发新 viewSnapshotID 污染 store（评审 M3），且需要手写可见性/bounds 判断。代价是失去 `scrolls`
/// 步数计数，但 agent 只关心「目标是否可见」，步数无业务意义。
///
/// 嵌套 scrollView（如外层 UITableView 内嵌 UICollectionView）：`scrollRectToVisible` 是否
/// 联动外层取决于 UIKit 的祖先链转发；若外层未联动而目标仍被裁切，agent 可显式传 `container`
/// 指向外层 scrollView 再调一次。
///
/// 不签发 viewSnapshotID：滚动后画面变化，旧 viewSnapshotID 失效，agent 应重新 `ui.inspect`。
@MainActor
enum UIScrollToElementExecutor {
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

        guard let target = findTarget(match: input.match, value: input.value, in: scrollView) else {
            throw UIKitCommandError.targetNotFound(
                action: action,
                message: "scroll target not found",
                logMessage: "ui scroll to element target not found action=\(action) match=\(input.match.rawValue)"
            )
        }

        // 容器禁用滚动或已脱离 window 时 scrollRectToVisible 是 no-op 却仍返回 found=true，
        // agent 会被误导以为已滚到目标。先校验，不可滚时显式失败。
        guard scrollView.isScrollEnabled, scrollView.window != nil else {
            throw UIKitCommandError.scrollContainerUnavailable(action: action,
                                                               target: "container disabled or detached")
        }
        // 把目标 bounds 转到 scrollView 坐标，让 UIKit 滚到它可见。
        let targetRect = target.convert(target.bounds, to: scrollView)
        scrollView.scrollRectToVisible(targetRect, animated: input.animated)

        let path = UIKitLocatorResolver.locatedView(for: target, in: context.rootView)?.pathString
        let targetType = String(describing: type(of: target))
        let container = String(describing: type(of: scrollView))
        UIKitCommandLogging.info("command", "ui scroll to element complete match=\(input.match.rawValue) found=true path=\(path ?? "nil") type=\(targetType) container=\(container)")

        return [
            "found": .bool(true),
            "match": .string(input.match.rawValue),
            "targetPath": path.map(JSONValue.string) ?? .null,
            "targetType": .string(targetType),
            "container": .string(container),
        ]
    }

    /// 在 root 子树内按匹配方式找第一个目标 view。
    ///
    /// `UITableView` 与 `UICollectionView` 的内容在 cell 内而非直接 subview，
    /// 因此额外搜索 `visibleCells`（这是唯一能在不触发 cell 注册/dataSource reload
    /// 情况下读到已有 cell 内容的路径）。非 scrollView 实体的 root 走标准 UIView
    /// 深度优先。
    ///
    /// - Parameters:
    ///   - match: 匹配方式（text / accessibilityIdentifier）。
    ///   - value: 匹配值。
    ///   - root: 搜索根（scrollView 或普通 view）。
    /// - Returns: 找到的第一个视图，nil 表示未找到。
    private static func findTarget(match: ScrollToElementMatch, value: String, in root: UIView) -> UIView? {
        // UITableView / UICollectionView：优先搜索 visibleCells 内容。
        if let tableView = root as? UITableView {
            for cell in tableView.visibleCells {
                if let found = findTargetDepthFirst(match: match, value: value, in: cell.contentView) {
                    return found
                }
                // 部分 cell 把 label 直接挂在 cell 一级而非 contentView（iOS <16 兼容）。
                if let found = findTargetDepthFirst(match: match, value: value, in: cell) {
                    return found
                }
            }
            return nil
        }
        if let collectionView = root as? UICollectionView {
            for cell in collectionView.visibleCells {
                if let found = findTargetDepthFirst(match: match, value: value, in: cell.contentView) {
                    return found
                }
            }
            return nil
        }
        return findTargetDepthFirst(match: match, value: value, in: root)
    }

    /// 纯 UIView 深度优先搜索（不含 visibleCells 逻辑）。
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
