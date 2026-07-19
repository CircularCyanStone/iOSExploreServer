# ui.webView.eval 命令实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 iOSExploreServer 实现 `ui.webView.eval` 命令，支持在 WKWebView 中执行 JavaScript（同步和异步模式）

**Architecture:** 遵循 iOSExploreUIKit 的三层架构（Input → Executor → Command），支持 iOS 14+ 的异步 JS 执行，iOS 14 以下自动降级到同步模式

**Tech Stack:** Swift 6.2, WKWebView, Swift Concurrency, Swift Testing

## Global Constraints

- Swift 6.2 严格并发（跨边界模型 `Sendable`，共享状态用 `Mutex`，闭包 `@Sendable`）
- iOS 部署目标 26.2+
- Debug-only 工具（`#if DEBUG` 隔离私有 API）
- 遵循 iOSExploreUIKit 三层架构（Input / Executor / Command）
- 所有文件包在 `#if canImport(UIKit)` 内
- 日志使用 `UIKitCommandLogging`，category 为 `"command"`
- 超时范围 1-30 秒，默认 5 秒
- 错误码：`target_not_found` / `invalid_data` / `stale_locator`

---

## File Structure

```
Sources/iOSExploreUIKit/Commands/WebViewEval/
├── UIWebViewEvalInput.swift       (~180 行)
│   └── 输入模型：参数定义、schema、parse 逻辑
├── UIWebViewEvalExecutor.swift    (~280 行)
│   └── 核心执行：定位、陈旧校验、同步/异步 JS 执行、超时处理、结果序列化
└── UIWebViewEvalCommand.swift     (~50 行)
    └── 薄 adapter：日志、错误处理、调用 executor
```

**注册位置**：`Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift`

**测试文件**：
- 单元测试（macOS）：`Tests/iOSExploreServerTests/UIWebViewEvalInputTests.swift`
- 集成测试（iOS）：`Tests/iOSExploreServerTests/UIWebViewEvalTests.swift`
- 端到端测试：`Examples/SPMExample/SPMExample/WebViewTestViewController.swift`

---

### Task 1: UIWebViewEvalInput（输入模型 + 单元测试）

**Files:**
- Create: `Sources/iOSExploreUIKit/Commands/WebViewEval/UIWebViewEvalInput.swift`
- Create: `Tests/iOSExploreServerTests/UIWebViewEvalInputTests.swift`

**Interfaces:**
- Consumes: `UIKitViewLookupTarget`, `CommandInput`, `CommandFields`, `UIKitLocatorFields`
- Produces: `UIWebViewEvalInput` struct with:
  - `target: UIKitViewLookupTarget`
  - `viewSnapshotID: String?`
  - `script: String?`
  - `function: String?`
  - `arguments: [String: Any]?`
  - `timeout: TimeInterval` (default 5.0)

- [ ] **Step 1: 写 Input 解析测试（script 模式）**

```swift
import Testing
import Foundation
import iOSExploreServer
@testable import iOSExploreUIKit

#if canImport(UIKit)

@Test("解析 script 模式")
func webViewEvalInputParsesScript() throws {
    let input = try UIWebViewEvalInput.parse(from: [
        "accessibilityIdentifier": .string("web_container"),
        "script": .string("document.title")
    ])
    #expect(input.target == .accessibilityIdentifier("web_container"))
    #expect(input.script == "document.title")
    #expect(input.function == nil)
    #expect(input.timeout == 5.0)
}

@Test("解析 function 模式")
func webViewEvalInputParsesFunction() throws {
    let input = try UIWebViewEvalInput.parse(from: [
        "path": .string("root/0/1"),
        "function": .string("return await fetch('/api/user')")
    ])
    #expect(input.target == .path("root/0/1"))
    #expect(input.function == "return await fetch('/api/user')")
    #expect(input.script == nil)
}

@Test("解析 arguments")
func webViewEvalInputParsesArguments() throws {
    let input = try UIWebViewEvalInput.parse(from: [
        "accessibilityIdentifier": .string("web"),
        "function": .string("return arguments[0].userId"),
        "arguments": .object(["userId": .double(123)])
    ])
    #expect(input.arguments?["userId"] as? Double == 123)
}

@Test("解析自定义 timeout")
func webViewEvalInputParsesTimeout() throws {
    let input = try UIWebViewEvalInput.parse(from: [
        "accessibilityIdentifier": .string("web"),
        "script": .string("true"),
        "timeout": .double(10)
    ])
    #expect(input.timeout == 10.0)
}

@Test("拒绝 script 与 function 同时提供")
func webViewEvalInputRejectsBothScriptAndFunction() {
    #expect(throws: CommandInputParseError.self) {
        _ = try UIWebViewEvalInput.parse(from: [
            "accessibilityIdentifier": .string("web"),
            "script": .string("true"),
            "function": .string("return true")
        ])
    }
}

@Test("拒绝 script 与 function 都不提供")
func webViewEvalInputRejectsNeitherScriptNorFunction() {
    #expect(throws: CommandInputParseError.self) {
        _ = try UIWebViewEvalInput.parse(from: [
            "accessibilityIdentifier": .string("web")
        ])
    }
}

@Test("拒绝 arguments 没有 function")
func webViewEvalInputRejectsArgumentsWithoutFunction() {
    #expect(throws: CommandInputParseError.self) {
        _ = try UIWebViewEvalInput.parse(from: [
            "accessibilityIdentifier": .string("web"),
            "script": .string("true"),
            "arguments": .object(["key": .string("value")])
        ])
    }
}

@Test("拒绝 timeout 超出范围")
func webViewEvalInputRejectsInvalidTimeout() {
    #expect(throws: CommandInputParseError.self) {
        _ = try UIWebViewEvalInput.parse(from: [
            "accessibilityIdentifier": .string("web"),
            "script": .string("true"),
            "timeout": .double(0)
        ])
    }
    #expect(throws: CommandInputParseError.self) {
        _ = try UIWebViewEvalInput.parse(from: [
            "accessibilityIdentifier": .string("web"),
            "script": .string("true"),
            "timeout": .double(31)
        ])
    }
}

@Test("schema 声明全部字段")
func webViewEvalInputSchemaFields() {
    let fields = UIWebViewEvalInput.inputSchema.fields.map(\.name)
    #expect(fields.contains("accessibilityIdentifier"))
    #expect(fields.contains("path"))
    #expect(fields.contains("viewSnapshotID"))
    #expect(fields.contains("script"))
    #expect(fields.contains("function"))
    #expect(fields.contains("arguments"))
    #expect(fields.contains("timeout"))
}

#endif
```

