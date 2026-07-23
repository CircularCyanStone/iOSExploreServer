#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.waitAny` 的执行核心。
///
/// 在 `MainActor` 上按共享 `intervalMs` 轮询，每轮按 `conditions` 顺序评估（复用
/// `UIWaitExecutor.evaluate` 的五模式判断原语，不复制判断），第一个满足的条件立即返回
/// `matchedID` / `matchedIndex` / `matchedMode` / `elapsedMs` / `attempts`。命令级兜底
/// （`WaitAnyCommand.timeoutNanoseconds = 35s`）高于最大业务超时 30s，确保业务 deadline 先于
/// 命令级 cancel 生效。
///
/// 退出语义对齐 `ui.wait`：
/// - `Task.sleep` 用 `try?` 吞掉 cancellation，循环顶部与 sleep 后各检查一次 `Task.isCancelled`，
///   把任何退出路径都收敛到 `waitTimeout`（不泄漏 `CancellationError` 成 `internal_error`）。
/// - `contextProvider` 瞬时层级不可用（转场/前后台切换）当作本轮所有条件未满足，继续轮询到 deadline。
///
/// 日志点：命中时记录 matchedID/matchedIndex/mode/attempts/elapsedMs；超时失败日志由 command
/// adapter 顶层 catch 统一记录。
@MainActor
enum UIWaitAnyExecutor {
    /// 执行一次多条件等待。
    ///
    /// - Parameters:
    ///   - input: 已通过 typed schema 校验的 waitAny 参数。
    ///   - contextProvider: 每轮轮询取当前查询上下文的闭包（注入便于测试）。
    /// - Returns: 命中时返回 satisfied/matchedID/matchedIndex/matchedMode/elapsedMs/attempts。
    /// - Throws: `UIKitCommandError.waitTimeout`——业务 deadline 到仍无命中，或被 cancel。
    ///   contextProvider 抛出的瞬时 hierarchy 不可用被当作本轮未满足继续轮询，不上抛成硬失败。
    static func execute(input: UIWaitAnyInput,
                        contextProvider: @escaping @MainActor () throws -> UIKitContextProvider.Context) async throws -> JSON {
        try await execute(input: input, snapshotStore: .shared, contextProvider: contextProvider)
    }

