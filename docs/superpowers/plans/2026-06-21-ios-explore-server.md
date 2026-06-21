# iOSExploreServer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 SPM 包 `iOSExploreServer` 里实现一个基于 `NWListener` 的手机端 HTTP Server，支持单端点 + JSON 命令分发，并在 `SPMExample` App 里用启动/停止 + 日志面板测试 Mac 经 iproxy 转发过来的请求。

**Architecture:** 手机端 Server（`NWListener` 监听 `:38321`）接收 `POST /` JSON 请求，按 `action` 字段分发到注册的 handler，返回统一 envelope。库只依赖 `Foundation` + `Network`，handler 注册式扩展。Mac 侧用 `iproxy 38321 38321` + `curl` 调用，不在包内。

**Tech Stack:** Swift 6.2（严格并发）/ `Network.framework`（`NWListener`/`NWConnection`）/ Swift Testing（`import Testing`）/ SPM / `iproxy`（libimobiledevice）/ UIKit（仅示例 App）

## Global Constraints

- `swift-tools-version: 6.2`，启用 Swift 6 严格并发；所有跨边界模型 `Sendable`，共享状态用 `actor`。
- 库 `iOSExploreServer` **只依赖 `Foundation` + `Network`**，不依赖 UIKit；UI 相关信息（如设备机型）由集成方注入额外 handler，不进库。
- 唯一命令端点 `POST /`，body 为 JSON `{"action": "...", "data": {...}}`，响应统一 envelope `{"ok":bool, "data"?|error?}`。
- 默认端口 **38321**（构造可配）。
- 测试框架 **Swift Testing**（`import Testing`、`@Test`、`#expect`），覆盖率 ≥ 80%。
- SPM 包与 `iOSExploreServer.xcodeproj` framework 工程**共享同一份源码**（根 `Sources/iOSExploreServer/`）。
- 频繁提交，commit message 用 `<type>: <description>`，不加 attribution。
- 当前分支：`feat/ios-explore-server`（已创建）。

## File Structure

实现后 `Sources/iOSExploreServer/` 拆分为以下文件（each one responsibility）：

| 文件 | 职责 |
|---|---|
| `Models.swift` | `JSONValue` / `JSON` / `ExploreRequest` / `ExploreResult` / `ExploreError`（Sendable 值类型） |
| `JSONCoder.swift` | `JSON` ↔ `Data`/`Any` 编解码（基于 `JSONSerialization`） |
| `HTTPRequest.swift` | HTTP 请求值类型 |
| `HTTPResponse.swift` | HTTP 响应值类型 + `serialized()` 报文序列化 |
| `HTTPParser.swift` | 请求解析（`parseRequest(from:)`）+ envelope 响应构造 |
| `Router.swift` | `actor`，`action → handler` 注册表与分发 |
| `Handlers/BuiltinHandlers.swift` | 内置 `ping` / `echo` / `info` |
| `HTTPListener.swift` | `NWListener` 封装：接连接、解析、路由、回写 |
| `ExploreServer.swift` | 对外门面 + `ServerEvent` 事件流 |

测试 `Tests/iOSExploreServerTests/`：`JSONCoderTests.swift` / `HTTPParserTests.swift` / `RouterTests.swift` / `BuiltinHandlersTests.swift` / `IntegrationTests.swift`。

---

## Task 1: 基础数据模型与 JSON 编解码

**Files:**
- Create: `Sources/iOSExploreServer/Models.swift`
- Create: `Sources/iOSExploreServer/JSONCoder.swift`
- Test: `Tests/iOSExploreServerTests/JSONCoderTests.swift`

**Interfaces:**
- Produces:
  - `public enum JSONValue: Sendable, Equatable` — `.string/.double/.bool/.object(JSON)/.array([JSONValue])/.null`，`ExpressibleBy*Literal`
  - `public struct JSON: Sendable, Equatable` — `storage: [String: JSONValue]`，`subscript(String) -> JSONValue?`，`ExpressibleByDictionaryLiteral`
  - `public struct ExploreRequest: Sendable, Equatable` — `action: String`、`data: JSON`
  - `public enum ExploreResult: Sendable, Equatable` — `.success(JSON)` / `.failure(code: ExploreError, message: String)`
  - `public enum ExploreError: String, Sendable` — `unknownAction/invalidData/internalError/badRequest`
  - `enum JSONCoder` — `static func encode(_ json: JSON) -> Data`、`static func decode(_ data: Data) -> JSON?`

- [ ] **Step 1: 写失败的测试 `JSONCoderTests.swift`**

```swift
import Testing
import Foundation
@testable import iOSExploreServer

@Test("JSON 字典字面量构造与下标")
func jsonLiteralAndSubscript() {
    let json: JSON = ["pong": true, "count": 3, "name": "hi"]
    #expect(json["pong"] == .bool(true))
    #expect(json["count"] == .double(3))
    #expect(json["name"]?.stringValue == "hi")
}

@Test("encode/decode 往返")
func coderRoundTrip() throws {
    let original: JSON = ["ok": true, "msg": "hi", "n": 1.5]
    let data = JSONCoder.encode(original)
    let decoded = try #require(JSONCoder.decode(data))
    #expect(decoded["ok"] == .bool(true))
    #expect(decoded["msg"]?.stringValue == "hi")
    #expect(decoded["n"]?.doubleValue == 1.5)
}

@Test("decode 非法 JSON 返回 nil")
func decodeInvalid() {
    #expect(JSONCoder.decode(Data("not json".utf8)) == nil)
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter JSONCoder`
Expected: FAIL — `cannot find 'JSON'/'JSONCoder' in scope`

- [ ] **Step 3: 实现 `Models.swift`**

