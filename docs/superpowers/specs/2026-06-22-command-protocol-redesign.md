# Command 协议与并发模型重构设计

- 日期：2026-06-22
- 状态：待实现
- 关联：`docs/superpowers/specs/2026-06-21-ios-explore-server-design.md`（初版设计）

## 1. 背景与动机

当前 `ExploreServer` 的公共 API 存在四个相互关联的设计问题，根因都指向一个选型：`Router` 被做成了 `actor`，且内置命令注册被塞进了 `start()`。

1. **`register` 被迫 async**：它内部 `await router.register(...)`，而 `Router` 是 actor → 跨 actor 调用强制 async。这是 actor 隔离的副作用，并非需求。注册本质是确定性的配置操作，不应带 async 语义。
2. **`start()` 是"假 async"**：其唯一的 `await` 是注册内置命令（可消除），`NWListener.start()` 本身立即返回、不挂起。同时存在真 bug——`NWListener` 端口绑定失败通过 `stateUpdateHandler` 异步回调暴露，当前完全未处理，端口冲突时 `start()` 不抛错、事件流无信号、server 静默起不来。
3. **`@unchecked Sendable` 是谎言**：`ExploreServer` 不是 actor，却持有 `listener: HTTPListener?` 与 `registeredBuiltins: Bool` 两个可变成员且无任何同步保护（代码注释自承"不保证并发安全启停"）。
4. **handler 是裸闭包，无元数据载体**：handler 签名 `@Sendable (ExploreRequest) async throws -> ExploreResult` 无法承载描述、参数 schema 等自省信息，阻碍 `help` 命令与后续 Mac 侧 MCP `tools/list` 对接（项目既定北极星）。

## 2. 目标与非目标

**目标**

- `register` 同步、非 async，"不分场景"，组件内部保证线程安全。
- 引入 `Command` 协议，承载 `action` / `description` / `parameters`，支持自省并为 MCP 对接铺路。
- `ExploreServer` 成为名副其实的 `Sendable`：`@unchecked` 收束到全库唯一的 `Mutex` 封装内部。
- 修复 `start()` 端口冲突静默失败：await 端口就绪，失败则 throw。
- 保持硬约束：仅依赖 Foundation/Network、不依赖 UIKit、iOS 13 部署目标、Swift 5 语言模式兼容（避免 Swift-6-only 语法）。

**非目标**

- 不实现请求中间件 / 鉴权 / 限流（作为预留扩展点列出，但不实现）。
- 不改 HTTP 协议、唯一端点 `POST /` 与 envelope 格式。
- 不引入 UIKit；需要 UIKit 的信息仍由集成方注册额外 handler 注入。

## 3. 设计决策（含被否决方案）

| 决策点 | 采用 | 被否决（理由） |
|---|---|---|
| 并发模型 | 锁保护 Router | 配置期/运行期零锁分离——锁开销纳秒级可忽略，snapshot 冻结机制更易出错；global actor——IO 热路径串行化、与"同步 register"自相矛盾；register 内包 `Task`——把确定性配置变成非确定性竞态（anti-pattern） |
| 锁选型 | 自封装 `os_unfair_lock` 的 `Mutex` | 裸 `os_unfair_lock_t`——Swift 值语义下 footgun；`OSAllocatedUnfairLock`——iOS 16+ 太高；`Synchronization.Mutex`——需 Swift 6 运行时，破坏 framework 5 语言模式兼容；`NSLock`——非 Sendable，Router 仍需 `@unchecked` |
| Command 协议 | 形态 C（含 `parameters`） | 形态 A（仅 action+handle）——闭包的类型化包装，零新运行期能力，unnecessary indirection |
| 参数校验 | Router 统一校验 | 命令自校验——重复代码，`parameters` 仅作 schema 浪费 |

## 4. 详细设计

### 4.1 Mutex 封装（全库唯一的不安全边界）

