# Command 协议与并发模型重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `ExploreServer.register` 同步化、引入承载元数据的 `Command` 协议(含参数 schema)、将 `Router` 从 actor 改为锁保护的 `final class`、使 `ExploreServer` 成为名副其实的 `Sendable`(`@unchecked` 收束到唯一 `Mutex`)、修复 `start()` 端口冲突静默失败。

**Architecture:** 自封装 `os_unfair_lock` 的 `Mutex<Value>` 作为全库唯一 `@unchecked` 边界;`Command` 协议承载 `action`/`description`/`parameters`;`Router` 用 `Mutex<[String: any Command]>` 保护字典,`route` 在锁内仅取命令、锁外做参数校验与 `await handle`;`ExploreServer` 在 `init` 注册内置命令、`listener` 用 `Mutex` 保护。

**Tech Stack:** Swift 6.2(SPM)/Swift 5(framework 工程)、Foundation + Network、Swift Testing(`import Testing`)、`os_unfair_lock`(iOS 10+)。

**Spec:** `docs/superpowers/specs/2026-06-22-command-protocol-redesign.md`

## Global Constraints

(每个任务的要求都隐含包含本节;值逐字取自 spec/AGENTS.md)

- 库源码只 `import Foundation`/`Network`,禁止 `import UIKit`;需要 UIKit 的信息由集成方 App 注册 handler 注入。
- 兼容 SPM(Swift 6.2)与 framework 工程(`SWIFT_VERSION=5.0`):**避免 Swift-6-only 语法**(if/else 表达式、typed throws)。`any Command` 为 Swift 5.6+ 语法——Task 3 引入后必须构建 framework 工程验证;若 5.0 编译失败,全局回退为裸 `Command` 存在类型(语义等价,SPM 6.2 下有 deprecation 警告,可接受)。
- 唯一命令端点 `POST /` + JSON envelope `{"ok":bool,"data"?,"error"?}` 不变。
- 默认端口 38321;集成测试用 38399 且 `@Suite(.serialized)` 串行。
- **`Mutex` 锁内禁止 `await`**——临界区只放纯同步字典访问,`handle`(async)必须在锁外。
- 改完**先 `swift test` 全绿**再说完成;新增命令同步在 `BuiltinHandlersTests` 补测试。

## File Structure

**库源码 `Sources/iOSExploreServer/`**

- Create `Mutex.swift` — `Mutex<Value>`(`os_unfair_lock` 封装,全库唯一 `@unchecked` 边界)。
- Create `Command.swift` — `ParameterKind`、`CommandParameter`、`Command` 协议、`ClosureCommand`(闭包适配器)。
- Modify `Router.swift` — `public actor` → `public final class: Sendable`;`Mutex` 保护字典;新增 `register(_:)`/同步 `register(action:...)`;`route` 锁内外分工 + 参数校验;新增 `commandMetadata()`。
- Modify `ExploreServer.swift` — 删 `@unchecked`、改 `Sendable`;`init` 注册内置命令、删 `registeredBuiltins`;`register` 同步重载;`listener` 改 `Mutex`;`start` await 就绪。
- Modify `HTTPListener.swift` — `start()` → `async throws`;新增 `waitUntilReady(_:)` await `NWListener` 状态。
- Modify `Handlers/BuiltinHandlers.swift` — `ping`/`echo`/`info` 由静态方法改为 `Command` struct;新增 `HelpCommand`;`registerAll(into:)` 改同步。

**测试 `Tests/iOSExploreServerTests/`**

- Create `MutexTests.swift` — 并发递增不丢更新、基本 withLock。
- Create `CommandTests.swift` — `ClosureCommand` 元数据与 handle、默认 `parameters`。
- Modify `RouterTests.swift` — 去 `await register`;加参数校验用例。
- Modify `BuiltinHandlersTests.swift` — 改测命令 struct;加 `help`;`registerAll` 去(await)。
- Modify `IntegrationTests.swift` — 去 `await register`;加端口冲突 throw、参数校验、`help` 端到端。
- Delete `iOSExploreServerTests.swift` — 占位测试,删除。

**集成方 `Examples/SPMExample/`**

- Modify `SPMExample/ViewController.swift` — `register` 去 `await`(同步注册,移出 `Task`)。

**规则文档**

- Modify `.claude/rules/handlers-rules.md` — handler 签名/注册方式规则重写。
- Modify `.claude/rules/library-rules.md` — 加"锁内禁 await"、并发模型条目。
- Modify `AGENTS.md` — 模块边界/关键约束里 handler 签名描述更新(`CLAUDE.md` 仅 `@AGENTS.md`,无需改)。

---

## Task 1: Mutex 封装

**Files:**
- Create: `Sources/iOSExploreServer/Mutex.swift`
- Test: `Tests/iOSExploreServerTests/MutexTests.swift`

**Interfaces:**
- Produces: `public final class Mutex<Value>: @unchecked Sendable`,`init(_ initial: Value)`、`withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R`。

- [ ] **Step 1: 写失败测试**

Create `Tests/iOSExploreServerTests/MutexTests.swift`:

```swift
import Testing
@testable import iOSExploreServer

@Test("withLock 串行化并发递增,不丢更新")
func mutexSerializesConcurrentIncrement() async {
    let mutex = Mutex(0)
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<1000 {
            group.addTask { mutex.withLock { $0 += 1 } }
        }
    }
    #expect(mutex.withLock { $0 } == 1000)
}

@Test("withLock 支持读取并返回变换值")
func withLockReturnsValue() {
    let mutex = Mutex(42)
    let doubled = mutex.withLock { $0 * 2 }
    #expect(doubled == 84)
    #expect(mutex.withLock { $0 } == 42)
}
```

- [ ] **Step 2: 运行测试验证失败**

Run: `swift test --filter MutexTests`
Expected: FAIL —— `cannot find 'Mutex' in scope`

