#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit
import WebKit

/// `ui.webView.eval` 命令的 executor。
///
/// 职责：
/// 1. 定位 WKWebView
/// 2. 陈旧校验（如果提供了 viewSnapshotID）
/// 3. 判断执行模式（sync/async）
/// 4. 执行 JS（带超时）
/// 5. 结果序列化
@MainActor
enum UIWebViewEvalExecutor {
    /// 执行 JavaScript。
    ///
    /// - Parameters:
    ///   - input: 已校验的输入模型。
    ///   - context: 当前 UIKit 查询上下文。
    /// - Returns: 执行结果（result / resultType / mode / executionTime / iosVersion）。
    /// - Throws: `UIKitCommandError` — 定位失败 / 陈旧 / 目标非 WKWebView / 超时 / JS 错误。
    static func execute(input: UIWebViewEvalInput, context: UIKitContextProvider.Context) async throws -> JSON {
        let action = "ui.webView.eval"

        // 1. 定位 WKWebView
        let located = try UIKitLocatorResolver.locate(
            locator: input.target.locator,
            in: context.rootView,
            notFound: {
                UIKitCommandError.targetNotFound(
                    action: action,
                    message: "webView target not found — the page view tree may have changed",
                    logMessage: "ui webView target not found action=\(action) target=\(input.target.logSummary)"
                )
            },
            ambiguous: { count in
                UIKitCommandError.invalidData(
                    action: action,
                    message: "webView target ambiguous count=\(count)"
                )
            }
        )

        // 2. 陈旧校验
        if let viewSnapshotID = input.viewSnapshotID {
            try UIKitActionExecutor.validateViewSnapshot(
                located: located,
                viewSnapshotID: viewSnapshotID,
                context: context,
                action: action
            )
        }

        // 3. 类型校验
        guard let webView = located.view as? WKWebView else {
            UIKitCommandLogging.error("command", "\(action) target is not WKWebView type=\(String(describing: type(of: located.view)))")
            throw UIKitCommandError.invalidData(
                action: action,
                message: "target is not a WKWebView (got \(String(describing: type(of: located.view))))"
            )
        }

        UIKitCommandLogging.info("command", "\(action) located WKWebView")

        // TODO: 执行 JS（后续任务实现）
        return ["placeholder": .bool(true)]
    }
}

#endif
