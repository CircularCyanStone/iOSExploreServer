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
    /// - Throws: `UIKitCommandError.waitTimeout`——业务 deadline 到仍未满足；或 contextProvider 抛出的 hierarchy 错误。
    static func execute(input: UIWaitInput,
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
            let context = try contextProvider()
            let now = DispatchTime.now().uptimeNanoseconds
            var satisfied = false

            switch input.mode {
            case .idle:
                let signature = activitySignature(in: context.rootView, includeHidden: input.includeHidden)
                if signature != lastSignature {
                    lastSignature = signature
                    lastChangeAt = now
                }
                if now - lastChangeAt >= stableNanos {
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
                if let snapshotID = input.snapshotID {
                    // whole table 比较（spec §6）：采集当前 path→fingerprint 表，与 snapshot 签发时
                    // 存的表整体比对。任一 path 的 fingerprint 变化或 path 集合变化都判为「已变化」。
                    // 注意：采集 query 应与签发时一致（默认 viewTargets/screenshot 用 .default）。
                    let digest = UIKitFingerprintCollector.digest(topViewController: context.topViewController)
                    let currentTable = UIKitFingerprintCollector.collectFingerprints(
                        rootView: context.rootView,
                        query: UIViewTargetsInput.default,
                        digest: digest
                    )
                    let snapshotContext = UIKitFingerprintCollector.context(window: context.window,
                                                                            topViewController: context.topViewController)
                    if let matched = UIKitSnapshotStore.shared.matchesWholeTable(snapshotID: snapshotID,
                                                                                  context: snapshotContext,
                                                                                  currentTable: currentTable) {
                        satisfied = !matched
                    } else if snapshotUnavailableReason == nil {
                        snapshotUnavailableReason = "snapshot unknown or expired"
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
