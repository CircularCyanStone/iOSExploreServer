#if canImport(UIKit)
import Foundation
import iOSExploreServer

/// 等待 UI 满足条件的命令。
///
/// action 为 `ui.wait`。adapter 只负责解析后的日志与上下文注入；轮询、deadline、cancellation
/// 处理全部收敛在 `UIWaitExecutor` 中。executor 是 `@MainActor async`（含 `Task.sleep`），故
/// adapter 直接 `await` 它 hop 到 MainActor，而非用 `MainActor.run`（其 body 为同步）。
struct WaitCommand: Command {
    /// typed 输入模型，负责 schema 暴露和 data 解析。
    typealias Input = UIWaitInput

    /// 固定 action 名。
    static let actionName = UIKitActionContracts.uiWaitContract.action

    /// 由 contracts 唯一事实源生成的命令元数据。
    let contract = UIKitActionContracts.uiWaitContract

    /// 命令级超时兜底，高于最大业务 timeoutMs（30000），让业务 waitTimeout 先生效。
    var timeoutNanoseconds: UInt64? { 35_000_000_000 }

    /// 执行 UI 等待。
    ///
    /// - Parameter input: 已通过 typed schema 校验的 wait 输入。
    /// - Returns: 满足时返回 satisfied/elapsedMs 等；超时返回 `wait_timeout` 业务失败 envelope。
    func handle(_ input: UIWaitInput) async -> ExploreResult {
        let action = WaitCommand.actionName
        UIKitCommandLogger.info("command", "command \(action) start mode=\(input.mode.rawValue) timeoutMs=\(input.timeoutMs) intervalMs=\(input.intervalMs)")
        do {
            let data = try await UIWaitExecutor.execute(input: input) {
                try UIKitContextProvider.currentContext(action: action)
            }
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogger.error("command", error.failure.logMessage)
            return error.result
        } catch {
            let wrapped = UIKitCommandError.hierarchyUnavailable(action: action, reason: "\(error)")
            UIKitCommandLogger.error("command", wrapped.failure.logMessage)
            return wrapped.result
        }
    }
}
#endif