```swift
import Foundation
#if canImport(os.lock)
import os.lock
#endif

/// 基于 os_unfair_lock 的轻量互斥锁，兼容 iOS 13+。
/// 内部手动保证线程安全，故 @unchecked —— 这是【全库唯一的不安全边界】。
/// Router / ExploreServer 依赖它即可获得真 Sendable，无需各自再标 @unchecked。
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

**正确性约束（必须一次写对，写进规则文档）**

1. 锁存堆上稳定地址（`UnsafeMutablePointer.allocate`），不可存入会被拷贝的值类型——os_unfair_lock 的硬性要求。
2. `deinit` 必须 `deinitialize` + `deallocate`，否则泄漏。
3. `defer` 解锁，保证闭包抛错也释放。
4. **锁内禁止 `await`**——os_unfair_lock 不可跨 suspension point 持有。临界区只放纯同步的字典访问，`handle`（async）必须在锁外。

### 4.2 Command 协议（形态 C）

```swift
public enum ParameterKind: String, Sendable {
    case string, number, boolean, object, array
}

public struct CommandParameter: Sendable, Equatable {
    public let name: String
    public let kind: ParameterKind
    public let required: Bool
    public let description: String
    public init(name: String, kind: ParameterKind, required: Bool, description: String) {
        self.name = name; self.kind = kind; self.required = required; self.description = description
    }
}

public protocol Command: Sendable {
    var action: String { get }
    var description: String { get }
    var parameters: [CommandParameter] { get }
    func handle(_ request: ExploreRequest) async throws -> ExploreResult
}

public extension Command {
    var parameters: [CommandParameter] { [] }   // 默认无参，不强制实现
}
```

`ParameterKind` 与 `JSONValue` 类型同构（string/number/boolean/object/array），使参数 schema 与 `data` 载荷类型系统统一演进。

### 4.3 Router（actor → 锁保护 final class）

```swift
public final class Router: Sendable {        // 真 Sendable，无 @unchecked
    private let handlers = Mutex<[String: any Command]>([:])

    public init() {}

    public func register(_ command: any Command) {
        handlers.withLock { $0[command.action] = command }
    }

    public func register(action: String,
                         description: String = "",
                         parameters: [CommandParameter] = [],
                         _ handler: @escaping @Sendable (ExploreRequest) async throws -> ExploreResult) {
        register(ClosureCommand(action: action, description: description,
                                parameters: parameters, handler: handler))
    }

    func route(_ request: ExploreRequest) async -> ExploreResult {
        let command = handlers.withLock { $0[request.action] }   // 锁内只取
        guard let command else {
            return .failure(code: .unknownAction, message: "no handler for '\(request.action)'")
        }
        if let msg = Self.validate(request.data, against: command.parameters) {
            return .failure(code: .invalidData, message: msg)
        }
        do { return try await command.handle(request) }          // 锁外 await
        catch { return .failure(code: .internalError, message: error.localizedDescription) }
    }

