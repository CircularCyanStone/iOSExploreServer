# iOSExploreServer — Agent Guide

手机端 HTTP Server 的 SPM 库（基于 `NWListener`）。Mac 经 `iproxy`（USB）+ `curl` 向 iPhone App 发送 JSON 命令，App 按 `action` 分发执行并返回统一 envelope。为后续 Mac 侧 MCP 对接铺路。

## Always follow（硬规则）

- **本项目是 Debug-only 开发工具**（定位类似 Lookin / Reveal / FLEX）：只在 Debug 环境集成，供 agent / 开发者探索和测试 App，**不打包进 Release 上架产物**。因此 UIKit 私有 API / runtime 技巧（KVC 反射、method swizzle 等）是实现探索能力的正当手段，**不是禁区**；但所有依赖私有 API 的代码必须用 `#if DEBUG`（或等价条件编译）隔离，确保绝不进入 Release 二进制。私有结构随 iOS 版本漂移属于工具的正常维护成本，按版本适配，不作为拒绝实现的理由。涉及私有 API 的复杂操作应下沉到 UIKit 控件 extension 或专用工具类（如 Swizzler），命令层只调用，不散写。
- 库 `iOSExploreServer` **只依赖 `Foundation` + `Network`，不依赖 UIKit**；需要 UIKit 的信息（如设备机型）由集成方 App 注册额外 handler 注入，不进库。
- Swift 6.2 严格并发：跨边界模型 `Sendable`，共享状态用 `Mutex`（全库唯一 `@unchecked` 边界，锁内禁 `await`），闭包 `@Sendable`。
- 唯一命令端点 `POST /`，body `{"action":"...","data":{...}}`，响应统一 envelope `{"code":"ok","data"?}` 或 `{"code":"...","message":"..."}`。**新增能力 = 注册新 action，不改协议**。
- 默认端口 **38321**（构造可配）。MVP 不强制鉴权（USB 物理连接隔离），`ExploreServer(authToken:)` 是预留钩子，当前不校验。
- SPM 包（根 `Sources/`）与 framework 工程（`iOSExploreServer/iOSExploreServer.xcodeproj`）**共享同一份 `Sources/iOSExploreServer/`**，不要维护两份源码。
- 库源码必须同时兼容 SPM（Swift 6.2）与 framework 工程（`SWIFT_VERSION=5.0`）：避免 Swift-6-only 语法。
- 底层网络 / 协议 / 连接 / 命令代码必须配套详细日志：新增或修改命令、关键属性、生命周期方法、状态转移方法、错误分支、资源限制、设计方案和文档时，要同步说明并实现对应日志点。用户不熟悉底层代码，不能只靠读实现推断运行状态。
- AI 配置与 docs 知识库（`AGENTS.md`/`CLAUDE.md`/`docs/`/`.claude/`）随项目正常纳入 git（个人项目，无保密约束）。

## 沟通约定：抽象短词必须解释

Agent 不能只用自己在完整上下文里才能理解的抽象短词、阶段词或内部术语来回复开发者。开发者通常只看到当前回复，不会自动拥有 agent 刚读过的全部文档、源码、测试输出和中间推理；因此“工程化”“落地”“打通”“闭环”“收敛”“主线”“兜底”“边界”“能力补齐”“行为对齐”“协议演进”“验证完成”这类词，如果不解释，会让人不知道到底要改什么、为什么改、下一步做什么。

使用这类词时，必须在同一段或紧随其后的段落里补上具体解释。解释至少要回答以下问题：这个词在当前任务里具体指哪些文件、模块或命令；会改变什么运行行为或对外契约；为什么现在要做这些事；推荐下一步先做哪一项；完成后用哪些测试、构建或真实操作验证。不能只说“下一步工程化”“继续落地”“把链路打通”这种短句，因为这些短句只表达 agent 自己的压缩记忆，不能把可执行信息传给开发者。

正确写法示例：不要只说“下一步进入工程化”。要写成“下一步建议先新增 `Swizzler.swift`、`UIAlertAction+Trigger.swift` 和 `UIAlertController+TriggerAction.swift`，把 spike 里验证过的 runtime hook、关联对象保存、KVC handler 兜底、真实展示 alert 的系统触发入口、block 调用签名放进 `iOSExploreUIKit` 的 Debug-only runtime 层。这样 executor 后续只需要选择按钮并调用这些扩展方法，不会散写私有 ivar 或 selector 细节。完成后先跑对应 iOS framework 测试，再用 SPMExample 的五个 alert 案例验证 dryRun=false 是否返回 `performed/dismissed/button`。”