```swift
import Foundation

/// 类型擦除的 JSON 值，承载命令的 data 载荷。
public enum JSONValue: Sendable, Equatable {
    case string(String)
    case double(Double)
    case bool(Bool)
    case object(JSON)
    case array([JSONValue])
    case null
}

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}
extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .double(Double(value)) }
}
extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}
extension JSONValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) { self = .null }
}

extension JSONValue {
    public var stringValue: String? { if case .string(let v) = self { return v } else { return nil } }
    public var doubleValue: Double? { if case .double(let v) = self { return v } else { return nil } }
    public var boolValue: Bool? { if case .bool(let v) = self { return v } else { return nil } }
}

/// JSON 对象容器：String 键 → JSONValue。
public struct JSON: Sendable, Equatable {
    public var storage: [String: JSONValue]
    public init(_ storage: [String: JSONValue] = [:]) { self.storage = storage }

    public subscript(key: String) -> JSONValue? {
        get { storage[key] }
        set { storage[key] = newValue }
    }
}

extension JSON: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self.storage = Dictionary(uniqueKeysWithValues: elements)
    }
}

/// 命令请求。
public struct ExploreRequest: Sendable, Equatable {
    public let action: String
    public let data: JSON
    public init(action: String, data: JSON = [:]) {
        self.action = action
        self.data = data
    }
}

/// 命令结果。
public enum ExploreResult: Sendable, Equatable {
    case success(JSON)
    case failure(code: ExploreError, message: String)
}

/// 错误码（与 envelope 中 error.code 一致）。
public enum ExploreError: String, Sendable {
    case unknownAction = "unknown_action"
    case invalidData = "invalid_data"
    case internalError = "internal_error"
    case badRequest = "bad_request"
}
```

- [ ] **Step 4: 实现 `JSONCoder.swift`**

```swift
import Foundation

/// JSON 与 Data/Any 之间的编解码（基于 JSONSerialization）。
enum JSONCoder {
    static func encode(_ json: JSON) -> Data {
        (try? JSONSerialization.data(withJSONObject: toAny(json),
                                     options: [.sortedKeys])) ?? Data()
    }

    static func decode(_ data: Data) -> JSON? {
        guard let any = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return fromAny(any)
    }

    static func toAny(_ json: JSON) -> [String: Any] {
        var dict: [String: Any] = [:]
        for (k, v) in json.storage { dict[k] = toAny(v) }
        return dict
    }

    static func toAny(_ value: JSONValue) -> Any {
        switch value {
        case .string(let s): return s
        case .double(let d): return d
        case .bool(let b): return b
        case .object(let o): return toAny(o)
        case .array(let a): return a.map { toAny($0) }
        case .null: return NSNull()
        }
    }

    static func fromAny(_ any: Any) -> JSON {
        guard let dict = any as? [String: Any] else { return JSON() }
        var storage: [String: JSONValue] = [:]
        for (k, v) in dict { storage[k] = fromAnyValue(v) }
        return JSON(storage)
    }

    static func fromAnyValue(_ any: Any) -> JSONValue {
        switch any {
        case let s as String:
            return .string(s)
        case let n as NSNumber:
            // NSNumber 可能包装 bool，用 CFBooleanGetTypeID 区分。
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return .bool(n.boolValue)
            }
            return .double(n.doubleValue)
        case let d as [String: Any]:
            return .object(fromAny(d))
        case let a as [Any]:
            return .array(a.map { fromAnyValue($0) })
        default:
            return .null
        }
    }
}
```

- [ ] **Step 5: 运行测试确认通过**

Run: `swift test --filter JSONCoder`
Expected: PASS（3 个测试）

- [ ] **Step 6: 提交**

```bash
git add Sources/iOSExploreServer/Models.swift Sources/iOSExploreServer/JSONCoder.swift Tests/iOSExploreServerTests/JSONCoderTests.swift
git commit -m "feat: add JSON value types and coder"
```

---

## Task 2: HTTP 请求/响应值类型

**Files:**
- Create: `Sources/iOSExploreServer/HTTPRequest.swift`
- Create: `Sources/iOSExploreServer/HTTPResponse.swift`
- Test: `Tests/iOSExploreServerTests/HTTPResponseTests.swift`

**Interfaces:**
- Produces:
  - `struct HTTPRequest: Sendable, Equatable` — `method/path/headers/body`
  - `struct HTTPResponse: Sendable` — `status/reason/body` + `func serialized() -> Data`

- [ ] **Step 1: 写失败的测试**

```swift
import Testing
import Foundation
@testable import iOSExploreServer

@Test("响应报文序列化包含状态行、头与 body")
func responseSerialized() {
    let body = Data(#"{"ok":true}"#.utf8)
    let resp = HTTPResponse(status: 200, reason: "OK", body: body)
    let text = String(data: resp.serialized(), encoding: .utf8) ?? ""

    #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
    #expect(text.contains("Content-Type: application/json"))
    #expect(text.contains("Content-Length: \(body.count)"))
    #expect(text.contains("\r\n\r\n{\"ok\":true}"))
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter HTTPResponse`
Expected: FAIL — `cannot find 'HTTPResponse' in scope`

- [ ] **Step 3: 实现 `HTTPRequest.swift`**

```swift
import Foundation

struct HTTPRequest: Sendable, Equatable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    init(method: String, path: String,
         headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }
}
```

- [ ] **Step 4: 实现 `HTTPResponse.swift`**

```swift
import Foundation

struct HTTPResponse: Sendable {
    let status: Int
    let reason: String
    let body: Data

    /// 序列化为完整 HTTP/1.1 响应报文。
    func serialized() -> Data {
        let headLines = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: application/json",
            "Content-Length: \(body.count)",
            "Connection: close",
        ]
        let head = headLines.joined(separator: "\r\n") + "\r\n\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }
}
```

- [ ] **Step 5: 运行测试确认通过**

