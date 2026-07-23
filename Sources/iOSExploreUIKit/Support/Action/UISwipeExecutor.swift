#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.swipe` 的执行核心。
///
/// 在 `MainActor` 上完成：经 `UISwipeResolver` 解析目标 view → 尝试多种滑动策略
/// → 触发手势或模拟滑动 → 回传语义 JSON。
///
/// 滑动策略按优先级尝试：
/// 1. **UIScrollView swipe actions**：若是 UIScrollView 且 direction 是 left/right，
///    尝试触发 leading/trailing swipe actions。**当前 iOS 无公开 API 合成触摸序列来驱动此交互，
///    诚实返回 false**（不再假阳性），落到后续策略。详见 `trySwipeActions` 文档。
/// 2. **UISwipeGestureRecognizer**：查找 view 上挂载的方向匹配的 `UISwipeGestureRecognizer`，
///    通过 runtime 派发其 target-action（仅 Debug 可用）。
/// 3. **UIPanGestureRecognizer**：查找 view 上挂载的 `UIPanGestureRecognizer`（跳过 UIScrollView
///    系统内置 pan），按 `.began`→`.ended` 状态序列派发 target-action（仅 Debug 可用）。
///
/// 所有策略均未命中时抛 `unsupported_target`（带 swipe 专用 message）。
@MainActor
enum UISwipeExecutor {
    /// 默认滑动距离比例。
    static let defaultDistance: Double = 0.8

    /// 在已定位上下文上执行滑动，返回滑动结果摘要。
    ///
    /// - Parameters:
    ///   - input: 已通过 typed schema 校验的 swipe 输入。
    ///   - context: 当前 MainActor 查询上下文（window / rootView / topViewController）。
    /// - Returns: 滑动结果 JSON（path / route / direction / targetType 等）。
    /// - Throws: 定位失败、陈旧等 `UIKitCommandError`。
    static func execute(input: UISwipeInput, context: UIKitContextProvider.Context) throws -> JSON {
        let action = SwipeCommand.actionName
        let resolved = try UISwipeResolver.resolveTarget(
            locator: input.locator,
            viewSnapshotID: input.viewSnapshotID,
            context: context,
            action: action
        )

        let view = resolved.view
        let path = resolved.path
        let distance = input.distance ?? Self.defaultDistance

        // 尝试不同滑动策略
        // 策略 1: UIScrollView → 边缘滑动触发 swipe actions
        if let scrollView = view as? UIScrollView {
            if input.direction == .left || input.direction == .right {
                let triggered = try trySwipeActions(on: scrollView, direction: input.direction, distance: distance, path: path, input: input, context: context)
                if triggered {
                    // 真正触发了 swipe action（cellLocator 模式）
                    let cellPath = input.cellLocator.map { loc in
                        if case .accessibilityIdentifier(let id) = loc {
                            return "cell(\(id))"
                        } else if case .path(let indexes) = loc {
                            return UIKitViewLookupTarget.pathString(from: indexes)
                        }
                        return "cell"
                    } ?? "N/A"
                    UIKitCommandLogger.info("command", "ui swipe scrollView swipe actions triggered direction=\(input.direction.rawValue) scrollViewPath=\(path) cellPath=\(cellPath)")
                    return [
                        "path": .string(path),
                        "cellPath": .string(cellPath),
                        "route": .string("scrollView.swipeActions"),
                        "direction": .string(input.direction.rawValue),
                        "actionTitle": input.actionTitle.map { .string($0) } ?? .null,
                        "targetType": .string(String(describing: type(of: scrollView))),
                        "distance": .double(distance),
                        "triggered": .bool(true),
                    ]
                }
            }
        }

        // 策略 2: UISwipeGestureRecognizer
        #if DEBUG
        if let triggered = trySwipeGesture(on: view, direction: input.direction, path: path), triggered {
            UIKitCommandLogger.info("command", "ui swipe UISwipeGestureRecognizer triggered direction=\(input.direction.rawValue) path=\(path)")
            return [
                "path": .string(path),
                "route": .string("swipeGesture.targetAction"),
                "direction": .string(input.direction.rawValue),
                "targetType": .string(String(describing: Swift.type(of: view))),
                "triggered": .bool(true),
            ]
        }
        #endif

        // 策略 3: UIPanGestureRecognizer (Debug only)
        #if DEBUG
        if let triggered = tryPanGesture(on: view, direction: input.direction, distance: distance, path: path), triggered {
            UIKitCommandLogger.info("command", "ui swipe UIPanGestureRecognizer triggered direction=\(input.direction.rawValue) path=\(path)")
            return [
                "path": .string(path),
                "route": .string("panGesture.targetAction"),
                "direction": .string(input.direction.rawValue),
                "targetType": .string(String(describing: Swift.type(of: view))),
                "distance": .double(distance),
                "triggered": .bool(true),
            ]
        }
        #endif

        // 所有策略都未触发
        let targetType = String(describing: Swift.type(of: view))
        UIKitCommandLogger.info("command", "ui swipe no gesture found direction=\(input.direction.rawValue) path=\(path) type=\(targetType)")
        throw UIKitCommandError.unsupportedTarget(
            action: action,
            targetDescription: path,
            type: targetType,
            message: "no matching swipe gesture recognizer found on target"
        )
    }