正确写法示例：不要只说“把闭环打通”。要写成“这里的闭环指从示例 App 弹出 alert，到 Mac 侧 curl 发送 `ui.alert.respond`，再到 App 内对应 `UIAlertAction` handler 被调用、alert 关闭、响应 envelope 返回 `performed/dismissed/button` 的全过程。要验证这个闭环，需要启动 `Examples/SPMExample`，进入弹窗测试页，触发目标 alert，然后发送 dryRun=false 请求并观察事件流和响应 JSON。”

如果一个词已经写成项目固定术语，也仍然要在第一次出现时给当前上下文解释。例如“typed factory”不能只当口号使用；需要说明它在当前改动里表示“先用 Foundation-only 输入模型解析和校验请求数据，只有解析成功后才进入 MainActor 上的 UIKit resolver/executor，因此 UIKit 类型不会穿过 public 命令边界”。这样后续读者不用回翻全部架构文档，也能理解这条约束会怎样影响当前实现。

## 任务完成汇报：必须讲清目标、改动和效果

每次完成任务后的最终回复，不能只写“已完成”“文档已更新”“测试通过”或一串文件名。开发者需要知道这次改动实际解决了什么问题、运行时会多出什么能力、哪些行为没有改变，所以收尾说明必须用通俗内容补齐下面几项。

- **本次任务目标**：先说明用户原本想解决的实际问题。例如“让 Agent 能在 App 进程里读取 `print` / stderr 输出”，而不是只说“第二阶段完成”。
- **修改了什么**：按模块、文件或命令解释改动内容，说明这些文件分别承担什么职责。不要只列路径；路径后面要补一句“它现在负责什么”。
- **产生什么效果**：说清对外行为、HTTP 命令响应、配置开关、日志来源或测试流程的变化。阶段性功能必须解释“第一阶段/第二阶段”到底让用户多了什么能力。
- **怎么使用或验证**：给出关键配置、curl、启动参数或测试命令。没有做真实 App 验证时也要明说，不能把单元测试说成真实闭环。
- **仍未实现和限制**：明确没做的能力、默认关闭项、平台限制和风险点，避免用户误解为“全自动”“全量捕获”或“Release 可用”。

正确写法示例：不要只说“进程日志捕获完成”。要写成“这次目标是让 Diagnostics 在 Debug 下可选捕获当前 App 进程里的 stdout、stderr、NSLog、`os_log` 和 Swift `Logger`。打开 `DiagnosticsConfiguration.captureStdout` 后，App 里的 `print(...)` 或 `FileHandle.standardOutput.write(...)` 会按行进入 `AppLogStore`，Agent 可以通过 `app.logs.read` 加 `sources:["stdout"]` 读到；打开 `captureStderr` 后，stderr 输出会以 `source:"stderr"`、`level:"error"` 进入同一个 store；打开 `captureNSLog` 后，`NSLog` 输出会被识别为 `source:"nslog"`；打开 `captureOSLog` 后，`os_log` 和 Swift `Logger` 会通过当前进程 `OSLogStore` 进入 `source:"oslog"`，如果系统不允许读取会返回 `capture.oslog.state:"unavailable"`。SPMExample 当前仍默认关闭这些进程级捕获，必须显式传启动参数或环境变量开启。”

## Common commands

- 构建 SPM 库：`swift build`
- 测试（含真实 TCP 端到端）：`swift test`（macOS SPM 当前 225 个；iOS framework `xcodebuild ... test` 当前 344 个；集成测试用端口 38399）
- 覆盖率：`swift test --enable-code-coverage`（当前行覆盖 86.62%）
- 构建 framework 工程（core + UIKit + Diagnostics 三个 framework）：`xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator build`
- framework 测试（含 iOS 正向注册断言）：`xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' test`
- 构建/运行测试 App：Xcode 打开 `Examples/SPMExample/SPMExample.xcodeproj`，选真机或模拟器 → Run；或用 XcodeBuildMCP 跑（`sim-app`/`sim-fw`/`device-app` profile、iproxy、curl 闭环见下方「XcodeBuildMCP 运行配置」节）
- 起 USB 转发：`./scripts/proxy.sh`（前台运行，Ctrl-C 停）
- 发命令：`curl -X POST http://localhost:38321/ -d '{"action":"ping"}'`