- [ ] **Step 3: 写最小实现**

Create `Sources/iOSExploreServer/Mutex.swift`:

```swift
import Foundation
#if canImport(os.lock)
import os.lock
#endif

/// 基于 os_unfair_lock 的轻量互斥锁,兼容 iOS 13+。
/// 内部手动保证线程安全,故 @unchecked —— 这是【全库唯一的不安全边界】。
/// Router / ExploreServer 依赖它即可获得真 Sendable,无需各自再标 @unchecked。
public final class Mutex<Value>: @unchecked Sendable {
    private let storage: UnsafeMutablePointer<os_unfair_lock>
    private var value: Value

    public init(_ initial: Value) {
        self.value = initial
        self.storage = .allocate(capacity: 1)
        self.storage.initialize(to: os_unfair_lock())
    }

    deinit {
        storage.deinitialize(count: 1)
        storage.deallocate()
    }

    @discardableResult
    public func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
        os_unfair_lock_lock(storage)
        defer { os_unfair_lock_unlock(storage) }
        return try body(&value)
    }
}
```

- [ ] **Step 4: 运行测试验证通过**

Run: `swift test --filter MutexTests`
Expected: PASS(2 个用例)。

- [ ] **Step 5: 提交**

```bash
git add Sources/iOSExploreServer/Mutex.swift Tests/iOSExploreServerTests/MutexTests.swift
git commit -m "feat: add Mutex (os_unfair_lock wrapper) as sole unchecked boundary"
```

---

## Task 2: Command 协议 + ClosureCommand

**Files:**
- Create: `Sources/iOSExploreServer/Command.swift`
- Test: `Tests/iOSExploreServerTests/CommandTests.swift`

**Interfaces:**
- Consumes: `ExploreRequest`/`ExploreResult`(来自 `Models.swift`,已存在)。
- Produces: `ParameterKind`、`CommandParameter`、`protocol Command: Sendable`、`ClosureCommand: Command`。

- [ ] **Step 1: 写失败测试**

Create `Tests/iOSExploreServerTests/CommandTests.swift`:

```swift
import Testing
@testable import iOSExploreServer

@Test("ClosureCommand 暴露元数据并转发 handle")
func closureCommandMetadataAndHandle() async throws {
    let cmd = ClosureCommand(
        action: "greet",
        description: "打招呼",
        parameters: [CommandParameter(name: "name", kind: .string, required: true, description: "名字")]
    ) { req in
        let name = req.data["name"]?.stringValue ?? "world"
        return .success(["message": .string("Hello, \(name)")])
    }
    #expect(cmd.action == "greet")
    #expect(cmd.description == "打招呼")
    #expect(cmd.parameters.count == 1)
    #expect(cmd.parameters[0].name == "name")

    let result = try await cmd.handle(ExploreRequest(action: "greet", data: ["name": "Claude"]))
    if case .success(let data) = result {
        #expect(data["message"]?.stringValue == "Hello, Claude")
    } else {
        Issue.record("expected success")
    }
}

@Test("Command 协议默认 parameters 为空")
func defaultParametersEmpty() {
    let cmd = ClosureCommand(action: "noop", description: "") { _ in .success([:]) }
    #expect(cmd.parameters.isEmpty)
}
```

- [ ] **Step 2: 运行测试验证失败**

Run: `swift test --filter CommandTests`
Expected: FAIL —— `cannot find 'ClosureCommand'/'CommandParameter' in scope`

- [ ] **Step 3: 写最小实现**

Create `Sources/iOSExploreServer/Command.swift`:

```swift
import Foundation

/// 参数类型,与 JSONValue 同构:使 schema 与 data 载荷类型系统统一演进。
public enum ParameterKind: String, Sendable {
    case string, number, boolean, object, array
}

/// 命令参数描述(对齐 MCP inputSchema 字段)。
public struct CommandParameter: Sendable, Equatable {
    public let name: String
    public let kind: ParameterKind
    public let required: Bool
    public let description: String

    public init(name: String, kind: ParameterKind, required: Bool, description: String) {
        self.name = name
        self.kind = kind
        self.required = required
        self.description = description
    }
}

/// 命令协议:承载 action 名、人类可读描述、参数 schema 与处理逻辑。
/// 扩展性靠协议扩展默认值:新增可选字段时在 extension 给默认,既有实现无需改动。
public protocol Command: Sendable {
    var action: String { get }
    var description: String { get }
    var parameters: [CommandParameter] { get }
    func handle(_ request: ExploreRequest) async throws -> ExploreResult
}

public extension Command {
    var parameters: [CommandParameter] { [] }
}

/// 闭包注册入口的适配器:与协议入口共享同一条路由路径。
struct ClosureCommand: Command {
    let action: String
    let description: String
    let parameters: [CommandParameter]
    let handler: @Sendable (ExploreRequest) async throws -> ExploreResult

    init(action: String,
         description: String = "",
         parameters: [CommandParameter] = [],
         handler: @escaping @Sendable (ExploreRequest) async throws -> ExploreResult) {
        self.action = action
        self.description = description
        self.parameters = parameters
        self.handler = handler
    }

    func handle(_ request: ExploreRequest) async throws -> ExploreResult {
        try await handler(request)
    }
}
```

- [ ] **Step 4: 运行测试验证通过**

Run: `swift test --filter CommandTests`
Expected: PASS(2 个用例)。

- [ ] **Step 5: 提交**

```bash
git add Sources/iOSExploreServer/Command.swift Tests/iOSExploreServerTests/CommandTests.swift
git commit -m "feat: add Command protocol with parameter schema and ClosureCommand adapter"
```

---

## Task 3: Router 并发模型切换(actor → 锁保护 class)

本任务是一次原子切换:改 `Router` 后,所有 `await router.register(...)` 调用点(库内 + 测试)必须同步去 `await`,否则编译失败。SPMExample 是独立 xcode 工程、不参与 `swift test`,其迁移留到 Task 7。