- [ ] **Step 2: 运行测试确认失败**

```bash
swift test --filter UIWebViewEvalInputTests
```

预期：所有测试 FAIL（`UIWebViewEvalInput` 不存在）

- [ ] **Step 3: 实现 UIWebViewEvalInput**

```swift
#if canImport(UIKit)
import Foundation
import iOSExploreServer

/// `ui.webView.eval` 命令的输入模型。
///
/// 通过 `accessibilityIdentifier` 或 `path` 定位 WKWebView，执行 JavaScript 代码。
/// 支持两种模式：
/// - `script`（同步）：直接执行 JS 代码，最后一个表达式的值自动作为返回值
/// - `function`（异步）：执行 async function body（iOS 14+，自动降级）
///
/// `arguments` 只能与 `function` 一起使用，作为函数的第一个参数传入。
/// `timeout` 范围 1-30 秒，默认 5 秒。
public struct UIWebViewEvalInput: CommandInput, Sendable, Equatable {
    private enum Fields {
        static let accessibilityIdentifier = UIKitLocatorFields.accessibilityIdentifier
        static let path = UIKitLocatorFields.path
        static let viewSnapshotID = UIKitLocatorFields.viewSnapshotID

        static let script = CommandFields.optionalString(
            "script", description: "JS 代码字符串（同步模式），与 function 互斥"
        )
        static let function = CommandFields.optionalString(
            "function", description: "JS 函数体（异步模式），与 script 互斥"
        )
        static let arguments = CommandFields.optionalObject(
            "arguments", description: "传递给 function 的参数，只能与 function 一起"
        )
        static let timeout = CommandFields.double(
            "timeout", default: 5.0, description: "超时时间（秒），范围 1-30"
        )

        static let all: [AnyCommandField] = [
            accessibilityIdentifier.erased,
            path.erased,
            viewSnapshotID.erased,
            script.erased,
            function.erased,
            arguments.erased,
            timeout.erased,
        ]
    }

    /// 目标 WKWebView 定位方式。
    public let target: UIKitViewLookupTarget
    /// 陈旧校验快照 ID（来自 `ui.inspect`）。
    public let viewSnapshotID: String?
    /// JS 代码字符串（同步模式）。
    public let script: String?
    /// JS 函数体（异步模式）。
    public let function: String?
    /// 传递给 function 的参数。
    public let arguments: [String: Any]?
    /// 超时时间（秒）。
    public let timeout: TimeInterval

    /// 创建输入。
    public init(target: UIKitViewLookupTarget,
                viewSnapshotID: String?,
                script: String?,
                function: String?,
                arguments: [String: Any]?,
                timeout: TimeInterval) {
        self.target = target
        self.viewSnapshotID = viewSnapshotID
        self.script = script
        self.function = function
        self.arguments = arguments
        self.timeout = timeout
    }

    /// 解析输入。
    public static func parse(from data: [String: JSONValue]) throws -> UIWebViewEvalInput {
        let target = try UIKitViewLookupTarget.parse(from: data)
        let viewSnapshotID = try Fields.viewSnapshotID.parse(from: data)
        let script = try Fields.script.parse(from: data)
        let function = try Fields.function.parse(from: data)
        let arguments = try Fields.arguments.parse(from: data)
        let timeout = try Fields.timeout.parse(from: data)

        // 约束：script 与 function 互斥
        guard (script != nil) != (function != nil) else {
            throw CommandInputParseError.constraintViolation(
                "script 与 function 必须提供且只能提供其中一个"
            )
        }

        // 约束：arguments 只能与 function 一起
        if arguments != nil && function == nil {
            throw CommandInputParseError.constraintViolation(
                "arguments 只能与 function 一起使用"
            )
        }

        // 约束：timeout 范围 1-30
        guard timeout >= 1.0 && timeout <= 30.0 else {
            throw CommandInputParseError.constraintViolation(
                "timeout 必须在 1-30 秒范围内（当前 \(timeout)）"
            )
        }

        return UIWebViewEvalInput(
            target: target,
            viewSnapshotID: viewSnapshotID,
            script: script,
            function: function,
            arguments: arguments,
            timeout: timeout
        )
    }

    /// Schema 定义。
    public static var inputSchema: CommandSchema {
        CommandSchema(
            fields: Fields.all,
            constraints: [
                .exactlyOneOf(["accessibilityIdentifier", "path"]),
                .exactlyOneOf(["script", "function"]),
                .implies("arguments", requires: "function")
            ]
        )
    }
}

#endif
```

- [ ] **Step 4: 运行测试确认通过**

```bash
swift test --filter UIWebViewEvalInputTests
```