Run: `swift test --filter HTTPResponse`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add Sources/iOSExploreServer/HTTPRequest.swift Sources/iOSExploreServer/HTTPResponse.swift Tests/iOSExploreServerTests/HTTPResponseTests.swift
git commit -m "feat: add HTTP request/response value types"
```

---

## Task 3: HTTP 解析与 envelope 响应构造

**Files:**
- Create: `Sources/iOSExploreServer/HTTPParser.swift`
- Test: `Tests/iOSExploreServerTests/HTTPParserTests.swift`

**Interfaces:**
- Consumes: `HTTPRequest`、`HTTPResponse`、`JSON`、`JSONCoder`、`ExploreRequest`、`ExploreResult`、`ExploreError`
- Produces:
  - `enum HTTPParser`
  - `static func parseRequest(from buffer: Data) -> (request: HTTPRequest, consumed: Int)?`
  - `static func exploreRequest(from body: Data) -> ExploreRequest?`
  - `static func response(for result: ExploreResult) -> HTTPResponse`
  - `static func errorResponse(status: Int, reason: String, code: ExploreError, message: String) -> HTTPResponse`

- [ ] **Step 1: 写失败的测试**

```swift
import Testing
import Foundation
@testable import iOSExploreServer

@Test("解析完整 POST 请求（带 body）")
func parseFullRequest() {
    let raw = Data("POST / HTTP/1.1\r\nContent-Length: 17\r\n\r\n{\"action\":\"ping\"}".utf8)
    let parsed = HTTPParser.parseRequest(from: raw)
    let req = try #require(parsed?.request)
    #expect(req.method == "POST")
    #expect(req.path == "/")
    #expect(req.headers["content-length"] == "17")
    #expect(String(data: req.body, encoding: .utf8) == #"{"action":"ping"}"#)
}

@Test("数据不完整时返回 nil")
func parseIncomplete() {
    let raw = Data("POST / HTTP/1.1\r\nContent-Length: 100\r\n\r\n{}".utf8)
    #expect(HTTPParser.parseRequest(from: raw) == nil)
}

