#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.longPress` 的执行核心。
///
/// 在 `MainActor` 上完成：经 `UIViewResolver` 解析目标 view → 尝试触发 `UILongPressGestureRecognizer`
/// → 通过 runtime 派发 target-action → 回传语义 JSON。
///
/// 长按策略：
/// 1. **UILongPressGestureRecognizer**：查找 view 上挂载的 `UILongPressGestureRecognizer`，
///    通过 runtime 派发其 target-action（仅 Debug 可用）。
///
/// 所有失败出口通过 `UIKitCommandError` 工厂构造。
@MainActor
enum UILongPressExecutor {
    /// 默认长按持续时间（秒）。
    static let defaultDuration: Double = 0.5

    /// 在已定位上下文上执行长按，返回长按结果摘要。
    ///
    /// 该函数为 `async`：长按等待阶段用 `await Task.sleep`（见 `tryLongPressGesture`），
    /// 在 `@MainActor` 的 async 上下文里 `await` 会让出（yield）actor，使其它排队的
    /// `@MainActor` 任务（并发到达的 `ui.*` 命令）能插队执行。这是 async 与同步阻塞
    /// （`RunLoop.current.run` 不排空 cooperative MainActor 任务队列）的本质区别。
    ///
    /// - Parameters:
    ///   - input: 已通过 typed schema 校验的 longPress 输入。
    ///   - context: 当前 MainActor 查询上下文（window / rootView / topViewController）。
    /// - Returns: 长按结果 JSON（path / route / duration / targetType 等）。
    /// - Throws: 定位失败、陈旧等 `UIKitCommandError`。
    static func execute(input: UILongPressInput, context: UIKitContextProvider.Context) async throws -> JSON {
        let action = LongPressCommand.actionName
        let resolved = try UILongPressResolver.resolveTarget(
            locator: input.locator,
            viewSnapshotID: input.viewSnapshotID,
            context: context,
            action: action
        )

        let view = resolved.view
        let path = resolved.path
        let duration = input.duration ?? Self.defaultDuration

        // 策略 1: UILongPressGestureRecognizer
        #if DEBUG
        if let triggered = try await tryLongPressGesture(on: view, duration: duration, path: path), triggered {
            UIKitCommandLogging.info("command", "ui longPress UILongPressGestureRecognizer triggered duration=\(duration) path=\(path)")
            return [
                "path": .string(path),
                "route": .string("longPressGesture.targetAction"),
                "duration": .double(duration),
                "targetType": .string(String(describing: Swift.type(of: view))),
                "triggered": .bool(true),
            ]
        }
        #endif

        // 所有策略都未触发
        let targetType = String(describing: Swift.type(of: view))
        UIKitCommandLogging.info("command", "ui longPress no UILongPressGestureRecognizer found path=\(path) type=\(targetType)")
        throw UIKitCommandError.unsupportedTarget(
            action: action,
            targetDescription: path,
            type: targetType,
            message: "no UILongPressGestureRecognizer found on target"
        )
    }

    // MARK: - UILongPressGestureRecognizer

    /// 尝试触发 view 上挂载的 UILongPressGestureRecognizer。
    ///
    /// 该函数为 `async throws`：began→ended 之间的等待用 `await Task.sleep`。`Task.sleep` 是
    /// async 挂起点，在 `@MainActor` 上挂起时会让出 actor，其它排队的 `@MainActor` 任务（并发
    /// 到达的 `ui.*` 命令）可插队执行，而不是被 duration 秒的同步阻塞挡住。
    ///
    /// - Parameters:
    ///   - view: 目标 view。
    ///   - duration: 长按持续时间（秒）。
    ///   - path: 目标路径（用于日志）。
    /// - Returns: 是否成功触发。
    /// - Throws: `Task.sleep` 抛出的 `CancellationError`（longPress 路径不主动取消，正常不抛）。
    #if DEBUG
    private static func tryLongPressGesture(on view: UIView, duration: Double, path: String) async throws -> Bool? {
        guard let gestures = view.gestureRecognizers, !gestures.isEmpty else {
            return nil
        }

        for gesture in gestures {
            guard let longPressGesture = gesture as? UILongPressGestureRecognizer else { continue }
            // 查找 longPress gesture 的 targets
            let targets = longPressGesture.explore_targetActionPairs()
            for pair in targets {
                // UILongPressGestureRecognizer 的状态转换：began → changed → ended
                // 先触发 began 状态（长按开始）
                longPressGesture.state = .began
                UIGestureTargetExecutor.invokeGestureAction(target: pair.target, action: pair.action, sender: longPressGesture)
                UIKitCommandLogging.info("command", "ui longPress triggered UILongPressGestureRecognizer.began path=\(path) action=\(NSStringFromSelector(pair.action))")

                // 按 duration 等待后触发 ended 状态（长按结束）。
                // 用 await Task.sleep 而非同步 RunLoop.current.run(until:)：两者都在 MainActor 上等待，
                // 但 Task.sleep 是 async 挂起点——挂起时会让出（yield）MainActor，让其它排队的 @MainActor
                // 任务（如并发到达的 ui.inspect / ui.tap 等 ui.* 命令）插队执行。
                // RunLoop.current.run 是同步调用，不排空 Swift 6 的 cooperative MainActor 任务队列，
                // 其它 ui.* 命令仍要等 longPress 返回才能跑。这是"同步阻塞"与"异步让出"的本质区别。
                // duration 上限由 UILongPressInput.parse 校验（<=10s），不会无限等待；Task.sleep 抛
                // CancellationError 由本函数 async throws 签名向上传递（longPress 路径不主动取消）。
                // 用 nanoseconds 重载（iOS 13+）而非 Task.sleep(for: .seconds)（iOS 16+），兼容
                // SPM 包声明的 .iOS(.v13) 部署目标。
                try await Task.sleep(nanoseconds: UInt64(max(duration, 0.1) * 1_000_000_000))
                longPressGesture.state = .ended
                UIGestureTargetExecutor.invokeGestureAction(target: pair.target, action: pair.action, sender: longPressGesture)
                UIKitCommandLogging.info("command", "ui longPress triggered UILongPressGestureRecognizer.ended duration=\(duration) path=\(path) action=\(NSStringFromSelector(pair.action))")
            }
            return !targets.isEmpty
        }
        return false
    }
    #endif
}
#endif
