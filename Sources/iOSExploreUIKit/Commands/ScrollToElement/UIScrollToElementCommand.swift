#if canImport(UIKit)
import Foundation
import iOSExploreServer

/// 滚动到指定元素可见的命令。
///
/// action 为 `ui.scrollToElement`。adapter 只负责解析后的日志、切到 `MainActor` 取上下文并
/// 调用同步 executor；业务逻辑（容器解析、目标查找、scrollRectToVisible）全部收敛在
/// `UIScrollToElementExecutor` 中。
struct ScrollToElementCommand: Command {
    /// typed 输入模型。
    typealias Input = UIScrollToElementInput

    /// 固定 action 名。
    static let actionName = "ui.scrollToElement"

    /// 命令名。
    let action = ScrollToElementCommand.actionName

    /// `help` 命令展示的说明。
    let description = "滚动到包含指定文本/identifier 的元素可见"

    /// 执行滚动到目标。
    ///
    /// - Parameter input: 已通过 typed schema 校验的 scroll-to-element 输入。
    /// - Returns: 成功时返回 found/target；失败时返回业务失败 envelope。
    func handle(_ input: UIScrollToElementInput) async -> ExploreResult {
        UIKitCommandLogging.info("command", "command \(action) start match=\(input.match.rawValue) valueLength=\(input.value.count)")
        do {
            let data = try await MainActor.run {
                let context = try UIKitContextProvider.currentContext(action: ScrollToElementCommand.actionName)
                return try UIScrollToElementExecutor.execute(input: input, context: context)
            }
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        } catch {
            let wrapped = UIKitCommandError.hierarchyUnavailable(action: ScrollToElementCommand.actionName, reason: "\(error)")
            UIKitCommandLogging.error("command", wrapped.failure.logMessage)
            return wrapped.result
        }
    }
}
#endif