@Test("从 body 提取 ExploreRequest")
func exploreRequestFromBody() {
    let body = Data(#"{"action":"echo","data":{"x":1}}"#.utf8)
    let req = try #require(HTTPParser.exploreRequest(from: body))
    #expect(req.action == "echo")
    #expect(req.data["x"] == .double(1))
}

@Test("缺 action 返回 nil")
func exploreRequestMissingAction() {
    let body = Data(#"{"data":{}}"#.utf8)
    #expect(HTTPParser.exploreRequest(from: body) == nil)
}

@Test("success 结果序列化为 ok:true envelope")
func responseForSuccess() {
    let resp = HTTPParser.response(for: .success(["pong": true]))
    let text = String(data: resp.body, encoding: .utf8) ?? ""
    #expect(text.contains(#""ok":true"#))
    #expect(text.contains(#""data":{"pong":true}"#))
    #expect(resp.status == 200)
}

@Test("failure 结果序列化为 ok:false envelope")
func responseForFailure() {
    let resp = HTTPParser.response(for: .failure(code: .unknownAction, message: "no handler"))
    let text = String(data: resp.body, encoding: .utf8) ?? ""
    #expect(text.contains(#""ok":false"#))
    #expect(text.contains(#""code":"unknown_action""#))
    #expect(text.contains(#""message":"no handler""#))
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter HTTPParser`
Expected: FAIL — `cannot find 'HTTPParser' in scope`

- [ ] **Step 3: 实现 `HTTPParser.swift`**

```swift
import Foundation

enum HTTPParser {
    private static let headerSeparator = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n

    /// 从累积 buffer 解析一个完整 HTTP/1.1 请求；数据不完整返回 nil。
    static func parseRequest(from buffer: Data) -> (request: HTTPRequest, consumed: Int)? {
        guard let sepRange = buffer.range(of: headerSeparator) else { return nil }
        let headerData = buffer[..<sepRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }

        var lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        lines.removeFirst()

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count == 3 else { return nil }
        let method = parts[0]
        let path = parts[1]

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = sepRange.upperBound
        guard buffer.count - bodyStart >= contentLength else { return nil }
        let body = buffer[bodyStart..<(bodyStart + contentLength)]

        return (HTTPRequest(method: method, path: path, headers: headers, body: Data(body)),
                bodyStart + contentLength)
    }

    /// 从请求 body 解析出 ExploreRequest（缺 action 或非 JSON 返回 nil）。
    static func exploreRequest(from body: Data) -> ExploreRequest? {
        guard let json = JSONCoder.decode(body) else { return nil }
        guard case .string(let action)? = json["action"] else { return nil }
        let data: JSON = {
            if case .object(let o)? = json["data"] { return o }
            return JSON()
        }()
        return ExploreRequest(action: action, data: data)
    }

    /// 业务结果 → HTTP 响应（统一 envelope）。
    static func response(for result: ExploreResult) -> HTTPResponse {
        switch result {
        case .success(let data):
            let body: JSON = ["ok": .bool(true), "data": .object(data)]
            return HTTPResponse(status: 200, reason: "OK", body: JSONCoder.encode(body))
        case .failure(let code, let message):
            let error: JSON = ["code": .string(code.rawValue), "message": .string(message)]
            let body: JSON = ["ok": .bool(false), "error": .object(error)]
            return HTTPResponse(status: 200, reason: "OK", body: JSONCoder.encode(body))
        }
    }

    /// 通信层错误响应（非业务 ExploreResult）。
    static func errorResponse(status: Int, reason: String,
                              code: ExploreError, message: String) -> HTTPResponse {
        let error: JSON = ["code": .string(code.rawValue), "message": .string(message)]
        let body: JSON = ["ok": .bool(false), "error": .object(error)]
        return HTTPResponse(status: status, reason: reason, body: JSONCoder.encode(body))
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --filter HTTPParser`
Expected: PASS（6 个测试）

- [ ] **Step 5: 提交**

```bash
git add Sources/iOSExploreServer/HTTPParser.swift Tests/iOSExploreServerTests/HTTPParserTests.swift
git commit -m "feat: add HTTP parser and envelope response builder"
```

---

## Task 4: 命令路由（actor）

**Files:**
- Create: `Sources/iOSExploreServer/Router.swift`
- Test: `Tests/iOSExploreServerTests/RouterTests.swift`

**Interfaces:**
- Consumes: `ExploreRequest`、`ExploreResult`、`ExploreError`
- Produces:
  - `public actor Router`
  - `public typealias Handler = @Sendable (ExploreRequest) async throws -> ExploreResult`
  - `public init()`
  - `public func register(action: String, _ handler: @escaping Handler)`
  - `func route(_ request: ExploreRequest) async -> ExploreResult`

- [ ] **Step 1: 写失败的测试**

```swift
import Testing
@testable import iOSExploreServer

@Test("注册的 action 被命中并返回 success")
func routeHitsRegistered() async {
    let router = Router()
    await router.register(action: "hello") { _ in .success(["msg": "hi"]) }
    let result = await router.route(ExploreRequest(action: "hello"))
    if case .success(let data) = result {
        #expect(data["msg"]?.stringValue == "hi")
    } else {
        Issue.record("expected success")
    }
}

@Test("未注册的 action 返回 unknown_action")
func routeUnknown() async {
    let router = Router()
    let result = await router.route(ExploreRequest(action: "nope"))
    if case .failure(let code, _) = result {
        #expect(code == .unknownAction)
    } else {
        Issue.record("expected failure")
    }
}

@Test("handler 抛异常转为 internal_error")
func routeThrowing() async {
    let router = Router()
    struct Boom: Error {}
    await router.register(action: "boom") { _ in throw Boom() }
    let result = await router.route(ExploreRequest(action: "boom"))
    if case .failure(let code, _) = result {
        #expect(code == .internalError)
    } else {
        Issue.record("expected failure")
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter Router`
Expected: FAIL — `cannot find 'Router' in scope`

- [ ] **Step 3: 实现 `Router.swift`**

```swift
import Foundation

/// 命令分发：action 名称 → handler。共享可变状态用 actor 保护。
public actor Router {
    public typealias Handler = @Sendable (ExploreRequest) async throws -> ExploreResult

    private var handlers: [String: Handler] = [:]

    public init() {}

    public func register(action: String, _ handler: @escaping Handler) {
        handlers[action] = handler
    }

    /// 按 action 查表分发；未命中或 handler 抛错都返回业务失败，不向外抛。
    func route(_ request: ExploreRequest) async -> ExploreResult {
        guard let handler = handlers[request.action] else {
            return .failure(code: .unknownAction,
                            message: "no handler for '\(request.action)'")
        }
        do {
            return try await handler(request)
        } catch {
            return .failure(code: .internalError, message: error.localizedDescription)
        }
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --filter Router`
Expected: PASS（3 个测试）

- [ ] **Step 5: 提交**

```bash
git add Sources/iOSExploreServer/Router.swift Tests/iOSExploreServerTests/RouterTests.swift
git commit -m "feat: add command router actor"
```

---

## Task 5: 内置命令 ping/echo/info

**Files:**
- Create: `Sources/iOSExploreServer/Handlers/BuiltinHandlers.swift`
- Test: `Tests/iOSExploreServerTests/BuiltinHandlersTests.swift`

**Interfaces:**
- Consumes: `ExploreRequest`、`ExploreResult`、`Router`
- Produces:
  - `enum BuiltinHandlers`
  - `static func ping(_ req: ExploreRequest) -> ExploreResult`
  - `static func echo(_ req: ExploreRequest) -> ExploreResult`
  - `static func info(_ req: ExploreRequest) -> ExploreResult`
  - `static func registerAll(into router: Router) async`

- [ ] **Step 1: 写失败的测试**

```swift
import Testing
@testable import iOSExploreServer

@Test("ping 返回 pong")
func pingReturns() {
    let result = BuiltinHandlers.ping(ExploreRequest(action: "ping"))
    if case .success(let data) = result {
        #expect(data["pong"] == .bool(true))
    } else { Issue.record("expected success") }
}

@Test("echo 原样回显 data")
func echoReturns() {
    let req = ExploreRequest(action: "echo", data: ["a": 1, "b": "x"])
    let result = BuiltinHandlers.echo(req)
    if case .success(let data) = result {
        #expect(data["a"] == .double(1))
        #expect(data["b"]?.stringValue == "x")
    } else { Issue.record("expected success") }
}

@Test("info 返回 system/app/bundle 字段")
func infoReturns() {
    let result = BuiltinHandlers.info(ExploreRequest(action: "info"))
    if case .success(let data) = result {
        #expect(data["system"]?.stringValue != nil)
        #expect(data["app"]?.stringValue != nil)
        #expect(data["bundle"]?.stringValue != nil)
    } else { Issue.record("expected success") }
}

@Test("registerAll 注册三个命令")
func registerAllRegisters() async {
    let router = Router()
    await BuiltinHandlers.registerAll(into: router)
    for action in ["ping", "echo", "info"] {
        let r = await router.route(ExploreRequest(action: action))
        if case .failure = r { Issue.record("\(action) should be registered") }
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter BuiltinHandlers`
Expected: FAIL — `cannot find 'BuiltinHandlers' in scope`

- [ ] **Step 3: 实现 `Handlers/BuiltinHandlers.swift`**

```swift
import Foundation

/// 内置命令。库内不依赖 UIKit；info 仅返回 ProcessInfo/Bundle 可得字段。
enum BuiltinHandlers {
    static func ping(_ req: ExploreRequest) -> ExploreResult {
        .success(["pong": .bool(true)])
    }

    static func echo(_ req: ExploreRequest) -> ExploreResult {
        .success(req.data)
    }

    static func info(_ req: ExploreRequest) -> ExploreResult {
        let processInfo = ProcessInfo.processInfo
        let bundle = Bundle.main
        let info: JSON = [
            "system": .string(processInfo.operatingSystemVersionString),
            "app": .string((bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"),
            "bundle": .string(bundle.bundleIdentifier ?? "unknown"),
        ]
        return .success(info)
    }

    /// 把三个内置命令注册进 router。
    static func registerAll(into router: Router) async {
        await router.register(action: "ping") { ping($0) }
        await router.register(action: "echo") { echo($0) }
        await router.register(action: "info") { info($0) }
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --filter BuiltinHandlers`
Expected: PASS（4 个测试）

- [ ] **Step 5: 提交**

```bash
git add Sources/iOSExploreServer/Handlers/BuiltinHandlers.swift Tests/iOSExploreServerTests/BuiltinHandlersTests.swift
git commit -m "feat: add builtin ping/echo/info handlers"
```

---

## Task 6: NWListener 封装（HTTP 传输层）

**Files:**
- Create: `Sources/iOSExploreServer/HTTPListener.swift`

**Interfaces:**
- Consumes: `Router`、`HTTPParser`、`HTTPRequest`、`HTTPResponse`、`ServerEvent`（Task 7 定义，本任务先声明在一个共享位置——见下方说明）
- Produces:
  - `final class HTTPListener: @unchecked Sendable`
  - `init(port: UInt16, router: Router, onEvent: @escaping @Sendable (ServerEvent) -> Void) throws`
  - `func start()`
  - `func stop()`

> **依赖说明**：`ServerEvent` 在 Task 7 的 `ExploreServer.swift` 定义。为避免循环，**先在本任务里于 `HTTPListener.swift` 顶部声明 `ServerEvent`**，Task 7 实现时**删除** `HTTPListener.swift` 里的声明，改由 `ExploreServer.swift` 提供（两者在同一 module，无需 import）。Task 6 的验证靠 Task 8 的集成测试（NWListener 无法纯单测）。

- [ ] **Step 1: 实现 `HTTPListener.swift`**

```swift
import Foundation
import Network

// Task 7 将把 ServerEvent 移到 ExploreServer.swift。
public enum ServerEvent: Sendable {
    case started(port: UInt16)
    case stopped
    case received(method: String, path: String, action: String?)
    case responded(status: Int, ok: Bool)
    case error(String)
}

/// NWListener 封装：接连接 → 解析 HTTP → 路由 → 回写响应。
/// start/stop 由调用方串行调用（App 主线程按钮），不保证并发安全启停。
final class HTTPListener: @unchecked Sendable {
    private let port: UInt16
    private let router: Router
    private let onEvent: @Sendable (ServerEvent) -> Void
    private var listener: NWListener?

    init(port: UInt16, router: Router,
         onEvent: @escaping @Sendable (ServerEvent) -> Void) throws {
        self.port = port
        self.router = router
        self.onEvent = onEvent
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "HTTPListener", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "invalid port \(port)"])
        }
        self.listener = try NWListener(using: .tcp, on: nwPort)
    }

    func start() {
        guard let listener else { return }
        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        listener.start(queue: .global())
        onEvent(.started(port: port))
    }

    func stop() {
        listener?.cancel()
        listener = nil
        onEvent(.stopped)
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global())
        Task { [router, onEvent] in
            var buffer = Data()
            var request: HTTPRequest?
            while request == nil {
                guard let chunk = await Self.receive(conn) else { conn.cancel(); return }
                buffer.append(chunk)
                if buffer.count > 1_000_000 { conn.cancel(); return } // 上限保护
                request = HTTPParser.parseRequest(from: buffer)?.request
            }
            await Self.process(request: request!, on: conn, router: router, onEvent: onEvent)
        }
    }

    private static func process(request: HTTPRequest, on conn: NWConnection,
                                router: Router,
                                onEvent: @Sendable (ServerEvent) -> Void) async {
        // 非法方法/路径
        guard request.method == "POST", request.path == "/" else {
            send(HTTPParser.errorResponse(status: 400, reason: "Bad Request",
                                          code: .badRequest,
                                          message: "only POST / is supported"), on: conn)
            onEvent(.responded(status: 400, ok: false))
            return
        }
        // 解析 action
        guard let exploreReq = HTTPParser.exploreRequest(from: request.body) else {
            send(HTTPParser.errorResponse(status: 400, reason: "Bad Request",
                                          code: .badRequest,
                                          message: "invalid JSON or missing 'action'"), on: conn)
            onEvent(.responded(status: 400, ok: false))
            return
        }
        onEvent(.received(method: request.method, path: request.path, action: exploreReq.action))
        let result = await router.route(exploreReq)
        send(HTTPParser.response(for: result), on: conn)
        let ok: Bool
        if case .success = result { ok = true } else { ok = false }
        onEvent(.responded(status: 200, ok: ok))
    }

    private static func receive(_ conn: NWConnection) async -> Data? {
        await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                if error != nil { cont.resume(returning: nil) }
                else { cont.resume(returning: data) }
            }
        }
    }

    private static func send(_ response: HTTPResponse, on conn: NWConnection) {
        conn.send(content: response.serialized(), completion: .contentProcessed { _ in
            conn.cancel()   // Connection: close：发完响应即关闭连接
        })
    }
}
```

- [ ] **Step 2: 编译确认**

Run: `swift build`
Expected: BUILD SUCCEEDED（无类型错误）

- [ ] **Step 3: 提交**

```bash
git add Sources/iOSExploreServer/HTTPListener.swift
git commit -m "feat: add NWListener-based HTTP transport"
```

---

## Task 7: 门面 ExploreServer + 事件流整合

**Files:**
- Create: `Sources/iOSExploreServer/ExploreServer.swift`
- Modify: `Sources/iOSExploreServer/HTTPListener.swift`（删除顶部 `ServerEvent` 声明，移到本文件）

**Interfaces:**
- Consumes: `Router`、`HTTPListener`、`BuiltinHandlers`、`ServerEvent`
- Produces（对外公共 API）:
  - `public final class ExploreServer: @unchecked Sendable`
  - `public init(port: UInt16 = 38321, authToken: String? = nil)`
  - `public func register(action: String, _ handler: @escaping @Sendable (ExploreRequest) async throws -> ExploreResult) async`
  - `public func start() async throws`
  - `public func stop()`
  - `public func events() -> AsyncStream<ServerEvent>`

- [ ] **Step 1: 实现 `ExploreServer.swift`（含 `ServerEvent`）**

```swift
import Foundation
import Network

public enum ServerEvent: Sendable {
    case started(port: UInt16)
    case stopped
    case received(method: String, path: String, action: String?)
    case responded(status: Int, ok: Bool)
    case error(String)
}

/// 对外门面：组合 Router + HTTPListener + 内置命令，暴露最简 API 与事件流。
public final class ExploreServer: @unchecked Sendable {
    private let port: UInt16
    private let router: Router
    private var listener: HTTPListener?
    private let eventContinuation: AsyncStream<ServerEvent>.Continuation
    private let eventStream: AsyncStream<ServerEvent>

    /// 预留鉴权令牌：设置后未来版本会校验请求头 `X-Auth-Token`（MVP 不校验）。
    public let authToken: String?

    public init(port: UInt16 = 38321, authToken: String? = nil) {
        self.port = port
        self.authToken = authToken
        self.router = Router()
        var continuation: AsyncStream<ServerEvent>.Continuation!
        self.eventStream = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
    }

    public func register(action: String,
                          _ handler: @escaping @Sendable (ExploreRequest) async throws -> ExploreResult) async {
        await router.register(action: action, handler)
    }

    public func start() async throws {
        await BuiltinHandlers.registerAll(into: router)
        let l = try HTTPListener(port: port, router: router) { [eventContinuation] event in
            eventContinuation.yield(event)
        }
        l.start()
        self.listener = l
    }

    public func stop() {
        listener?.stop()
        listener = nil
    }

    public func events() -> AsyncStream<ServerEvent> {
        eventStream
    }
}
```

- [ ] **Step 2: 从 `HTTPListener.swift` 删除 `ServerEvent` 声明**

删除 Task 6 写入的这段（已移到 `ExploreServer.swift`）：

```swift
// Task 7 将把 ServerEvent 移到 ExploreServer.swift。
public enum ServerEvent: Sendable {
    case started(port: UInt16)
    case stopped
    case received(method: String, path: String, action: String?)
    case responded(status: Int, ok: Bool)
    case error(String)
}
```

保留 `HTTPListener.swift` 其余内容。

- [ ] **Step 3: 编译确认**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: 提交**

```bash
git add Sources/iOSExploreServer/ExploreServer.swift Sources/iOSExploreServer/HTTPListener.swift
git commit -m "feat: add ExploreServer facade and event stream"
```

---

## Task 8: 端到端集成测试

**Files:**
- Test: `Tests/iOSExploreServerTests/IntegrationTests.swift`

**Interfaces:**
- Consumes: `ExploreServer`、`JSONCoder`

- [ ] **Step 1: 写集成测试**

```swift
import Testing
import Foundation
import Network
@testable import iOSExploreServer

/// 集成测试用固定端口，避开生产默认 38321。
private let testPort: UInt16 = 38399

@Test("端到端 ping 经真实 TCP 往返")
func endToEndPing() async throws {
    let server = ExploreServer(port: testPort)
    try await server.start()
    defer { server.stop() }

    let text = try await send(action: "ping")
    #expect(text.contains(#""ok":true"#))
    #expect(text.contains(#""pong":true"#))
}

@Test("端到端 echo 回显")
func endToEndEcho() async throws {
    let server = ExploreServer(port: testPort)
    try await server.start()
    defer { server.stop() }

    let text = try await send(action: "echo", data: ["hi": "claude"])
    #expect(text.contains(#""hi":"claude""#))
}

@Test("未知 action 返回 unknown_action envelope")
func endToEndUnknown() async throws {
    let server = ExploreServer(port: testPort)
    try await server.start()
    defer { server.stop() }

    let text = try await send(action: "nope")
    #expect(text.contains(#""ok":false"#))
    #expect(text.contains(#""code":"unknown_action""#))
}

@Test("自定义注册命令经 HTTP 可达")
func endToEndCustom() async throws {
    let server = ExploreServer(port: testPort)
    await server.register(action: "greet") { req in
        let name = req.data["name"]?.stringValue ?? "world"
        return .success(["message": .string("Hello, \(name)")])
    }
    try await server.start()
    defer { server.stop() }

    let text = try await send(action: "greet", data: ["name": "Claude"])
    #expect(text.contains(#""message":"Hello, Claude""#))
}

/// 发送一条命令并返回响应文本。
private func send(action: String, data: JSON = [:]) async throws -> String {
    let payload: JSON = ["action": .string(action), "data": .object(data)]
    let body = JSONCoder.encode(payload)
    let request = Data("POST / HTTP/1.1\r\nContent-Length: \(body.count)\r\n\r\n".utf8) + body

    let conn = NWConnection(host: .ipv4(.loopback),
                            port: NWEndpoint.Port(rawValue: testPort)!,
                            using: .tcp)
    conn.start(queue: .global())
    try await waitUntilReady(conn)

    return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
        conn.send(content: request, completion: .contentProcessed { _ in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: String(data: data ?? Data(), encoding: .utf8) ?? "")
            }
        })
    }
}

private func waitUntilReady(_ conn: NWConnection) async throws {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                cont.resume()
                conn.stateUpdateHandler = nil   // 防止后续 cancelled 回调重复 resume
            case .failed(let err):
                cont.resume(throwing: err)
                conn.stateUpdateHandler = nil
            default:
                break
            }
        }
    }
}
```

- [ ] **Step 2: 运行集成测试确认通过**

Run: `swift test --filter Integration`
Expected: PASS（4 个测试）

- [ ] **Step 3: 跑全量测试 + 覆盖率**

Run: `swift test --enable-code-coverage`
Expected: 全部 PASS；覆盖率 ≥ 80%（用 `xcrun llvm-cov` 或 Xcode 查看库覆盖率）

- [ ] **Step 4: 提交**

```bash
git add Tests/iOSExploreServerTests/IntegrationTests.swift
git commit -m "test: add end-to-end integration tests"
```

---

## Task 9: framework 工程源码统一（共享根 Sources）

**Files:**
- Modify: `iOSExploreServer/iOSExploreServer.xcodeproj/project.pbxproj`
- Delete: `iOSExploreServer/iOSExploreServer/iOSExploreServer.swift`
- Delete: `iOSExploreServer/iOSExploreServer/iOSExploreServer.docc/iOSExploreServer.md`（空文档，可删）
- Delete: `iOSExploreServer/iOSExploreServerTests/iOSExploreServerTests.swift`（占位，改用根 Tests 或留空）

**Goal**：让 framework 工程编译根 `Sources/iOSExploreServer/` 的同一份源码，与 SPM 包零漂移。

- [ ] **Step 1: 修改同步组 path**

打开 `iOSExploreServer/iOSExploreServer.xcodeproj/project.pbxproj`，把 framework target 的同步组 path：

```
FBBA96F32FE8056B009FFEC3 /* iOSExploreServer */ = {
    isa = PBXFileSystemSynchronizedRootGroup;
    path = iOSExploreServer;          ← 改为 ../Sources/iOSExploreServer
    sourceTree = "<group>";
};
```

改为 `path = "../Sources/iOSExploreServer";`。tests 同步组（`FBBA97002FE8056B009FFEC3`）path 改为 `path = "../Tests/iOSExploreServerTests";`。

> 工程容器目录是 `iOSExploreServer/`（含 `.xcodeproj`），`..` 回到仓库根，再进 `Sources/iOSExploreServer`。

- [ ] **Step 2: 删除独立源码副本**

```bash
rm iOSExploreServer/iOSExploreServer/iOSExploreServer.swift
rm -rf iOSExploreServer/iOSExploreServer/iOSExploreServer.docc
rm iOSExploreServer/iOSExploreServerTests/iOSExploreServerTests.swift
```

（保留 `iOSExploreServer/iOSExploreServer/` 与 `iOSExploreServer/iOSExploreServerTests/` 空目录无意义，可一并删除整层；但同步组 path 已指向根 Sources，原目录不再被引用。）

- [ ] **Step 3: 验证 framework 工程编译**

Run: `xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator build`
Expected: BUILD SUCCEEDED。

> **验证点**：若 Xcode 26 不接受指向工程目录外的相对路径（报错 "missing file" 或同步组不生效），改用**备选方案**：在 `iOSExploreServer/` 下建 symlink `ln -s ../Sources/iOSExploreServer iOSExploreServer/iOSExploreServer`，同步组 path 保持 `iOSExploreServer`。两者都验证不过再回退讨论。

- [ ] **Step 4: 验证 SPM 仍可编译**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: 提交**

```bash
git add iOSExploreServer/iOSExploreServer.xcodeproj/project.pbxproj
git add -A iOSExploreServer/iOSExploreServer/ iOSExploreServer/iOSExploreServerTests/
git commit -m "chore: point framework project at shared Sources/"
```

---

## Task 10: iproxy 脚本 + README

**Files:**
- Create: `scripts/proxy.sh`
- Create: `README.md`

- [ ] **Step 1: 创建 `scripts/proxy.sh`**

```bash
#!/usr/bin/env bash
# 一键起 iproxy 转发到 iOSExploreServer（前台运行，Ctrl-C 停止）。
set -euo pipefail

PORT="${PORT:-38321}"

if ! command -v iproxy >/dev/null 2>&1; then
  echo "未找到 iproxy，正在安装 libimobiledevice..." >&2
  brew install libimobiledevice
fi

echo "转发 Mac :${PORT} <-> 设备 :${PORT}（Ctrl-C 停止）"
exec iproxy "${PORT}" "${PORT}"
```

- [ ] **Step 2: 赋予执行权限**

Run: `chmod +x scripts/proxy.sh`

- [ ] **Step 3: 创建 `README.md`**

```markdown
# iOSExploreServer

手机端 HTTP Server（基于 `NWListener`），让 Mac 经 iproxy 转发后用 curl 向 App 发送命令。SPM 库 + 可编译的 framework 工程。

## 通信链路

```
Mac curl ──→ localhost:38321 ──[iproxy 38321 38321]──→ iPhone :38321 ──→ ExploreServer
```

## 快速开始

1. 在手机上运行集成了 iOSExploreServer 的 App（见 `Examples/SPMExample`），点击「启动 Server」。
2. Mac 上起转发：
   ```bash
   ./scripts/proxy.sh
   ```
3. 另开终端发命令：
   ```bash
   curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
   curl -X POST http://localhost:38321/ -d '{"action":"info"}'
   ```

## 命令协议

请求：`POST /`，body `{"action":"<name>","data":{...}}`。
响应：`{"ok":true,"data":{...}}` 或 `{"ok":false,"error":{"code":"...","message":"..."}}`。

内置命令：`ping`、`echo`、`info`。

### 注册自定义命令

```swift
await server.register(action: "greet") { req in
    let name = req.data["name"]?.stringValue ?? "world"
    return .success(["message": .string("Hello, \(name)")])
}
```

## 开发

```bash
swift test                 # 运行测试
swift test --enable-code-coverage
```

端口默认 `38321`，构造时可配。MVP 不做强制鉴权（依赖 USB 物理连接），App 须保持前台。
```

- [ ] **Step 4: 提交**

```bash
git add scripts/proxy.sh README.md
git commit -m "docs: add iproxy script and README"
```

---

## Task 11: SPMExample 测试 App

**Files:**
- Modify: `Examples/SPMExample/SPMExample/ViewController.swift`（重写为代码布局）
- Modify: `Examples/SPMExample/SPMExample/Info.plist`（加本地网络权限文案）
- Modify: `Examples/SPMExample/SPMExample.xcodeproj/project.pbxproj`（加本地 SPM 依赖 + ViewController.swift 的 storyboard 引用处理）

**Goal**：App 里集成 `iOSExploreServer`，提供「启动/停止」按钮 + 请求日志面板，并演示自定义命令与 UIKit 信息注入。

- [ ] **Step 1: 在 SPMExample 工程添加本地 SPM 依赖（GUI 操作，最可靠）**

用 Xcode 打开 `Examples/SPMExample/SPMExample.xcodeproj`：

1. 菜单 `File → Add Package Dependencies…`
2. 左下角 `Add Local…`，选择仓库根目录（含 `Package.swift` 的 `iOSExploreServer/`）
3. 在 `Add to Project` 选 `SPMExample`，`Add to Target` 选 `SPMExample`，勾选 library `iOSExploreServer`
4. 点 `Add Package`

完成后 `project.pbxproj` 会自动加入 `XCSwiftPackageProductDependency` 与 frameworks 引用。

- [ ] **Step 2: 重写 `ViewController.swift`**

```swift
import UIKit
import iOSExploreServer

final class ViewController: UIViewController {
    private let server = ExploreServer()
    private var logLines: [String] = []
    private let statusLabel = UILabel()
    private let startButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)
    private let tableView = UITableView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "iOSExploreServer"
        setupLayout()
        updateStatus(running: false)

        // 演示自定义命令 + UIKit 信息注入
        Task {
            await server.register(action: "greet") { req in
                let name = req.data["name"]?.stringValue ?? "world"
                return .success(["message": .string("Hello, \(name)")])
            }
            await server.register(action: "device") { _ in
                await MainActor.run {
                    .success(["model": .string(UIDevice.current.model),
                              "name": .string(UIDevice.current.name)])
                }
            }
        }

        // 订阅事件 → 日志面板
        Task { @MainActor in
            for await event in server.events() {
                appendLog(Self.describe(event))
                updateStatus(running: event.isRunning)
            }
        }
    }

    private func setupLayout() {
        statusLabel.font = .systemFont(ofSize: 15, weight: .medium)
        startButton.setTitle("启动 Server", for: .normal)
        stopButton.setTitle("停止", for: .normal)
        startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)

        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = UIStackView(arrangedSubviews: [startButton, stopButton])
        buttonRow.spacing = 16
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let header = UIStackView(arrangedSubviews: [statusLabel, buttonRow])
        header.axis = .vertical
        header.spacing = 12
        header.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(header)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            tableView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func startTapped() {
        Task {
            do { try await server.start() }
            catch { appendLog("启动失败：\(error)") }
        }
    }

    @objc private func stopTapped() {
        server.stop()
    }

    @MainActor
    private func updateStatus(running: Bool) {
        statusLabel.text = running ? "● 监听中 :\(serverPort)" : "○ 已停止"
        statusLabel.textColor = running ? .systemGreen : .secondaryLabel
    }

    private var serverPort: UInt16 { 38321 }

    @MainActor
    private func appendLog(_ line: String) {
        logLines.insert(line, at: 0)
        if logLines.count > 200 { logLines.removeLast() }
        tableView.reloadData()
    }

    private static func describe(_ event: ServerEvent) -> String {
        switch event {
        case .started(let port): return "started :\(port)"
        case .stopped: return "stopped"
        case .received(_, _, let action): return "← POST action=\(action ?? "?")"
        case .responded(let status, let ok): return "→ \(status) ok=\(ok)"
        case .error(let msg): return "error \(msg)"
        }
    }
}

private extension ServerEvent {
    var isRunning: Bool {
        if case .started = self { return true }
        return false
    }
}

extension ViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { logLines.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.text = logLines[indexPath.row]
        config.textFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
        cell.contentConfiguration = config
        return cell
    }
}
```

- [ ] **Step 3: 修改 `Info.plist` 加本地网络权限文案**

在 `Examples/SPMExample/SPMExample/Info.plist` 的顶层 `<dict>` 内加入：

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>用于接收来自 Mac 的调试请求。</string>
```

