import Testing
import Foundation
import iOSExploreServer
@testable import iOSExploreUIKit

#if canImport(UIKit) && !os(macOS)
import UIKit
import WebKit

/// 测试用 WKWebView 容器。
private final class TestWebViewController: UIViewController {
    let webView: WKWebView

    init(identifier: String) {
        self.webView = WKWebView()
        super.init(nibName: nil, bundle: nil)
        webView.accessibilityIdentifier = identifier
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(webView)
        webView.frame = view.bounds
    }
}

@Test("定位 WKWebView 成功")
@MainActor
func webViewEvalLocatesWebView() async throws {
    let vc = TestWebViewController(identifier: "test_web")
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    window.rootViewController = vc
    window.makeKeyAndVisible()

    vc.webView.loadHTMLString("<html></html>", baseURL: nil)
    try await Task.sleep(nanoseconds: 1_000_000_000)

    let input = try UIWebViewEvalInput.parse(from: [
        "accessibilityIdentifier": .string("test_web"),
        "script": .string("1 + 1")
    ])

    let context = UIKitContextProvider.Context(
        window: window,
        rootViewController: vc,
        topViewController: vc,
        rootView: vc.view
    )
    let result = try await UIWebViewEvalExecutor.execute(input: input, context: context)

    // 验证返回正确的 sync 结果结构
    guard case .object(let obj) = result else {
        Issue.record("Expected object result")
        return
    }

    #expect(obj["result"] == .double(2))
    #expect(obj["resultType"] == .string("number"))
    #expect(obj["mode"] == .string("sync"))
}

@Test("定位失败返回 target_not_found")
@MainActor
func webViewEvalLocateFailsReturnsError() async throws {
    let context = UIKitTestHost.context { _ in }

    let input = try UIWebViewEvalInput.parse(from: [
        "accessibilityIdentifier": .string("nonexistent"),
        "script": .string("true")
    ])

    await #expect(throws: UIKitCommandError.self) {
        try await UIWebViewEvalExecutor.execute(input: input, context: context)
    }
}

@Test("目标非 WKWebView 返回 invalid_data")
@MainActor
func webViewEvalNonWebViewReturnsError() async throws {
    let context = UIKitTestHost.context { rootView in
        let label = UILabel()
        label.accessibilityIdentifier = "not_webview"
        label.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        rootView.addSubview(label)
    }

    let input = try UIWebViewEvalInput.parse(from: [
        "accessibilityIdentifier": .string("not_webview"),
        "script": .string("true")
    ])

    await #expect(throws: UIKitCommandError.self) {
        try await UIWebViewEvalExecutor.execute(input: input, context: context)
    }
}

@Test("同步执行返回 string")
@MainActor
func webViewEvalSyncReturnsString() async throws {
    let vc = TestWebViewController(identifier: "test_web")
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    window.rootViewController = vc
    window.makeKeyAndVisible()

    // 加载简单 HTML
    vc.webView.loadHTMLString("<html><head><title>Test</title></head></html>", baseURL: nil)
    try await Task.sleep(nanoseconds: 1_000_000_000) // 等待加载

    let input = try UIWebViewEvalInput.parse(from: [
        "accessibilityIdentifier": .string("test_web"),
        "script": .string("'Test'")
    ])

    let context = UIKitContextProvider.Context(
        window: window,
        rootViewController: vc,
        topViewController: vc,
        rootView: vc.view
    )
    let result = try await UIWebViewEvalExecutor.execute(input: input, context: context)

    guard case .object(let obj) = result else {
        Issue.record("Expected object result")
        return
    }

    #expect(obj["result"] == .string("Test"))
    #expect(obj["resultType"] == .string("string"))
    #expect(obj["mode"] == .string("sync"))
}

@Test("同步执行返回 number")
@MainActor
func webViewEvalSyncReturnsNumber() async throws {
    let vc = TestWebViewController(identifier: "test_web")
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    window.rootViewController = vc
    window.makeKeyAndVisible()

    vc.webView.loadHTMLString("<html></html>", baseURL: nil)
    try await Task.sleep(nanoseconds: 1_000_000_000)

    let input = try UIWebViewEvalInput.parse(from: [
        "accessibilityIdentifier": .string("test_web"),
        "script": .string("1 + 1")
    ])

    let context = UIKitContextProvider.Context(
        window: window,
        rootViewController: vc,
        topViewController: vc,
        rootView: vc.view
    )
    let result = try await UIWebViewEvalExecutor.execute(input: input, context: context)

    guard case .object(let obj) = result else {
        Issue.record("Expected object result")
        return
    }

    #expect(obj["result"] == .double(2))
    #expect(obj["resultType"] == .string("number"))
}

@Test("同步执行返回 boolean")
@MainActor
func webViewEvalSyncReturnsBoolean() async throws {
    let vc = TestWebViewController(identifier: "test_web")
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    window.rootViewController = vc
    window.makeKeyAndVisible()

    vc.webView.loadHTMLString("<html></html>", baseURL: nil)
    try await Task.sleep(nanoseconds: 1_000_000_000)

    let input = try UIWebViewEvalInput.parse(from: [
        "accessibilityIdentifier": .string("test_web"),
        "script": .string("true")
    ])

    let context = UIKitContextProvider.Context(
        window: window,
        rootViewController: vc,
        topViewController: vc,
        rootView: vc.view
    )
    let result = try await UIWebViewEvalExecutor.execute(input: input, context: context)

    guard case .object(let obj) = result else {
        Issue.record("Expected object result")
        return
    }

    #expect(obj["result"] == .bool(true))
    #expect(obj["resultType"] == .string("boolean"))
}

@Test("同步执行返回 null")
@MainActor
func webViewEvalSyncReturnsNull() async throws {
    let vc = TestWebViewController(identifier: "test_web")
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    window.rootViewController = vc
    window.makeKeyAndVisible()

    vc.webView.loadHTMLString("<html></html>", baseURL: nil)
    try await Task.sleep(nanoseconds: 1_000_000_000)

    let input = try UIWebViewEvalInput.parse(from: [
        "accessibilityIdentifier": .string("test_web"),
        "script": .string("null")
    ])

    let context = UIKitContextProvider.Context(
        window: window,
        rootViewController: vc,
        topViewController: vc,
        rootView: vc.view
    )
    let result = try await UIWebViewEvalExecutor.execute(input: input, context: context)

    guard case .object(let obj) = result else {
        Issue.record("Expected object result")
        return
    }

    #expect(obj["result"] == .null)
    #expect(obj["resultType"] == .string("null"))
}

@Test("同步执行 JS 错误返回 invalid_data")
@MainActor
func webViewEvalSyncJSErrorReturnsError() async throws {
    let vc = TestWebViewController(identifier: "test_web")
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    window.rootViewController = vc
    window.makeKeyAndVisible()

    vc.webView.loadHTMLString("<html></html>", baseURL: nil)
    try await Task.sleep(nanoseconds: 1_000_000_000)

    let input = try UIWebViewEvalInput.parse(from: [
        "accessibilityIdentifier": .string("test_web"),
        "script": .string("nonexistentFunction()")
    ])

    let context = UIKitContextProvider.Context(
        window: window,
        rootViewController: vc,
        topViewController: vc,
        rootView: vc.view
    )

    await #expect(throws: UIKitCommandError.self) {
        try await UIWebViewEvalExecutor.execute(input: input, context: context)
    }
}

#endif
