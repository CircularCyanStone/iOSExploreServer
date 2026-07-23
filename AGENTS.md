# iOSExploreServer — Agent Guide

iOS App HTTP Server 的 SPM 库（基于 `NWListener`）。Mac 经 `iproxy`（USB）+ `curl` 向 iPhone App 发送 JSON 命令，App 按 `action` 分发执行并返回统一 envelope。

## 核心原则

1. **Debug-only 开发工具**：只 Debug 集成，私有 API 代码用 `#if DEBUG` 隔离。
2. **core 不依赖 UIKit**：需要 UIKit 信息由宿主注册 handler 注入。
3. **新增能力 = 注册新 action，不改协议**：唯一端点 `POST /`，响应统一 `{"code":"ok","data"?}` 或 `{"code":"...","message":"..."}`。
4. **typed factory**：UIKit 命令入参先用 Foundation-only typed query 解析校验，UIKit 类型不穿 public 边界。
5. **Swift 6.2 严格并发**：跨边界模型 `Sendable`，共享状态用 `Mutex`，闭包 `@Sendable`。
6. **通信失败用 HTTP 状态码（400/500），业务失败用 HTTP 200 + body 失败 code/message**。
7. **内置命令在 `ExploreServer.init` 同步注册一次**；UIKit 命令由宿主显式 `server.registerUIKitCommands()` 注册。
8. **开发期只留最合理设计**：任何设计不合理的地方都应推到最合理方案，不保留"能用先这样"的妥协代码。
9. **验证按影响范围选择**：不要机械全量跑 `swift test`。只读、解释、查文件不跑测试；只改文档、README、注释时默认不跑测试，必要时只做链接、路径或格式检查；只移动文件或调整目录结构时优先做轻量验证（如 `swift build`、`swift package describe` 或相关工程引用检查），只有影响编译引用、target 配置或 public API 时才升级测试；改源码逻辑、HTTP 协议、命令行为、并发、网络、日志捕获、错误码或 public API 时，先跑与改动直接相关的定向测试，风险高或改动跨模块时再跑全量 `swift test`。如果用户明确要求不跑测试，不得擅自运行，只报告未验证风险。
10. **通用 skills 必须与本地项目解耦**：`.codex/skills` / `.claude/skills` 是可迁移能力说明，开发期间不得在 skill 本体里写入本仓库项目名、示例 App、测试工程路径、bundle id、设备 ID、测试账号、本机绝对路径或任何本地开发/测试项目内容；需要真实案例时放到 `docs/skills/examples/` 或仓库文档中，并在 skill 本体只保留占位符和通用规则。

## 通用 Skill 内容治理（必须执行）

以下规则适用于所有新建和后续修改的通用 skill，不限于当前已整改的 `ios-ui-form`、`ios-ui-wait`、`ios-logs` 和 `ios-automation`。本仓库以 `.codex/skills/` 为唯一可编辑源；`.claude/skills/` 和 `.trae/skills/` 中的对应目录是指向它的快捷方式，不得重复维护或改成分叉副本。规则立即生效，但不能据此宣称未逐项审计的存量 skill 已经合规。

### 修改前先确认问题真实存在

- 先阅读当前 `SKILL.md`、关联 `references/`、`agents/openai.yaml` 和实际快捷方式目标，再决定是否修改；不得只根据旧测试报告、旧文档、搜索摘要或其他 agent 的结论直接修复。
- 涉及 action 名、参数、默认值、返回结构、错误码、平台差异或限制时，必须以当前实现、工具 schema 和测试为准；三者不一致时先查明真实契约，不把猜测写进 skill。
- 发现疑似问题但当前源码并不存在时，记录核验结果并停止该项修改，避免为了“完整整改”制造新规则或兼容分支。

### 正文准入与分层