**Files:**
- Modify: `Sources/iOSExploreServer/Router.swift`(整体重写)
- Modify: `Sources/iOSExploreServer/Handlers/BuiltinHandlers.swift`(`registerAll` 去 async)
- Modify: `Sources/iOSExploreServer/ExploreServer.swift`(`register` 同步、`init` 注册内置、`start` 去掉 `await registerAll`)
- Modify: `Tests/iOSExploreServerTests/RouterTests.swift`(去 `await register` + 加校验用例)
- Modify: `Tests/iOSExploreServerTests/BuiltinHandlersTests.swift`(`registerAll` 去 await)
- Modify: `Tests/iOSExploreServerTests/IntegrationTests.swift`(去 `await register`)

**Interfaces:**
- Consumes: `Mutex`(Task 1)、`Command`/`CommandParameter`/`ClosureCommand`(Task 2)、`ExploreRequest`/`ExploreResult`/`ExploreError`/`JSON`/`JSONValue`(已有)。
- Produces: `Router` 为 `public final class: Sendable`;`register(_ command: any Command)`、`register(action:description:parameters:_:)`(均同步)、`route(_:) async -> ExploreResult`(签名不变,仍 async)、`commandMetadata()`(internal)。

- [ ] **Step 1: 重写 Router**

Replace entire contents of `Sources/iOSExploreServer/Router.swift`:

```swift
import Foundation

/// 命令分发:action 名称 → Command。字典由 Mutex 保护;route 锁内取命令、锁外校验与 handle。
public final class Router: Sendable {
    private let handlers = Mutex<[String: any Command]>([:])

    public init() {}

    /// 协议对象注册(首选)。
    public func register(_ command: any Command) {
        handlers.withLock { $0[command.action] = command }
    }

    /// 闭包便捷入口(内部适配成 ClosureCommand,与协议入口共享路由)。
    public func register(action: String,
                         description: String = "",
                         parameters: [CommandParameter] = [],
                         _ handler: @escaping @Sendable (ExploreRequest) async throws -> ExploreResult) {
        register(ClosureCommand(action: action, description: description,
                                parameters: parameters, handler: handler))
    }

    /// 按 action 查表分发;未命中/参数非法/handler 抛错都返回业务失败,不向外抛。
    func route(_ request: ExploreRequest) async -> ExploreResult {
        let command = handlers.withLock { $0[request.action] }
        guard let command else {
            return .failure(code: .unknownAction,
                            message: "no handler for '\(request.action)'")
        }
        if let msg = Self.validate(request.data, against: command.parameters) {
            return .failure(code: .invalidData, message: msg)
        }
        do {
            return try await command.handle(request)
        } catch {
            return .failure(code: .internalError, message: error.localizedDescription)
        }
    }

    /// 供 help 命令自省:列出全部命令元数据(锁内取快照)。
    func commandMetadata() -> [(action: String, description: String, parameters: [CommandParameter])] {
        handlers.withLock { dict in
            dict.values.map { ($0.action, $0.description, $0.parameters) }
        }
    }

    private static func validate(_ data: JSON, against parameters: [CommandParameter]) -> String? {
        for p in parameters {
            let v = data[p.name]
            if v == nil || v == .null {
                if p.required { return "missing required parameter '\(p.name)'" }
                continue
            }
            if let v = v, !typeMatches(v, kind: p.kind) {
                return "parameter '\(p.name)' expects \(p.kind.rawValue)"
            }
        }
        return nil
    }

    private static func typeMatches(_ v: JSONValue, kind: ParameterKind) -> Bool {
        switch (v, kind) {
        case (.string, .string), (.double, .number), (.bool, .boolean),
             (.object, .object), (.array, .array):
            return true
        default:
            return false
        }
    }
}
```

- [ ] **Step 2: BuiltinHandlers.registerAll 改同步**

In `Sources/iOSExploreServer/Handlers/BuiltinHandlers.swift`,改 `registerAll`(注意:命令 struct 重构在 Task 6,此处仍用闭包入口,仅去 `async`/`await`):

Replace:

```swift
    /// 把三个内置命令注册进 router。
    static func registerAll(into router: Router) async {
        await router.register(action: "ping") { ping($0) }
        await router.register(action: "echo") { echo($0) }
        await router.register(action: "info") { info($0) }
    }
```

With:

```swift
    /// 把三个内置命令注册进 router(同步)。
    static func registerAll(into router: Router) {
        router.register(action: "ping", description: "健康检查,返回 pong") { ping($0) }
        router.register(action: "echo", description: "原样回显 data") { echo($0) }
        router.register(action: "info", description: "返回系统/应用/Bundle 信息") { info($0) }
    }
```

- [ ] **Step 3: ExploreServer 改 register 同步 + init 注册内置**

In `Sources/iOSExploreServer/ExploreServer.swift`:

3a. 删除 `registeredBuiltins` 属性。删掉这一行:

```swift
    private var registeredBuiltins = false
```

3b. 改 `register` 为同步并新增协议入口。Replace:

```swift
    public func register(action: String,
                          _ handler: @escaping @Sendable (ExploreRequest) async throws -> ExploreResult) async {
        await router.register(action: action, handler)
    }
```

With:

```swift
    public func register(_ command: any Command) {
        router.register(command)
    }

    public func register(action: String,
                         description: String = "",
                         parameters: [CommandParameter] = [],
                         _ handler: @escaping @Sendable (ExploreRequest) async throws -> ExploreResult) {
        router.register(action: action, description: description, parameters: parameters, handler)
    }
```

3c. 改 `start`:把内置命令注册挪进 `init`,`start` 不再注册。Replace `start`:

```swift
    public func start() async throws {
        if !registeredBuiltins {
            await BuiltinHandlers.registerAll(into: router)
            registeredBuiltins = true
        }
        let l = try HTTPListener(port: port, router: router) { [eventContinuation] event in
            eventContinuation.yield(event)
        }
        l.start()
        self.listener = l
    }
```

