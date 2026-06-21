# 架构概览

> 本文是 agent 日常参考的精炼版。完整设计背景见 `docs/superpowers/specs/2026-06-21-ios-explore-server-design.md`。

## 通信链路

```
Mac                      USB (usbmux)                       iPhone
─────                    ────────────                       ──────
curl ──→ localhost:38321 ──[iproxy 38321 38321]──→ :38321 ──→ ExploreServer
                                                              │ HTTPListener (NWListener)
                                                              │  ├─ accumulate bytes
                                                              │  ├─ HTTPParser.parseRequest
                                                              │  ├─ Router.route (actor)
                                                              │  └─ write response + close
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
| `HTTPParser.swift` | 解析请求 + 构造 envelope 响应 | `parseRequest` 对 partial body 严格返回 nil；`response(for:)`/`errorResponse` |
| `Router.swift` | `actor`，action→handler 注册表与分发 | 未命中→`.unknownAction`；handler 抛错→`.internalError`；不 rethrow |
| `HTTPListener.swift` | `NWListener` 封装 | 接连接→解析→路由→回写→`conn.cancel()`；`@unchecked Sendable`（serial start/stop） |
| `ExploreServer.swift` | 对外门面 + `ServerEvent` 事件流 | `start()/stop()/register()/events()`；内置命令只注册一次 |
| `Handlers/BuiltinHandlers.swift` | ping/echo/info | 库内只用 `ProcessInfo`/`Bundle`，**不用 UIDevice** |

## 模块边界与共享源码

- **SPM 包**（根 `Package.swift` + `Sources/` + `Tests/`）是主交付物，`swift test` 跑这里。
- **framework 工程**（`iOSExploreServer/iOSExploreServer.xcodeproj`）的 `PBXFileSystemSynchronizedRootGroup` 指向 `../Sources/iOSExploreServer/`——与 SPM **共享同一份源码**，零漂移。改源码只改一处。
- **SPMExample**（`Examples/`）是 UIKit App，通过本地 SPM 依赖消费库；它才允许 `import UIKit`，并在 App 层注册需要 UIKit 的 handler（如 `device`）。

## 并发模型

- `Router` 是 `actor`（handler 表共享可变状态）。
- `HTTPListener`/`ExploreServer` 是 `@unchecked Sendable`：约定 start/stop 由调用方串行触发（App 主线程按钮），不保证并发启停安全。
- 连接处理 `Task { [router, onEvent] in ... }` 只捕获 actor + `@Sendable` 闭包，**不捕获 self**。

## envelope 协议

- 成功：`{"ok":true,"data":{...}}`
- 业务失败：`{"ok":false,"error":{"code":"...","message":"..."}}`
- 错误码：`unknown_action` / `invalid_data` / `internal_error` / `bad_request`
- 通信层错误（非 POST、非法 JSON）用 HTTP 400/500 + `ok:false`；业务失败用 HTTP 200 + `ok:false`——区分"通信失败"与"业务失败"。
