#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// 选择 UIPickerView 指定行的命令。
///
/// action 为 `ui.picker.selectRow`。通过 identifier/path 定位 UIPickerView,在指定 `component`
/// 用 `row`(索引)或 `title`(标题)选行,并触发 `didSelectRow` delegate。UIPickerView 不是
/// UIControl,`ui.inspect` 不为其声明 action,`ui.control.sendAction` 不适用,故本命令是其
/// 唯一的程序选行入口。
struct UIPickerSelectRowCommand: Command {
    /// typed 输入模型。
    typealias Input = UIPickerSelectRowInput

    /// 固定 action 名。
    static let actionName = "ui.picker.selectRow"

    /// 命令名。
    let action = UIPickerSelectRowCommand.actionName

    /// `help` 命令展示的说明。
    let description = "选择 UIPickerView 指定列的某一行。目标用 accessibilityIdentifier 或 path 定位;行用 row(0-based 索引)或 title(读 dataSource/delegate 的 titleForRow 比对首个匹配)二选一;component 必填(列索引)。选行后触发 didSelectRow delegate。viewSnapshotID 可选,支持陈旧校验"

    /// 执行行选择。
    func handle(_ input: UIPickerSelectRowInput) async -> ExploreResult {
        let source = input.row.map { _ in "row" } ?? "title"
        UIKitCommandLogger.info("command", "command \(action) start target=\(input.target.logSummary) component=\(input.component) source=\(source) animated=\(input.animated)")
        do {
            let data = try await MainActor.run {
                let context = try UIKitContextProvider.currentContext(action: UIPickerSelectRowCommand.actionName)
                return try UIPickerSelectRowExecutor.execute(input: input, context: context)
            }
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogger.error("command", error.failure.logMessage)
            return error.result
        } catch {
            // executor 只 throw UIKitCommandError;兜底任何意外错误,避免裸异常穿到路由层。
            let e = UIKitCommandError.hierarchyUnavailable(action: UIPickerSelectRowCommand.actionName, reason: "\(error)")
            UIKitCommandLogger.error("command", e.failure.logMessage)
            return e.result
        }
    }
}
#endif
