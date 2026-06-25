#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// 模拟页面点击语义的命令。
///
/// action 为 `ui.tap`。命令只负责解析请求并构造 `UIKitActionPlan.tap`，再
/// `await UIKitActionExecutor.execute(plan)`。第一版的执行语义（取 Context、resolve locator、
/// hit-test、对 UIControl 派发 `touchUpInside` fallback、对非 UIControl 返回不支持）全部
/// 收敛在 `UIKitActionExecutor` 中，本命令不再内联执行逻辑。
struct UITapCommand: Command {
    /// typed 输入模型，负责 schema 暴露和 data 解析。
    typealias Input = UITapInput

    /// 固定 action 名。
    static let actionName = "ui.tap"

    /// 命令名。
    let action = UITapCommand.actionName

    /// `help` 命令展示的说明。
    let description = "按 accessibilityIdentifier、path 或 window 坐标执行点击"

    /// 执行 tap。
    ///
    /// 解析请求构造 `UIKitActionPlan.tap`，在 MainActor 上 `await` executor。失败时返回明确原因。
    ///
    /// - Parameter input: 已通过 typed schema 校验的 tap 输入。
    /// - Returns: 成功时返回命中目标与派发方式；失败时返回明确原因。
    func handle(_ input: UITapInput) async throws -> ExploreResult {
        UIKitCommandLogging.info("command", "command \(action) start target=\(input.target.logSummary)")
        do {
            let plan = UIKitActionPlan.tap(locator: input.target.locator, snapshotID: input.snapshotID)
            let data = try await UIKitActionExecutor.execute(plan)
            UIKitCommandLogging.info("command", "command \(action) completed target=\(input.target.logSummary) dispatchMode=\(data["dispatchMode"]?.stringValue ?? "unknown")")
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        }
    }
}
#endif