    // MARK: - Swipe Actions on UIScrollView

    /// 在 UIScrollView 上触发 leading/trailing swipe actions（如 swipe to delete）。
    ///
    /// **两种模式**：
    /// 1. **真正触发 per-cell swipe actions**：当 `input.cellLocator` 非 nil 时，定位到具体 cell，
    ///    通过 tableView/collectionView delegate 拿到对应 `UISwipeActionsConfiguration`，
    ///    直接调 `UIContextualAction.handler` 触发。绕过合成触摸死路（iOS 无公开 API 合成完整触摸序列）。
    /// 2. **对 scrollView 本身滑动**（`cellLocator` 为 nil）：iOS 没有公开 API 合成 UITouch 序列来驱动
    ///    `UITableView`/`UICollectionView` 的内部 swipe action 交互，诚实返回 `false` 让调用方
    ///    落到策略 2（UISwipeGestureRecognizer）→ 策略 3（UIPanGestureRecognizer）→ 最终
    ///    `unsupported_target`，不再产生假阳性。
    ///
    /// - Parameters:
    ///   - scrollView: 目标 scrollView（含 UITableView/UICollectionView）。
    ///   - direction: 滑动方向（仅 left/right 进入本函数，up/down 在调用方已过滤）。
    ///   - distance: 滑动距离比例（当前未使用，保留以便后续扩展）。
    ///   - path: scrollView 路径（用于日志）。
    ///   - input: 完整输入（包含 cellLocator 和 actionTitle）。
    ///   - context: UIKit 查询上下文（用于定位 cell）。
    /// - Returns: 是否成功触发；模式 2（不传 cellLocator）时返回 `false`。
    /// - Throws: cell 定位失败、不是合法 cell 类型、delegate 未返回 actions、actionTitle 不匹配等错误。
    private static func trySwipeActions(on scrollView: UIScrollView, direction: SwipeDirection, distance: Double, path: String, input: UISwipeInput, context: UIKitContextProvider.Context) throws -> Bool {
        // 模式 1：真正触发 per-cell swipe actions
        guard let cellLocator = input.cellLocator else {
            // 模式 2：对 scrollView 本身滑动，不实现（诚实返回 false）
            UIKitCommandLogger.info("command", "ui swipe scrollView swipe actions not implemented (no public API to synthesize touch sequence) direction=\(direction.rawValue) path=\(path)")
            return false
        }

        UIKitCommandLogger.info("command", "ui swipe cell-based swipe actions mode: locating cell direction=\(direction.rawValue) scrollViewPath=\(path)")

        // 定位 cell（在 scrollView 子树内）
        let cellLocated = try UIKitLocatorResolver.locate(
            locator: cellLocator.locator,
            in: scrollView,
            notFound: {
                UIKitCommandError.targetNotFound(
                    action: SwipeCommand.actionName,
                    message: "cell not found in scrollView subtree",
                    logMessage: "ui swipe cell not found in scrollView cellLocator=\(cellLocator.logSummary) scrollViewPath=\(path)"
                )
            },
            ambiguous: { count in
                UIKitCommandError.targetAmbiguous(
                    action: SwipeCommand.actionName,
                    targetDescription: cellLocator.description,
                    count: count
                )
            }
        )
        let cell = cellLocated.view
        let cellPath = cellLocated.pathString

        UIKitCommandLogger.info("command", "ui swipe cell located: cellPath=\(cellPath) cellType=\(String(describing: type(of: cell)))")

        // 判断 cell 类型并获取 indexPath
        if let tableView = scrollView as? UITableView, let tableCell = cell as? UITableViewCell {
            guard let indexPath = tableView.indexPath(for: tableCell) else {
                throw UIKitCommandError.targetNotFound(
                    action: SwipeCommand.actionName,
                    message: "cell not in visible cells",
                    logMessage: "ui swipe cell not in visible cells (indexPath(for:) returned nil) cellPath=\(cellPath)"
                )
            }
            return try triggerTableViewSwipeAction(
                tableView: tableView,
                cell: tableCell,
                indexPath: indexPath,
                direction: direction,
                actionTitle: input.actionTitle,
                cellPath: cellPath
            )
        } else if let collectionView = scrollView as? UICollectionView, let collectionCell = cell as? UICollectionViewCell {
            guard let indexPath = collectionView.indexPath(for: collectionCell) else {
                throw UIKitCommandError.targetNotFound(
                    action: SwipeCommand.actionName,
                    message: "cell not in visible cells",
                    logMessage: "ui swipe cell not in visible cells (indexPath(for:) returned nil) cellPath=\(cellPath)"
                )
            }
            return try triggerCollectionViewSwipeAction(
                collectionView: collectionView,
                cell: collectionCell,
                indexPath: indexPath,
                direction: direction,
                actionTitle: input.actionTitle,
                cellPath: cellPath
            )
        } else {
            // cell 定位到的 view 不是 UITableViewCell/UICollectionViewCell
            throw UIKitCommandError.invalidData(
                action: SwipeCommand.actionName,
                message: "target is not a UITableViewCell or UICollectionViewCell (found \(String(describing: type(of: cell))))"
            )
        }
    }

