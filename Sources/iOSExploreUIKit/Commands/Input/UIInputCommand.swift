#if canImport(UIKit)
import Foundation
import iOSExploreServer

/// 向文本控件批量注入文本的命令。
///
/// action 为 `ui.input`。命令只负责解析请求并在 `MainActor.run` 内取上下文、调用
/// `UITextInputExecutor.execute`。执行语义（批量顺序、定位、陈旧校验、白名单、first responder、
/// insertText、委托比对、密码脱敏）全部收敛在 executor 中，本命令不再内联执行逻辑。
///
/// handler 顶层 catch：`UIKitCommandError` 转 envelope（业务码不丢），其它意外错误兜底
/// 为 `hierarchyUnavailable`。批量命令的顶层生命周期日志由 `execute(input:context:)` 统一记录，
/// 避免 command adapter 与 executor 重复记录同一条 start/complete 日志。
struct InputCommand: Command {
    /// typed 输入模型，负责 schema 暴露和 data 解析。
    typealias Input = UIInputInput

    /// 固定 action 名。
    static let actionName = "ui.input"

    /// 命令名。
    let action = InputCommand.actionName

    /// `help` 命令展示的说明。
    let description = "按顺序向多个 UITextField/UITextView/UISearchTextField 注入文本 (UITextInput.insertText)。顶层传 fields 数组，单字段输入也必须放进数组；viewSnapshotID 可选，stopOnFailure 默认 true。"

    /// 执行文本注入。
    ///
    /// - Parameter input: 已通过 typed schema 校验的 input 参数。
    /// - Returns: 成功时返回批量结果 JSON；失败时返回对应业务码 envelope。
    func handle(_ input: UIInputInput) async -> ExploreResult {
        do {
            return try await MainActor.run {
                let context = try UIKitContextProvider.currentContext(action: InputCommand.actionName)
                return InputCommand.execute(input: input, context: context)
            }
        } catch {
            // context 获取失败发生在批量执行入口之外，仍由 handler 统一兜底，避免裸异常穿到路由层。
            let e = UIKitCommandError.hierarchyUnavailable(action: InputCommand.actionName, reason: "\(error)")
            UIKitCommandLogger.error("command", e.failure.logMessage)
            return e.result
        }
    }

    /// 在已取得的 MainActor UIKit context 上执行一次批量输入并记录顶层生命周期。
    ///
    /// - Parameters:
    ///   - input: 已通过 typed schema 校验的输入。
    ///   - context: 当前 UIKit 查询上下文，调用方必须在 MainActor 上取得。
    /// - Returns: 成功时返回批量结果；UIKit 执行失败时返回对应业务码 envelope。
    @MainActor
    static func execute(input: UIInputInput, context: UIKitContextProvider.Context) -> ExploreResult {
        // 顶层 start 只在命令层记录一次；executor 只记录字段级步骤。
        UIKitCommandLogger.info("command", "command \(actionName) start fields=\(input.fields.count) stopOnFailure=\(input.stopOnFailure) viewSnapshot=\(input.viewSnapshotID ?? "nil")")
        do {
            let data = try UITextInputExecutor.execute(input: input, context: context)
            let completed = data["completed"]?.boolValue ?? false
            let failedIndex = data["failedIndex"]?.doubleValue.map { String(Int($0)) } ?? "nil"
            UIKitCommandLogger.info("command", "command \(actionName) completed fields=\(input.fields.count) completed=\(completed) failedIndex=\(failedIndex)")
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogger.error("command", error.failure.logMessage)
            return error.result
        } catch {
            // executor 只 throw UIKitCommandError；这里兜底任何意外错误，避免裸异常穿到路由层。
            let e = UIKitCommandError.hierarchyUnavailable(action: actionName, reason: "\(error)")
            UIKitCommandLogger.error("command", e.failure.logMessage)
            return e.result
        }
    }
}
#endif
