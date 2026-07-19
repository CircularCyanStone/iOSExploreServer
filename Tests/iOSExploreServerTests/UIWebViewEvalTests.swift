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

    // 暂时只验证不抛错
    #expect(result["placeholder"] == .bool(true))
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

#endif
