# iOSExploreServer — Agent Guide

手机端 HTTP Server 的 SPM 库（基于 `NWListener`）。Mac 经 `iproxy`（USB）+ `curl` 向 iPhone App 发送 JSON 命令，App 按 `action` 分发执行并返回统一 envelope。为后续 Mac 侧 MCP 对接铺路。

## Always follow（硬规则）

- 库 `iOSExploreServer` **只依赖 `Foundation` + `Network`，不依赖 UIKit**；需要 UIKit 的信息（如设备机型）由集成方 App 注册额外 handler 注入，不进库。
- Swift 6.2 严格并发：跨边界模型 `Sendable`，共享状态用 `Mutex`（全库唯一 `@unchecked` 边界，锁内禁 `await`），闭包 `@Sendable`。
- 唯一命令端点 `POST /`，body `{"action":"...","data":{...}}`，响应统一 envelope `{"ok":bool,"data"?,"error"?}`。**新增能力 = 注册新 action，不改协议**。
- 默认端口 **38321**（构造可配）。MVP 不强制鉴权（USB 物理连接隔离），`ExploreServer(authToken:)` 是预留钩子，当前不校验。
- SPM 包（根 `Sources/`）与 framework 工程（`iOSExploreServer/iOSExploreServer.xcodeproj`）**共享同一份 `Sources/iOSExploreServer/`**，不要维护两份源码。
- 库源码必须同时兼容 SPM（Swift 6.2）与 framework 工程（`SWIFT_VERSION=5.0`）：避免 Swift-6-only 语法。
- 底层网络 / 协议 / 连接 / 命令代码必须配套详细日志：新增或修改命令、关键属性、生命周期方法、状态转移方法、错误分支、资源限制、设计方案和文档时，要同步说明并实现对应日志点。用户不熟悉底层代码，不能只靠读实现推断运行状态。
- AI 配置与 docs 知识库（`AGENTS.md`/`CLAUDE.md`/`docs/`/`.claude/`）随项目正常纳入 git（个人项目，无保密约束）。

## Common commands

- 构建 SPM 库：`swift build`
- 测试（含真实 TCP 端到端）：`swift test`（macOS SPM 当前 105 个；iOS framework `xcodebuild ... test` 当前 109 个；集成测试用端口 38399）
- 覆盖率：`swift test --enable-code-coverage`（当前行覆盖 86.62%）
- 构建 framework 工程（core + UIKit 两个 framework）：`xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator build`
- framework 测试（含 iOS 正向注册断言）：`xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' test`
- 构建/运行测试 App：Xcode 打开 `Examples/SPMExample/SPMExample.xcodeproj`，选真机或模拟器 → Run
- 起 USB 转发：`./scripts/proxy.sh`（前台运行，Ctrl-C 停）
- 发命令：`curl -X POST http://localhost:38321/ -d '{"action":"ping"}'`

## 模块边界