## 示例 App 真实验证：必须自动启动 Server

对 `Examples/SPMExample/SPMExample/ViewController.swift` 做真实闭环验证时，不要再依赖手动点“启动 Server”按钮，也不要每次重新探索“服务没启动所以无法远程点击启动服务”的解决方案。这个问题的固定处理方式是：测试工具通过启动参数或环境变量让示例 App 在 Debug 启动后自动执行 `ViewController.server.start()`，使 `POST /` 的 38321 端口先进入可用状态，然后再用 `curl` 或 `ui.*` 命令继续触发页面、弹窗和其它交互。

推荐固定使用语义清楚的开关，例如启动参数 `--ios-explore-autostart` 或环境变量 `IOS_EXPLORE_AUTOSTART=1` 表示“启动 App 后自动调用 `server.start()`”。如果验证流程还需要直接进入弹窗测试页，可以再使用 `--ios-explore-open-alert-test` 或 `IOS_EXPLORE_OPEN_ALERT_TEST=1` 表示“server 启动后自动 push 到 `AlertTestViewController`”。如果当前示例 App 代码尚未实现这些开关，下一步应先补 Debug-only 的启动参数/环境变量读取逻辑，而不是切回手动 UI 点击方案。

这些启动参数和环境变量属于测试工具约定，不是一次性临时状态。验证完成后不用刻意删除或清理它们；后续 agent 应复用同一套开关，保持真实闭环测试流程稳定可重复。只有在开关名称或行为本身需要升级时，才同步修改这里和对应示例 App 代码。

## XcodeBuildMCP 运行配置（真机 + 模拟器）

用 XcodeBuildMCP 跑 `Examples/SPMExample` 时，项目默认值持久化在 `.xcodebuildmcp/config.yaml`（项目级，重启会话自动加载）。下面是经实测打通的完整闭环流程，不是占位规划。

### workflow 与 profile

`.xcodebuildmcp/config.yaml` 顶层 `enabledWorkflows` 启用 `simulator` + `device` + `debugging` + `ui-automation`（默认只有 simulator，其余三个必须显式开）。改完 `enabledWorkflows` 后必须重连 MCP server（Claude Code 里 `/mcp` → reconnect XcodeBuildMCP）新注册的工具才会出现——同一 session 内改 config 不会热生效。

profile 用 `session_use_defaults_profile("<name>")` 切换：

| profile | 工程 / scheme | target | 用途 |
|---|---|---|---|
| `sim-app` | SPMExample / SPMExample | iPhone 17 模拟器 | App 模拟器闭环验证 |
| `sim-fw` | iOSExploreServer / iOSExploreServer | iPhone 17 模拟器 | framework 测试 |
| `device-app` | SPMExample / SPMExample | iOS 真机 | App 真机闭环验证 |

framework 真机测试按需加 `device-fw`，照搬 `device-app` 换 `projectPath`/`scheme` 即可。

### 模拟器跑法（已实测 curl 通）

```
session_use_defaults_profile("sim-app")
build_run_sim()                                       # 构建+装+首启（server 此刻还没起）
launch_app_sim(env={"IOS_EXPLORE_AUTOSTART":"1"})     # 重启让 server.start() 自动执行
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
# → {"code":"ok","data":{"pong":true}}
```

模拟器与 Mac 共享 localhost 网络栈，App 监听的 38321 直接 `curl localhost:38321` 可达，**不需要 iproxy**（iproxy 是真机 USB 转发专用的）。

### 真机跑法（已实测 curl 通）

```
session_use_defaults_profile("device-app")
build_run_device()                                    # 构建+签名(DEVELOPMENT_TEAM=UQ35W3765Z)+装+首启
launch_app_device(env={"IOS_EXPLORE_AUTOSTART":"1"})  # 重启带起 server
# 另开终端做 USB 转发（二选一）：
#   ./scripts/proxy.sh
#   iproxy 38321 38321 -u 00008030-001045C136D1402E
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
# → {"code":"ok","data":{"pong":true}}
```

真机不共享 Mac localhost，38321 **必须经 iproxy 转发**才能从 Mac curl 到。

### 四个必须记住的差异（实测踩过坑）