With:

```swift
    public func start() async throws {
        let l = try HTTPListener(port: port, router: router) { [eventContinuation] event in
            eventContinuation.yield(event)
        }
        l.start()
        self.listener = l
    }
```

3d. 在 `init` 末尾追加内置命令注册(同步)。在 `self.eventContinuation = continuation` 之后加:

```swift
        BuiltinHandlers.registerAll(into: router)
```

完整 `init` 此时为:

```swift
    public init(port: UInt16 = 38321, authToken: String? = nil) {
        self.port = port
        self.authToken = authToken
        self.router = Router()
        var continuation: AsyncStream<ServerEvent>.Continuation!
        self.eventStream = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
        BuiltinHandlers.registerAll(into: router)
    }
```

> 注意:`router` 当前声明为 `private let router: Router`——`init` 里先 `self.router = Router()` 再用,合法。本任务保留 `listener` 为裸 `var listener: HTTPListener?` 与 `@unchecked Sendable`(Task 5 再 Mutex 化)。HTTPListener.start 此时仍是同步(`l.start()`),Task 4 才改 async。

- [ ] **Step 4: 改 RouterTests**

Replace entire contents of `Tests/iOSExploreServerTests/RouterTests.swift`:

```swift
import Testing
@testable import iOSExploreServer

@Test("注册的 action 被命中并返回 success")
func routeHitsRegistered() async {
    let router = Router()
    router.register(action: "hello") { _ in .success(["msg": "hi"]) }
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
    router.register(action: "boom") { _ in throw Boom() }
    let result = await router.route(ExploreRequest(action: "boom"))
    if case .failure(let code, _) = result {
        #expect(code == .internalError)
    } else {
        Issue.record("expected failure")
    }
}

@Test("缺必填参数返回 invalid_data")
func routeMissingRequiredParam() async {
    let router = Router()
    router.register(action: "greet",
                    parameters: [CommandParameter(name: "name", kind: .string, required: true, description: "")]) { _ in
        .success([:])
    }
    let result = await router.route(ExploreRequest(action: "greet"))
    if case .failure(let code, let msg) = result {
        #expect(code == .invalidData)
        #expect(msg.contains("name"))
    } else {
        Issue.record("expected invalidData")
    }
}

@Test("参数类型不匹配返回 invalid_data")
func routeTypeMismatch() async {
    let router = Router()
    router.register(action: "add",
                    parameters: [CommandParameter(name: "x", kind: .number, required: true, description: "")]) { _ in
        .success([:])
    }
    let result = await router.route(ExploreRequest(action: "add", data: ["x": "not-a-number"]))
    if case .failure(let code, _) = result {
        #expect(code == .invalidData)
    } else {
        Issue.record("expected invalidData")
    }
}

@Test("参数合法时不拦截,正常进入 handler")
func routeValidParamsPassThrough() async {
    let router = Router()
    router.register(action: "add",
                    parameters: [CommandParameter(name: "x", kind: .number, required: true, description: "")]) { req in
        .success(["doubled": req.data["x"] ?? .null])
    }
    let result = await router.route(ExploreRequest(action: "add", data: ["x": 21]))
    if case .success(let data) = result {
        #expect(data["doubled"] == .double(21))
    } else {
        Issue.record("expected success")
    }
}

@Test("协议对象注册与闭包注册等价可达")
func routeProtocolRegistration() async {
    let router = Router()
    struct Ping: Command {
        let action = "ping2"
        let description = ""
        func handle(_ request: ExploreRequest) async throws -> ExploreResult { .success(["ok": .bool(true)]) }
    }
    router.register(Ping())
    let result = await router.route(ExploreRequest(action: "ping2"))
    if case .success(let data) = result {
        #expect(data["ok"] == .bool(true))
    } else {
        Issue.record("expected success")
    }
}
```

- [ ] **Step 5: 改 BuiltinHandlersTests(registerAll 去 await)**

In `Tests/iOSExploreServerTests/BuiltinHandlersTests.swift`,改最后一个用例:

Replace:

```swift
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

With:

```swift
@Test("registerAll 注册三个命令")
func registerAllRegisters() async {
    let router = Router()
    BuiltinHandlers.registerAll(into: router)
    for action in ["ping", "echo", "info"] {
        let r = await router.route(ExploreRequest(action: action))
        if case .failure = r { Issue.record("\(action) should be registered") }
    }
}
```

> 前三个用例(`pingReturns`/`echoReturns`/`infoReturns`)仍直接调静态方法 `BuiltinHandlers.ping/echo/info`,本任务不动;Task 6 命令重构时再改。

- [ ] **Step 6: 改 IntegrationTests(greet 注册去 await)**

In `Tests/iOSExploreServerTests/IntegrationTests.swift`,在 `endToEndCustom`:

Replace:

```swift
    let server = ExploreServer(port: testPort)
    await server.register(action: "greet") { req in
        let name = req.data["name"]?.stringValue ?? "world"
        return .success(["message": .string("Hello, \(name)")])
    }
    try await server.start()
```

With:

```swift
    let server = ExploreServer(port: testPort)
    server.register(action: "greet") { req in
        let name = req.data["name"]?.stringValue ?? "world"
        return .success(["message": .string("Hello, \(name)")])
    }
    try await server.start()
```

- [ ] **Step 7: 构建并跑全量测试**

Run: `swift test`
Expected: PASS —— 全部用例绿(含新增 RouterTests 校验用例)。

- [ ] **Step 8: 验证 framework 工程 `any` 兼容性**

Run: `xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED。

> 若因 `any Command` 在 `SWIFT_VERSION=5.0` 下编译失败:全局把 `any Command` 替换为裸 `Command`(Router 字典类型、`register(_:)` 参数、`commandMetadata` 返回值中的元素),SPM 6.2 下会出现 deprecation 警告但可编译。修复后重跑本步与 Step 7。

