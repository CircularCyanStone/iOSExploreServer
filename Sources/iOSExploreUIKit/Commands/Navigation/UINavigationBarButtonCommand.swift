#if canImport(UIKit)
import Foundation
import iOSExploreServer

/// 触发 navigationBar 上的按钮。
///
/// action 为 `ui.navigation.tapBarButton`。adapter 只负责日志、MainActor 切换和错误转换；
/// 真实查找与触发逻辑收敛在 `UINavigationBarButtonExecutor`。
struct NavigationBarButtonCommand: Command {
    /// typed 输入模型，负责 schema 暴露和 data 解析。
    typealias Input = UINavigationBarButtonInput

    /// 固定 action 名。
    static let actionName = "ui.navigation.tapBarButton"

    /// 命令名。
    let action = NavigationBarButtonCommand.actionName

    /// `help` 命令展示的说明。
    let description = "触发导航栏按钮: 按 left/right + index 定位, 可用 title/identifier 防误点"

    /// 执行导航栏按钮触发。
    ///
    /// - Parameter input: 已通过 typed schema 校验的导航栏按钮输入。
    /// - Returns: 成功时返回 performed 与 top 控制器变化；失败时返回业务失败 envelope。
    func handle(_ input: UINavigationBarButtonInput) async -> ExploreResult {
        UIKitCommandLogger.info("command", "command \(action) start \(input.selectorSummary) waitAfterMs=\(input.waitAfterMs)")
        do {
            let data = try await MainActor.run {
                let context = try UIKitContextProvider.currentContext(action: NavigationBarButtonCommand.actionName)
                return try UINavigationBarButtonExecutor.execute(input: input, context: context)
            }
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogger.error("command", error.failure.logMessage)
            return error.result
        } catch {
            let wrapped = UIKitCommandError.hierarchyUnavailable(action: NavigationBarButtonCommand.actionName, reason: "\(error)")
            UIKitCommandLogger.error("command", wrapped.failure.logMessage)
            return wrapped.result
        }
    }
}
#endif
