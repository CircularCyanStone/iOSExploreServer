# iOSExploreServer 设计文档

- **日期**: 2026-06-21
- **状态**: 已通过口头评审，待 spec 审阅
- **作者**: coo (coocy) + Claude

## 1. 背景与目标

需要一个工具，打通「Mac 命令 → 手机 App」的通信链路：在 Mac 上执行简单的 HTTP 命令，经 USB 转发到 iPhone 上正在运行的 App，让 App 执行预定义能力并返回结果。

本次是**第一次搭建**，核心目标是：

1. **验证可行性**：跑通 Mac → iproxy → iPhone → HTTP Server 的完整链路。
2. **不浪费封装**：设计成可扩展的「命令注册」框架，后续无论是新增手机端能力，还是在 Mac 侧构建 MCP，都能直接复用，而不必推倒重来。

传输层刻意选 HTTP：这样 Mac 侧只需 `curl`，手机侧也可用任意简单 HTTP 工具调用，不引入私有协议或额外依赖。

## 2. MVP 范围

### In scope（本次实现）

- SPM 库 `iOSExploreServer`：基于 `NWListener` 的手机端 HTTP Server。
- 单一命令端点 + JSON 分发的路由机制。
- 三个内置命令：`ping` / `echo` / `info`。
- 可扩展的 handler 注册机制（供后续加命令）。
- 示例 App `SPMExample`：启动/停止 Server + 请求日志面板。
- iproxy 转发说明 + 一键脚本。
- Swift Testing 单元 + 集成测试，覆盖率 ≥ 80%。

### Out of scope（明确不做）

- 任意 shell 命令执行（iOS 沙盒不允许，也不是目标）。
- UI 自动化操作（点击/输入等）——留给后续阶段。
- Mac 侧 MCP server（本工具为其铺路，但本次不实现）。
- 强制鉴权 / TLS（USB 物理连接已提供一层隔离；仅预留 token 钩子）。

## 3. 架构总览

```
Mac                          USB (usbmux)                       iPhone
─────                        ────────────                       ──────
curl ──→ localhost:38321 ──[iproxy 38321 38321]──→ :38321 ──→ ExploreServer
                                                              │ HTTPListener (NWListener)
                                                              │  ├─ 解析 HTTP 请求
                                                              │  ├─ 交给 Router
                                                              │  └─ 回写 HTTP 响应
                                                              ▼
                                                         Router (actor)
                                                              │ action 字段分发
                                                              ▼
                                                      注册的 handler ──→ ExploreResult
                                                              │
                                                              ▼
                                                      { "ok": true, "data": {...} }
```

**通信方向**：Mac 是客户端，iPhone 是服务端。请求/响应一次往返。

**传输选型理由**：HTTP 明文经 iproxy 的 USB 隧道传输，无需 TLS；Mac 侧 `curl` 即客户端，无需任何 SDK。

## 4. 产物与仓库结构

仓库保留**三种产物形态**：

| 产物 | 形态 | 作用 | 位置 |
|---|---|---|---|
| `iOSExploreServer` (SPM) | SPM 库 | 主交付物，SPM 集成与 `swift test` | 根 `Package.swift` + `Sources/` + `Tests/` |
| `iOSExploreServer.xcodeproj` | Xcode framework 工程 | 手动编译出 `.framework`，嵌入非 SPM 项目 | `iOSExploreServer/iOSExploreServer.xcodeproj` |
| `SPMExample` | iOS App | 集成库 + 测试 UI | `Examples/SPMExample/` |

**源码单一来源原则**：SPM 包与 framework 工程**必须共享同一份源码**（根 `Sources/iOSExploreServer/`），避免双份维护漂移。framework 工程当前同步的是自己目录下的独立空文件，需要修正（见 §10）。

最终目录结构（实现后）：

```
iOSExploreServer/                      ← 仓库根
├── Package.swift                      ← SPM 清单
├── Sources/
│   └── iOSExploreServer/              ← 唯一源码源（SPM + framework 共用）
│       ├── ExploreServer.swift
│       ├── HTTPListener.swift
│       ├── HTTPRequest.swift
│       ├── HTTPResponse.swift
│       ├── HTTPParser.swift
│       ├── Router.swift
│       ├── Models.swift
│       └── Handlers/
│           └── BuiltinHandlers.swift
├── Tests/
│   └── iOSExploreServerTests/
│       ├── HTTPParserTests.swift
│       ├── RouterTests.swift
│       ├── BuiltinHandlersTests.swift
│       └── IntegrationTests.swift
├── iOSExploreServer/
│   └── iOSExploreServer.xcodeproj/    ← framework 工程（同步组指向 ../Sources/iOSExploreServer）
├── Examples/
│   └── SPMExample/                    ← 测试 App
└── docs/
    └── superpowers/specs/
        └── 2026-06-21-ios-explore-server-design.md   ← 本文件
```

