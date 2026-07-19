#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// 在 WKWebView 中执行 JavaScript 的命令。
///
/// action 为 `ui.webView.eval`。支持两种模式：
/// - `script`（同步）：直接执行 JS 代码
/// - `function`（异步）：执行 async function body（iOS 14+，自动降级）
struct UIWebViewEvalCommand: Command {
    /// typed 输入模型。
    typealias Input = UIWebViewEvalInput

    /// 固定 action 名。
    static let actionName = "ui.webView.eval"

    /// 命令名。
    let action = UIWebViewEvalCommand.actionName

    /// `help` 命令展示的说明。
    let description = "在 WKWebView 中执行 JavaScript。支持 script（同步）和 function（异步，iOS 14+）两种模式。通过 accessibilityIdentifier 或 path 定位 WKWebView，返回执行结果及类型信息。支持 timeout（1-30s）和 viewSnapshotID 陈旧校验"

    /// 执行 JS。
    func handle(_ input: UIWebViewEvalInput) async -> ExploreResult {
        let mode = input.script != nil ? "script" : "function"
        UIKitCommandLogging.info("command", "command \(action) start target=\(input.target.logSummary) mode=\(mode) timeout=\(input.timeout)")
        do {
            let data = try await executeOnMainActor(input: input)
            UIKitCommandLogging.info("command", "command \(action) completed")
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        } catch {
            // executor 只 throw UIKitCommandError；兜底任何意外错误。
            let e = UIKitCommandError.hierarchyUnavailable(action: UIWebViewEvalCommand.actionName, reason: "\(error)")
            UIKitCommandLogging.error("command", e.failure.logMessage)
            return e.result
        }
    }

    /// 在 MainActor 上取上下文并执行 webView.eval executor。
    ///
    /// 独立 `@MainActor async throws` 方法：`handle`（非隔离）里 `await` 调用时自动 hop 到
    /// MainActor。executor 内部的 `await` 挂起时会 yield MainActor（让出 actor），
    /// 使并发到达的其它 `ui.*` 命令能插队执行。
    ///
    /// - Parameter input: 已通过 typed schema 校验的 webView.eval 输入。
    /// - Returns: JS 执行结果 JSON。
    /// - Throws: 定位/陈旧/超时等 `UIKitCommandError`。
    @MainActor
    private func executeOnMainActor(input: UIWebViewEvalInput) async throws -> JSON {
        let context = try UIKitContextProvider.currentContext(action: UIWebViewEvalCommand.actionName)
        let result = try await UIWebViewEvalExecutor.execute(input: input, context: context)
        // executor 返回 JSONValue，需要转为 JSON
        guard case .object(let json) = result else {
            throw UIKitCommandError.hierarchyUnavailable(
                action: UIWebViewEvalCommand.actionName,
                reason: "executor returned non-object JSONValue"
            )
        }
        return json
    }
}
#endif