    /// 供 help 命令自省：列出全部命令元数据（锁内快照，锁外构造）。
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
            if let v = v, !Self.typeMatches(v, kind: p.kind) {
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

`route` 与 `commandMetadata` 均同步；`route` 仍为 `async` 仅因 `handle` 是 async（业务可异步），与注册/隔离无关。

### 4.4 ExploreServer（去 @unchecked、init 注册内置、修 start）

```swift
public final class ExploreServer: Sendable {        // 真 Sendable，无 @unchecked
    private let port: UInt16
    public let authToken: String?
    private let router = Router()
    private let listener = Mutex<HTTPListener?>(nil)
    private let eventContinuation: AsyncStream<ServerEvent>.Continuation
    private let eventStream: AsyncStream<ServerEvent>
    // registeredBuiltins 删除：内置命令在 init 注册

    public init(port: UInt16 = 38321, authToken: String? = nil) {
        self.port = port
        self.authToken = authToken
        var continuation: AsyncStream<ServerEvent>.Continuation!
        self.eventStream = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
        BuiltinHandlers.registerAll(into: router)    // 同步，无 await
    }

    public func register(_ command: any Command) { router.register(command) }

    public func register(action: String,
                         description: String = "",
                         parameters: [CommandParameter] = [],
                         _ handler: @escaping @Sendable (ExploreRequest) async throws -> ExploreResult) {
        router.register(action: action, description: description, parameters: parameters, handler)
    }

    public func start() async throws {
        let l = try HTTPListener(port: port, router: router) { [eventContinuation] event in
            eventContinuation.yield(event)
        }
        try await l.start()                            // await 端口就绪；占用则 throw
        listener.withLock { $0 = l }
    }

    public func stop() {
        listener.withLock { $0?.stop(); $0 = nil }
    }

    public func events() -> AsyncStream<ServerEvent> { eventStream }
}
```

`start()` 现在的 async 名副其实——await 端口绑定就绪、失败 throw，修掉静默失败 bug。签名保持 `async throws`，调用方代码不变。

### 4.5 闭包适配器 ClosureCommand

让闭包注册入口与协议入口共享同一条路由路径，两套 API 零重复。

```swift
struct ClosureCommand: Command {
    let action: String
    let description: String
    let parameters: [CommandParameter]
    let handler: @Sendable (ExploreRequest) async throws -> ExploreResult
    func handle(_ request: ExploreRequest) async throws -> ExploreResult { try await handler(request) }
}
```

### 4.6 内置命令重构 + help

`ping`/`echo`/`info` 由静态方法改为 `Command` 结构体；新增 `help` 遍历 router 输出全部命令元数据，**让协议价值当场可见**。

```swift
struct HelpCommand: Command {
    let action = "help"
    let description = "列出所有已注册命令及其参数说明"
    let parameters: [CommandParameter] = []
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
    static func registerAll(into router: Router) {     // 同步，不再是 async
        router.register(PingCommand())
        router.register(EchoCommand())
        router.register(InfoCommand())
        router.register(HelpCommand(router: router))
    }
}
```

`help` 输出结构（`action` + `description` + `parameters`）刻意对齐 MCP `tools/list` 的 `name` + `description` + `inputSchema`，为 Mac 侧 MCP 网关直接消费做好准备。`info` 仍只用 `ProcessInfo`/`Bundle`，不依赖 UIKit。

### 4.7 start() 端口失败修复（HTTPListener）

```swift
func start() async throws {
    guard let listener else { return }
    listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
    listener.start(queue: .global())
    try await Self.waitUntilReady(listener)        // .ready 通过；.failed/.cancelled 抛错
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

`stateUpdateHandler` 可能多次回调，continuation 只能 resume 一次——resume 后立即置 nil handler 防重入（写进正确性约束）。

## 5. 数据流

请求到达 → `HTTPListener.handle`（`.global()` queue 的 Task）→ HTTP 解析 → `Router.route`（锁内取 `command`，锁外参数校验 + `await handle`）→ envelope → 回写响应。锁临界区仅覆盖字典查找，纳秒级，不阻塞并发连接。

## 6. 错误处理

沿用现有分层，新增参数校验：

- **通信失败**：HTTP 状态码 400（非法方法/路径/JSON）/500。
- **业务失败**：envelope `ok:false` + `ExploreError`。
  - `unknownAction`：未注册的 action。
  - `invalidData`：新增——必填参数缺失或类型不匹配（Router 统一校验产出）。
  - `internalError`：handler 抛错被 Router 捕获转换。
- **启动失败**：`start()` throw（端口冲突等），调用方需 try。

## 7. 扩展性设计（核心原则）

扩展性靠**抽象边界 + 协议扩展默认值**体现，不预先实现未需求的能力。

1. **协议扩展默认值机制**：`Command` 未来新增可选字段（如返回值 schema、权限标记）时，用 `extension Command { var foo: ... { 默认 } }` 提供默认值，既有 `Command` 实现无需改动。这是核心扩展模式。
2. **元数据自描述 → MCP**：`help` 输出 + `CommandParameter` schema 直接映射 MCP `tools/list`。Mac 侧 MCP 网关未来可直接消费，无需库改造。
3. **`Mutex<Value>` 通用复用**：库内任何需锁保护的状态（当前 `handlers`、`listener`；未来缓存/计数器）复用同一原语，`@unchecked` 永远只此一处。
4. **`ParameterKind` 与 `JSONValue` 同构**：数据与 schema 类型系统统一演进，加类型同步两边。
5. **预留但未实现的扩展点**（明确标注，避免被当 YAGNI 误删）：
   - 请求中间件/hook 链（日志、鉴权、限流）——Router 可加 `middleware`，当前不做。
   - 返回值 schema（`var resultSchema`）——当前不做。
   - 命令分组/命名空间——当前 action 扁平。
   - 运行期动态注销——Mutex 方案天然支持，`unregister` API 暂不暴露。

## 8. 向后兼容与迁移

**公共 API 变更**

- `Router`：`public actor` → `public final class: Sendable`。外部若直接用了 `await router.register(...)`，需去掉 `await`（actor→class，breaking）。
- `ExploreServer.register(action:_:)`：新增 `description`/`parameters` 参数，均有默认值 → 既有 `server.register(action: "greet") { ... }` 调用仍兼容。
- 新增 `ExploreServer.register(_ command: any Command)` 与 `Router.register(_ command: any Command)`。
- `ExploreServer`：`@unchecked Sendable` → `Sendable`（兼容，都是 Sendable）。
- `ExploreServer.start()`：签名不变（`async throws`），行为变（真正 await + 端口冲突可 throw），调用方代码不变但需意识到端口冲突会抛错。
- `BuiltinHandlers.registerAll`：`async` → 同步。

**迁移点**

- `Examples/SPMExample`：`await server.register(...)` → `server.register(...)`；可选地展示 `register(GreetCommand())` 协议式注册作为示范。
- 测试套件：去掉所有 `register` 前的 `await`；`BuiltinHandlers.registerAll` 调用去 `await`。

## 9. 测试计划

- **Mutex**：并发读写正确性（多 Task 并发 register + route，断言一致性）、deinit 不泄漏。
- **参数校验**：必填缺失、类型不匹配、可选缺失通过、无 parameters 通过。
- **help 命令**：输出结构正确、包含全部已注册命令（含 help 自身）。
- **Router**：同步 register/route、unknownAction、internalError 捕获、闭包入口与协议入口等价。
- **ExploreServer**：init 后内置命令即已注册（不再依赖 start）、stop 幂等、start 端口冲突 throw（集成测试用端口 38399 复现占用）。
- **集成测试**：沿用 `@Suite(.serialized)`、端口 38399 串行；端到端 ping/echo/info/help + 自定义命令。
- **覆盖率**：维持 ≥ 80%（当前 89.91%）。

## 10. 已知风险 / 待验证

- **`any Command` 语法兼容**：`any P` 存在类型语法为 Swift 5.6+。framework 工程 `SWIFT_VERSION=5.0` + 6.2 工具链下能否编译需实测；若不能，回退为裸 `Command` 存在类型（语义等价，6.2 下会有 deprecation 警告）。实现首步先验证此项。
- **部署目标不一致**：`Package.swift` 声明 iOS 13 / macOS 10.15，framework 与 SPMExample 工程为 26.2。os_unfair_lock（iOS 10+）满足最低的 13，安全。建议另起任务对齐两处部署目标，但不在本次重构范围内。
- **NWListener stateUpdateHandler 防重入**：见 4.7，resume 后置 nil。
- **`Route`/`commandMetadata` 同步访问**：确认 `HTTPListener` 的 Task 调 `route`、`HelpCommand` 调 `commandMetadata` 在锁语义下正确（锁内仅字典访问，无 await）。

## 11. 验证标准

- `swift test` 全绿（含集成测试）。
- 覆盖率 ≥ 80%。
- framework 工程 `xcodebuild ... -sdk iphonesimulator build` 通过。
- SPMExample 运行：`ping`/`echo`/`info`/`help` + 自定义 `greet`/`device` 均正常，`help` 返回全部命令元数据。
- 通过 `iproxy` + `curl` 真机端到端验证 `help` 与参数校验（缺参返回 `invalid_data`）。
