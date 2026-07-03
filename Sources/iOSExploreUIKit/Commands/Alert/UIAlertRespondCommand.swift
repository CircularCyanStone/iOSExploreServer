#if canImport(UIKit)
import Foundation
import iOSExploreServer

/// 查询/响应弹窗的命令。
///
/// action 为 `ui.alert.respond`。adapter 只负责解析后的日志、切到 `MainActor` 取上下文并
/// 调用同步 executor；查询逻辑（定位 alert、列出按钮）和响应逻辑（选择按钮、触发 handler、
/// 请求关闭 alert）收敛在 `UIAlertInspector`/executor。
struct AlertRespondCommand: Command {
    /// typed 输入模型。
    typealias Input = UIAlertRespondInput

    /// 固定 action 名。
    static let actionName = "ui.alert.respond"

    /// 命令名。
    let action = AlertRespondCommand.actionName

    /// `help` 命令展示的说明。
    let description = "查询或响应当前 UIAlertController（dryRun=true 返回按钮列表；dryRun=false 触发指定按钮)"

    /// 执行 alert 查询/响应。
    ///
    /// - Parameter input: 已通过 typed schema 校验的 alert respond 输入。
    /// - Returns: 成功时返回 alert 信息或已触发按钮；失败返回业务失败 envelope。
    func handle(_ input: UIAlertRespondInput) async -> ExploreResult {
        UIKitCommandLogging.info("command", "command \(action) start dryRun=\(input.dryRun)")
        do {
            let data = try await MainActor.run {
                let context = try UIKitContextProvider.currentContext(action: AlertRespondCommand.actionName)
                return try UIAlertRespondExecutor.execute(input: input, context: context)
            }
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        } catch {
            let wrapped = UIKitCommandError.hierarchyUnavailable(action: AlertRespondCommand.actionName, reason: "\(error)")
            UIKitCommandLogging.error("command", wrapped.failure.logMessage)
            return wrapped.result
        }
    }
}
#endif