预期：所有测试 PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/iOSExploreUIKit/Commands/WebViewEval/UIWebViewEvalInput.swift
git add Tests/iOSExploreServerTests/UIWebViewEvalInputTests.swift
git commit -m "feat(webview): add UIWebViewEvalInput with validation tests"
```

---
### Task 2: UIWebViewEvalExecutor 骨架（定位 + 陈旧校验）

**Files:**
- Create: `Sources/iOSExploreUIKit/Commands/WebViewEval/UIWebViewEvalExecutor.swift`

**Interfaces:**
- Consumes: `UIWebViewEvalInput`, `UIKitContextProvider`, `UIKitLocatorResolver`, `UIKitCommandError`
- Produces: `UIWebViewEvalExecutor.execute(input:context:) throws -> JSON`

- [ ] **Step 1: 写集成测试（定位成功）**

创建 `Tests/iOSExploreServerTests/UIWebViewEvalTests.swift`:

```swift
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
    let window = UIWindow()
    window.rootViewController = vc
    window.makeKeyAndVisible()
    
    let input = try UIWebViewEvalInput.parse(from: [
        "accessibilityIdentifier": .string("test_web"),
        "script": .string("1 + 1")
    ])
    
    let context = try UIKitContextProvider.currentContext(action: "ui.webView.eval")
    let result = try await UIWebViewEvalExecutor.execute(input: input, context: context)
    
    // 暂时只验证不抛错
    #expect(result != nil)
}

@Test("定位失败返回 target_not_found")
@MainActor
func webViewEvalLocateFailsReturnsError() async throws {
    let window = UIWindow()
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    
    let input = try UIWebViewEvalInput.parse(from: [
        "accessibilityIdentifier": .string("nonexistent"),
        "script": .string("true")
    ])
    
    let context = try UIKitContextProvider.currentContext(action: "ui.webView.eval")
    
    #expect(throws: UIKitCommandError.self) {
        _ = try await UIWebViewEvalExecutor.execute(input: input, context: context)
    }
}

@Test("目标非 WKWebView 返回 invalid_data")
@MainActor
func webViewEvalNonWebViewReturnsError() async throws {
    let vc = UIViewController()
    let label = UILabel()
    label.accessibilityIdentifier = "not_webview"
    vc.view.addSubview(label)
    
    let window = UIWindow()
    window.rootViewController = vc
    window.makeKeyAndVisible()
    
    let input = try UIWebViewEvalInput.parse(from: [
        "accessibilityIdentifier": .string("not_webview"),
        "script": .string("true")
    ])
    
    let context = try UIKitContextProvider.currentContext(action: "ui.webView.eval")
    
    #expect(throws: UIKitCommandError.self) {
        _ = try await UIWebViewEvalExecutor.execute(input: input, context: context)
    }
}

#endif
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild -project iOSExploreServer.xcodeproj -scheme iOSExploreServer-Package -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:iOSExploreServerTests/UIWebViewEvalTests
```

预期：FAIL（`UIWebViewEvalExecutor` 不存在）

- [ ] **Step 3: 实现 Executor 骨架（定位 + 类型校验）**

```swift
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
        
        UIKitCommandLogging.debug("command", "\(action) located WKWebView")
        
        // TODO: 执行 JS（后续任务实现）
        return .object(["placeholder": .bool(true)])
    }
}

#endif
```

- [ ] **Step 4: 运行测试确认通过**

```bash
xcodebuild -project iOSExploreServer.xcodeproj -scheme iOSExploreServer-Package -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:iOSExploreServerTests/UIWebViewEvalTests
```

预期：前 3 个测试 PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/iOSExploreUIKit/Commands/WebViewEval/UIWebViewEvalExecutor.swift
git add Tests/iOSExploreServerTests/UIWebViewEvalTests.swift
git commit -m "feat(webview): add UIWebViewEvalExecutor skeleton with locate + type check"
```

---

### Task 3: 同步 JS 执行（script 模式）

**Files:**
- Modify: `Sources/iOSExploreUIKit/Commands/WebViewEval/UIWebViewEvalExecutor.swift`
- Modify: `Tests/iOSExploreServerTests/UIWebViewEvalTests.swift`

**Interfaces:**
- Extends: `UIWebViewEvalExecutor.execute` 增加同步 JS 执行逻辑
- Uses: `WKWebView.evaluateJavaScript(_:completionHandler:)`

- [ ] **Step 1: 写同步执行测试**

在 `UIWebViewEvalTests.swift` 追加：

