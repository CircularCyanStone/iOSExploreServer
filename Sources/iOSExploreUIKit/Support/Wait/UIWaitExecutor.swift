#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.wait` 的执行核心。
///
/// 在 `MainActor` 上按 `intervalMs` 轮询 UI 状态，满足条件即返回，业务 `timeoutMs` 到则抛
/// `waitTimeout`。命令级兜底（`WaitCommand.timeoutNanoseconds = 35s`）高于最大业务超时 30s，
/// 确保业务 deadline 先于命令级 cancel 生效；`Task.sleep` 用 `try?` 吞掉 cancellation，再在
/// 循环条件里检查 `Task.isCancelled`，把任何退出路径都收敛到 `waitTimeout` 而非 `internal_error`。
///
/// 模式语义：
/// - `idle`：连续 `stableMs` 内画面活动签名（可见文本片段拼接 + 片段数）不变。
/// - `targetExists` / `targetGone`：目标 view 出现 / 消失（`UIKitLocatorResolver.contains`）。
/// - `textExists`：可见文本包含目标片段（`UIKitVisibleTextCollector`，不含用户输入）。
/// - `snapshotChanged`：页面整体指纹表变化（path→fingerprint 表整体比对，含同页面内容变化；`UIKitSnapshotStore.matchesWholeTable`）。
///
/// 日志点：满足时记录 mode/attempts/elapsedMs；超时失败日志由 command adapter 顶层统一记录。
@MainActor
enum UIWaitExecutor {
    /// 执行一次 UI 等待。
    ///
    /// - Parameters:
    ///   - input: 已通过 typed schema 校验的 wait 参数。
    ///   - contextProvider: 每轮轮询取当前查询上下文的闭包（注入便于测试）。
    /// - Returns: 满足时返回 satisfied/mode/elapsedMs/attempts，snapshotChanged 不可用时附 reason。
    /// - Throws: `UIKitCommandError.waitTimeout`——业务 deadline 到仍未满足。contextProvider 抛出的瞬时
    ///   hierarchy 不可用（转场/前后台切换）被当作本轮未满足继续轮询，不上抛成硬失败。
    static func execute(input: UIWaitInput,
                        contextProvider: @escaping @MainActor () throws -> UIKitContextProvider.Context) async throws -> JSON {
        try await execute(input: input, snapshotStore: .shared, contextProvider: contextProvider)
    }

