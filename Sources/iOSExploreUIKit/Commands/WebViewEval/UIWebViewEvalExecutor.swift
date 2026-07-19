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
    static func execute(input: UIWebViewEvalInput, context: UIKitContextProvider.Context) async throws -> JSONValue {
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

        // 执行 JS
        let startTime = Date()

        if let script = input.script {
            // 同步模式
            UIKitCommandLogging.info("command", "\(action) executing sync script")
            let result = try await executeSync(webView: webView, script: script, timeout: input.timeout, action: action)
            let elapsed = Date().timeIntervalSince(startTime)

            return .object(JSON([
                "result": result.value,
                "resultType": .string(result.type),
                "mode": .string("sync"),
                "executionTime": .double(elapsed),
                "iosVersion": .string(UIDevice.current.systemVersion)
            ]))
        } else {
            // TODO: 异步模式（后续任务）
            throw UIKitCommandError.invalidData(action: action, message: "async mode not implemented yet")
        }
    }

    /// 同步执行 JS（使用 async/await 避免阻塞主线程）。
    private static func executeSync(webView: WKWebView, script: String, timeout: TimeInterval, action: String) async throws -> (value: JSONValue, type: String) {
        return try await withThrowingTaskGroup(of: Result<(Any?, Error?), Error>.self) { group in
            // JS 执行任务
            group.addTask {
                let result = await withCheckedContinuation { (continuation: CheckedContinuation<(Any?, Error?), Never>) in
                    webView.evaluateJavaScript(script) { result, error in
                        continuation.resume(returning: (result, error))
                    }
                }
                return .success(result)
            }

            // 超时任务
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return .failure(TimeoutError())
            }

            // 等待第一个完成的任务
            guard let firstResult = try await group.next() else {
                throw UIKitCommandError.invalidData(action: action, message: "unexpected group completion")
            }

            group.cancelAll()

            switch firstResult {
            case .success(let (jsResult, jsError)):
                if let error = jsError {
                    UIKitCommandLogging.error("command", "\(action) JS execution failed error=\(error)")
                    throw UIKitCommandError.invalidData(action: action, message: "JS execution failed: \(error.localizedDescription)")
                }
                return serializeJSResult(jsResult)
            case .failure:
                UIKitCommandLogging.error("command", "\(action) JS execution timed out after \(timeout)s")
                throw UIKitCommandError.invalidData(action: action, message: "JS execution timed out after \(Int(timeout))s (elapsed \(String(format: "%.2f", timeout))s)")
            }
        }
    }

    /// 超时错误。
    private struct TimeoutError: Error {}

    /// 序列化 JS 结果。
    private static func serializeJSResult(_ result: Any?) -> (value: JSONValue, type: String) {
        if result == nil || result is NSNull {
            return (.null, "null")
        }

        if let number = result as? NSNumber {
            // 使用 CFNumberGetType 区分 Bool / Int / Double
            let cfType = CFNumberGetType(number as CFNumber)
            if cfType == .charType {
                // Bool
                return (.bool(number.boolValue), "boolean")
            } else {
                // Number
                return (.double(number.doubleValue), "number")
            }
        }

        if let string = result as? String {
            return (.string(string), "string")
        }

        if let array = result as? [Any] {
            let jsonArray = array.map { serializeJSResult($0).value }
            return (.array(jsonArray), "array")
        }

        if let dict = result as? [String: Any] {
            let jsonDict = dict.mapValues { serializeJSResult($0).value }
            return (.object(JSON(jsonDict)), "object")
        }

        // 不可序列化类型（DOM 节点、Function 等）
        UIKitCommandLogging.info("command", "JS result not serializable type=\(String(describing: type(of: result)))")
        return (.null, "object")
    }
}

#endif
