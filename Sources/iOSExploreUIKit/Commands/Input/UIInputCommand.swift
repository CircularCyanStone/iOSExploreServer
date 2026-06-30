#if canImport(UIKit)
import Foundation
import iOSExploreServer

/// 向文本控件注入文本的命令。
///
/// action 为 `ui.input`。命令只负责解析请求并在 `MainActor.run` 内取上下文、调用
/// `UITextInputExecutor.execute`。执行语义（定位、陈旧校验、白名单、first responder、
/// insertText、委托比对、密码脱敏）全部收敛在 executor 中，本命令不再内联执行逻辑。
///
/// handler 顶层 catch：`UIKitCommandError` 转 envelope（业务码不丢），其它意外错误兜底
/// 为 `hierarchyUnavailable`。失败日志只在此处记一次（与既有 UIKit 命令一致）。
struct InputCommand: Command {
    /// typed 输入模型，负责 schema 暴露和 data 解析。
    typealias Input = UIInputInput

    /// 固定 action 名。
    static let actionName = "ui.input"

    /// 命令名。
    let action = InputCommand.actionName

    /// `help` 命令展示的说明。
    let description = "向 UITextField/UITextView/UISearchTextField 注入文本 (UITextInput.insertText)"

    /// 执行文本注入。
    ///
    /// - Parameter input: 已通过 typed schema 校验的 input 参数。
    /// - Returns: 成功时返回 type + finalText（secure 时为 masked + length）；失败时返回对应业务码 envelope。
    func handle(_ input: UIInputInput) async -> ExploreResult {
        // 日志只记大小与模式，不回原文（可能含敏感信息）。
        UIKitCommandLogging.info("command", "command \(action) start target=\(input.target.logSummary) mode=\(input.mode.rawValue) textLen=\(input.text.count) submit=\(input.submit)")
        do {
            let data = try await MainActor.run {
                let context = try UIKitContextProvider.currentContext(action: InputCommand.actionName)
                return try UITextInputExecutor.execute(input: input, context: context)
            }
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        } catch {
            // executor 只 throw UIKitCommandError；这里兜底任何意外错误，避免裸异常穿到路由层。
            let e = UIKitCommandError.hierarchyUnavailable(action: InputCommand.actionName, reason: "\(error)")
            UIKitCommandLogging.error("command", e.failure.logMessage)
            return e.result
        }
    }
}
#endif