1. **设备 ID 有两套体系，不能混用**。XcodeBuildMCP 的 `deviceId`（`list_devices`/`build_run_device`/`launch_app_device`）用 **CoreDevice identifier**（形如 `3AC0C7D6-22F6-572B-8368-4047A14BAB52`，`devicectl` 那套）；`iproxy -u` 用 **USB UDID**（形如 `00008030-001045C136D1402E`，`xctrace list devices` 那套）。同一台设备两个 ID。换真机时：先 `list_devices` 拿 `state: connected` 那条的 CoreDevice identifier 填进 `device-app` profile 的 `deviceId`，UDID 用 `xctrace list devices` 或 `idevice_id -l` 查后填进 iproxy 命令。

2. **判 iOS 版本别信 devicectl 的机型字段**。`xcrun devicectl list devices` 的 `Model`（如 `iPhone12,1`）会缓存串号——本项目里它把一台 iOS 26.5 的真机错显成"iPhone 11"，曾导致误判版本不够。判版本用 `list_devices` 返回的 `osVersion`，或直接 `build_run_device` 实测能否装上。SPMExample 部署目标是 **iOS 26.2**，低于此的真机装不上。

3. **`build_run_sim`/`build_run_device` 不把 session default 的 `env` 注入 App 进程**。在 profile 里设 `env: {IOS_EXPLORE_AUTOSTART:"1"}` 对 build 阶段生效、对 launch 阶段不生效，App 启动后 `autostart=false`、server 不起。可靠驱动 autostart 的方式是 `launch_app_sim`/`launch_app_device` 的 `env` 参数或 `launchArgs: ["--ios-explore-autostart"]`；且已运行的 App 不会重启进程、新参数不生效，必须先 `stop_app_*` 再 `launch_app_*`。SPMExample 的开关读取逻辑在 `ViewController.swift` 约 L207-215（启动参数与环境变量二选一）。

4. **curl 真机前必须 `lsof -iTCP:38321` 确认监听进程是 `iproxy` 而非残留 `SPMExampl`**。`sim-app` profile 跑过没关的模拟器 SPMExample 会残留成 Mac 进程，继续监听 Mac localhost 38321；此时 `curl localhost:38321` 打到的是这个**模拟器残留 App**（旧 binary、不是真机、env 也没设），结果自然对不上真机预期——曾导致真机验证反复卡住。固定排查：curl 真机前先 `lsof -iTCP:38321 -sTCP:LISTEN`，COMMAND 列是 `iproxy` 才对；是 `SPMExampl` 则 `xcrun simctl terminate 065CC8DB-8978-46C5-82D6-C96625B608D8 com.coo.SPMExample`（或 `pkill -f "CoreSimulator/Devices/065CC8DB.*SPMExample"`）清理后再起 iproxy。`iproxy` 启动立即报 `Address already in use: 38321` 也是这个原因。

## 模块边界

