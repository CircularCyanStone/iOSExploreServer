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
    /// typed 输入模型，负责 schema 暴露和 data 解析。
    typealias Input = UIControlSendActionInput

    /// 固定 action 名。
    static let actionName = "ui.control.sendAction"

    /// 命令名。
    let action = UIControlSendActionCommand.actionName

    /// `help` 命令展示的说明。
    let description = "向指定 UIControl 发送 target-action 事件"

    /// 执行 sendAction。
    ///
    /// 解析请求构造 `UIKitActionPlan.controlEvent`，在 MainActor 上 `await` executor。
    ///
    /// - Parameter input: 已通过 typed schema 校验的 control action 输入。
    /// - Returns: 成功时返回目标摘要；失败时返回 `invalid_data` 或 UI 不可用错误。
    func handle(_ input: UIControlSendActionInput) async throws -> ExploreResult {
        UIKitCommandLogging.info("command", "command \(action) start target=\(input.target.logSummary) event=\(input.event.rawValue)")
        do {
            let plan = UIKitActionPlan.controlEvent(locator: input.target.locator,
                                                    event: input.event,
                                                    snapshotID: input.snapshotID)
            let data = try await UIKitActionExecutor.execute(plan)
            UIKitCommandLogging.info("command", "command \(action) completed target=\(input.target.logSummary) event=\(input.event.rawValue) type=\(data["type"]?.stringValue ?? "unknown")")
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        }
    }
}
#endif
