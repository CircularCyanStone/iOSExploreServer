#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.tap` 默认激活动作命令。
///
/// action 为 `ui.tap`。命令只负责解析请求并构造 `UIKitActionPlan.tap`，再
/// `await UIKitActionExecutor.execute(plan)`。`ui.tap` 是 Agent 层默认激活动作：对
/// `ui.viewTargets` 签发的 canonical target 执行其类型对应的默认激活路由（UIButton →
/// touchUpInside、UISwitch → 翻转 + valueChanged、文本输入 → 聚焦）。它不是触摸注入、
/// 不接受坐标、不做 hit-test、不找祖先 UIControl fallback。执行逻辑全部收敛在
/// `UIKitActionExecutor` 中，本命令不再内联执行逻辑。
struct UITapCommand: Command {
    /// typed 输入模型，负责 schema 暴露和 data 解析。
    typealias Input = UITapInput

    /// 固定 action 名。
    static let actionName = "ui.tap"

    /// 命令名。
    let action = UITapCommand.actionName

    /// `help` 命令展示的说明。
    let description = "对已发现的目标执行默认激活动作 (按钮/开关/输入框)。调用前必须先调 ui.viewTargets，并把同响应返回的 viewSnapshotID 原样传入"

    /// 执行 tap 默认激活。
    ///
    /// 解析请求构造 `UIKitActionPlan.tap`（locator + viewSnapshotID），在 MainActor 上
    /// `await` executor。失败时返回明确原因。
    ///
    /// - Parameter input: 已通过 typed schema 校验的 tap 输入。
    /// - Returns: 成功时返回 activationRoute/type 等；失败时返回明确原因。
    func handle(_ input: UITapInput) async throws -> ExploreResult {
        UIKitCommandLogging.info("command", "command \(action) start target=\(input.target.logSummary)")
        do {
            let plan = UIKitActionPlan.tap(locator: input.target.locator,
                                            viewSnapshotID: input.viewSnapshotID)
            let data = try await UIKitActionExecutor.execute(plan)
            UIKitCommandLogging.info("command", "command \(action) completed target=\(input.target.logSummary) activationRoute=\(data["activationRoute"]?.stringValue ?? "unknown")")
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        }
    }
}
#endif
