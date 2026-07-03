#if canImport(UIKit)
import Foundation
import iOSExploreServer

/// 等待多个可能结局中第一个命中的命令。
///
/// action 为 `ui.waitAny`。adapter 只负责解析后的日志与上下文注入；多条件轮询、deadline、
/// cancellation 处理全部收敛在 `UIWaitAnyExecutor` 中，单条件判断原语复用 `UIWaitExecutor.evaluate`。
struct WaitAnyCommand: Command {
    /// typed 输入模型，负责 schema 暴露和 data 解析。
    typealias Input = UIWaitAnyInput

    /// 固定 action 名。
    static let actionName = "ui.waitAny"

    /// 命令名。
    let action = WaitAnyCommand.actionName

    /// `help` 命令展示的说明。
    let description = "在一个轮询循环内等待多个条件, 第一个满足立即返回(matchedID/matchedIndex)"

    /// 命令级超时兜底，高于最大业务 timeoutMs（30000），让业务 waitTimeout 先生效。
    var timeoutNanoseconds: UInt64? { 35_000_000_000 }

    /// 执行多条件等待。
    ///
    /// - Parameter input: 已通过 typed schema 校验的 waitAny 输入。
    /// - Returns: 命中时返回 satisfied/matchedID/matchedIndex/matchedMode/elapsedMs/attempts；
    ///   超时返回 `wait_timeout` 业务失败 envelope。
    func handle(_ input: UIWaitAnyInput) async -> ExploreResult {
        let action = WaitAnyCommand.actionName
        UIKitCommandLogging.info("command", "command \(action) start conditions=\(input.conditions.count) timeoutMs=\(input.timeoutMs) intervalMs=\(input.intervalMs)")
        do {
            let data = try await UIWaitAnyExecutor.execute(input: input) {
                try UIKitContextProvider.currentContext(action: action)
            }
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        } catch {
            let wrapped = UIKitCommandError.hierarchyUnavailable(action: action, reason: "\(error)")
            UIKitCommandLogging.error("command", wrapped.failure.logMessage)
            return wrapped.result
        }
    }
}
#endif
