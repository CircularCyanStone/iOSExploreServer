#if canImport(UIKit)
import Foundation
import iOSExploreServer

/// 在 `UIScrollView` 系（排除 `UITextView`）上按方向 + 距离滚动的命令。
///
/// action 为 `ui.scroll`。adapter 只负责切到 MainActor 取上下文并调用同步 executor，
/// 业务逻辑（locate → nearestScrollView → setContentOffset → reachedExtent）全部收敛在
/// `UIScrollExecutor` 中。失败由 executor 顶层抛出的 `UIKitCommandError` 在此 catch 并转
/// 为业务 envelope，日志在顶层一处记录。
struct ScrollCommand: Command {
    /// typed 输入模型，负责 schema 暴露和 data 解析。
    typealias Input = UIScrollInput

    /// 固定 action 名。
    static let actionName = "ui.scroll"

    /// 命令名。
    let action = ScrollCommand.actionName

    /// `help` 命令展示的说明。
    let description = "在 UIScrollView 系(排除 UITextView)上按方向+距离滚动"

    /// 执行滚动。
    ///
    /// `MainActor.run` 闭包内只调用同步 `execute`（无 `try await`），保证 adapter body
    /// 不持锁、不跨越额外异步边界。executor 抛出的 `UIKitCommandError` 在此 catch。
    ///
    /// - Parameter input: 已通过 typed schema 校验的 scroll 输入。
    /// - Returns: 成功时返回 container/offset/extent/inset 摘要；失败时返回业务失败 envelope。
    func handle(_ input: UIScrollInput) async -> ExploreResult {
        let amountDescription = input.amount.map { "\($0)" } ?? "half"
        UIKitCommandLogging.info("command", "command \(action) start direction=\(input.direction.rawValue) amount=\(amountDescription) animated=\(input.animated)")
        do {
            let data = try await MainActor.run {
                let context = try UIKitContextProvider.currentContext(action: ScrollCommand.actionName)
                return try UIScrollExecutor.execute(input: input, context: context)
            }
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        } catch {
            let wrapped = UIKitCommandError.hierarchyUnavailable(action: ScrollCommand.actionName, reason: "\(error)")
            UIKitCommandLogging.error("command", wrapped.failure.logMessage)
            return wrapped.result
        }
    }
}
#endif
