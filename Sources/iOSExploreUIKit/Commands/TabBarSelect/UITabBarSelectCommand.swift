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
    static let actionName = "ui.tabBar.selectTab"

    /// 命令名。
    let action = UITabBarSelectCommand.actionName

    /// `help` 命令展示的说明。
    let description = "切换 UITabBarController 选中的 tab。通过 index(索引)或 title(标题)定位目标 tab,设置 selectedIndex,并可选触发 delegate 回调(默认触发)。完全走 controller 层,不依赖 view 遍历"

    /// 执行 tab 切换。
    ///
    /// - Parameter input: 已校验的输入模型。
    /// - Returns: 切换结果(previousIndex / selectedIndex / previousTitle / selectedTitle / tabCount)。
    func handle(_ input: UITabBarSelectInput) async throws -> ExploreResult {
        let logSummary = input.index.map { "index=\($0)" } ?? input.title.map { "title=\($0)" } ?? "unknown"
        UIKitCommandLogging.info("command", "command \(action) start \(logSummary) triggerDelegate=\(input.triggerDelegate)")

        do {
            let context = try await MainActor.run {
                try UIKitContextProvider.currentContext(action: action)
            }
            let data = try await MainActor.run {
                try UITabBarSelectExecutor.execute(input: input, context: context)
            }
            UIKitCommandLogging.info("command", "command \(action) completed \(logSummary) selectedIndex=\(data["selectedIndex"]?.doubleValue ?? -1)")
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        }
    }
}
#endif