```swift
@Test("同步执行返回 string")
@MainActor
func webViewEvalSyncReturnsString() async throws {
    let vc = TestWebViewController(identifier: "test_web")
    let window = UIWindow()
    window.rootViewController = vc
    window.makeKeyAndVisible()
    
    // 加载简单 HTML
    vc.webView.loadHTMLString("<html><head><title>Test</title></head></html>", baseURL: nil)
    try await Task.sleep(nanoseconds: 500_000_000) // 等待加载
    
    let input = try UIWebViewEvalInput.parse(from: [
        "accessibilityIdentifier": .string("test_web"),
        "script": .string("document.title")
    ])
    
    let context = try UIKitContextProvider.currentContext(action: "ui.webView.eval")
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
    let window = UIWindow()
    window.rootViewController = vc
    window.makeKeyAndVisible()
    
    vc.webView.loadHTMLString("<html></html>", baseURL: nil)
    try await Task.sleep(nanoseconds: 500_000_000)
    
    let input = try UIWebViewEvalInput.parse(from: [
        "accessibilityIdentifier": .string("test_web"),
        "script": .string("1 + 1")
    ])
    
    let context = try UIKitContextProvider.currentContext(action: "ui.webView.eval")
    let result = try await UIWebViewEvalExecutor.execute(input: input, context: context)
    
    guard case .object(let obj) = result else {
        Issue.record("Expected object result")
        return
    }
    
    #expect(obj["result"] == .number(2))
    #expect(obj["resultType"] == .string("number"))
}

@Test("同步执行返回 boolean")
@MainActor
func webViewEvalSyncReturnsBoolean() async throws {
    let vc = TestWebViewController(identifier: "test_web")
    let window = UIWindow()
    window.rootViewController = vc
    window.makeKeyAndVisible()
    
    vc.webView.loadHTMLString("<html></html>", baseURL: nil)
    try await Task.sleep(nanoseconds: 500_000_000)
    
    let input = try UIWebViewEvalInput.parse(from: [
        "accessibilityIdentifier": .string("test_web"),
        "script": .string("true")
    ])
    
    let context = try UIKitContextProvider.currentContext(action: "ui.webView.eval")
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
    let window = UIWindow()
    window.rootViewController = vc
    window.makeKeyAndVisible()
    
    vc.webView.loadHTMLString("<html></html>", baseURL: nil)
    try await Task.sleep(nanoseconds: 500_000_000)
    
    let input = try UIWebViewEvalInput.parse(from: [
        "accessibilityIdentifier": .string("test_web"),
        "script": .string("null")
    ])
    
    let context = try UIKitContextProvider.currentContext(action: "ui.webView.eval")
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
    let window = UIWindow()
    window.rootViewController = vc
    window.makeKeyAndVisible()
    
    vc.webView.loadHTMLString("<html></html>", baseURL: nil)
    try await Task.sleep(nanoseconds: 500_000_000)
    
    let input = try UIWebViewEvalInput.parse(from: [
        "accessibilityIdentifier": .string("test_web"),
        "script": .string("nonexistentFunction()")
    ])
    
    let context = try UIKitContextProvider.currentContext(action: "ui.webView.eval")
    
    #expect(throws: UIKitCommandError.self) {
        _ = try await UIWebViewEvalExecutor.execute(input: input, context: context)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild -project iOSExploreServer.xcodeproj -scheme iOSExploreServer-Package -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:iOSExploreServerTests/UIWebViewEvalTests
```

预期：新测试 FAIL（同步执行未实现）

- [ ] **Step 3: 实现同步 JS 执行**

在 `UIWebViewEvalExecutor.swift` 中替换 TODO 部分：

```swift
// 在 execute 方法的末尾，替换 TODO
let startTime = Date()

if let script = input.script {
    // 同步模式
    UIKitCommandLogging.debug("command", "\(action) executing sync script")
    let result = try executeSync(webView: webView, script: script, timeout: input.timeout, action: action)
    let elapsed = Date().timeIntervalSince(startTime)
    
    return .object([
        "result": result.value,
        "resultType": .string(result.type),
        "mode": .string("sync"),
        "executionTime": .number(elapsed),
        "iosVersion": .string(UIDevice.current.systemVersion)
    ])
} else {
    // TODO: 异步模式（后续任务）
    throw UIKitCommandError.invalidData(action: action, message: "async mode not implemented yet")
}

// 在文件末尾添加辅助方法

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
            return (.number(number.doubleValue), "number")
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
        return (.object(jsonDict), "object")
    }
    
    // 不可序列化类型（DOM 节点、Function 等）
    UIKitCommandLogging.debug("command", "JS result not serializable type=\(String(describing: type(of: result)))")
    return (.null, "object")
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
xcodebuild -project iOSExploreServer.xcodeproj -scheme iOSExploreServer-Package -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:iOSExploreServerTests/UIWebViewEvalTests
```

预期：所有测试 PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/iOSExploreUIKit/Commands/WebViewEval/UIWebViewEvalExecutor.swift
git add Tests/iOSExploreServerTests/UIWebViewEvalTests.swift
git commit -m "feat(webview): implement sync JS execution with result serialization"
```

---
### Task 4: 异步 JS 执行（function 模式 + iOS 版本降级）

**Files:**
- Modify: `Sources/iOSExploreUIKit/Commands/WebViewEval/UIWebViewEvalExecutor.swift`
- Modify: `Tests/iOSExploreServerTests/UIWebViewEvalTests.swift`

**Interfaces:**
- Extends: `UIWebViewEvalExecutor.execute` 增加异步 JS 执行逻辑
- Uses: `WKWebView.callAsyncJavaScript(_:arguments:in:contentWorld:)` (iOS 14+)

- [ ] **Step 1: 写异步执行测试**

在 `UIWebViewEvalTests.swift` 追加：

```swift
@Test("异步执行返回 Promise 结果")
@MainActor
@available(iOS 14.0, *)
func webViewEvalAsyncReturnsPromise() async throws {
    let vc = TestWebViewController(identifier: "test_web")
    let window = UIWindow()
    window.rootViewController = vc
    window.makeKeyAndVisible()
    
    vc.webView.loadHTMLString("<html></html>", baseURL: nil)
    try await Task.sleep(nanoseconds: 500_000_000)
    
    let input = try UIWebViewEvalInput.parse(from: [
        "accessibilityIdentifier": .string("test_web"),
        "function": .string("return await Promise.resolve(42)")
    ])
    
    let context = try UIKitContextProvider.currentContext(action: "ui.webView.eval")
    let result = try await UIWebViewEvalExecutor.execute(input: input, context: context)
    
    guard case .object(let obj) = result else {
        Issue.record("Expected object result")
        return
    }
    
    #expect(obj["result"] == .number(42))
    #expect(obj["mode"] == .string("async"))
}

@Test("异步执行带参数")
@MainActor
@available(iOS 14.0, *)
func webViewEvalAsyncWithArguments() async throws {
    let vc = TestWebViewController(identifier: "test_web")
    let window = UIWindow()
    window.rootViewController = vc
    window.makeKeyAndVisible()
    
    vc.webView.loadHTMLString("<html></html>", baseURL: nil)
    try await Task.sleep(nanoseconds: 500_000_000)
    
    let input = try UIWebViewEvalInput.parse(from: [
        "accessibilityIdentifier": .string("test_web"),
        "function": .string("const {userId} = arguments[0]; return userId * 2"),
        "arguments": .object(["userId": .double(10)])
    ])
    
    let context = try UIKitContextProvider.currentContext(action: "ui.webView.eval")
    let result = try await UIWebViewEvalExecutor.execute(input: input, context: context)
    
    guard case .object(let obj) = result else {
        Issue.record("Expected object result")
        return
    }
    
    #expect(obj["result"] == .number(20))
}