    /// 触发 UITableView cell 的 swipe action。
    private static func triggerTableViewSwipeAction(
        tableView: UITableView,
        cell: UITableViewCell,
        indexPath: IndexPath,
        direction: SwipeDirection,
        actionTitle: String?,
        cellPath: String
    ) throws -> Bool {
        // direction left → trailing, right → leading
        guard direction == .left || direction == .right else {
            throw UIKitCommandError.unsupportedTarget(
                action: SwipeCommand.actionName,
                targetDescription: cellPath,
                type: "UITableViewCell",
                message: "swipe actions only support left/right (trailing/leading), not up/down"
            )
        }

        let isTrailing = (direction == .left)
        guard let delegate = tableView.delegate else {
            throw UIKitCommandError.unsupportedTarget(
                action: SwipeCommand.actionName,
                targetDescription: cellPath,
                type: "UITableView",
                message: "tableView has no delegate"
            )
        }

        // 调用 delegate 方法获取 swipe actions configuration
        let configuration: UISwipeActionsConfiguration?
        if isTrailing {
            configuration = delegate.tableView?(tableView, trailingSwipeActionsConfigurationForRowAt: indexPath)
        } else {
            configuration = delegate.tableView?(tableView, leadingSwipeActionsConfigurationForRowAt: indexPath)
        }

        guard let config = configuration, !config.actions.isEmpty else {
            throw UIKitCommandError.unsupportedTarget(
                action: SwipeCommand.actionName,
                targetDescription: cellPath,
                type: "UITableViewCell",
                message: "no \(isTrailing ? "trailing" : "leading") swipe actions available for this cell"
            )
        }

        UIKitCommandLogger.info("command", "ui swipe found \(config.actions.count) \(isTrailing ? "trailing" : "leading") actions: \(config.actions.map { $0.title })")

        // 选择要触发的 action
        let targetAction: UIContextualAction
        if let title = actionTitle {
            guard let action = config.actions.first(where: { $0.title == title }) else {
                let availableTitles = config.actions.map { "'\($0.title)'" }.joined(separator: ", ")
                throw UIKitCommandError.targetNotFound(
                    action: SwipeCommand.actionName,
                    message: "action '\(title)' not found in available actions",
                    logMessage: "ui swipe action not found actionTitle='\(title)' available=[\(availableTitles)] cellPath=\(cellPath)"
                )
            }
            targetAction = action
        } else {
            targetAction = config.actions[0]
        }

        UIKitCommandLogger.info("command", "ui swipe triggering action='\(targetAction.title)' cellPath=\(cellPath)")

        // 调用 action handler
        var handlerCompleted = false
        targetAction.handler(targetAction, cell) { performed in
            handlerCompleted = true
            UIKitCommandLogger.info("command", "ui swipe action handler completed performed=\(performed) action='\(targetAction.title)'")
        }

        // handler 是同步还是异步取决于 App 实现，这里假设同步完成（多数场景如此）
        // 如果 handler 异步，handlerCompleted 可能仍是 false，但 action 已触发
        return true
    }

