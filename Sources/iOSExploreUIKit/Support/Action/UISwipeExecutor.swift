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
                let triggered = trySwipeActions(on: scrollView, direction: input.direction, distance: distance, path: path)
                if triggered {
                    UIKitCommandLogging.info("command", "ui swipe scrollView swipe actions triggered direction=\(input.direction.rawValue) path=\(path)")
                    return [
                        "path": .string(path),
                        "route": .string("scrollView.swipeActions"),
                        "direction": .string(input.direction.rawValue),
                        "targetType": .string(String(describing: UIScrollView.self)),
                        "distance": .double(distance),
                        "triggered": .bool(true),
                    ]
                }
            }
        }

        // 策略 2: UISwipeGestureRecognizer
        #if DEBUG
        if let triggered = trySwipeGesture(on: view, direction: input.direction, path: path), triggered {
            UIKitCommandLogging.info("command", "ui swipe UISwipeGestureRecognizer triggered direction=\(input.direction.rawValue) path=\(path)")
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
            UIKitCommandLogging.info("command", "ui swipe UIPanGestureRecognizer triggered direction=\(input.direction.rawValue) path=\(path)")
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
        UIKitCommandLogging.info("command", "ui swipe no gesture found direction=\(input.direction.rawValue) path=\(path) type=\(targetType)")
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
    /// **当前不实现真正触发，诚实返回 `false`。** iOS 没有公开 API 合成 UITouch 序列来驱动
    /// `UITableView`/`UICollectionView` 的内部 swipe action 交互：合成 `UITouch` 在 iOS 26 已被
    /// 证实不可行（见 realTouch spike 报告），而仅 invoke scrollView 内置的 pan gesture recognizer
    ///（或 `_swipeActionGestureRecognizer`）只会派发其 target-action，不产生真实触摸事件流，
    /// iOS 的 swipe action 交互需要完整触摸序列才会展开 action button。
    ///
    /// 真正支持 swipe actions 需要后续设计：定位到具体 cell（path/identifier 指向 cell 或其行号）
    /// + 通过 tableView delegate 拿到对应 `UISwipeActionsConfiguration` 的 `UIContextualAction`，
    /// 直接调 action handler（`UIContextualAction` 的 handler 闭包）。这需要新增「cell 定位 + action
    /// 选择」参数，本次不做（见报告「后续增强建议」）。
    ///
    /// 返回 `false` 让 `execute` 落到策略 2（UISwipeGestureRecognizer）→ 策略 3
    ///（UIPanGestureRecognizer）→ 最终 `unsupported_target`（带 swipe 专用 message），
    /// 不再产生 `triggered:true / route:scrollView.swipeActions` 的假阳性。
    ///
    /// - Parameters:
    ///   - scrollView: 目标 scrollView（含 UITableView/UICollectionView）。
    ///   - direction: 滑动方向（仅 left/right 进入本函数，up/down 在调用方已过滤）。
    ///   - distance: 滑动距离比例（当前未使用，保留以便后续真实触发实现复用签名）。
    ///   - path: 目标路径（用于日志）。
    /// - Returns: 恒为 `false`——未真正触发 swipe actions。
    private static func trySwipeActions(on scrollView: UIScrollView, direction: SwipeDirection, distance: Double, path: String) -> Bool {
        UIKitCommandLogging.info("command", "ui swipe scrollView swipe actions not implemented (no public API to synthesize touch sequence) direction=\(direction.rawValue) path=\(path)")
        return false
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
                UIKitCommandLogging.info("command", "ui swipe triggered UISwipeGestureRecognizer direction=\(direction.rawValue) path=\(path) action=\(NSStringFromSelector(pair.action))")
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
            UIKitCommandLogging.info("command", "ui swipe pan gesture skipped: target is UIScrollView (system pan not actionable) path=\(path)")
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
                UIKitCommandLogging.info("command", "ui swipe triggered UIPanGestureRecognizer.began direction=\(direction.rawValue) path=\(path) action=\(NSStringFromSelector(pair.action))")

                panGesture.state = .ended
                UIGestureTargetExecutor.invokeGestureAction(target: pair.target, action: pair.action, sender: panGesture)
                UIKitCommandLogging.info("command", "ui swipe triggered UIPanGestureRecognizer.ended direction=\(direction.rawValue) path=\(path) action=\(NSStringFromSelector(pair.action))")
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