@Test("异步执行超时返回 invalid_data")
@MainActor
@available(iOS 14.0, *)
func webViewEvalAsyncTimeoutReturnsError() async throws {
    let vc = TestWebViewController(identifier: "test_web")
    let window = UIWindow()
    window.rootViewController = vc
    window.makeKeyAndVisible()
    
    vc.webView.loadHTMLString("<html></html>", baseURL: nil)
    try await Task.sleep(nanoseconds: 500_000_000)
    
    let input = try UIWebViewEvalInput.parse(from: [
        "accessibilityIdentifier": .string("test_web"),
        "function": .string("await new Promise(resolve => setTimeout(resolve, 5000))"),
        "timeout": .double(1)
    ])
    
    let context = try UIKitContextProvider.currentContext(action: "ui.webView.eval")
    
    #expect(throws: UIKitCommandError.self) {
        _ = try await UIWebViewEvalExecutor.execute(input: input, context: context)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild -project iOSExploreServer.xcodeproj -scheme iOSExploreServer-Package -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:iOSExploreServerTests/UIWebViewEvalTests
```

预期：新测试 FAIL（异步执行未实现）

- [ ] **Step 3: 实现异步 JS 执行**

在 `UIWebViewEvalExecutor.swift` 中替换异步 TODO：

```swift
// 在 execute 方法中，替换 else 分支
else if let function = input.function {
    // 异步模式
    if #available(iOS 14.0, *) {
        UIKitCommandLogging.debug("command", "\(action) executing async function")
        let result = try executeAsync(
            webView: webView,
            function: function,
            arguments: input.arguments,
            timeout: input.timeout,
            action: action
        )
        let elapsed = Date().timeIntervalSince(startTime)
        
        return .object([
            "result": result.value,
            "resultType": .string(result.type),
            "mode": .string("async"),
            "executionTime": .number(elapsed),
            "iosVersion": .string(UIDevice.current.systemVersion)
        ])
    } else {
        // iOS 14 以下降级到同步模式
        UIKitCommandLogging.debug("command", "\(action) iOS < 14.0, downgrade to sync mode")
        let result = try executeSync(webView: webView, script: function, timeout: input.timeout, action: action)
        let elapsed = Date().timeIntervalSince(startTime)
        
        return .object([
            "result": result.value,
            "resultType": .string(result.type),
            "mode": .string("sync"),  // 降级标记
            "executionTime": .number(elapsed),
            "iosVersion": .string(UIDevice.current.systemVersion)
        ])
    }
} else {
    throw UIKitCommandError.invalidData(action: action, message: "neither script nor function provided")
}

// 在文件末尾添加异步执行方法

/// 异步执行 JS（iOS 14+，使用 async/await 避免阻塞主线程）。
@available(iOS 14.0, *)
private static func executeAsync(
    webView: WKWebView,
    function: String,
    arguments: [String: Any]?,
    timeout: TimeInterval,
    action: String
) async throws -> (value: JSONValue, type: String) {
    return try await withThrowingTaskGroup(of: Result<(Any?, Error?), Error>.self) { group in
        // JS 执行任务
        group.addTask {
            let args = arguments ?? [:]
            let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<Any, Error>, Never>) in
                webView.callAsyncJavaScript(function, arguments: args, in: nil, in: .page) { jsResult in
                    continuation.resume(returning: jsResult)
                }
            }
            switch result {
            case .success(let value):
                return .success((value, nil))
            case .failure(let error):
                return .success((nil, error))
            }
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
                UIKitCommandLogging.error("command", "\(action) async JS execution failed error=\(error)")
                throw UIKitCommandError.invalidData(action: action, message: "JS execution failed: \(error.localizedDescription)")
            }
            return serializeJSResult(jsResult)
        case .failure:
            UIKitCommandLogging.error("command", "\(action) async JS execution timed out after \(timeout)s")
            throw UIKitCommandError.invalidData(action: action, message: "JS execution timed out after \(Int(timeout))s (elapsed \(String(format: "%.2f", timeout))s)")
        }
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
xcodebuild -project iOSExploreServer.xcodeproj -scheme iOSExploreServer-Package -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:iOSExploreServerTests/UIWebViewEvalTests
```

预期：所有测试 PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/iOSExploreUIKit/Commands/WebViewEval/UIWebViewEvalExecutor.swift
git add Tests/iOSExploreServerTests/UIWebViewEvalTests.swift
git commit -m "feat(webview): implement async JS execution with iOS 14+ support and downgrade"
```

---

### Task 5: UIWebViewEvalCommand（薄 adapter）

**Files:**
- Create: `Sources/iOSExploreUIKit/Commands/WebViewEval/UIWebViewEvalCommand.swift`

**Interfaces:**
- Consumes: `UIWebViewEvalInput`, `UIWebViewEvalExecutor`
- Produces: `Command` 实现，action 为 `"ui.webView.eval"`

- [ ] **Step 1: 实现 Command**

```swift
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
            let data = try await MainActor.run {
                let context = try UIKitContextProvider.currentContext(action: UIWebViewEvalCommand.actionName)
                return try UIWebViewEvalExecutor.execute(input: input, context: context)
            }
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
}
#endif
```

- [ ] **Step 2: 在 UIKitCommandRegistrar 中注册**