    /// 触发 UICollectionView cell 的 swipe action。
    private static func triggerCollectionViewSwipeAction(
        collectionView: UICollectionView,
        cell: UICollectionViewCell,
        indexPath: IndexPath,
        direction: SwipeDirection,
        actionTitle: String?,
        cellPath: String
    ) throws -> Bool {
        // UICollectionView 的 swipe actions 也是 trailing/leading
        guard direction == .left || direction == .right else {
            throw UIKitCommandError.unsupportedTarget(
                action: SwipeCommand.actionName,
                targetDescription: cellPath,
                type: "UICollectionViewCell",
                message: "swipe actions only support left/right (trailing/leading), not up/down"
            )
        }

        let isTrailing = (direction == .left)
        guard let delegate = collectionView.delegate else {
            throw UIKitCommandError.unsupportedTarget(
                action: SwipeCommand.actionName,
                targetDescription: cellPath,
                type: "UICollectionView",
                message: "collectionView has no delegate"
            )
        }

        // UICollectionView 没有 trailingSwipeActionsConfiguration 方法（iOS 未提供标准 API）
        // 但自定义 layout 可能实现类似逻辑。这里先返回 unsupported
        throw UIKitCommandError.unsupportedTarget(
            action: SwipeCommand.actionName,
            targetDescription: cellPath,
            type: "UICollectionViewCell",
            message: "UICollectionView swipe actions not yet supported (no standard delegate API)"
        )
    }

    // MARK: - UISwipeGestureRecognizer

