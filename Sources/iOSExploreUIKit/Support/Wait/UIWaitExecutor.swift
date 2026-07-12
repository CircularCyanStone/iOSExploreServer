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
        let intervalNanos = UInt64(input.intervalMs) * 1_000_000

        var attempts = 0
        var state = PollState(start: start)
        var snapshotUnavailableReason: String?

        while true {
            // 循环顶部检查 cancel：覆盖 cancel 落在非-sleep 同步段（contextProvider/UIKit 遍历）的情形，
            // 避免 cancel 响应延迟一轮或（未来 contextProvider 改 async 时）CancellationError 泄漏成 internal_error。
            if Task.isCancelled {
                let elapsedMs = Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                throw UIKitCommandError.waitTimeout(action: WaitCommand.actionName,
                                                    mode: input.mode.rawValue,
                                                    elapsedMs: elapsedMs,
                                                    attempts: attempts)
            }
            attempts += 1
            // 瞬时层级不可用（控制器转场、前后台切换、root 交换导致 activeWindow/topView 短暂为空）
            // 当作本轮「未满足」继续轮询到 deadline，而非上抛 hierarchy_unavailable 把整个 wait
            // 中止成硬失败——等待命令的本职就是桥接这类瞬态。try? 仅吞 contextProvider 抛出的
            // hierarchyUnavailable（其唯一抛出路径）；其余模式分支在 context 为 nil 时整体跳过。
            let now = DispatchTime.now().uptimeNanoseconds
            var satisfied = false
            if let context = try? contextProvider() {
                // 五模式判断收敛到 evaluate，与 ui.waitAny 共享同一套原语，避免复制。idle 的稳定
                // 窗口状态封装在 state 里，由 evaluate 回写；其余模式无状态。
                satisfied = evaluate(ConditionProbe(input: input),
                                     state: &state,
                                     now: now,
                                     context: context,
                                     snapshotStore: snapshotStore,
                                     snapshotUnavailableReason: &snapshotUnavailableReason)
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
                throw UIKitCommandError.waitTimeout(action: WaitCommand.actionName,
                                                    mode: input.mode.rawValue,
                                                    elapsedMs: elapsedMs,
                                                    attempts: attempts)
            }
        }
    }

    /// 单条件一轮评估的不可变视图，`ui.wait` 与 `ui.waitAny` 共享同一套五模式判断原语。
    ///
    /// 把 mode 相关字段从完整 input 投影出来，使 `evaluate` 不依赖具体命令的输入形状：
    /// `ui.wait` 由单条件 input 构造，`ui.waitAny` 由每个 condition 叠加顶层共享的 stableMs/includeHidden 构造。
    struct ConditionProbe: Sendable {
        /// 等待模式。
        let mode: WaitMode
        /// textExists 要等待的文本。
        let text: String?
        /// snapshotChanged 参照的 viewSnapshotID。
        let viewSnapshotID: String?
        /// targetExists / targetGone 的定位目标。
        let target: UIKitViewLookupTarget?
        /// idle 连续稳定的毫秒数。
        let stableMs: Int
        /// idle / textExists 是否考虑隐藏 view。
        let includeHidden: Bool

        /// 从 `ui.wait` 单条件输入投影 probe。
        init(input: UIWaitInput) {
            self.mode = input.mode
            self.text = input.text
            self.viewSnapshotID = input.viewSnapshotID
            self.target = input.target
            self.stableMs = input.stableMs
            self.includeHidden = input.includeHidden
        }

        /// 按 `ui.waitAny` 单条件叠加顶层共享字段投影 probe。
        init(mode: WaitMode,
             text: String?,
             viewSnapshotID: String?,
             target: UIKitViewLookupTarget?,
             stableMs: Int,
             includeHidden: Bool) {
            self.mode = mode
            self.text = text
            self.viewSnapshotID = viewSnapshotID
            self.target = target
            self.stableMs = stableMs
            self.includeHidden = includeHidden
        }
    }

    /// 单条件轮询的可变状态，仅 idle 的稳定窗口用到。
    struct PollState: Sendable {
        /// 上一轮活动签名，首轮为 nil（首轮写入必判为 changed，从而不计稳）。
        var lastSignature: String?
        /// 最近一次签名变化时刻（uptime 纳秒），首轮初始化为轮询起点。
        var lastChangeAt: UInt64

        /// 创建初始空状态。
        ///
        /// - Parameter start: 轮询起点 uptime 纳秒，作为 lastChangeAt 初值。
        init(start: UInt64) {
            self.lastSignature = nil
            self.lastChangeAt = start
        }
    }

    /// 评估单个条件在当前 context 下是否满足（单轮）。
    ///
    /// 这是 `ui.wait` 与 `ui.waitAny` 共享的判断核心：targetExists/targetGone/textExists/snapshotChanged
    /// 无状态，idle 需要调用方传入并回写稳定窗口状态（`state`）。调用方在 contextProvider 瞬时不可用
    /// 时应整体跳过本轮（不调本方法），与 `ui.wait` 一致地把瞬态当未满足继续轮询。
    ///
    /// - Parameters:
    ///   - probe: 单条件评估的不可变视图。
    ///   - state: idle 的稳定窗口状态，由本方法回写；其余模式不读写。
    ///   - now: 当前 uptime 纳秒。
    ///   - context: 当前查询上下文（调用方已确保层级可用）。
    ///   - snapshotStore: snapshotChanged 的 snapshot 查询与整表比对。
    ///   - snapshotUnavailableReason: snapshotChanged 不可用时回写的原因，跨轮保留首次原因。
    /// - Returns: 该条件本轮是否满足。
    static func evaluate(_ probe: ConditionProbe,
                         state: inout PollState,
                         now: UInt64,
                         context: UIKitContextProvider.Context,
                         snapshotStore: UIKitSnapshotStore,
                         snapshotUnavailableReason: inout String?) -> Bool {
        let stableNanos = UInt64(probe.stableMs) * 1_000_000
        switch probe.mode {
        case .idle:
            let signature = activitySignature(in: context.rootView, includeHidden: probe.includeHidden)
            let signatureChanged = signature != state.lastSignature
            if signatureChanged {
                state.lastSignature = signature
                state.lastChangeAt = now
            }
            // 仅当本轮未发生变化、且距上次变化已持续 stableMs 才判稳。stableMs=0 时也要求
            // 「连续两帧相同」（首轮 lastSignature 由 nil→写入必 changed，不 satisfied），避免
            // 首轮单采样或「每轮都在变」时被误判为已稳定——变化当轮 lastChangeAt=now，
            // 若不卡 !signatureChanged，stableMs=0 下 0>=0 会假稳。
            if !signatureChanged, now - state.lastChangeAt >= stableNanos {
                return true
            }
            return false
        case .targetExists:
            guard let target = probe.target else { return false }
            return UIKitLocatorResolver.contains(locator: target.locator,
                                                  in: context.rootView,
                                                  includeHidden: probe.includeHidden)
        case .targetGone:
            guard let target = probe.target else { return false }
            return !UIKitLocatorResolver.contains(locator: target.locator,
                                                   in: context.rootView,
                                                   includeHidden: probe.includeHidden)
        case .textExists:
            guard let text = probe.text else { return false }
            return UIKitVisibleTextCollector.contains(text: text,
                                                      in: context.rootView,
                                                      includeHidden: probe.includeHidden)
        case .snapshotChanged:
            guard let viewSnapshotID = probe.viewSnapshotID else { return false }
            // whole table 比较（spec §6）：用签发时同一 query 重采当前 path→fingerprint 表，
            // 再与 snapshot 存的表整体比对。query 从 store 取（签发方诚实记录，签发方只能是
            // ui.inspect），避免签发 query（如 ui.inspect 带 includeHidden）与重采 query
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
                return !matched
            }
            if snapshotUnavailableReason == nil {
                snapshotUnavailableReason = "view snapshot unknown or expired"
            }
            return false
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