- `Sources/iOSExploreServer/` — SPM 库 core（主交付物，**不依赖 UIKit**）。门面 `ExploreServer`（`Sendable`）；传输 `HTTPListener`（NWListener，`start` await 端口就绪、串行 network queue、session map）；单连接 `ClientSession`（session id、receive buffer、读/命令超时、统一 close）；解析 `HTTPParser`（三态 complete/incomplete/invalid）；统一错误 `ExploreServerError`（HTTP status/reason、envelope code/message、logMessage 单一来源）；分发 `Router`（`Mutex` 保护的 `final class`，同步 register、route 锁外校验+await）；同步原语 `Mutex`；typed 命令协议 `Command`（associated `Input: CommandInput`、action/description/handle）；命令输入系统 `CommandInput`/`CommandField`/`CommandInputSchema`/`CommandInputDecoder`（schema 与解析单一来源）；命令扩展缝 `ExploreCommandSupport`（`ExploreCommandFailure`、`ExploreLogging.emitExtension` 给扩展模块复用日志）；模型 `Models`/`JSONCoder`；HTTP 值类型 `HTTPRequest`/`HTTPResponse`；日志 `ExploreLogging`；内置命令 `Handlers/BuiltinHandlers`（ping/echo/info/help，均为 `Command` struct）。
- `Sources/iOSExploreUIKit/` — UIKit 扩展模块（依赖 core，源码整体 `#if canImport(UIKit)`；macOS 编译为空壳，iOS 提供 `ui.*` 实现）。**typed factory 规则**：入参先用 Foundation-only typed query（如 `UITapQuery`）解析校验，通过后才进 `@MainActor` 的 resolver/executor，UIKit 类型绝不穿过 public 边界回非隔离域。**执行核心 throw 化**：executor/collector 成功返回 `JSON`、失败 `throw UIKitCommandError`（conform `Error`），由命令 handler 顶层 `catch` 转 `ExploreResult` envelope（业务码不丢），失败日志在顶层一处记。子结构分两层 `Commands/`（命令）+ `Support/`（辅助）：
  - `UIKitCommandRegistrar.swift` — 显式注册入口 `server.registerUIKitCommands()`；注册前后打 `uikit.registrar` 日志（started/completed count）。**core 初始化不自动注册 UIKit 命令**，宿主必须显式调用。
  - `Support/Context/UIKitContextProvider.swift` — `@MainActor` 上下文（前台 window/顶部控制器/根 view）；`currentContext(action:) throws` 失败抛 `hierarchyUnavailable`。
  - `Support/Locator/UIKitLocator.swift` + `UIKitLocatorResolver.swift` + `UIKitViewLookupModels.swift` — 定位模型（query→identifier/path/snapshotID 的 Foundation-only 值）与仅 iOS 的真实 `UIView` 解析（`locate(...) throws`，notFound/ambiguous 由调用方工厂构造错误）。
  - `Support/Action/UIKitActionExecutor.swift` + `UIKitActionCapabilityResolver.swift` — `@MainActor` 动作执行（tap/control 路由）；`execute throws -> JSON`，失败 throw `UIKitCommandError`，handler 顶层 catch 转 envelope。
  - `Support/Snapshot/UIKitSnapshotStore.swift` + `UIKitFingerprintCollector.swift` — 快照与陈旧检测（容量 8 条快照 × 每条 512 指纹、TTL、LRU）；`isStale` 为 true 时 executor 抛 `stale_locator` + 固定陈旧消息。
  - `Support/Parsing/` — UIKit 命令复用的 Foundation-only 字段声明与定位解析入口：`UIKitCommandFields`（筛选字段/定位字段）、`UIKitLocatorInput`（identifier/path 二选一与 path 文法桥接）；单字段取值统一走 core `CommandInputDecoder`，解析错误统一为 `CommandInputParseError`，由 `AnyCommand` 转 `invalid_data`。
  - `UIKitCommandLogging.swift` — 日志入口，复用 core `ExploreLogging.emitExtension`，category 统一 `command`。
  - `UIKitCommandError.swift` — UIKit 错误工厂（conform `Error`）。
  - `Commands/TopViewHierarchy/`、`Commands/ViewTargets/`、`Commands/Tap/`、`Commands/ControlAction/`、`Commands/Screenshot/`、`Commands/Input/`、`Commands/Scroll/`、`Commands/Keyboard/`、`Commands/Navigation/`、`Commands/Wait/`、`Commands/ScrollToElement/`、`Commands/Alert/` — 14 个 `ui.*` 命令（adapter + typed query 模型；查询命令含 collector）。`Commands/Navigation/` 现含 `ui.navigation.back` 与 `ui.navigation.tapBarButton`；后者由 `Support/Navigation/UINavigationBarInspector.swift`（读 navigationItem 摘要）+ `Support/Action/UINavigationBarButtonExecutor.swift`（按签名派发 target-action）支撑，`ui.inspect` / `ui.topViewHierarchy` 响应均追加 `navigationBar` 区块。
  - `ui.inspect`（`Commands/ViewTargets/`）重设计为**全节点输出 + full/minimal 两档**：每个被采集的节点带 `isFull` 标记——full 节点含完整 `availableActions`/文本/状态并**进入 `viewSnapshotID` 签发集合**（可被 `ui.tap`/`ui.control.sendAction` 直接操作）；minimal 节点只给 `path`+`type`+必要定位字段、强制 `availableActions=[]`、**不签发指纹**（仅用于让 agent 看见 cell 内 `UILabel` 等子节点位置）。对 minimal 节点调 `ui.tap`/`ui.control.sendAction` 返回业务码 `not_actionable`（独立业务码，与参数解析错误的 `invalid_data` 区分；固定提示该节点不可操作）。cell 内 `UILabel`/子 view 通过 `cellAncestor` 自动进 full（capability resolver 在 `isInteractable` 通过后追加 `explore_cellAncestor != nil` 分支累加 `.tap`），agent 可直接按 cell 标题文本定位并 tap 子 label path，无需 `ui.topViewHierarchy` 二次解析；cell 容器本身仍走 `hasGestureRecognizers`/`didSelectRow` adapter 路径，不因 minimal 改变可点性。