    /// 执行一次多条件等待，并允许测试注入独立 snapshot store。
    ///
    /// 产品路径始终通过 `execute(input:contextProvider:)` 使用共享 store；该入口只用于把需要
    /// `await` 轮询的测试从全局 LRU 状态中隔离出来，对齐 `UIWaitExecutor` 的测试隔离方式。
    ///
    /// - Parameters:
    ///   - input: 已通过 typed schema 校验的 waitAny 参数。
    ///   - snapshotStore: 用于 snapshotChanged 条件的 snapshot 查询与整表比对。
    ///   - contextProvider: 每轮轮询取当前查询上下文的闭包（注入便于测试）。
    /// - Returns: 命中时返回 satisfied/matchedID/matchedIndex/matchedMode/elapsedMs/attempts。
    /// - Throws: `UIKitCommandError.waitTimeout`——业务 deadline 到仍无命中，或被 cancel。
    static func execute(input: UIWaitAnyInput,
                        snapshotStore: UIKitSnapshotStore,
                        contextProvider: @escaping @MainActor () throws -> UIKitContextProvider.Context) async throws -> JSON {
        let start = DispatchTime.now().uptimeNanoseconds
        let deadline = start + UInt64(input.timeoutMs) * 1_000_000
        let intervalNanos = UInt64(input.intervalMs) * 1_000_000

        // 预构造每条件的 probe（叠加顶层共享 stableMs/includeHidden）与各自独立的 idle 稳定窗口状态。
        // probe/conditions/states 三者同序，靠 index 关联，无需在循环内重复构造。
        let probes = input.conditions.map { condition in
            UIWaitExecutor.ConditionProbe(mode: condition.mode,
                                          text: condition.text,
                                          viewSnapshotID: condition.viewSnapshotID,
                                          target: condition.target,
                                          stableMs: input.stableMs,
                                          includeHidden: input.includeHidden)
        }
        var states = input.conditions.map { _ in UIWaitExecutor.PollState(start: start) }
        var attempts = 0
        var snapshotUnavailableReason: String?

        while true {
            // 循环顶部检查 cancel：覆盖 cancel 落在非-sleep 同步段（contextProvider/evaluate）的情形，
            // 避免 cancel 响应延迟一轮或 CancellationError 泄漏成 internal_error。
            if Task.isCancelled {
                let elapsedMs = Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                throw UIKitCommandError.waitTimeout(action: WaitAnyCommand.actionName,
                                                    mode: "any",
                                                    elapsedMs: elapsedMs,
                                                    attempts: attempts)
            }
            attempts += 1
            let now = DispatchTime.now().uptimeNanoseconds
            // 瞬时层级不可用（控制器转场、前后台切换、root 交换）当作本轮全部未满足继续轮询，
            // 而非上抛 hierarchy_unavailable 把整个 waitAny 中止成硬失败——与 ui.wait 一致。
            // try? 仅吞 contextProvider 抛出的 hierarchyUnavailable（其唯一抛出路径）。
            if let context = try? contextProvider() {
                // 按 conditions 顺序评估，第一个满足立即返回，保持稳定的优先级。
                for index in probes.indices {
                    if UIWaitExecutor.evaluate(probes[index],
                                               state: &states[index],
                                               now: now,
                                               context: context,
                                               snapshotStore: snapshotStore,
                                               snapshotUnavailableReason: &snapshotUnavailableReason) {
                        let elapsedMs = Int((now - start) / 1_000_000)
                        let matched = input.conditions[index]
                        UIKitCommandLogger.info("command", "ui waitAny complete satisfied=true matchedID=\(matched.id) matchedIndex=\(index) mode=\(matched.mode.rawValue) attempts=\(attempts) elapsedMs=\(elapsedMs)")
                        return response(satisfied: true,
                                        matchedID: matched.id,
                                        matchedIndex: index,
                                        matchedMode: matched.mode,
                                        elapsedMs: elapsedMs,
                                        attempts: attempts,
                                        snapshotUnavailableReason: snapshotUnavailableReason)
                    }
                }
            }

            if now >= deadline {
                let elapsedMs = Int((now - start) / 1_000_000)
                throw UIKitCommandError.waitTimeout(action: WaitAnyCommand.actionName,
                                                    mode: "any",
                                                    elapsedMs: elapsedMs,
                                                    attempts: attempts)
            }

            // sleep clamp 到剩余 deadline，确保业务 waitTimeout 先于命令级 35s cancel。
            let remaining = deadline - now
            let sleepNanos = min(intervalNanos, remaining)
            if sleepNanos > 0 {
                try? await Task.sleep(nanoseconds: sleepNanos)
            }
            if Task.isCancelled {
                let elapsedMs = Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                throw UIKitCommandError.waitTimeout(action: WaitAnyCommand.actionName,
                                                    mode: "any",
                                                    elapsedMs: elapsedMs,
                                                    attempts: attempts)
            }
        }
    }

    /// 构造命中响应 JSON，回传 matchedID/matchedIndex/matchedMode，不返回文本原文。
    private static func response(satisfied: Bool,
                                 matchedID: String,
                                 matchedIndex: Int,
                                 matchedMode: WaitMode,
                                 elapsedMs: Int,
                                 attempts: Int,
                                 snapshotUnavailableReason: String?) -> JSON {
        var json: JSON = [
            "satisfied": .bool(satisfied),
            "matchedID": .string(matchedID),
            "matchedIndex": .double(Double(matchedIndex)),
            "matchedMode": .string(matchedMode.rawValue),
            "elapsedMs": .double(Double(elapsedMs)),
            "attempts": .double(Double(attempts)),
        ]
        if let reason = snapshotUnavailableReason {
            json["snapshotUnavailableReason"] = .string(reason)
        }
        return json
    }
}
#endif