- `Sources/iOSExploreServer/` — SPM 库 core（主交付物，**不依赖 UIKit**）。门面 `ExploreServer`（`Sendable`）；传输 `HTTPListener`（NWListener，`start` await 端口就绪、串行 network queue、session map）；单连接 `ClientSession`（session id、receive buffer、读/命令超时、统一 close）；解析 `HTTPParser`（三态 complete/incomplete/invalid）；统一错误 `ExploreServerError`（HTTP status/reason、envelope code/message、logMessage 单一来源）；分发 `Router`（`Mutex` 保护的 `final class`，同步 register、route 锁外校验+await）；同步原语 `Mutex`；命令协议 `Command`（action/description/parameters）；命令扩展缝 `ExploreCommandSupport`（`register(_:)` 接收 `Command`、`ExploreLogging.emitExtension` 给扩展模块复用日志）；模型 `Models`/`JSONCoder`；HTTP 值类型 `HTTPRequest`/`HTTPResponse`；日志 `ExploreLogging`；内置命令 `Handlers/BuiltinHandlers`（ping/echo/info/help，均为 `Command` struct）。
- `Sources/iOSExploreUIKit/` — UIKit 扩展模块（依赖 core，源码整体 `#if canImport(UIKit)`；macOS 编译为空壳，iOS 提供 `ui.*` 实现）。**typed factory 规则**：入参先用 Foundation-only typed query（如 `UITapQuery`）解析校验，通过后才进 `@MainActor` 的 resolver/executor，UIKit 类型绝不穿过 public 边界回非隔离域。子结构：
  - `UIKitCommandRegistrar.swift` — 显式注册入口 `server.registerUIKitCommands()`；注册前后打 `uikit.registrar` 日志（started/completed count）。**core 初始化不自动注册 UIKit 命令**，宿主必须显式调用。
  - `Context/UIKitContextProvider.swift` — `@MainActor` 上下文（前台 window/顶部控制器/根 view）；记录 MainActor hop 日志。
  - `Locator/UIKitLocator.swift` + `UIKitLocatorResolver.swift` — 定位模型（query→identifier/path/snapshotID 的 Foundation-only 值）与仅 iOS 的真实 `UIView` 解析。
  - `Action/UIKitActionExecutor.swift` + `UIKitActionCapabilityResolver.swift` — `@MainActor` 动作执行（tap/control 路由）；解析失败/定位失败/能力不支持各记 error 日志。
  - `Snapshot/UIKitSnapshotStore.swift` + `UIKitFingerprintCollector.swift` — 快照与陈旧检测（容量 512、TTL、LRU）；path+snapshotID 页面变动返回 `invalid_data` + 固定陈旧消息。
  - `UIKitCommandLogging.swift` — 日志入口，复用 core `ExploreLogging.emitExtension`，category 统一 `command`。
  - `UIKitCommandError.swift` — UIKit 错误工厂。
  - `ViewHierarchy/`、`ViewTargets/`、`Tap/`、`ControlAction/` — 四个 `ui.*` 命令及其 typed query 模型。
- `iOSExploreServer/iOSExploreServer.xcodeproj/` — framework 工程，两个 target：`iOSExploreServer.framework`（`PBXFileSystemSynchronizedRootGroup` 指向 `../Sources/iOSExploreServer/`）与 `iOSExploreUIKit.framework`（指向 `../Sources/iOSExploreUIKit/`，链接并依赖 core framework）；测试 target 同时链接两个 framework。Debug/Release 均 `SWIFT_VERSION=5.0`、`BUILD_LIBRARY_FOR_DISTRIBUTION=NO`（Swift 6.2 工具链要求，详见 runbooks）。
- `Examples/SPMExample/` — UIKit 测试 App，本地 SPM 依赖同时选 core 与 `iOSExploreUIKit` product；`ViewController` 显式 `server.registerUIKitCommands()` 开放 UIKit 命令；启动/停止按钮 + 请求日志面板 + `greet`/`device` 自定义命令演示。
- `scripts/proxy.sh` — iproxy 一键转发（`iproxy 38321 38321`）。

## Read when relevant（文档路由表）

- 改 `Sources/iOSExploreServer/**` 库源码、加新命令、改 HTTP 协议
  → `docs/architecture/index.md` + `docs/tools/network-tools.md`
- 改 framework 工程、源码共享方式、构建配置
  → `docs/architecture/index.md`（模块边界节）+ `docs/runbooks/build-and-test.md`
- 构建 / 测试 / 真机端到端验证流程
  → `docs/runbooks/build-and-test.md`
- iproxy / 端口 / 连接 / 权限 / 真机排障
  → `docs/runbooks/debugging.md`
- 完整设计背景与决策依据
  → `docs/superpowers/specs/2026-06-21-ios-explore-server-design.md`
- 阅读 / 改 `Sources/iOSExploreUIKit` 子包（从哪看 / 整体设计 / 逐文件档案）
  → `docs/uikit/README.md`（[阅读指南](docs/uikit/reading-guide.md) / [文件档案](docs/uikit/uikit-file-reference.md)）