## 5. 库组件设计（`Sources/iOSExploreServer/`）

遵循「many small files / 高内聚低耦合」原则。每个文件单一职责，可独立理解与测试。

### 5.1 `Models.swift` — 数据模型（Sendable 值类型）

```swift
public struct ExploreRequest: Sendable {
    public let action: String
    public let data: [String: AnyCodable]   // 宽松 JSON 容器
}

public enum ExploreResult: Sendable {
    case success(JSON)                       // data 字段
    case failure(code: String, message: String)
}

// 错误码常量
public enum ExploreError: String, Sendable {
    case unknownAction   = "unknown_action"
    case invalidData     = "invalid_data"
    case internalError   = "internal_error"
    case badRequest      = "bad_request"
}
```

`AnyCodable` / `JSON` 是类型擦除的 JSON 容器（参考常见开源实现），让 handler 不必为每个命令定义专用 DTO（MVP 阶段够用；后续高频命令可再定义强类型）。

### 5.2 `HTTPRequest.swift` / `HTTPResponse.swift` — HTTP 值类型

```swift
struct HTTPRequest {
    let method: String      // "POST"
    let path: String        // "/"
    let headers: [String: String]
    let body: Data
}

struct HTTPResponse {
    let status: Int          // 200 / 400 / 500
    let reason: String       // "OK" / "Bad Request"
    let body: Data           // JSON
    func serialized() -> Data  // 拼成完整 HTTP/1.1 报文
}
```

值类型，纯数据，不涉及网络。

### 5.3 `HTTPParser.swift` — HTTP 报文解析（纯函数）

```swift
enum HTTPParser {
    static func parse(_ data: Data) -> HTTPRequest?      // 解析请求行 + headers + body
    static func makeJSONResponse(result: ExploreResult) -> HTTPResponse  // 业务结果 → 响应
}
```

按 HTTP/1.1 解析请求行、Headers、Content-Length 定界 body。**只解析最小必要**（POST、单端点、JSON body），不实现完整 HTTP 规范（YAGNI）。

### 5.4 `Router.swift` — 命令分发（actor）

```swift
public actor Router {
    private var handlers: [String: @Sendable (ExploreRequest) async throws -> ExploreResult] = [:]

    public func register(action: String,
                         _ handler: @Sendable @escaping (ExploreRequest) async throws -> ExploreResult)
    public func route(_ request: ExploreRequest) async -> ExploreResult
}
```

- `register` 注册 action → handler。
- `route` 按 `request.action` 查表；未命中返回 `.failure(.unknownAction)`。
- handler 抛异常被捕获，转为 `.failure(.internalError)`。

### 5.5 `HTTPListener.swift` — NWListener 封装

```swift
final class HTTPListener {
    private let listener: NWListener
    private let router: Router
    private let onEvent: @Sendable (ServerEvent) -> Void   // 事件上报给 ExploreServer

    init(port: UInt16, router: Router, onEvent: @escaping @Sendable (ServerEvent) -> Void) throws
    func start()    // 监听，每条连接 spawn 一个处理任务
    func stop()
}
```

- `NWListener` 用 `NWEndpoint.hostPort(host: .ipv4(.any), port:)`，监听所有接口（USB 与 Wi-Fi 均可达）。
- `newConnectionHandler` 里 receive 完整请求 → `HTTPParser.parse` → 提取 `ExploreRequest` → `router.route` → 回写响应；每一步通过 `onEvent` 上报事件。
- 连接处理用结构化并发（`async let` / 独立 `Task`），单连接失败不影响其他连接。
- **事件归属**：`HTTPListener` 不持有事件流，仅通过 `onEvent` 回调上报；事件流的源（`AsyncStream` + continuation）唯一地由 `ExploreServer` 持有。

### 5.6 `ExploreServer.swift` — 对外门面（Facade）

```swift
public final class ExploreServer {
    public init(port: UInt16 = 38321)
    public func register(action: String,
                         _ handler: @Sendable @escaping (ExploreRequest) async throws -> ExploreResult)
    public func start() async throws
    public func stop()
    public var events: AsyncStream<ServerEvent> { get }   // 唯一事件流源；HTTPListener 通过 onEvent 回调注入事件
}

public enum ServerEvent: Sendable {
    case started(port: UInt16)
    case stopped
    case received(method: String, path: String, action: String?)
    case responded(status: Int, ok: Bool)
    case error(String)
}
```

- 内部持有 `Router` + `HTTPListener`，对外暴露最简 API。
- 构造时自动注册三个内置命令（ping/echo/info）。
- `events` 供示例 App 日志面板订阅。

### 5.7 `Handlers/BuiltinHandlers.swift` — 内置命令