修改 `Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift`，在注册列表末尾添加：

```swift
register(UIWebViewEvalCommand(), logCategory: .extensionCommand(category: "command"))
```

同时更新注释中的命令数量：从 20 改为 21，并在命令列表中添加 `ui.webView.eval`。

- [ ] **Step 3: 端到端测试（curl 验证）**

```bash
# 启动 SPMExample
xcodebuild -project iOSExploreServer.xcodeproj -scheme SPMExample -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation

# 在模拟器中手动创建一个带 WKWebView 的页面（或使用现有测试页）

# 发送测试请求
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.webView.eval",
  "data": {
    "accessibilityIdentifier": "test_web",
    "script": "document.title"
  }
}'
```

预期：返回 `{"code":"ok","data":{"result":"...","resultType":"string","mode":"sync",...}}`

- [ ] **Step 4: Commit**

```bash
git add Sources/iOSExploreUIKit/Commands/WebViewEval/UIWebViewEvalCommand.swift
git add Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift
git commit -m "feat(webview): add UIWebViewEvalCommand and register to UIKit registrar"
```

---

### Task 6: 端到端测试 ViewController（SPMExample）

**Files:**
- Create: `Examples/SPMExample/SPMExample/WebViewTestViewController.swift`
- Modify: `Examples/SPMExample/SPMExample/ViewController.swift` (添加入口)

**Interfaces:**
- Produces: 一个包含 WKWebView 和 JSBridge 的测试页面

- [ ] **Step 1: 创建 WebViewTestViewController**

```swift
import UIKit
import WebKit

/// WebView 测试页面。
///
/// 包含一个 WKWebView，加载带 JSBridge 的 HTML 页面，用于测试 `ui.webView.eval` 命令。
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
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>WebView 测试页</title>
            <style>
                body { font-family: -apple-system; padding: 20px; }
                button { 
                    padding: 12px 24px; 
                    font-size: 16px; 
                    margin: 10px 0;
                    display: block;
                    width: 100%;
                }
                #status { 
                    margin-top: 20px; 
                    padding: 10px; 
                    background: #f0f0f0; 
                    border-radius: 5px;
                }
            </style>
        </head>
        <body>
            <h1>WebView 测试页</h1>
            <p>用于测试 <code>ui.webView.eval</code> 命令</p>
            
            <button onclick="window.testBridge.showAlert('Alert from JS')">
                触发 Native Alert
            </button>
            
            <button onclick="window.testBridge.navigate('detail')">
                跳转到 Native 详情页
            </button>
            
            <div id="status">
                <strong>当前状态：</strong><span id="status-text">就绪</span>
            </div>
            
            <script>
                // 模拟 JSBridge
                window.testBridge = {
                    showAlert: function(message) {
                        document.getElementById('status-text').textContent = 'showAlert called: ' + message;
                        // 实际场景会调用 webkit.messageHandlers
                    },
                    navigate: function(page) {
                        document.getElementById('status-text').textContent = 'navigate called: ' + page;
                    }
                };
                
                // 测试用全局状态
                window.testData = {
                    userId: 12345,
                    userName: 'Alice'
                };
            </script>
        </body>
        </html>
        """
        
        webView.loadHTMLString(html, baseURL: nil)
    }
}
```

- [ ] **Step 2: 在主 ViewController 添加入口**

在 `ViewController.swift` 的按钮列表中添加：

```swift
("WebView 测试", {
    let vc = WebViewTestViewController()
    self.navigationController?.pushViewController(vc, animated: true)
})
```

- [ ] **Step 3: 真机验证流程**

```bash
# 1. 启动 SPMExample（真机）
xcodebuild -project iOSExploreServer.xcodeproj -scheme SPMExample -destination 'platform=iOS,name=YOUR_DEVICE' install

# 2. 启动 iproxy
./scripts/proxy.sh

# 3. 进入 WebView 测试页

# 4. 执行同步 JS
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.webView.eval",
  "data": {
    "accessibilityIdentifier": "webview_test",
    "script": "document.title"
  }
}'

# 预期：{"code":"ok","data":{"result":"WebView 测试页","resultType":"string","mode":"sync",...}}

# 5. 触发 JSBridge
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.webView.eval",
  "data": {
    "accessibilityIdentifier": "webview_test",
    "script": "window.testBridge.showAlert(\"Hello from Agent\"); document.getElementById(\"status-text\").textContent"
  }
}'

# 预期：返回状态文本

# 6. 读取全局状态
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.webView.eval",
  "data": {
    "accessibilityIdentifier": "webview_test",
    "script": "window.testData"
  }
}'

# 预期：{"code":"ok","data":{"result":{"userId":12345,"userName":"Alice"},"resultType":"object",...}}
```

- [ ] **Step 4: Commit**

```bash
git add Examples/SPMExample/SPMExample/WebViewTestViewController.swift
git add Examples/SPMExample/SPMExample/ViewController.swift
git commit -m "feat(webview): add WebViewTestViewController for e2e testing"
```

---
### Task 7: Skill 文档

**Files:**
- Create: `.claude/skills/ios-ui-webview/SKILL.md`

**Interfaces:**
- Produces: Agent 使用指南，说明何时使用 / 不使用 `ui.webView.eval`

- [ ] **Step 1: 创建 Skill 文档**

