//
//  WebViewTestViewController.swift
//  SPMExample
//
//  WebView 测试页：承载一个 WKWebView，加载包含 JSBridge 的 HTML，
//  供 ui.webView.eval 端到端验证。
//

import UIKit
import WebKit

/// `ui.webView.eval` 命令的端到端测试载体页。
///
/// 页面包含：
/// - 一个 WKWebView（占高度 60%），加载带 JSBridge 模拟的 HTML
/// - 一个 resultLabel（底部），显示 JSBridge 调用结果
///
/// HTML 内容包括：
/// - `window.testBridge`：模拟 JSBridge，提供 `showAlert` 和 `navigate` 方法
/// - `window.testData`：全局测试数据（userId / userName）
/// - 两个按钮：触发 Native Alert、跳转到 Native 详情页
///
/// 验证流程：
/// 1. 同步 JS：`ui.webView.eval` 执行 `document.title`，返回页面标题
/// 2. 触发 JSBridge：执行 `window.testBridge.showAlert(...)`，验证方法调用
/// 3. 读取全局状态：执行 `window.testData`，返回对象
/// 4. DOM 操作：修改元素内容，读取状态文本
final class WebViewTestViewController: UIViewController {
    private let webView: WKWebView
    private let resultLabel: UILabel

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        self.webView = WKWebView()
        self.resultLabel = UILabel()
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "WebView 测试"
        view.backgroundColor = .systemBackground

        // 配置 WebView
        webView.accessibilityIdentifier = "webview_test"
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        // 配置结果 label
        resultLabel.accessibilityIdentifier = "bridge_result"
        resultLabel.translatesAutoresizingMaskIntoConstraints = false
        resultLabel.textAlignment = .center
        resultLabel.numberOfLines = 0
        resultLabel.text = "等待 JSBridge 调用..."
        view.addSubview(resultLabel)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.6),

            resultLabel.topAnchor.constraint(equalTo: webView.bottomAnchor, constant: 20),
            resultLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            resultLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])

        loadTestHTML()
    }

    private func loadTestHTML() {
        guard let htmlPath = Bundle.main.path(forResource: "webview_test", ofType: "html"),
              let htmlString = try? String(contentsOfFile: htmlPath, encoding: .utf8) else {
            resultLabel.text = "❌ 无法加载测试 HTML 文件"
            resultLabel.textColor = .systemRed
            return
        }
        webView.loadHTMLString(htmlString, baseURL: Bundle.main.bundleURL)
    }
}
