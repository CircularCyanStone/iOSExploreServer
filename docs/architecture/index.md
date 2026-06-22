# 架构概览

> 本文是 agent 日常参考的精炼版。完整设计背景见 `docs/superpowers/specs/2026-06-21-ios-explore-server-design.md`。

## 通信链路

```
Mac                      USB (usbmux)                       iPhone
─────                    ────────────                       ──────
curl ──→ localhost:38321 ──[iproxy 38321 38321]──→ :38321 ──→ ExploreServer
                                                              │ HTTPListener (NWListener)
                                                              │  ├─ accept / limit sessions
                                                              │  └─ ClientSession
                                                              │     ├─ accumulate bytes
                                                              │     ├─ HTTPParser.parseRequestResult
                                                              │     ├─ Router.route (Mutex-protected registry)
                                                              │     └─ write response + close
                                                              ▼
                                                      { "ok": true, "data": {...} }
```

方向：Mac 是客户端，iPhone 是服务端，一次请求/响应往返。传输刻意用明文 HTTP——经 iproxy 的 USB 隧道，无需 TLS；Mac 侧 `curl` 即客户端，零 SDK 依赖。

## 组件职责（`Sources/iOSExploreServer/`）

| 文件 | 职责 | 关键点 |
|---|---|---|
| `Models.swift` | `JSONValue`/`JSON`/`ExploreRequest`/`ExploreResult`/`ExploreError` | Sendable 值类型；`JSON` 是命令 data 容器 |
| `JSONCoder.swift` | JSON ↔ Data/Any 编解码 | 基于 `JSONSerialization`；`NSNumber` bool/number 用 `CFBooleanGetTypeID` 区分 |
| `HTTPRequest.swift` / `HTTPResponse.swift` | HTTP 值类型 | `serialized()` 产出 `HTTP/1.1 ... \r\n\r\n body` |
| `HTTPParser.swift` | 解析请求 + 构造 envelope 响应 | `parseRequestResult` 区分 complete/incomplete/invalid；`parseRequest` 保留兼容 |
| `ExploreServerError.swift` | 统一错误模型 | HTTP status/reason、envelope code/message、日志文本的单一来源 |
| `ExploreLogging.swift` | Apple Unified Logging 封装 | 默认关闭；`ExploreLogging.setEnabled(true)` 开启；category 区分 server/listener/http/router/command |
| `Router.swift` | `Mutex` 保护的 action→handler 注册表与分发 | 未命中→`.unknownAction`；handler 抛错→`.internalError`；不 rethrow |
| `ClientSession.swift` | 单连接生命周期 | session id、receive buffer、读/命令超时、发送响应、统一 close |
| `HTTPListener.swift` | `NWListener` 封装 | 串行 network queue；session map；连接上限；ready 后继续观测 listener 状态 |
| `ExploreServer.swift` | 对外门面 + `ServerEvent` 事件流 | `start()/stop()/register()/events()`；内置命令只注册一次 |
| `Handlers/BuiltinHandlers.swift` | ping/echo/info | 库内只用 `ProcessInfo`/`Bundle`，**不用 UIDevice** |

## 模块边界与共享源码

- **SPM 包**（根 `Package.swift` + `Sources/` + `Tests/`）是主交付物，`swift test` 跑这里。
- **framework 工程**（`iOSExploreServer/iOSExploreServer.xcodeproj`）的 `PBXFileSystemSynchronizedRootGroup` 指向 `../Sources/iOSExploreServer/`——与 SPM **共享同一份源码**，零漂移。改源码只改一处。
- **SPMExample**（`Examples/`）是 UIKit App，通过本地 SPM 依赖消费库；它才允许 `import UIKit`，并在 App 层注册需要 UIKit 的 handler（如 `device`）。

## 并发模型

- `Router` 是 `final class`，handler 表共享可变状态由 `Mutex` 保护；`route` 锁内只取命令快照，锁外校验和 `await handle`。
- `ExploreLogging` 的全局配置同样用 `Mutex` 保护；日志 sink 调用在锁外执行，避免锁内 I/O。
- `HTTPListener` 使用独立串行 `networkQueue` 承载 `NWListener`/`NWConnection` 回调；活跃 session map 由 `Mutex` 保护。
- `ClientSession` 当前仍是短连接模型，一连接只处理一个 HTTP 请求；关闭路径统一走 `close(reason:)`，并回调 listener 移除 session。
- listener 进入 `.ready` 后不会移除 `stateUpdateHandler`；后续 `.waiting`/`.failed`/`.cancelled` 会继续记录并通过事件暴露不可恢复失败。

## 资源限制

- 默认在线 session 上限为 4；超出后返回 HTTP 503 + `ok:false` envelope。
- 默认 header 上限 16 KB，body/request 上限 1 MB；非法或超限请求通过 parser 三态返回 `bad_request`。
- 默认读请求超时和命令执行超时均为 10 秒。命令超时会返回 `internal_error` envelope，避免单个 handler 长时间占住连接。

## envelope 协议

- 成功：`{"ok":true,"data":{...}}`
- 业务失败：`{"ok":false,"error":{"code":"...","message":"..."}}`
- 错误码：`unknown_action` / `invalid_data` / `internal_error` / `bad_request`
- 通信层错误（非 POST、非法 JSON）用 HTTP 400/500 + `ok:false`；业务失败用 HTTP 200 + `ok:false`——区分"通信失败"与"业务失败"。

## 错误模型

- 新增错误出口必须先在 `ExploreServerError` 增加工厂方法，再由该对象生成 HTTP response、业务 failure 和日志。
- `ExploreServerError` 同时持有 `httpStatus`、`httpReason`、`ExploreError code`、对外 `message` 和内部 `logMessage`，避免调用点分别拼接导致语义漂移。
- `HTTPParser.parseRequestResult` 的 `.invalid`、`ClientSession` 的超时/请求校验、`HTTPListener` 的端口/连接上限、`Router` 的 unknown/invalid/throw 都应统一使用该类型。