```markdown
# ios-ui-webview

在 WKWebView 中执行 JavaScript，用于混合 App 的轻量级 Web 自动化。

## 何时使用此 Skill

✅ **适用场景**（轻交互）：
- 触发 JSBridge 调用（如 `window.bridge.goPay()`）
- 简单的点击操作（如 `document.querySelector('#btn').click()`）
- 简单的表单填充（如 `document.querySelector('#input').value = 'text'`）
- 读取状态验证（如 `document.title`、`localStorage.getItem('key')`）

❌ **不适用场景**（复杂 Web 自动化，应使用 Puppeteer/CDP）：
- 复杂的表单验证和多步骤流程
- 等待 AJAX 完成、复杂异步状态
- Web 页面的截图对比和视觉验证
- 网络拦截、请求修改、Performance 监控

## 命令：ui.webView.eval

在 WKWebView 中执行 JavaScript。

### 参数

| 参数 | 类型 | 必填 | 说明 |
|-----|------|------|------|
| `accessibilityIdentifier` | String | 二选一 | WKWebView 的 accessibilityIdentifier |
| `path` | String | 二选一 | WKWebView 的路径（如 `root/0/1`） |
| `script` | String | 二选一 | JS 代码字符串（同步模式） |
| `function` | String | 二选一 | JS 函数体（异步模式，iOS 14+） |
| `arguments` | Object | 否 | 传递给 `function` 的参数 |
| `timeout` | Number | 否 | 超时时间（秒），默认 5，范围 1-30 |
| `viewSnapshotID` | String | 否 | 陈旧校验快照 ID |

### 同步模式 vs 异步模式

**同步模式（`script`）**：
- 适用于简单 JS 表达式
- 最后一个表达式的值自动作为返回值
- 不支持 `await` 和 Promise

```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.webView.eval",
  "data": {
    "accessibilityIdentifier": "web_container",
    "script": "document.title"
  }
}'
```

**异步模式（`function`）**：
- 支持 `await` 和 Promise（iOS 14+）
- 函数体会被自动包装为 `async function() { ... }`
- iOS 14 以下自动降级到同步模式

```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.webView.eval",
  "data": {
    "accessibilityIdentifier": "web_container",
    "function": "const res = await fetch(\"/api/user\"); return await res.json();"
  }
}'
```

**带参数的异步模式**：

```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.webView.eval",
  "data": {
    "accessibilityIdentifier": "web_container",
    "function": "const {userId} = arguments[0]; return document.querySelector(`#user-${userId}`).textContent;",
    "arguments": {"userId": 123}
  }
}'
```

### 常见场景

**1. 触发 JSBridge 调用**

```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.webView.eval",
  "data": {
    "accessibilityIdentifier": "web_container",
    "script": "window.bridge.goPay(); true"
  }
}'
```

**2. 点击 Web 元素**

```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.webView.eval",
  "data": {
    "accessibilityIdentifier": "web_container",
    "script": "document.querySelector('#submit-btn').click(); true"
  }
}'
```

**3. 填充表单**

```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.webView.eval",
  "data": {
    "accessibilityIdentifier": "web_container",
    "script": "document.querySelector('#username').value = 'alice'; document.querySelector('#password').value = '123456'; true"
  }
}'
```

**4. 读取页面状态**

```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.webView.eval",
  "data": {
    "accessibilityIdentifier": "web_container",
    "script": "localStorage.getItem('token')"
  }
}'
```

**5. 等待异步内容加载（iOS 14+）**

```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.webView.eval",
  "data": {
    "accessibilityIdentifier": "web_container",
    "function": "await new Promise(resolve => { const check = () => { if (document.querySelector('#content')) resolve(true); else setTimeout(check, 100); }; check(); }); return document.querySelector('#content').textContent;",
    "timeout": 10
  }
}'
```

### 典型工作流

```bash
# 1. 定位 WebView 容器
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.inspect",
  "data": {"includeText": false}
}'

# 2. 执行 JS 操作
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.webView.eval",
  "data": {
    "path": "root/0/1",
    "script": "document.querySelector('#buy-btn').click(); true"
  }
}'

# 3. 验证跳转（Native 页面）
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.topViewHierarchy"
}'
```

### 错误处理

| 错误码 | 触发条件 | 解决方案 |
|--------|----------|---------|
| `target_not_found` | WKWebView 定位失败 | 先用 `ui.inspect` 确认路径 |
| `invalid_data` | 目标非 WKWebView | 检查定位是否正确 |
| `invalid_data` | JS 执行超时 | 增大 `timeout` 或简化 JS |
| `invalid_data` | JS 执行错误 | 检查 JS 语法和 API 可用性 |
| `stale_locator` | viewSnapshotID 陈旧 | 重新 `ui.inspect` 获取新快照 |

### 限制

1. **不深入 WebView 内部**：`ui.inspect` 只能看到 WKWebView 容器，看不到内部 DOM 结构
2. **跨域限制**：遵循 WKWebView 的同源策略，无法访问跨域 iframe
3. **结果序列化**：无法返回 DOM 节点、Function、Symbol 等不可序列化类型
4. **iOS 版本降级**：iOS 14 以下不支持异步模式，自动降级到同步

### 何时切换到专业 Web 工具

当遇到以下场景时，应使用 Puppeteer/CDP/Playwright：
- 需要等待复杂的异步状态（多个 AJAX 请求完成）
- 需要网络拦截、请求修改、响应 mock
- 需要 Web 页面截图对比和视觉回归测试
- 需要 Performance 监控和分析
- 需要复杂的 DOM 查询和遍历

`ui.webView.eval` 的定位是**最小化 JS 执行原语**，不做 Web DSL 封装。
```

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/ios-ui-webview/SKILL.md
git commit -m "docs(webview): add ios-ui-webview skill documentation"
```

---

### Task 8: 更新项目文档

**Files:**
- Modify: `docs/superpowers/specs/2026-07-16-capability-gap-analysis.md`
- Modify: `docs/uikit/agent-command-protocol.md`
- Modify: `docs/uikit/uikit-file-reference.md`

**Interfaces:**
- Updates: 能力缺口分析、命令调用契约、文件档案

- [ ] **Step 1: 更新能力缺口分析**

在 `docs/superpowers/specs/2026-07-16-capability-gap-analysis.md` 中修改：

**§3.2.2 WebView 操作**：从"不实现"改为"已实现"

```markdown
### 3.2.2 WebView 操作

