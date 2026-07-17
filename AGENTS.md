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
8. **开发期只留最合理设计**：任何设计不合理的地方都应推到最合理方案，不保留"能用先这样"的妥协代码。改完代码先 `swift test` 再说完成。

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
| `./scripts/proxy.sh` | iproxy USB 转发（前台运行，Ctrl-C 停） |
| `./scripts/proxy.sh --daemon` | iproxy 后台运行（推荐） |
| `./scripts/proxy.sh --status` | 检查 iproxy 运行状态 + 端口占用诊断 |
| `./scripts/proxy.sh --stop` | 停止后台 iproxy |
| `curl -X POST http://localhost:38321/ -d '{"action":"ping"}'` | 验证服务 |

## Claude Code Skills（自动化测试入口）

> 三层架构 + 命名分组重写完成。权威清单与状态见 `docs/skills/inventory.md`；看一个文件懂全貌见 `docs/skills/README.md`。L0/L1 选择规则见 `docs/skills/l0-build-debug.md`。

| Skill | 层 | 说明 |
|---|---|---|
| `/ios-automation` | **L1 入口** | **统一入口**：连接管理 + iproxy + 路由到 `ios-ui-*` / `ios-logs` 子 skill + 快速诊断 |
| `/ios-ui-nav` | L1 UI | 屏幕导航、返回、导航栏按钮、controller 层级树（吸收原 `ios-controller-navigation`） |
| `/ios-ui-list` | L1 UI | 列表 / 集合视图查找、滚动定位、cell 选中、swipe action |
| `/ios-ui-form` | L1 UI | 文本输入、开关、滑块、步进器、分段控件、提交、收键盘 |
| `/ios-ui-picker` | L1 UI | UIDatePicker / UIPickerView 设值（`ui.datePicker.setDate` / `ui.picker.selectRow`，走 `call_action`；这两类控件不在 `ui.inspect` 能力表，需专用命令） |
| `/ios-ui-alert` | L1 UI | alert / action sheet / dialog 检测与响应、输入框弹窗 |
| `/ios-ui-shot` | L1 UI | 截图、视觉验证、前后对比、回归取证 |
| `/ios-ui-gesture` | L1 UI | swipe 方向滑动、long press 长按、cell 滑动操作（不含 drag） |
| `/ios-ui-wait` | L1 UI | 等待动态内容 / loading / 异步状态稳定（`ui_wait` / `ui_waitAny`） |
| `/ios-logs` | L1 日志 | 读 App 进程内日志（`app.logs.mark` / `app.logs.read`，按 source / level 过滤） |
| `/ios-test-intent` | **L2 测试** | 离线读 App 业务代码，产出 per-scenario pass/fail 判据清单 |
| `/ios-test-runner` | **L2 测试** | 消费判据清单，驱动 UI 跑测试，出覆盖报告 |
| `/ios-debugger-agent` | **L0 构建调试** | XcodeBuildMCP：编译 / 运行 / 启动 / 调试 App 进程，系统级日志（全局 skill） |

已删除 3 个空壳 / 重叠 skill：`ios-date-picker` / `ios-table-actions` / `ios-controller-navigation`（原因见 `docs/skills/inventory.md` §2）。其中 `ios-date-picker` 当时因 `ui.datePicker.*` / `ui.picker.*` action 不存在而删，该能力已于 2026-07-17 在 iOSExploreServer 实现，并以 `ios-ui-picker` 重建。

覆盖率：`swift test --enable-code-coverage`（当前 86.62%）。

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
# 另开终端：./scripts/proxy.sh 或 iproxy 38321 38321 -u <USB-UDID>
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
```

真机 38321 必须经 iproxy USB 转发。Server 会在 App 启动时自动启动（DEBUG 环境）。

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