```swift
enum BuiltinHandlers {
    static let ping: Handler  = { _ in .success(["pong": true, "uptime": uptimeSeconds]) }
    static let echo:  Handler = { req in .success(req.data) }
    static let info:  Handler = { _ in
        .success([
            "device":  uid.machineModelName,      // 设备机型
            "system":  osVersion,
            "app":     bundleVersion,
            "bundle":  bundleId,
        ])
    }
}
```

`info` 用 `UIDevice` / `ProcessInfo` / `Bundle`。注意 `UIDevice` 是 UIKit，库本身保持 **Foundation + Network only**（不依赖 UIKit），`info` 的设备字段通过注入的闭包或 `ProcessInfo`/`Bundle` 提供非 UI 部分；UI 相关字段由 App 层注入（见 §7）。

> **库依赖约束**：`iOSExploreServer` 库只依赖 `Foundation` + `Network`，保持可在 App 之外（如测试进程、未来 macOS MCP host）复用。需要 UIKit 的信息（如 `UIDevice.model`）由集成方通过注册额外 handler 注入，不硬编码进库。

## 6. 命令协议（单端点 + JSON 分发）

### 请求

`POST /`，body 为 JSON：

```json
{ "action": "ping", "data": { "echo": "hi" } }
```

- `action`：命令名（必填，字符串）。
- `data`：命令参数（可选，任意 JSON 对象）。

### 成功响应 envelope

```json
{ "ok": true, "data": { "pong": true, "uptime": 12.3 } }
```

### 业务失败 envelope（通信成功，命令本身失败）

```json
{ "ok": false, "error": { "code": "unknown_action", "message": "no handler for 'foo'" } }
```

遵循通用 API 封装约定：`ok` 表示成功与否，`data` 成功时携带载荷，`error` 失败时携带 `code`+`message`。

### 内置命令返回样例

| action | data 入参 | 成功 data 出参 |
|---|---|---|
| `ping` | 忽略 | `{ "pong": true, "uptime": <秒> }` |
| `echo` | 任意对象 | 原样回显入参 `data` |
| `info` | 忽略 | `{ "system":..., "app":..., "bundle":..., "device":...(若注入) }` |

### 扩展示例

集成方：

```swift
server.register(action: "greet") { req in
    let name = req.data["name"]?.stringValue ?? "world"
    return .success(["message": "Hello, \(name)"])
}
```

Mac 调用：

```bash
curl -X POST http://localhost:38321/ \
     -H 'Content-Type: application/json' \
     -d '{"action":"greet","data":{"name":"Claude"}}'
```

## 7. 示例 App（`Examples/SPMExample/`）

### 7.1 集成方式

`SPMExample.xcodeproj` 是 xcodeproj 工程，添加一个**本地 SPM 依赖**指向根 `../Package.swift`，target `SPMExample` link `iOSExploreServer` 库，`import iOSExploreServer`。

### 7.2 UI（代码布局，弃用 storyboard 拖拽）

`ViewController` 用代码布局：

```
┌──────────────────────────────┐
│  状态: ● 监听中 :38321        │  ← UILabel（绿=监听 / 灰=停止）
├──────────────────────────────┤
│  [ 启动 Server ]  [ 停止 ]    │  ← 两个 UIButton
├──────────────────────────────┤
│  请求日志                     │
│  12:01:03 POST action=ping →200 ok│
│  12:01:10 POST action=info  →200 ok│  ← UITableView，倒序
│  ...                          │
└──────────────────────────────┘
```

- App 启动**不自动起 Server**，由按钮控制。
- 订阅 `server.events`，追加到日志列表（保留最近 N 条）。
- 启动时注册一个示例自定义命令 `greet`（演示扩展机制），并注入 UIKit 设备信息（演示 §5.7 的注入约定）。

### 7.3 Info.plist

- 预留 `NSLocalNetworkUsageDescription = "用于接收来自 Mac 的调试请求。"`（走 Wi-Fi 时会触发；经 USB/iproxy 通常不触发，实测确认）。
- Server 是入站 HTTP，受 ATS 影响的是出站连接，无需改 ATS 配置。

## 8. 错误处理

分层处理，区分「通信失败」（HTTP 状态码）与「业务失败」（envelope `ok:false`）：

| 场景 | HTTP 状态 | body |
|---|---|---|
| 非 POST / 路径非 `/` | 400 | `{ ok:false, error:{ code:"bad_request" } }` |
| body 非合法 JSON / 缺 action | 400 | `{ ok:false, error:{ code:"bad_request" } }` |
| action 未注册 | 200 | `{ ok:false, error:{ code:"unknown_action" } }` |
| handler 抛异常 | 500 | `{ ok:false, error:{ code:"internal_error" } }` |
| handler 返回 `.failure` | 200 | `{ ok:false, error:{ code:<自定义> } }` |
| 正常 | 200 | `{ ok:true, data:{...} }` |