- [ ] **Step 9: 提交**

```bash
git add Sources/iOSExploreServer/Router.swift Sources/iOSExploreServer/ExploreServer.swift Sources/iOSExploreServer/Handlers/BuiltinHandlers.swift Tests/iOSExploreServerTests/RouterTests.swift Tests/iOSExploreServerTests/BuiltinHandlersTests.swift Tests/iOSExploreServerTests/IntegrationTests.swift
git commit -m "refactor: switch Router from actor to Mutex-protected class, sync register"
```

---

## Task 4: HTTPListener start 失败修复

`NWListener` 端口绑定失败走 `stateUpdateHandler` 异步回调;当前 `start()` 立即返回不检测,端口冲突时静默失败。改为 await `.ready`,失败 throw。参考 `IntegrationTests.waitUntilReady` 已有的防重入写法。

**Files:**
- Modify: `Sources/iOSExploreServer/HTTPListener.swift`(`start` → `async throws`,新增 `waitUntilReady`)
- Modify: `Sources/iOSExploreServer/ExploreServer.swift`(`start` 里 `l.start()` → `try await l.start()`)

**Interfaces:**
- Consumes: 无新依赖。
- Produces: `HTTPListener.start() async throws`(internal,签名变化)。

- [ ] **Step 1: 改 HTTPListener.start**

In `Sources/iOSExploreServer/HTTPListener.swift`,Replace `start`:

```swift
    func start() {
        guard let listener else { return }
        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        listener.start(queue: .global())
        onEvent(.started(port: port))
    }
```

With:

```swift
    func start() async throws {
        guard let listener else { return }
        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        listener.start(queue: .global())
        try await Self.waitUntilReady(listener)
        onEvent(.started(port: port))
    }

    private static func waitUntilReady(_ listener: NWListener) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil   // 防 continuation 重入
                    cont.resume()
                case .failed(let err):
                    listener.stateUpdateHandler = nil
                    cont.resume(throwing: err)
                case .cancelled:
                    listener.stateUpdateHandler = nil
                    cont.resume(throwing: NSError(domain: "HTTPListener", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "listener cancelled"]))
                default:
                    break   // .setup 等中间态忽略
                }
            }
        }
    }
```

> `HTTPListener` 已 `import Network`,`NWListener`/`withCheckedThrowingContinuation`/`NSError` 可用,无需新增 import。

- [ ] **Step 2: ExploreServer.start 改为 await**

In `Sources/iOSExploreServer/ExploreServer.swift`,在 `start` 内:

Replace:

```swift
        l.start()
        self.listener = l
```

With:

```swift
        try await l.start()
        self.listener = l
```

(`start` 本已是 `async throws`,签名不变。)

- [ ] **Step 3: 跑全量测试验证未回归**

Run: `swift test`
Expected: PASS —— 集成测试 4 个用例仍绿(端口 38399 串行,每个 server 独占端口,start 正常 await ready)。此时端口冲突 throw 行为的专项测试在 Task 8 补。

- [ ] **Step 4: 提交**

```bash
git add Sources/iOSExploreServer/HTTPListener.swift Sources/iOSExploreServer/ExploreServer.swift
git commit -m "fix: await NWListener ready in start, surface port bind failures"
```

---

## Task 5: ExploreServer 去 @unchecked(listener Mutex 化)

把 `listener` 由裸 `var` 改为 `Mutex<HTTPListener?>`,使 `ExploreServer` 成为真 `Sendable`(`@unchecked` 在 Task 3 后只剩 `listener` 这一处来源,本任务消除它)。

**Files:**
- Modify: `Sources/iOSExploreServer/ExploreServer.swift`

**Interfaces:**
- Produces: `ExploreServer` 改为 `public final class ExploreServer: Sendable`(去 `@unchecked`)。

- [ ] **Step 1: 写失败测试(确认 init 后内置命令已注册,不依赖 start)**

Add to `Tests/iOSExploreServerTests/IntegrationTests.swift`(新用例,验证 init 注册):

```swift
    @Test("init 后内置命令即已注册,无需 start")
    func builtinRegisteredAfterInit() async {
        let server = ExploreServer(port: testPort)
        // 不 start,直接经 router 验证 ping 已注册
        let r = await server.routerSnapshotRoute(ExploreRequest(action: "ping"))
        if case .failure = r { Issue.record("ping should be registered at init") }
    }
```

> 需要一个测试钩子访问 router。在 Step 2 给 `ExploreServer` 加 `internal func routerSnapshotRoute(_:)` 测试辅助。

- [ ] **Step 2: Mutex 化 listener + 加测试钩子 + 去 @unchecked**

In `Sources/iOSExploreServer/ExploreServer.swift`:

2a. 改类声明与 listener 属性。Replace:

```swift
public final class ExploreServer: @unchecked Sendable {
    private let port: UInt16
    private let router: Router
    private var listener: HTTPListener?
```

With:

```swift
public final class ExploreServer: Sendable {
    private let port: UInt16
    private let router: Router
    private let listener = Mutex<HTTPListener?>(nil)
```

2b. 改 `start`/`stop` 用 Mutex。Replace:

```swift
    public func start() async throws {
        let l = try HTTPListener(port: port, router: router) { [eventContinuation] event in
            eventContinuation.yield(event)
        }
        try await l.start()
        self.listener = l
    }

    public func stop() {
        listener?.stop()
        listener = nil
    }
```

With:

```swift
    public func start() async throws {
        let l = try HTTPListener(port: port, router: router) { [eventContinuation] event in
            eventContinuation.yield(event)
        }
        try await l.start()
        listener.withLock { $0 = l }
    }

    public func stop() {
        listener.withLock { $0?.stop(); $0 = nil }
    }
```

