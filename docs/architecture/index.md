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
| `Handlers/BuiltinHandlers.swift` | ping/echo/info/help | 库内只用 `ProcessInfo`/`Bundle`，**不用 UIDevice** |

## UIKit 扩展模块（`Sources/iOSExploreUIKit/`）

core 库刻意不依赖 UIKit；所有 `ui.*` 命令下沉到独立模块 `iOSExploreUIKit`，由宿主 App **显式注册**（`server.registerUIKitCommands()`）。core 与 UIKit 之间只通过 public 缝交互，core 永不 `import UIKit` / `canImport(UIKit)`。

| 文件/目录 | 职责 | 关键点 |
|---|---|---|
| `UIKitCommandRegistrar.swift` | 显式注册入口 | `public extension ExploreServer`；注册前后打 `uikit.registrar` 日志（started/completed count） |
| `UIKitHandlers.swift` | 命令注册聚合 | 汇总四个命令的注册点 |
| `UIKitCommandLogging.swift` | 日志入口 | 复用 core public 缝 `ExploreLogging.emitExtension`，category 统一 `command`；不暴露 core internal logger |
| `UIKitCommandError.swift` | UIKit 错误工厂 | 生成 `invalid_data`/`internal_error`，单一来源 |
| `Context/UIKitContextProvider.swift` | `@MainActor` 上下文 | 取当前前台 window / 顶部控制器 / 根 view；记录 MainActor hop 日志 |
| `Locator/UIKitLocator.swift` + `UIKitLocatorResolver.swift` | 目标定位 | `UIKitLocator` 是 Foundation-only 值类型（query→identifier/path/snapshotID），resolver 仅 iOS 编译把 locator 解析为真实 `UIView` |
| `Action/UIKitActionExecutor.swift` | 动作执行 | `@MainActor`；按能力（tap/control）路由到具体执行；解析失败/定位失败/能力不支持各自记 error 日志 |
| `Action/UIKitActionCapabilityResolver.swift` | 能力解析 | 判断目标 view 支持哪种动作 |
| `Snapshot/UIKitSnapshotStore.swift` + `UIKitFingerprintCollector.swift` | 快照与陈旧检测 | 容量 512、TTL、LRU；path+snapshotID 页面变动返回 `invalid_data` + 固定陈旧消息 |

**typed factory 规则**：每个 UIKit 命令的入参先用 Foundation-only 的 typed query 模型（如 `UITapQuery`）解析并校验，校验通过后才进入 `@MainActor` 的 resolver/executor；UIKit 类型绝不穿过 public 边界回到非隔离域。这保证模型/解析逻辑可在 macOS `swift test` 覆盖，真实 `UIView` 采集只在 iOS 编译执行。

## 模块边界与共享源码

- **SPM 包**（根 `Package.swift` + `Sources/` + `Tests/`）是主交付物，`swift test` 跑这里。两个 product：`iOSExploreServer`（core）与 `iOSExploreUIKit`（依赖 core）。
- **framework 工程**（`iOSExploreServer/iOSExploreServer.xcodeproj`）有两个 framework target：
  - `iOSExploreServer.framework`：`PBXFileSystemSynchronizedRootGroup` 指向 `../Sources/iOSExploreServer/`。
  - `iOSExploreUIKit.framework`：指向 `../Sources/iOSExploreUIKit/`，链接并依赖 core framework。
  - 两者与 SPM **共享同一份源码**，零漂移。Debug/Release 均 `SWIFT_VERSION=5.0`、`BUILD_LIBRARY_FOR_DISTRIBUTION=NO`、相同 deployment target。
- **SPMExample**（`Examples/`）是 UIKit App，本地 SPM 依赖同时选 core 与 `iOSExploreUIKit` product；它允许 `import UIKit`，并在 App 层注册需要 UIKit 的 handler（如 `device`）。
- **显式注册**：core 初始化**不会**自动注册任何 UIKit 命令；宿主必须调用 `server.registerUIKitCommands()` 才开放 `ui.*`。未注册时 `help` 不含 UIKit action，是回归保护点。

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

## UIKit 层级快照

`ui.topViewHierarchy` 是首个 UIKit 内置命令，用于返回当前 foreground window 顶部控制器 view 及其子视图信息。命令在 `MainActor` 上读取 UIKit 状态，输出结构化节点：

- 定位：`path`，例如 `root/0/2/1`，只读且不写回业务 UI。
- 语义：`accessibilityIdentifier`、`accessibilityLabel`、`accessibilityValue`、`accessibilityHint`。
- 布局：`frame`、`bounds`。
- 状态：hidden、alpha、opaque、userInteractionEnabled。
- 验收：文本、字体、文本色、背景色、tint、圆角、边框、控件状态、图片尺寸、滚动信息。

优先用业务层设置的 `accessibilityIdentifier` 做稳定语义锚点；缺失时用 `path` 描述快照内位置。命令不主动设置 identifier。

`ui.viewTargets` 是事件下发前的轻量目标发现命令，返回扁平 targets 列表，不返回完整 `subviews` 树，也不承担视觉验收职责。每个 target 包含 `path`、运行时类型、轻量 role、`accessibilityIdentifier`、短文本、window 坐标 frame 和基础交互状态；agent 应优先调用它来找到 `ui.tap`、`ui.control.sendAction` 以及后续事件命令所需的目标。

`Utils/`（`iOSExploreUIKit` 内）集中保存 UIKit view 定位能力：当前前台 window、顶部控制器、顶部根 view、`accessibilityIdentifier` 精确查找、`path` 查找、命中 view 与目标 view 的祖先关系判断。后续 UIKit 命令应复用该目录，不要各自重新实现路径解析和遍历。

## UIKit 定位语义

所有 `ui.*` 交互命令的定位遵循统一优先级：`identifier`（精确）→ `path`（只读路径）→ 可选 `snapshotID`（陈旧防护）。

- `identifier`：按业务层设置的 `accessibilityIdentifier` 精确定位。**完整匹配、不截断**（历史 bug 曾截断 prefix）；匹配多个 view 返回 `invalid_data`。
- `path`：来自 `ui.viewTargets`/`ui.topViewHierarchy` 的只读路径（如 `root/0/2`），仅描述快照内位置。
- `snapshotID` + `path`：交互命令携带 `ui.viewTargets` 返回的 `snapshotID` 时，executor 会重新采集当前 view 树指纹并逐字段比对；页面已变动（类型/identifier/role/状态任一不同）即判陈旧，返回 HTTP 200 + `ok:false` + `invalid_data` + **固定陈旧消息**（不泄露具体哪个字段变了）。无 `snapshotID` 时跳过陈旧检查，按当前树直接定位。

`ui.control.sendAction` 复用同一套顶部控制器根 view 和 `path` 规则，按 `accessibilityIdentifier` 或 `path` 定位目标，校验目标是 `UIControl` 后在 `MainActor` 调用 `sendActions(for:)`。该命令触发 target-action，不模拟真实触摸坐标、命中测试或高亮过程。

`ui.tap` 表达更接近用户点击的语义：按 `accessibilityIdentifier` / `path` 定位 view 后取中心点，或直接使用 window 坐标，先用 `window.hitTest` 校验实际命中。第一版对 UIControl 使用 `.touchUpInside` fallback，并在响应中标记 `dispatchMode=controlActionFallback`；非 UIControl 会返回明确不支持，避免伪造不稳定的私有触摸事件。