## 关键约束速记

- 改完代码先 `swift test` 再说完成；集成测试串行（`@Suite(.serialized)`，端口 38399 不能并行）；iOS 模拟器 framework 测试用 `startWithPortRetry` 规避 cancel 异步释放端口的竞态。
- 内置命令在 `ExploreServer.init` 同步注册一次；不要在每次 `start()` 重注册。**UIKit 命令不在此列**——core 不自动注册任何 `ui.*`，宿主必须显式 `server.registerUIKitCommands()`。
- 通信失败用 HTTP 状态码（400/500），业务失败用 envelope `ok:false`，二者要区分。
- 所有新增错误出口必须先建 `ExploreServerError`（core）/ `UIKitCommandError`（UIKit）工厂，再由该对象生成 HTTP response /业务 failure /日志，不要在调用点散写 status、reason、code、message。
- `Router` 是锁保护的 `final class`（非 actor）：`register` 同步、`route` 锁内取命令+锁外校验/`await handle`（锁内禁 await）；`ExploreServer` 是真 `Sendable`，`@unchecked` 只在 `Mutex` 一处。
- **typed factory**：UIKit 命令入参先经 Foundation-only typed query 解析校验，UIKit 类型不穿 public 边界；定位统一 `identifier` 精确（不截断）→ `path` 只读 → 可选 `snapshotID` 陈旧防护。

## 日志要求（必须执行）

- 所有底层生命周期必须有日志：server 初始化/启动/停止、listener created/ready/waiting/failed/cancelled、connection accepted/rejected、session ready/closed/removed。
- 所有命令路径必须有日志：action 注册、请求收到、参数校验失败、命令开始/完成/超时/抛错、响应发送。日志至少包含能关联问题的 `sessionID`、`action`、payload 大小、HTTP 状态或 error code。
- 所有资源限制必须有日志：连接数上限、header/body/request 超限、read timeout、command timeout、send/receive error。
- 涉及 UIKit/Accessibility/截图/手势/日志流等 App 侧能力时，handler 内必须记录进入/退出、MainActor 切换、高成本耗时、失败原因；不要在 network queue 上静默执行重任务。
- UIKit 扩展模块（`iOSExploreUIKit`）日志走 `UIKitCommandLogging`（复用 core `ExploreLogging.emitExtension`，category `command`），必须覆盖：registrar 进入/完成（`uikit.registrar`，含注册数量）、每次命令 start/complete/failed（含 action、payloadKeys、dispatchMode、error code）、Context Provider 的 MainActor hop、query 解析与 resolver 定位结果、executor 各失败分支（解析失败/定位失败/能力不支持）、snapshot store 的 insert/evict/expired/mismatch/stale。
- 新增设计文档或改架构文档时，要写清楚新增文件、关键属性、关键方法各自负责哪些日志点；如果刻意不加日志，必须在文档和最终回复里说明原因。
- 日志不能泄露 auth token、完整截图、大块 payload 或用户输入全文；记录大小、摘要、错误码和必要上下文即可。

## 注释要求（必须执行）

- 所有 public 类型、属性、方法必须有 `///` 文档注释：说明用途，方法写清 `- Parameters:`/`- Returns:`/`- Throws:`，错误工厂写清触发场景与对应 HTTP status/code。风格对齐 `Command.swift`。
- 关键内部类型与生命周期方法（`HTTPListener`/`ClientSession`/`HTTPParser`/`Router`）也要有 `///` 注释，写清职责、状态转移、与日志点的对应关系——用户不熟悉底层代码，不能只靠读实现推断运行状态。
- 注释用简体中文，写"为什么"和"在生命周期中的角色"，不复述类型签名；trivial 存储属性可不单独注释，但语义不直观的（超时纳秒、关闭原因字符串、错误 category）必须说明。
- 新增 `.swift` 文件必须随首个实现一起补齐类型/关键属性/关键方法注释，不留 TODO。
