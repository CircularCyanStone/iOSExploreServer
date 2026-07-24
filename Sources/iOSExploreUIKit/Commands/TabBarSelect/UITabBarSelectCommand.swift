#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// 切换 UITabBarController 选中 tab 的命令。
///
/// action 为 `ui.tabBar.selectTab`。完全走 controller 层操作(基于 ui_controllers 能拿到
/// UITabBarController 的事实),不依赖 view 子树遍历,因此不受 modal 场景 resolver 盲区影响。
struct UITabBarSelectCommand: Command {
    /// typed 输入模型。
    typealias Input = UITabBarSelectInput

    /// 固定 action 名。
    static let actionName = UIKitActionContracts.uiTabBarSelectTabContract.action

    /// 由 contracts 唯一事实源生成的命令元数据。
    let contract = UIKitActionContracts.uiTabBarSelectTabContract

    /// 执行 tab 切换。
    ///
    /// - Parameter input: 已校验的输入模型。
    /// - Returns: 切换结果(previousIndex / selectedIndex / previousTitle / selectedTitle / tabCount)。
    func handle(_ input: UITabBarSelectInput) async throws -> ExploreResult {
        let logSummary = input.index.map { "index=\($0)" } ?? input.title.map { "title=\($0)" } ?? "unknown"
        UIKitCommandLogger.info("command", "command \(action) start \(logSummary) triggerDelegate=\(input.triggerDelegate)")

        do {
            let context = try await MainActor.run {
                try UIKitContextProvider.currentContext(action: action)
            }
            let data = try await MainActor.run {
                try UITabBarSelectExecutor.execute(input: input, context: context)
            }
            UIKitCommandLogger.info("command", "command \(action) completed \(logSummary) selectedIndex=\(data["selectedIndex"]?.doubleValue ?? -1)")
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogger.error("command", error.failure.logMessage)
            return error.result
        }
    }
}
#endif
