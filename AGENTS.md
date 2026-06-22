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
- 测试（含真实 TCP 端到端）：`swift test`（当前 46 个；集成测试用端口 38399）
- 覆盖率：`swift test --enable-code-coverage`（当前 91.19%）
- 构建 framework 工程：`xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator build`
- 构建/运行测试 App：Xcode 打开 `Examples/SPMExample/SPMExample.xcodeproj`，选真机或模拟器 → Run
- 起 USB 转发：`./scripts/proxy.sh`（前台运行，Ctrl-C 停）
- 发命令：`curl -X POST http://localhost:38321/ -d '{"action":"ping"}'`

## 模块边界

- `Sources/iOSExploreServer/` — SPM 库（主交付物）。门面 `ExploreServer`（`Sendable`）；传输 `HTTPListener`（NWListener，`start` await 端口就绪、串行 network queue、session map）；单连接 `ClientSession`（session id、receive buffer、读/命令超时、统一 close）；解析 `HTTPParser`（三态 complete/incomplete/invalid）；统一错误 `ExploreServerError`（HTTP status/reason、envelope code/message、logMessage 单一来源）；分发 `Router`（`Mutex` 保护的 `final class`，同步 register、route 锁外校验+await）；同步原语 `Mutex`；命令协议 `Command`（action/description/parameters）；模型 `Models`/`JSONCoder`；HTTP 值类型 `HTTPRequest`/`HTTPResponse`；日志 `ExploreLogging`；内置命令 `Handlers/BuiltinHandlers`（ping/echo/info/help，均为 `Command` struct）。
- `iOSExploreServer/iOSExploreServer.xcodeproj/` — framework 工程，`PBXFileSystemSynchronizedRootGroup` 指向根 `Sources/iOSExploreServer/`，手动编 `.framework`。`BUILD_LIBRARY_FOR_DISTRIBUTION=NO`（Swift 6.2 工具链要求，详见 runbooks）。
- `Examples/SPMExample/` — UIKit 测试 App，本地 SPM 依赖集成库；启动/停止按钮 + 请求日志面板 + `greet`/`device` 自定义命令演示。
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

## 关键约束速记

- 改完代码先 `swift test` 再说完成；集成测试串行（`@Suite(.serialized)`，端口 38399 不能并行）。
- 内置命令在 `ExploreServer.init` 同步注册一次；不要在每次 `start()` 重注册。
- 通信失败用 HTTP 状态码（400/500），业务失败用 envelope `ok:false`，二者要区分。
- 所有新增错误出口必须先建 `ExploreServerError` 工厂，再由该对象生成 HTTP response /业务 failure /日志，不要在调用点散写 status、reason、code、message。
- `Router` 是锁保护的 `final class`（非 actor）：`register` 同步、`route` 锁内取命令+锁外校验/`await handle`（锁内禁 await）；`ExploreServer` 是真 `Sendable`，`@unchecked` 只在 `Mutex` 一处。

## 日志要求（必须执行）

- 所有底层生命周期必须有日志：server 初始化/启动/停止、listener created/ready/waiting/failed/cancelled、connection accepted/rejected、session ready/closed/removed。
- 所有命令路径必须有日志：action 注册、请求收到、参数校验失败、命令开始/完成/超时/抛错、响应发送。日志至少包含能关联问题的 `sessionID`、`action`、payload 大小、HTTP 状态或 error code。
- 所有资源限制必须有日志：连接数上限、header/body/request 超限、read timeout、command timeout、send/receive error。
- 涉及 UIKit/Accessibility/截图/手势/日志流等 App 侧能力时，handler 内必须记录进入/退出、MainActor 切换、高成本耗时、失败原因；不要在 network queue 上静默执行重任务。
- 新增设计文档或改架构文档时，要写清楚新增文件、关键属性、关键方法各自负责哪些日志点；如果刻意不加日志，必须在文档和最终回复里说明原因。
- 日志不能泄露 auth token、完整截图、大块 payload 或用户输入全文；记录大小、摘要、错误码和必要上下文即可。

## 注释要求（必须执行）

- 所有 public 类型、属性、方法必须有 `///` 文档注释：说明用途，方法写清 `- Parameters:`/`- Returns:`/`- Throws:`，错误工厂写清触发场景与对应 HTTP status/code。风格对齐 `Command.swift`。
- 关键内部类型与生命周期方法（`HTTPListener`/`ClientSession`/`HTTPParser`/`Router`）也要有 `///` 注释，写清职责、状态转移、与日志点的对应关系——用户不熟悉底层代码，不能只靠读实现推断运行状态。
- 注释用简体中文，写"为什么"和"在生命周期中的角色"，不复述类型签名；trivial 存储属性可不单独注释，但语义不直观的（超时纳秒、关闭原因字符串、错误 category）必须说明。
- 新增 `.swift` 文件必须随首个实现一起补齐类型/关键属性/关键方法注释，不留 TODO。
