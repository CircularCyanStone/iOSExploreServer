#if canImport(UIKit)
import Foundation
import iOSExploreServer

/// 返回上一页的命令。
///
/// action 为 `ui.navigation.back`。adapter 只负责解析后的日志、切到 `MainActor` 取上下文并
/// 调用同步 executor；业务逻辑（dismiss / pop 决策、转场等待）全部收敛在
/// `UINavigationBackExecutor` 中。
struct NavigationBackCommand: Command {
    /// typed 输入模型，负责 schema 暴露和 data 解析。
    typealias Input = UINavigationBackInput

    /// 固定 action 名。
    static let actionName = "ui.navigation.back"

    /// 命令名。
    let action = NavigationBackCommand.actionName

    /// `help` 命令展示的说明。
    let description = "返回上一页: auto 先 dismiss 再 navigation pop"

    /// 执行导航返回。
    ///
    /// - Parameter input: 已通过 typed schema 校验的 navigation back 输入。
    /// - Returns: 成功时返回 performed 与 top 控制器变化；失败时返回业务失败 envelope。
    func handle(_ input: UINavigationBackInput) async -> ExploreResult {
        UIKitCommandLogging.info("command", "command \(action) start strategy=\(input.strategy.rawValue) animated=\(input.animated) waitAfterMs=\(input.waitAfterMs)")
        do {
            let data = try await MainActor.run {
                let context = try UIKitContextProvider.currentContext(action: NavigationBackCommand.actionName)
                return try UINavigationBackExecutor.execute(input: input, context: context)
            }
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        } catch {
            let wrapped = UIKitCommandError.hierarchyUnavailable(action: NavigationBackCommand.actionName, reason: "\(error)")
            UIKitCommandLogging.error("command", wrapped.failure.logMessage)
            return wrapped.result
        }
    }
}
#endif