- [ ] **Step 4: 用 XcodeBuildMCP 构建到模拟器验证**

Run（MCP）: `build_run_sim`（确认 SPMExample scheme + 一个 iPhone 模拟器已设为 session defaults）
Expected: App 启动，显示「○ 已停止」与两个按钮。

- [ ] **Step 5: 手动验证链路（文档化为验收步骤）**

1. 模拟器里点「启动 Server」，状态变「● 监听中 :38321」。
   > 注：模拟器无 USB，`iproxy` 链路需真机；模拟器可用本机 `curl http://127.0.0.1:38321/` 直接打（模拟器与 Mac 共享网络栈）验证 `ping`，日志面板应出现 `← POST action=ping` 与 `→ 200 ok=true`。
2. 真机：连数据线 → 信任 → `./scripts/proxy.sh` → `curl -X POST http://localhost:38321/ -d '{"action":"greet","data":{"name":"Claude"}}'` → App 日志面板与 curl 输出同时出现响应。

- [ ] **Step 6: 提交**

```bash
git add Examples/SPMExample/SPMExample/ViewController.swift Examples/SPMExample/SPMExample/Info.plist Examples/SPMExample/SPMExample.xcodeproj/project.pbxproj
git commit -m "feat: integrate iOSExploreServer into SPMExample with start/stop + log panel"
```

---

## 完成标准（Definition of Done）

- `swift test --enable-code-coverage` 全绿，库覆盖率 ≥ 80%。
- `swift build` 与 framework 工程 `xcodebuild ... build` 均 SUCCEEDED，且共享同一份 `Sources/`。
- SPMExample 能在模拟器启动 Server，Mac `curl 127.0.0.1:38321` ping/info/greet 均返回正确 envelope，App 日志面板实时显示事件。
- 真机经 `./scripts/proxy.sh` + curl 端到端打通。