内容进入 `SKILL.md` 正文前必须同时满足：多数目标任务需要；能写成明确的“条件 -> 动作/结论”并减少临场判断；跨 App 和版本相对稳定；由该 skill 唯一负责；不能从工具 schema、运行时 inspect 结果或通用知识直接可靠推导。

- **正文保留**：稳定工作流、关键且不直观的参数语义、常见误判、失败分诊、终止条件，以及为了执行安全必须就地看到的约束。
- **下沉 `references/`**：仅在特定条件下需要的可复用模板、参数变体、完整示例和较长说明；正文必须写明何时读取。引用保持一层，不建立 reference 再引用 reference 的深链。
- **移出通用 skill**：具体业务案例、真实账号或设备信息、本仓库测试路径、带日期的验收结果、修复历史、旧 skill 纠错叙述和待办矩阵；这些内容放 `docs/skills/examples/`、测试报告或其他项目文档。
- **禁止为覆盖场景持续堆案例**：正文长度不是唯一指标，优先检查决策密度。出现多个完整业务流程、重复参数表或大量“曾经如何”时，应先拆分或删除，而不是继续追加。
- Skill 的触发条件统一写在 frontmatter `description`；正文不重复“何时使用”清单。修改职责或触发范围时同步检查 `agents/openai.yaml`。

### 边界与单一事实源

- 每条跨 skill 规则只能有一个所有者。入口/路由 skill 只说明何时转交以及交接契约，参数细节、模板和失败分诊留给具体 skill；不得在正文、references 和其他 skill 中复制同一规则。
- 交叉引用必须指向仍存在的文件或章节，并说明读取条件；被引用内容移动或删除时，同一次修改中清理所有引用。
- 示例必须符合真实返回层级，并区分“过程信号”和“终态信号”。会导致立即误判成功、掩盖失败分支或依赖特定业务文案的示例不得进入通用 skill。

### 完成前验证

- 每个改动过的 skill 都要运行 `quick_validate.py`，检查 frontmatter、命名和目录结构；同时检查链接、快捷方式、重复内容和本地工程耦合。
- 文档声称的工具契约必须通过对应实现/schema 测试验证；关键执行路径还要做有目标的 handler 或真实运行验证，不能只靠 Markdown 检查或 grep 标记完成。
- 复杂流程修改后，安排未接触预期答案的 subagent 做正向任务验证，观察它能否仅凭 skill 和原始运行信息完成决策；验证失败要继续收敛规则，而不是补一整套业务案例。
- 全量测试存在无关失败时，必须如实报告全量结果，并补跑与本次改动直接相关的定向测试；不得把“定向通过”表述成“全量通过”。

## 沟通约定：抽象短词必须解释

Agent 不能只用自己在完整上下文里才能理解的抽象短词回复开发者。使用这类词时，必须在同一段里补上具体解释：这个词在当前任务里具体指哪些文件、模块或命令；会改变什么运行行为；为什么现在要做这些事；推荐下一步先做哪一项；完成后用哪些测试验证。

## 任务完成汇报：必须讲清目标、改动和效果

每次任务结束必须说明：
- **本次任务目标**：用户原本想解决的实际问题
- **修改了什么**：按模块/文件解释，说明每个文件现在负责什么
- **产生什么效果**：对外行为、HTTP 命令响应、配置开关的变化
- **怎么使用或验证**：关键配置、curl、启动参数或测试命令
- **仍未实现和限制**：没做的能力、默认关闭项、平台限制

## 常用命令

| 命令 | 说明 |
|---|---|
| `swift build` | 构建 SPM 库 |
| `swift test` | macOS SPM 测试（~225 个）；集成测试串行，端口 38399 |
| `xcodebuild ... test` | iOS framework 测试（~344 个），端口 38399 |
| `curl -X POST http://localhost:38321/ -d '{"action":"ping"}'` | 验证服务 |

## 示例 App 集成方式

`Examples/SPMExample` 在 DEBUG 环境下直接调用 `server.start()`（`ViewController.viewDidAppear` 中自动执行），这是推荐的集成方式：