2c. 加测试钩子(在 `events()` 之后):

```swift
    /// 测试辅助:不经网络直接路由,验证命令注册状态。
    func routerSnapshotRoute(_ request: ExploreRequest) async -> ExploreResult {
        await router.route(request)
    }
```

> `router` 是 `private let`,同模块 `@testable import` 下 internal 方法可访问 `router.route`。`route` 本是 internal,可达。

- [ ] **Step 3: 跑测试**

Run: `swift test --filter "builtinRegisteredAfterInit|IntegrationTests"`
Expected: PASS —— 新用例绿,集成测试不回归。

- [ ] **Step 4: 跑全量 + 确认无 @unchecked 残留**

Run: `swift test`
Expected: PASS。

Run: `grep -rn "@unchecked Sendable" Sources/iOSExploreServer/`
Expected: 只剩 `Sources/iOSExploreServer/Mutex.swift` 一处(全库唯一不安全边界);`ExploreServer.swift`/`HTTPListener.swift` 无 `@unchecked`。

> 注:`HTTPListener` 仍是 `@unchecked Sendable`(它内部 `NWListener` 等非 Sendable 且由调用方串行 start/stop)——这不在本次改动范围,保持现状。

- [ ] **Step 5: 提交**

```bash
git add Sources/iOSExploreServer/ExploreServer.swift Tests/iOSExploreServerTests/IntegrationTests.swift
git commit -m "refactor: make ExploreServer genuinely Sendable via Mutex-protected listener"
```

---

## Task 6: 内置命令重构为 Command struct + help 命令

把 `ping`/`echo`/`info` 由静态方法改为 `Command` struct,新增 `HelpCommand`(遍历 router 输出元数据,对齐 MCP `tools/list`),`registerAll` 改用 struct 注册。

**Files:**
- Modify: `Sources/iOSExploreServer/Handlers/BuiltinHandlers.swift`(整体重写为命令 struct + registerAll)
- Modify: `Tests/iOSExploreServerTests/BuiltinHandlersTests.swift`(改测 struct + 加 help)

**Interfaces:**
- Consumes: `Command`/`CommandParameter`(Task 2)、`Router.commandMetadata()`(Task 3)、`JSON`/`JSONValue`(已有)。
- Produces: `PingCommand`/`EchoCommand`/`InfoCommand`/`HelpCommand`(internal);`BuiltinHandlers.registerAll(into:)`(同步)。

- [ ] **Step 1: 写失败测试(help 输出结构 + 各命令 struct 可直接调用)**

Replace entire contents of `Tests/iOSExploreServerTests/BuiltinHandlersTests.swift`:

```swift
import Testing
@testable import iOSExploreServer

@Test("PingCommand 返回 pong")
func pingCommandReturns() async throws {
    let r = try await PingCommand().handle(ExploreRequest(action: "ping"))
    if case .success(let data) = r {
        #expect(data["pong"] == .bool(true))
    } else { Issue.record("expected success") }
}

@Test("EchoCommand 原样回显 data")
func echoCommandReturns() async throws {
    let req = ExploreRequest(action: "echo", data: ["a": 1, "b": "x"])
    let r = try await EchoCommand().handle(req)
    if case .success(let data) = r {
        #expect(data["a"] == .double(1))
        #expect(data["b"]?.stringValue == "x")
    } else { Issue.record("expected success") }
}

@Test("InfoCommand 返回 system/app/bundle 字段")
func infoCommandReturns() async throws {
    let r = try await InfoCommand().handle(ExploreRequest(action: "info"))
    if case .success(let data) = r {
        #expect(data["system"]?.stringValue != nil)
        #expect(data["app"]?.stringValue != nil)
        #expect(data["bundle"]?.stringValue != nil)
    } else { Issue.record("expected success") }
}

@Test("registerAll 注册 ping/echo/info/help")
func registerAllRegisters() async {
    let router = Router()
    BuiltinHandlers.registerAll(into: router)
    for action in ["ping", "echo", "info", "help"] {
        let r = await router.route(ExploreRequest(action: action))
        if case .failure = r { Issue.record("\(action) should be registered") }
    }
}

@Test("help 列出全部命令元数据,结构对齐 MCP")
func helpListsAllCommands() async throws {
    let router = Router()
    BuiltinHandlers.registerAll(into: router)
    let r = try await HelpCommand(router: router).handle(ExploreRequest(action: "help"))
    guard case .success(let data) = r else { Issue.record("expected success"); return }
    guard case .array(let entries) = data["commands"] else { Issue.record("commands not array"); return }
    let actions: [String] = entries.compactMap { entry in
        if case .object(let obj) = entry, case .string(let a) = obj["action"] { return a }
        return nil
    }
    #expect(actions.contains("ping"))
    #expect(actions.contains("echo"))
    #expect(actions.contains("info"))
    #expect(actions.contains("help"))
}
```

- [ ] **Step 2: 运行测试验证失败**

Run: `swift test --filter BuiltinHandlersTests`
Expected: FAIL —— `cannot find 'PingCommand'/'HelpCommand' in scope`

- [ ] **Step 3: 重写 BuiltinHandlers 为命令 struct**

Replace entire contents of `Sources/iOSExploreServer/Handlers/BuiltinHandlers.swift`:

```swift
import Foundation

/// 内置命令。库内不依赖 UIKit;info 仅返回 ProcessInfo/Bundle 可得字段。

struct PingCommand: Command {
    let action = "ping"
    let description = "健康检查,返回 pong"
    func handle(_ request: ExploreRequest) async throws -> ExploreResult {
        .success(["pong": .bool(true)])
    }
}

struct EchoCommand: Command {
    let action = "echo"
    let description = "原样回显 data"
    func handle(_ request: ExploreRequest) async throws -> ExploreResult {
        .success(request.data)
    }
}

struct InfoCommand: Command {
    let action = "info"
    let description = "返回系统/应用/Bundle 信息"
    func handle(_ request: ExploreRequest) async throws -> ExploreResult {
        let processInfo = ProcessInfo.processInfo
        let bundle = Bundle.main
        let info: JSON = [
            "system": .string(processInfo.operatingSystemVersionString),
            "app": .string((bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"),
            "bundle": .string(bundle.bundleIdentifier ?? "unknown"),
        ]
        return .success(info)
    }
}

/// 列出所有已注册命令的 action/description/parameters(对齐 MCP tools/list)。
struct HelpCommand: Command {
    let action = "help"
    let description = "列出所有已注册命令及其参数说明"
    private let router: Router
    init(router: Router) { self.router = router }

    func handle(_ request: ExploreRequest) async throws -> ExploreResult {
        let entries: [JSONValue] = router.commandMetadata().map { entry in
            let params: [JSONValue] = entry.parameters.map { p in
                .object(JSON([
                    "name": .string(p.name),
                    "kind": .string(p.kind.rawValue),
                    "required": .bool(p.required),
                    "description": .string(p.description),
                ]))
            }
            return .object(JSON([
                "action": .string(entry.action),
                "description": .string(entry.description),
                "parameters": .array(params),
            ]))
        }
        return .success(JSON(["commands": .array(entries)]))
    }
}

enum BuiltinHandlers {
    /// 把内置命令注册进 router(同步)。
    static func registerAll(into router: Router) {
        router.register(PingCommand())
        router.register(EchoCommand())
        router.register(InfoCommand())
        router.register(HelpCommand(router: router))
    }
}
```

- [ ] **Step 4: 运行测试验证通过**

Run: `swift test --filter BuiltinHandlersTests`
Expected: PASS(5 个用例)。

- [ ] **Step 5: 跑全量测试**

Run: `swift test`
Expected: PASS。

- [ ] **Step 6: 提交**

```bash
git add Sources/iOSExploreServer/Handlers/BuiltinHandlers.swift Tests/iOSExploreServerTests/BuiltinHandlersTests.swift
git commit -m "refactor: builtin commands as Command structs, add help command"
```

---

## Task 7: SPMExample 迁移(register 同步化)

`register` 已同步,移出 `Task` 包装,直接在 `viewDidLoad` 同步注册。

**Files:**
- Modify: `Examples/SPMExample/SPMExample/ViewController.swift`

**Interfaces:**
- Consumes: `ExploreServer.register(action:description:parameters:_:)`(同步,Task 3)。

- [ ] **Step 1: 改 ViewController**

In `Examples/SPMExample/SPMExample/ViewController.swift`,Replace(行 27-41 的 `Task { ... }` 注册块):

```swift
        // 演示自定义命令 + UIKit 信息注入
        let server = self.server
        Task { [weak self] in
            guard self != nil else { return }
            await server.register(action: "greet") { req in
                let name = req.data["name"]?.stringValue ?? "world"
                return .success(["message": .string("Hello, \(name)")])
            }
            await server.register(action: "device") { _ in
                return await MainActor.run {
                    .success(["model": .string(UIDevice.current.model),
                              "name": .string(UIDevice.current.name)])
                }
            }
        }
```

With:

```swift
        // 演示自定义命令 + UIKit 信息注入(register 同步,无需 Task)
        server.register(action: "greet", description: "按 name 打招呼") { req in
            let name = req.data["name"]?.stringValue ?? "world"
            return .success(["message": .string("Hello, \(name)")])
        }
        server.register(action: "device", description: "返回设备机型与名称(UIKit 注入)") { _ in
            return await MainActor.run {
                .success(["model": .string(UIDevice.current.model),
                          "name": .string(UIDevice.current.name)])
            }
        }
```

> handler 闭包仍是 `async`(签名要求),内部 `MainActor.run` 不变;仅注册调用去 `await`、移出 `Task`。`[weak self]` 不再需要(注册不捕获 self)。

- [ ] **Step 2: 构建 SPMExample(模拟器)**

Run: `xcodebuild -project Examples/SPMExample/SPMExample.xcodeproj -scheme SPMExample -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED。

- [ ] **Step 3: 提交**

```bash
git add Examples/SPMExample/SPMExample/ViewController.swift
git commit -m "refactor: migrate SPMExample to sync register"
```

---

## Task 8: 集成测试补强 + 删除占位测试

补:端口冲突 throw、参数校验端到端、`help` 端到端;删占位 `iOSExploreServerTests.swift`;确认覆盖率 ≥ 80%。

**Files:**
- Modify: `Tests/iOSExploreServerTests/IntegrationTests.swift`
- Delete: `Tests/iOSExploreServerTests/iOSExploreServerTests.swift`

**Interfaces:**
- Consumes: `ExploreServer.start() async throws`(端口冲突 throw,Task 4)。

- [ ] **Step 1: 加端口冲突 + help 端到端用例**

In `Tests/iOSExploreServerTests/IntegrationTests.swift`,在 `endToEndCustom` 之后、`}` (struct 结束)之前插入:

```swift
    @Test("端口被占用时 start 抛错")
    func startThrowsOnPortInUse() async throws {
        let server1 = ExploreServer(port: testPort)
        try await server1.start()
        defer { server1.stop() }

        let server2 = ExploreServer(port: testPort)
        await #expect(throws: (any Error).self) {
            try await server2.start()
        }
        server2.stop()   // start 失败后 listener 未赋值,stop 无害
    }

    @Test("help 端到端返回全部命令")
    func endToEndHelp() async throws {
        let server = ExploreServer(port: testPort)
        try await server.start()
        defer { server.stop() }

        let text = try await send(action: "help")
        #expect(text.contains(#""ok":true"#))
        #expect(text.contains(#""action":"ping""#))
        #expect(text.contains(#""action":"help""#))
    }