**状态**：✅ **已实现**（2026-07-19）

**能力**：
- `ui.webView.eval`：在 WKWebView 中执行 JavaScript
- 支持同步和异步两种模式
- iOS 14+ 支持 Promise/async-await
- 超时控制、结果序列化、错误处理

**定位**：轻量级 Web 自动化，覆盖 JSBridge 触发、简单点击、表单填充、状态读取等场景。复杂 Web 自动化应使用专业工具（Puppeteer/CDP）。

**实现文件**：
- `Sources/iOSExploreUIKit/Commands/WebViewEval/UIWebViewEvalInput.swift`
- `Sources/iOSExploreUIKit/Commands/WebViewEval/UIWebViewEvalExecutor.swift`
- `Sources/iOSExploreUIKit/Commands/WebViewEval/UIWebViewEvalCommand.swift`
```

**§4 实现优先级矩阵**：WKWebView 状态更新为"已实现"

**§7.2 短期规划**：删除"实现 `ui.webView.eval` 命令（2-3 天）"

- [ ] **Step 2: 更新命令调用契约**

在 `docs/uikit/agent-command-protocol.md` 中添加 `ui.webView.eval` 一节：

```markdown
### ui.webView.eval

**前置条件**：
- 已通过 `ui.inspect` 或 `ui.topViewHierarchy` 定位到 WKWebView
- WebView 已加载内容（否则 JS 执行可能失败）

**调用时序示例**：

```bash
# 1. 定位 WebView
ui.inspect → 找到 WKWebView path

# 2. 执行 JS 操作
ui.webView.eval(path, script) → 返回结果

# 3. 验证 Native 跳转
ui.topViewHierarchy → 确认页面切换
```

**常见错误模式**：

1. **超时**：JS 执行时间过长或陷入死循环
   - 解决：增大 `timeout` 或简化 JS 逻辑
   
2. **JS 语法错误**：传入的 script 或 function 有语法问题
   - 解决：先在浏览器 console 验证 JS

3. **跨域限制**：尝试访问跨域 iframe
   - 解决：使用同源 API 或切换到专业工具

4. **iOS 版本不支持**：iOS 13 使用异步模式
   - 解决：自动降级，无需手动处理
```

- [ ] **Step 3: 更新文件档案**

在 `docs/uikit/uikit-file-reference.md` 中添加 WebViewEval 条目：

```markdown
### Commands/WebViewEval/

| 文件 | 职责 | 行数 |
|-----|------|------|
| `UIWebViewEvalInput.swift` | 输入模型：参数定义、schema、parse 逻辑 | ~180 |
| `UIWebViewEvalExecutor.swift` | 核心执行：定位、陈旧校验、同步/异步 JS 执行、超时处理、结果序列化 | ~280 |
| `UIWebViewEvalCommand.swift` | 薄 adapter：日志、错误处理、调用 executor | ~50 |
```

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-07-16-capability-gap-analysis.md
git add docs/uikit/agent-command-protocol.md
git add docs/uikit/uikit-file-reference.md
git commit -m "docs(webview): update capability gap analysis, protocol, and file reference"
```

---

## 实现完成验证清单

完成所有任务后，运行以下命令验证：

- [ ] **单元测试（macOS）**

```bash
swift test --filter UIWebViewEvalInputTests
```

预期：所有解析和校验测试 PASS

- [ ] **集成测试（iOS framework）**

```bash
xcodebuild -project iOSExploreServer.xcodeproj -scheme iOSExploreServer-Package -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:iOSExploreServerTests/UIWebViewEvalTests
```

预期：所有执行和错误处理测试 PASS

- [ ] **端到端测试（真机）**

```bash
# 1. 部署到真机
xcodebuild -project iOSExploreServer.xcodeproj -scheme SPMExample -destination 'platform=iOS,name=YOUR_DEVICE' install

# 2. 启动 iproxy
./scripts/proxy.sh

# 3. 进入 WebView 测试页

# 4. 验证同步模式
curl -X POST http://localhost:38321/ -d '{"action":"ui.webView.eval","data":{"accessibilityIdentifier":"webview_test","script":"document.title"}}'

# 5. 验证异步模式
curl -X POST http://localhost:38321/ -d '{"action":"ui.webView.eval","data":{"accessibilityIdentifier":"webview_test","function":"return await Promise.resolve(42)"}}'

# 6. 验证 JSBridge 触发
curl -X POST http://localhost:38321/ -d '{"action":"ui.webView.eval","data":{"accessibilityIdentifier":"webview_test","script":"window.testBridge.showAlert(\"Hello\"); true"}}'
```

预期：所有请求返回 `{"code":"ok","data":{...}}`

- [ ] **覆盖率检查**

```bash
swift test --enable-code-coverage
xcrun llvm-cov report .build/debug/iOSExploreServerPackageTests.xctest/Contents/MacOS/iOSExploreServerPackageTests -instr-profile .build/debug/codecov/default.profdata
```

预期：WebViewEval 相关文件覆盖率 > 80%

---

## 总结

**实现内容**：
- 3 个源文件（Input / Executor / Command）
- 2 个测试文件（单元测试 / 集成测试）
- 1 个端到端测试页面
- 1 个 Skill 文档
- 3 个项目文档更新

**核心能力**：
- 同步 JS 执行（iOS 10+）
- 异步 JS 执行（iOS 14+，自动降级）
- 超时控制（1-30 秒）
- 结果序列化（null/bool/number/string/array/object）
- 错误处理（定位失败 / 类型错误 / 超时 / JS 错误）

**工作量**：预计 2-3 天（符合设计文档估算）