- 任何解析/分发异常都**不使连接悬挂**，必定返回一个 HTTP 响应后关闭连接。
- handler 内部用 typed throws（Swift 6）或转 `.failure`，错误信息不泄漏敏感数据。

## 9. iproxy / Mac 侧（不进包）

Mac 侧直接使用 `iproxy` 做端口转发：

```bash
PORT=38321
command -v iproxy >/dev/null || brew install libimobiledevice
exec iproxy "$PORT" "$PORT"
```

README 写明三步：

```bash
# 1) 手机上启动 SPMExample，点「启动 Server」
# 2) Mac 上起转发
iproxy 38321 38321
# 3) 另开终端发命令
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
```

## 10. framework 工程源码统一（实现期处理项）

framework 工程当前用 `PBXFileSystemSynchronizedRootGroup` 同步 `iOSExploreServer/iOSExploreServer/` 下的独立副本。需改为同步根 `Sources/iOSExploreServer/`：

- **首选方案**：把 `project.pbxproj` 中 framework target 的同步组 `path` 由 `iOSExploreServer` 改为 `../Sources/iOSExploreServer`（相对工程容器目录 `iOSExploreServer/`），tests 同步组改为 `../Tests/iOSExploreServerTests`；删除 `iOSExploreServer/iOSExploreServer/` 与 `iOSExploreServer/iOSExploreServerTests/` 下的独立副本。
- **验证点**：Xcode 26 的同步组是否接受指向工程目录外的相对路径。若不接受，**备选方案**：在 `iOSExploreServer/` 下建指向根 `Sources/iOSExploreServer` 的 symlink，同步组 path 指向该 symlink。
- 同步 `SWIFT_VERSION`：framework 工程当前为 5.0，SPM tools-version 6.2。源码以 Swift 6 严格并发写法为准，但**避免 6-only 语法**，保证 5.0 模式也能编译（两者共用一份源码）。

此项在实现阶段执行，验证后定稿。

## 11. 测试计划（Swift Testing，≥ 80%）

| 测试文件 | 覆盖 | 形式 |
|---|---|---|
| `HTTPParserTests` | 请求行/headers/Content-Length 定界、缺 body、非法输入、响应序列化 | 单元 |
| `RouterTests` | 注册、命中分发、未知 action、handler 抛异常转 internal_error | 单元 |
| `BuiltinHandlersTests` | ping/echo/info 返回结构正确性 | 单元 |
| `IntegrationTests` | 进程内 `start()` Server，用 `NWConnection` 连本地端口发 JSON，验证端到端往返与错误 envelope | 集成 |

集成测试利用 `NWListener` 本机可监听的特性，在模拟器 / CI 均可跑，无需真机。

## 12. 并发模型

- `Router` 为 `actor`（handler 表是共享可变状态）。
- 所有跨边界模型 `Sendable`；handler 闭包 `@Sendable`。
- 单连接处理用结构化并发，连接间隔离。
- `ExploreServer` 为 `final class`，内部状态经由 actor 保护；对 App 层呈现简单同步 API + `AsyncStream` 事件流。

## 13. 端口与安全

- **默认端口 38321**（非常见、无知名服务占用），构造时可配。
- **监听所有接口**：USB（iproxy）与同网段 Wi-Fi 均可达。
- **MVP 不强制鉴权**：依赖 USB 物理连接 + 设备信任作为隔离层。预留 token 校验钩子（`init(authToken:)`，设置后校验请求头 `X-Auth-Token`），默认关闭，留给后续开启。

## 14. 非目标 / 未来扩展

- **Mac 侧 MCP server**：本工具的 JSON 命令分发天然适配 MCP 的 tool 模型；未来在 Mac 侧写一个 MCP server，把每个 `action` 暴露为一个 MCP tool，HTTP 转发到手机即可。
- **只读探索能力**：屏幕截图、UI 层级树、日志流 —— 按 §6 协议新增 action 即可。
- **可执行动作**：UI 操作代理（tap/input）—— 同协议扩展。
- **多客户端 / 连接池 / 长连接（WebSocket）**：MVP 用一请求一连接，够用。

## 15. 已知风险与验证点

1. **iOS 后台限制**：`NWListener` 在 App 进入后台后可能被挂起。MVP 接受「App 须保持前台」的限制，文档标注。
2. **本地网络权限**：走 Wi-Fi 访问触发 `NSLocalNetworkUsageDescription` 弹窗；USB/iproxy 路径实测是否触发（Info.plist 已预留文案）。
3. **framework 同步组外部相对路径**：见 §10，实现期验证。
4. **Swift 版本兼容**：framework（5.0）与 SPM（6.2）共用源码，避免 6-only 语法。
5. **大 body / 慢连接**：MVP 假设小 JSON 请求；超大 body 暂不流式处理（YAGNI）。
