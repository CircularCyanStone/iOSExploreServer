#if canImport(UIKit)
import Foundation
import iOSExploreServer

/// 触发 navigationBar 上的按钮。
///
/// action 为 `ui.navigation.tapBarButton`。adapter 只负责日志、MainActor 切换和错误转换；
/// 真实查找与触发逻辑收敛在 `UINavigationBarButtonExecutor`。
struct NavigationBarButtonCommand: Command {
    /// typed 输入模型，负责 wire 校验和 data 解析。
    typealias Input = UINavigationBarButtonInput

    /// 固定 action 名。
    static let actionName = UIKitActionContracts.uiNavigationTapBarButtonContract.action

    /// 由 contracts 唯一事实源生成的命令元数据。
    let contract = UIKitActionContracts.uiNavigationTapBarButtonContract

    /// 执行导航栏按钮触发。
    ///
    /// - Parameter input: 已通过 generated wire 校验的导航栏按钮输入。
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
