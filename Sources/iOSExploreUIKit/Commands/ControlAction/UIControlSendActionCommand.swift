#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// 向指定 UIControl 发送 target-action 事件的命令。
///
/// action 为 `ui.control.sendAction`。命令只负责解析请求并构造
/// `UIKitActionPlan.controlEvent`，再 `await UIKitActionExecutor.execute(plan)`。执行语义
/// （取 Context、resolve locator、校验 `UIControl`、`sendActions(for:)`）全部收敛在
/// `UIKitActionExecutor` 中，本命令不再内联执行逻辑。
struct UIControlSendActionCommand: Command {
    /// typed 输入模型，负责 wire 校验和 data 解析。
    typealias Input = UIControlSendActionInput

    /// 固定 action 名。
    static let actionName = UIKitActionContracts.uiControlSendActionContract.action

    /// 由 contracts 唯一事实源生成的命令元数据。
    let contract = UIKitActionContracts.uiControlSendActionContract

    /// 执行 sendAction。
    ///
    /// 解析请求构造 `UIKitActionPlan.controlEvent`，在 MainActor 上 `await` executor。
    ///
    /// - Parameter input: 已通过 generated wire 校验的 control action 输入。
    /// - Returns: 成功时返回目标摘要；失败时返回 `invalid_data` 或 UI 不可用错误。
    func handle(_ input: UIControlSendActionInput) async throws -> ExploreResult {
        UIKitCommandLogger.info("command", "command \(action) start target=\(input.target.logSummary) event=\(input.event.rawValue) valueProvided=\(input.value != nil)")
        do {
            let plan = UIKitActionPlan.controlEvent(locator: input.target.locator,
                                                    event: input.event,
                                                    value: input.value,
                                                    viewSnapshotID: input.viewSnapshotID)
            let data = try await UIKitActionExecutor.execute(plan)
            UIKitCommandLogger.info("command", "command \(action) completed target=\(input.target.logSummary) event=\(input.event.rawValue) valueProvided=\(input.value != nil) type=\(data["type"]?.stringValue ?? "unknown")")
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogger.error("command", error.failure.logMessage)
            return error.result
        }
    }
}
#endif