    /// 执行一次 UI 等待，并允许测试注入独立 snapshot store。
    ///
    /// 产品路径始终通过 `execute(input:contextProvider:)` 使用共享 store；该入口只用于把需要
    /// `await` 轮询的测试从全局 LRU 状态中隔离出来，避免其它并发 UIKit 测试插入 snapshot 后
    /// 淘汰本用例刚签发的 `viewSnapshotID`。
    ///
    /// - Parameters:
    ///   - input: 已通过 typed schema 校验的 wait 参数。
    ///   - snapshotStore: 用于 `snapshotChanged` 的 snapshot 查询与整表比对。
    ///   - contextProvider: 每轮轮询取当前查询上下文的闭包（注入便于测试）。
    /// - Returns: 满足时返回 satisfied/mode/elapsedMs/attempts，snapshotChanged 不可用时附 reason。
    /// - Throws: `UIKitCommandError.waitTimeout`——业务 deadline 到仍未满足。
    static func execute(input: UIWaitInput,
                        snapshotStore: UIKitSnapshotStore,
                        contextProvider: @escaping @MainActor () throws -> UIKitContextProvider.Context) async throws -> JSON {
        let start = DispatchTime.now().uptimeNanoseconds
        let deadline = start + UInt64(input.timeoutMs) * 1_000_000
        let stableNanos = UInt64(input.stableMs) * 1_000_000
        let intervalNanos = UInt64(input.intervalMs) * 1_000_000

        var attempts = 0
        var lastSignature: String?
        var lastChangeAt = start
        var snapshotUnavailableReason: String?

        while true {
            // 循环顶部检查 cancel：覆盖 cancel 落在非-sleep 同步段（contextProvider/UIKit 遍历）的情形，
            // 避免 cancel 响应延迟一轮或（未来 contextProvider 改 async 时）CancellationError 泄漏成 internal_error。
            if Task.isCancelled {
                let elapsedMs = Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                throw UIKitCommandError.waitTimeout(action: WaitCommand.actionName,
                                                    mode: input.mode.rawValue,
                                                    elapsedMs: elapsedMs)
            }
            attempts += 1
            // 瞬时层级不可用（控制器转场、前后台切换、root 交换导致 activeWindow/topView 短暂为空）
            // 当作本轮「未满足」继续轮询到 deadline，而非上抛 hierarchy_unavailable 把整个 wait
            // 中止成硬失败——等待命令的本职就是桥接这类瞬态。try? 仅吞 contextProvider 抛出的
            // hierarchyUnavailable（其唯一抛出路径）；其余模式分支在 context 为 nil 时整体跳过。
            let now = DispatchTime.now().uptimeNanoseconds
            var satisfied = false
            if let context = try? contextProvider() {
                switch input.mode {
                case .idle:
                    let signature = activitySignature(in: context.rootView, includeHidden: input.includeHidden)
                    let signatureChanged = signature != lastSignature
                    if signatureChanged {
                        lastSignature = signature
                        lastChangeAt = now
                    }
                    // 仅当本轮未发生变化、且距上次变化已持续 stableMs 才判稳。stableMs=0 时也要求
                    // 「连续两帧相同」（首轮 lastSignature 由 nil→写入必 changed，不 satisfied），避免
                    // 首轮单采样或「每轮都在变」时被误判为已稳定——变化当轮 lastChangeAt=now，
                    // 若不卡 !signatureChanged，stableMs=0 下 0>=0 会假稳。
                    if !signatureChanged, now - lastChangeAt >= stableNanos {
                        satisfied = true
                    }
                case .targetExists:
                    if let target = input.target {
                        satisfied = UIKitLocatorResolver.contains(locator: target.locator, in: context.rootView)
                    }
                case .targetGone:
                    if let target = input.target {
                        satisfied = !UIKitLocatorResolver.contains(locator: target.locator, in: context.rootView)
                    }
                case .textExists:
                    if let text = input.text {
                        satisfied = UIKitVisibleTextCollector.contains(text: text,
                                                                       in: context.rootView,
                                                                       includeHidden: input.includeHidden)
                    }
                case .snapshotChanged:
                    if let viewSnapshotID = input.viewSnapshotID {
                        // whole table 比较（spec §6）：用签发时同一 query 重采当前 path→fingerprint 表，
                        // 再与 snapshot 存的表整体比对。query 从 store 取（签发方诚实记录，签发方只能是
                        // ui.viewTargets），避免签发 query（如 viewTargets 带 includeHidden）与重采 query
                        // 不一致导致首轮误判「已变化」。
                        let query = snapshotStore.signingQuery(for: viewSnapshotID) ?? .default
                        let digest = UIKitFingerprintCollector.digest(topViewController: context.topViewController)
                        let currentTable = UIKitFingerprintCollector.collectFingerprints(
                            rootView: context.rootView,
                            query: query,
                            digest: digest
                        )
                        let snapshotContext = UIKitFingerprintCollector.context(window: context.window,
                                                                                topViewController: context.topViewController)
                        if let matched = snapshotStore.matchesWholeTable(viewSnapshotID: viewSnapshotID,
                                                                         context: snapshotContext,
                                                                         currentTable: currentTable) {
                            satisfied = !matched
                        } else if snapshotUnavailableReason == nil {
                            snapshotUnavailableReason = "view snapshot unknown or expired"
                        }
                    }
                }
            }

            if satisfied {
                let elapsedMs = Int((now - start) / 1_000_000)
                UIKitCommandLogging.info("command", "ui wait complete satisfied=true mode=\(input.mode.rawValue) attempts=\(attempts) elapsedMs=\(elapsedMs)")
                return response(satisfied: true,
                                mode: input.mode,
                                elapsedMs: elapsedMs,
                                attempts: attempts,
                                snapshotUnavailableReason: snapshotUnavailableReason)
            }

            if now >= deadline {
                let elapsedMs = Int((now - start) / 1_000_000)
                throw UIKitCommandError.waitTimeout(action: WaitCommand.actionName,
                                                    mode: input.mode.rawValue,
                                                    elapsedMs: elapsedMs)
            }

            // sleep clamp 到剩余 deadline，确保业务 waitTimeout 先于命令级 35s cancel。
            let remaining = deadline - now
            let sleepNanos = min(intervalNanos, remaining)
            if sleepNanos > 0 {
                try? await Task.sleep(nanoseconds: sleepNanos)
            }
            if Task.isCancelled {
                let elapsedMs = Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                throw UIKitCommandError.waitTimeout(action: WaitCommand.actionName,
                                                    mode: input.mode.rawValue,
                                                    elapsedMs: elapsedMs)
            }
        }
    }

    /// 当前画面活动签名：可见文本片段数 + 文本拼接。idle 用其判断连续 stableMs 是否静止。
    private static func activitySignature(in rootView: UIView, includeHidden: Bool) -> String {
        let fragments = UIKitVisibleTextCollector.collect(from: rootView, includeHidden: includeHidden)
        return "\(fragments.count)|" + fragments.map(\.text).joined(separator: "\n")
    }

    /// 构造对外 JSON 响应，不返回文本原文。
    private static func response(satisfied: Bool,
                                 mode: WaitMode,
                                 elapsedMs: Int,
                                 attempts: Int,
                                 snapshotUnavailableReason: String?) -> JSON {
        var json: JSON = [
            "satisfied": .bool(satisfied),
            "mode": .string(mode.rawValue),
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
