#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// 设置 UIDatePicker 日期的命令。
///
/// action 为 `ui.datePicker.setDate`。通过 identifier/path 定位 UIDatePicker,用 `date`
/// (ISO 8601)或分量(`year`/`month`/`day`/`hour`/`minute`)设置日期,并触发 `.valueChanged`。
/// UIDatePicker 在 `ui.inspect` 里不暴露可设值 action,`ui.control.sendAction` 的 value 也不
/// 支持 UIDatePicker,故本命令是其唯一的程序设值入口。
struct UIDatePickerSetDateCommand: Command {
    /// typed 输入模型。
    typealias Input = UIDatePickerSetDateInput

    /// 固定 action 名。
    static let actionName = UIKitActionContracts.uiDatePickerSetDateContract.action

    /// 由 contracts 唯一事实源生成的命令元数据。
    let contract = UIKitActionContracts.uiDatePickerSetDateContract

    /// 执行日期设置。
    func handle(_ input: UIDatePickerSetDateInput) async -> ExploreResult {
        let source = input.date != nil ? "date=iso" : "components"
        UIKitCommandLogger.info("command", "command \(action) start target=\(input.target.logSummary) source=\(source) animated=\(input.animated)")
        do {
            let data = try await MainActor.run {
                let context = try UIKitContextProvider.currentContext(action: UIDatePickerSetDateCommand.actionName)
                return try UIDatePickerSetDateExecutor.execute(input: input, context: context)
            }
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogger.error("command", error.failure.logMessage)
            return error.result
        } catch {
            // executor 只 throw UIKitCommandError;兜底任何意外错误,避免裸异常穿到路由层。
            let e = UIKitCommandError.hierarchyUnavailable(action: UIDatePickerSetDateCommand.actionName, reason: "\(error)")
            UIKitCommandLogger.error("command", e.failure.logMessage)
            return e.result
        }
    }
}
#endif