    /// 尝试触发 view 上挂载的 UISwipeGestureRecognizer。
    ///
    /// - Parameters:
    ///   - view: 目标 view。
    ///   - direction: 滑动方向。
    ///   - path: 目标路径（用于日志）。
    /// - Returns: 是否成功触发。
    #if DEBUG
    private static func trySwipeGesture(on view: UIView, direction: SwipeDirection, path: String) -> Bool? {
        guard let gestures = view.gestureRecognizers, !gestures.isEmpty else {
            return nil
        }

        // 将 SwipeDirection 转换为 UISwipeGestureRecognizer.Direction
        let swipeDirection = directionToUISwipeDirection(direction)

        for gesture in gestures {
            guard let swipeGesture = gesture as? UISwipeGestureRecognizer else { continue }
            // 检查方向是否匹配
            if swipeGesture.direction.contains(swipeDirection) {
                // 尝试触发
            let targets = swipeGesture.explore_targetActionPairs()
            for pair in targets {
                UIGestureTargetExecutor.invokeGestureAction(target: pair.target, action: pair.action, sender: swipeGesture)
                UIKitCommandLogger.info("command", "ui swipe triggered UISwipeGestureRecognizer direction=\(direction.rawValue) path=\(path) action=\(NSStringFromSelector(pair.action))")
            }
            return !targets.isEmpty
            }
        }
        return false
    }
    #endif

    // MARK: - UIPanGestureRecognizer

    /// 尝试触发 view 上挂载的 UIPanGestureRecognizer。
    ///
    /// - Parameters:
    ///   - view: 目标 view。
    ///   - direction: 滑动方向。
    ///   - distance: 滑动距离比例。
    ///   - path: 目标路径（用于日志）。
    /// - Returns: 是否成功触发。
    #if DEBUG
    private static func tryPanGesture(on view: UIView, direction: SwipeDirection, distance: Double, path: String) -> Bool? {
        // 策略 3 只处理用户显式添加的 UIPanGestureRecognizer。
        // UIScrollView（含 UITableView/UICollectionView/UITextView）自带系统 pan gesture
        //（UIScrollViewPanGestureRecognizer）用于滚动——它需要完整触摸序列才能滚动，单次 invoke
        // 不会产生滚动却会让本策略假阳性返回 true。故对 scrollView 直接跳过，落到 unsupported_target。
        if view is UIScrollView {
            UIKitCommandLogger.info("command", "ui swipe pan gesture skipped: target is UIScrollView (system pan not actionable) path=\(path)")
            return nil
        }

        guard let gestures = view.gestureRecognizers, !gestures.isEmpty else {
            return nil
        }

        for gesture in gestures {
            guard let panGesture = gesture as? UIPanGestureRecognizer else { continue }
            // 查找 pan gesture 的 targets
            let targets = panGesture.explore_targetActionPairs()
            for pair in targets {
                // UIPanGestureRecognizer 是连续手势，handler 通常按 state 分支处理。
                // 仿照 UILongPressExecutor.tryLongPressGesture：先设 .began 派发一次，
                // 再设 .ended 派发一次，让 handler 收到正确的状态转换（而非默认的 .possible）。
                // 注意：UIGestureRecognizer.state 是 public var，但实际由 UIKit 内部管理，
                // 此处赋值在 Debug 模拟器上能让 handler 观察到 state 变化（端到端验证）。
                panGesture.state = .began
                UIGestureTargetExecutor.invokeGestureAction(target: pair.target, action: pair.action, sender: panGesture)
                UIKitCommandLogger.info("command", "ui swipe triggered UIPanGestureRecognizer.began direction=\(direction.rawValue) path=\(path) action=\(NSStringFromSelector(pair.action))")

                panGesture.state = .ended
                UIGestureTargetExecutor.invokeGestureAction(target: pair.target, action: pair.action, sender: panGesture)
                UIKitCommandLogger.info("command", "ui swipe triggered UIPanGestureRecognizer.ended direction=\(direction.rawValue) path=\(path) action=\(NSStringFromSelector(pair.action))")
            }
            return !targets.isEmpty
        }
        return false
    }
    #endif

    // MARK: - Helpers

    /// 将 SwipeDirection 转换为 UISwipeGestureRecognizer.Direction。
    private static func directionToUISwipeDirection(_ direction: SwipeDirection) -> UISwipeGestureRecognizer.Direction {
        switch direction {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        }
    }
}
#endif
