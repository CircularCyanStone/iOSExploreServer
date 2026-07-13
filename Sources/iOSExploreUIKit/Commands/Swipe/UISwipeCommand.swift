#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// 在 view 或 scrollView 上执行滑动操作的命令。
///
/// action 为 `ui.swipe`。支持三种滑动场景：
/// 1. **UIScrollView swipe actions**：模拟从边缘开始的滑动以触发 leading/trailing swipe actions。
/// 2. **自定义 swipe gesture**：触发挂载在 view 上的 `UISwipeGestureRecognizer`。
/// 3. **普通 pan gesture**：对非 scrollView view 尝试合成 pan gesture 触摸事件。
///
/// adapter 只负责切到 MainActor 取上下文并调用同步 executor，失败由 executor 顶层抛出的
/// `UIKitCommandError` 在此 catch 并转为业务 envelope。
struct SwipeCommand: Command {
    /// typed 输入模型，负责 schema 暴露和 data 解析。
    typealias Input = UISwipeInput

    /// 固定 action 名。
    static let actionName = "ui.swipe"

    /// 命令名。
    let action = SwipeCommand.actionName

    /// `help` 命令展示的说明。
    let description = "在 UIScrollView 上触发 swipe actions (swipe to delete)，或触发 view 上的 swipe gesture"

    /// 执行滑动操作。
    ///
    /// `MainActor.run` 闭包内只调用同步 `execute`（无 `try await`），保证 adapter body
    /// 不持锁、不跨越额外异步边界。executor 抛出的 `UIKitCommandError` 在此 catch。
    ///
    /// - Parameter input: 已通过 typed schema 校验的 swipe 输入。
    /// - Returns: 成功时返回滑动结果；失败时返回业务失败 envelope。
    func handle(_ input: UISwipeInput) async -> ExploreResult {
        let distanceDescription = input.distance.map { String(format: "%.2f", $0) } ?? "default"
        UIKitCommandLogging.info("command", "command \(action) start direction=\(input.direction.rawValue) distance=\(distanceDescription) target=\(input.locator?.logSummary ?? "keyWindow")")
        do {
            let data = try await MainActor.run {
                let context = try UIKitContextProvider.currentContext(action: SwipeCommand.actionName)
                return try UISwipeExecutor.execute(input: input, context: context)
            }
            UIKitCommandLogging.info("command", "command \(action) completed path=\(data["path"]?.stringValue ?? "nil") route=\(data["route"]?.stringValue ?? "unknown")")
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        } catch {
            let wrapped = UIKitCommandError.hierarchyUnavailable(action: SwipeCommand.actionName, reason: "\(error)")
            UIKitCommandLogging.error("command", wrapped.failure.logMessage)
            return wrapped.result
        }
    }
}
#endif