```

- [ ] **Step 2: 删除占位测试**

Run: `git rm Tests/iOSExploreServerTests/iOSExploreServerTests.swift`

- [ ] **Step 3: 跑全量测试**

Run: `swift test`
Expected: PASS —— 集成测试串行执行,含新增 2 个用例;端口冲突用例中 server2.start 抛错。

> 若端口冲突用例偶发不抛错:确认 `.serialized` 生效、testPort 无其他进程占用;该用例依赖 OS 拒绝二次 bind,在 loopback 上确定性成立。

- [ ] **Step 4: 覆盖率检查**

Run: `swift test --enable-code-coverage 2>&1 | tail -5`
Expected: 覆盖率 ≥ 80%(基线 89.91%;新增 Mutex/Command/校验/help 均有用例覆盖,应维持或提升)。

- [ ] **Step 5: 提交**

```bash
git add Tests/iOSExploreServerTests/IntegrationTests.swift
git commit -m "test: port-conflict throw, help e2e; remove placeholder test"
```

---

## Task 9: 规则文档更新

把 handler 签名/注册方式/并发模型的硬规则同步到新设计。

**Files:**
- Modify: `.claude/rules/handlers-rules.md`
- Modify: `.claude/rules/library-rules.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: 重写 handlers-rules.md**

Replace entire contents of `.claude/rules/handlers-rules.md`:

```markdown
# Handler 规则

- 命令实现 `Command` 协议:`var action`/`var description`/`var parameters`/`func handle(_:) async throws -> ExploreResult`。`parameters` 默认空,声明参数的命令才填。
- 注册方式(二选一,均同步):
  - 协议对象(首选):`server.register(MyCommand())` 或 `router.register(MyCommand())`。
  - 闭包便捷入口:`server.register(action: "name", description: "...", parameters: [...]) { req in ... }`。
- 返回 `.success(JSON)` 或 `.failure(code: ExploreError, message: String)`;**不要向外 rethrow**——`Router` 已捕获异常并转为 `.internalError`。
- 参数校验由 `Router` 统一做(按 `parameters` 校验必填 + 类型,不过返回 `.invalidData`);handler 内无需重复校验,只管业务。
- 取入参用 `req.data["key"]?.stringValue` / `.doubleValue` / `.boolValue`。
- **禁止依赖 UIKit**。需要 UIKit 信息(如 `UIDevice`)时,在 App 层(`SPMExample`)注册单独 handler,handler 内用 `await MainActor.run { ... }` 取值后返回。
- 新内置命令:实现 `Command` struct,在 `BuiltinHandlers.registerAll(into:)` 注册,同步在 `BuiltinHandlersTests` 补测试。
```

- [ ] **Step 2: 更新 library-rules.md(并发模型 + 锁内禁 await)**

In `.claude/rules/library-rules.md`,Replace 第二条:

```markdown
- **Swift 6.2 严格并发**：跨边界模型 `Sendable`；共享可变状态用 `actor`；闭包 `@Sendable`；连接处理 `Task` 捕获 actor/@Sendable 闭包，不捕获 `self`。
```

With:

```markdown
- **Swift 6.2 严格并发**：跨边界模型 `Sendable`；共享可变状态用 `Mutex`（库内自封装的 `os_unfair_lock`，全库唯一 `@unchecked` 边界）；闭包 `@Sendable`。**`Mutex` 锁内禁止 `await`**——临界区只放纯同步访问，async 工作在锁外。
```

- [ ] **Step 3: 更新 AGENTS.md(handler 签名描述)**

In `AGENTS.md`,定位"模块边界"段中描述 Router 的那行:

Replace:

```markdown
- `Sources/iOSExploreServer/` — SPM 库（主交付物）。门面 `ExploreServer`；传输 `HTTPListener`（NWListener）；解析 `HTTPParser`；分发 `Router`（actor）；模型 `Models`/`JSONCoder`；HTTP 值类型 `HTTPRequest`/`HTTPResponse`；内置命令 `Handlers/BuiltinHandlers`（ping/echo/info）。
```

With:

```markdown
- `Sources/iOSExploreServer/` — SPM 库（主交付物）。门面 `ExploreServer`（`Sendable`）；传输 `HTTPListener`（NWListener，`start` await 端口就绪）；解析 `HTTPParser`；分发 `Router`（`Mutex` 保护的 `final class`，同步 register、route 锁外校验+await）；同步原语 `Mutex`；命令协议 `Command`（action/description/parameters）；模型 `Models`/`JSONCoder`；HTTP 值类型 `HTTPRequest`/`HTTPResponse`；内置命令 `Handlers/BuiltinHandlers`（ping/echo/info/help，均为 `Command` struct）。
```

并在"关键约束速记"段末追加一条:

```markdown
- `Router` 是锁保护的 `final class`（非 actor）：`register` 同步、`route` 锁内取命令+锁外校验/`await handle`（锁内禁 await）；`ExploreServer` 是真 `Sendable`，`@unchecked` 只在 `Mutex` 一处。
```

- [ ] **Step 4: 提交**

```bash
git add .claude/rules/handlers-rules.md .claude/rules/library-rules.md AGENTS.md
git commit -m "docs: sync handler/concurrency rules to Command protocol + Mutex design"
```

---

## 收尾验证(所有任务完成后)

- [ ] `swift test` 全绿(含集成测试,端口 38399 串行)。
- [ ] `swift test --enable-code-coverage` 覆盖率 ≥ 80%。
- [ ] `grep -rn "@unchecked Sendable" Sources/iOSExploreServer/` 仅 `Mutex.swift` 命中。
- [ ] framework 工程 `xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator build` 成功。
- [ ] SPMExample 编译成功;真机/模拟器运行,`curl -X POST http://localhost:38321/ -d '{"action":"help"}'`(经 `./scripts/proxy.sh`)返回全部命令元数据;`curl ... -d '{"action":"greet"}'`(缺必填,若 greet 声明了参数)返回 `invalid_data`。