```swift
#if DEBUG
override func viewDidLoad() {
    super.viewDidLoad()
    Task {
        try? await server.start()
    }
}
#endif
```

可选的测试页面启动参数：
- `--ios-explore-open-alert-test` 或 `IOS_EXPLORE_OPEN_ALERT_TEST=1` — 启动后自动进入弹窗测试页
- `--ios-explore-show-login` 或 `IOS_EXPLORE_SHOW_LOGIN=1` — 显示登录流程测试界面

这些开关用于测试工程快速进入特定测试场景，不是 iOSExploreServer 的核心 API。

## 测试凭据

SPMExample 预置测试账号（位于 `Examples/SPMExample/SPMExample/Login/Services/AuthService.swift:31`）：

| 用户名 | 密码 | 说明 |
|-------|------|------|
| test | 123456 | 预置账号，用于登录测试 |

登录失败后密码框会被清空（iOS 标准行为），重试需重新输入密码。

## XcodeBuildMCP 运行配置

### 三个 profile

| profile | 工程/scheme | target | 用途 |
|---|---|---|---|
| `sim-app` | SPMExample | iPhone 17 模拟器 | App 模拟器闭环 |
| `sim-fw` | iOSExploreServer | iPhone 17 模拟器 | framework 测试 |
| `device-app` | SPMExample | iOS 真机 | App 真机闭环 |

> `.xcodebuildmcp/config.yaml` 顶层 `enabledWorkflows` 需启用 `simulator` + `device` + `debugging` + `ui-automation`（默认只有 simulator）。改完后 `/mcp` → reconnect XcodeBuildMCP 新工具才生效。

### 模拟器跑法

```
session_use_defaults_profile("sim-app")
build_run_sim()
launch_app_sim()
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
# → {"code":"ok","data":{"pong":true}}
```

不需要 iproxy（模拟器与 Mac 共享 localhost）。Server 会在 App 启动时自动启动（DEBUG 环境）。

### 真机跑法

```
session_use_defaults_profile("device-app")
build_run_device()
launch_app_device()
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
```

真机 38321 必须经 USB 转发后 Mac 才能访问；具体连接管理入口不在 `AGENTS.md` 固化，由当前会话可用的连接能力决定。Server 会在 App 启动时自动启动（DEBUG 环境）。

## 四个必须记住的差异（实测踩过坑）

1. **设备 ID 有两套体系**。XcodeBuildMCP 的 `deviceId`（`list_devices`/`launch_app_device`）用 **CoreDevice identifier**（`3AC0C7D6-...`）；`iproxy -u` 用 **USB UDID**（`00008030-...`）。

2. **判 iOS 版本别信 devicectl 的机型字段**。会缓存串号，iOS 26.5 真机可能显示成 iPhone 11。判版本用 `list_devices` 的 `osVersion`，或直接 build 实测。部署目标 **iOS 26.2**。

3. **`build_run_sim`/`build_run_device` 不把 session default 的 `env` 注入 App 进程**。驱动 autostart 必须用 `launch_app_*(env/launchArgs)`；已运行的 App 不会重启，必须先 `stop_app_*` 再 `launch_app_*`。

4. **curl 真机前必须 `lsof -iTCP:38321` 确认监听进程是 `iproxy` 而非残留 `SPMExampl`**。模拟器跑过的 SPMExample 会残留成 Mac 进程占住 38321。COMMAND 列是 `iproxy` 才对。

## 模块结构

- `Sources/iOSExploreServer/` — SPM 库 core，**不依赖 UIKit**
- `Sources/iOSExploreUIKit/` — UIKit 扩展模块，**依赖 core**，含 14 个 `ui.*` 命令
- `Sources/iOSExploreDiagnostics/` — 进程日志扩展模块，**依赖 core**。宿主调用 `server.registerDiagnosticsCommands()` 后注册 `app.logs.mark`/`app.logs.read`。stdout/stderr/NSLog/os_log capture 默认关闭，由 `DiagnosticsConfiguration.captureStdout` 等控制。