- `Sources/iOSExploreDiagnostics/` — 进程日志扩展模块（依赖 core，不依赖 UIKit）。宿主显式调用 `server.registerDiagnosticsCommands()` 后注册 `app.logs.mark` / `app.logs.read`，安装 `ExploreLogging` observer，把 iOSExplore 内部日志写入有界 `AppLogStore`；宿主可用 `ExploreAppLog.emit` 主动写入 bridge 业务日志。stdout/stderr/NSLog/os_log capture 已接入但默认关闭，由 `DiagnosticsConfiguration.captureStdout` / `captureStderr` / `captureNSLog` / `captureOSLog` 控制；打开后 stdout 为 `source=stdout level=info`，stderr 为 `source=stderr level=error`，NSLog 为 `source=nslog`，`os_log` 与 Swift `Logger` 通过当前进程 `OSLogStore` 进入 `source=oslog`。停止或 `resetForTesting()` 时会 flush stdout/stderr/NSLog 相关无换行尾部并恢复 fd；`OSLogStore` 不可用时 `capture.oslog` 返回 `unavailable`，避免误解为“没有发生日志”。
- `iOSExploreServer/iOSExploreServer.xcodeproj/` — framework 工程，三个 target：`iOSExploreServer.framework`（`PBXFileSystemSynchronizedRootGroup` 指向 `../Sources/iOSExploreServer/`）、`iOSExploreUIKit.framework`（指向 `../Sources/iOSExploreUIKit/`，链接并依赖 core framework）与 `iOSExploreDiagnostics.framework`（指向 `../Sources/iOSExploreDiagnostics/`，链接并依赖 core framework）；测试 target 同时链接三个 framework。Debug/Release 均 `SWIFT_VERSION=5.0`、`BUILD_LIBRARY_FOR_DISTRIBUTION=NO`（Swift 6.2 工具链要求，详见 runbooks）。
- `Examples/SPMExample/` — UIKit 测试 App，本地 SPM 依赖同时选 core、`iOSExploreUIKit` 与 `iOSExploreDiagnostics` product；`ViewController` 显式 `server.registerUIKitCommands()` 开放 UIKit 命令，显式 `server.registerDiagnosticsCommands()` 开放 `app.logs.mark/read`；启动/停止按钮 + 请求日志面板 + `greet`/`device` 自定义命令演示，`debug.emitAppLog` 用于真实 curl 验证 bridge 日志，`debug.emitStdout` / `debug.emitStderr` / `debug.emitNSLog` / `debug.emitOSLog` / `debug.emitLogger` 用于验证进程日志读取。示例 App 在 Debug 构建下通过 `ViewController.exampleDiagnosticsConfiguration()` 直接打开 stdout/stderr/NSLog/os_log 四个 capture（Release 构建关闭），不再通过环境变量或启动参数控制。
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

## 开发阶段规则：只留最合理的设计，不留妥协

本项目仍处于开发阶段（未 Release），所有接口/字段/优先级/模块边界都还没有外部兼容性承诺。

- **任何设计不合理的地方都应推到最合理方案，不保留"能用就先这样"的妥协代码。**
- 改名、改类型、改优先级、推翻现有设计——只要经过评估确认当前方案不合理，就直接改，不考虑"改了有没有风险"（合理即改）。
- 不改的情况只有一种：改动会导致 App 崩溃或破坏已通过的核心测试（Git 可回溯，回归可修）。
- 评估时先说清楚"现状是什么、问题在哪"，然后直接给最合理的方案，不需要在妥协方案上消耗讨论时间。

该规则同样适用于 `MCPServer/`（TypeScript MCP 适配层）——它也是项目的一部分，一样是开发期。

- 改完代码先 `swift test` 再说完成；集成测试串行（`@Suite(.serialized)`，端口 38399 不能并行）；iOS 模拟器 framework 测试用 `startWithPortRetry` 规避 cancel 异步释放端口的竞态。
- 内置命令在 `ExploreServer.init` 同步注册一次；不要在每次 `start()` 重注册。**UIKit 命令不在此列**——core 不自动注册任何 `ui.*`，宿主必须显式 `server.registerUIKitCommands()`。
- 通信失败用 HTTP 状态码（400/500），业务失败用 HTTP 200 + body 顶层失败 `code/message`，二者要区分。
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
