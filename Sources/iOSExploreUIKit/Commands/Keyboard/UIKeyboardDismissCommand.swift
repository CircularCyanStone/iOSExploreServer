#if canImport(UIKit)
import Foundation
import iOSExploreServer

/// 收起当前 first responder / 键盘的命令。
///
/// action 为 `ui.keyboard.dismiss`。adapter 只负责解析后的日志、切到 `MainActor` 取上下文并
/// 调用同步 executor；业务逻辑（first responder 查找、策略执行、settle 等待）全部收敛在
/// `UIKeyboardDismissExecutor` 中。
struct KeyboardDismissCommand: Command {
    /// typed 输入模型，负责 schema 暴露和 data 解析。
    typealias Input = UIKeyboardDismissInput

    /// 固定 action 名。
    static let actionName = "ui.keyboard.dismiss"

    /// 命令名。
    let action = KeyboardDismissCommand.actionName

    /// `help` 命令展示的说明。
    let description = "收起当前 first responder / 键盘"

    /// 执行键盘收起。
    ///
    /// - Parameter input: 已通过 typed schema 校验的 keyboard dismiss 输入。
    /// - Returns: 成功时返回 dismissed 与 first responder 类型变化；失败时返回业务失败 envelope。
    func handle(_ input: UIKeyboardDismissInput) async -> ExploreResult {
        UIKitCommandLogger.info("command", "command \(action) start strategy=\(input.strategy.rawValue) waitAfterMs=\(input.waitAfterMs)")
        do {
            let data = try await MainActor.run {
                let context = try UIKitContextProvider.currentContext(action: KeyboardDismissCommand.actionName)
                return try UIKeyboardDismissExecutor.execute(input: input, context: context)
            }
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogger.error("command", error.failure.logMessage)
            return error.result
        } catch {
            let wrapped = UIKitCommandError.hierarchyUnavailable(action: KeyboardDismissCommand.actionName, reason: "\(error)")
            UIKitCommandLogger.error("command", wrapped.failure.logMessage)
            return wrapped.result
        }
    }
}
#endif