framework 工程三个 target（`iOSExploreServer.xcodeproj`）：`iOSExploreServer.framework`、`iOSExploreUIKit.framework`、`iOSExploreDiagnostics.framework`。

## ui.inspect 设计要点

- **全节点输出 + full/minimal 两档**：full 节点含完整 `availableActions`/文本/状态并进入指纹签发集合；minimal 节点只给 `path`+`type`，强制 `availableActions=[]`，不签发指纹
- **对 minimal 节点调 `ui.tap`/`ui.control.sendAction` 返回业务码 `not_actionable`**（与 `invalid_data` 区分）
- **cell 内子 view 通过 `cellAncestor` 自动进 full**，agent 可直接按 cell 标题文本定位并 tap 子 label path
- **采集根是最外层容器 VC.view（含 chrome）**：`ui.inspect`/`ui.topViewHierarchy` 从 `hierarchyRootController.view`（沿 `presentedViewController` 走到最外层，**不**钻 nav/tab/split）采集，故容器 chrome（`UITabBar`/`UITabBarButton`/`UINavigationBar`）落在子树里；`ui.tap`/`ui.input`/`ui.control.sendAction` 的 path 与 inspect 同根（都用 `context.rootView`），定位一致。修复前采集根是 `topViewController.view`（叶子 VC），chrome 与之平级、不在子树里会丢失（modal 容器采集根盲区，详见 `docs/superpowers/specs/2026-07-17-resolver-modal-blindspot.md`）。`topViewController`（钻叶子）仍用于 navBar/alert/fingerprint 摘要，操作语义不变

## 日志与注释要求

### 日志（必须执行）

- 所有底层生命周期必须有日志：server 初始化/启动/停止、listener created/ready/waiting/failed/cancelled、connection accepted/rejected、session ready/closed/removed
- 所有命令路径必须有日志：action 注册、请求收到、参数校验失败、命令开始/完成/超时/抛错、响应发送
- 所有资源限制必须有日志：连接数上限、header/body/request 超限、read timeout、command timeout、send/receive error
- UIKit 命令日志走 `UIKitCommandLogging`（category `command`）：registrar 进入/完成、每次命令 start/complete/failed、resolver 定位结果、executor 各失败分支、snapshot store 的 insert/evict/expired/mismatch/stale
- 日志不能泄露 auth token、完整截图、大块 payload 或用户输入全文

### 注释（必须执行）

- 所有 public 类型、属性、方法必须有 `///` 文档注释：说明用途，方法写清 `- Parameters:`/`- Returns:`/`- Throws:`，错误工厂写清触发场景与对应 HTTP status/code
- 关键内部类型（`HTTPListener`/`ClientSession`/`HTTPParser`/`Router`）也要有 `///` 注释，写清职责、状态转移、与日志点的对应关系
- 注释用简体中文，写"为什么"和"在生命周期中的角色"，不复述类型签名

## 文档路由

| 改什么 | 查哪里 |
|---|---|
| 库源码 / HTTP 协议 | `docs/architecture/index.md` |
| framework 工程 / 构建配置 | `docs/architecture/index.md` + `docs/runbooks/build-and-test.md` |
| 构建 / 测试 / 真机验证 | `docs/runbooks/build-and-test.md` |
| iproxy / 端口 / 排障 | `docs/runbooks/debugging.md` |
| 完整设计背景 | `docs/superpowers/specs/2026-06-21-ios-explore-server-design.md` |
| iOSExploreUIKit 子包 | `docs/uikit/README.md` + [reading-guide.md](docs/uikit/reading-guide.md) + [uikit-file-reference.md](docs/uikit/uikit-file-reference.md) |
