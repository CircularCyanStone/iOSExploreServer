---
name: ios-automation
description: iOS App 自动化测试 L1 总入口(连接管理 + 路由到 ios-ui-* / ios-logs 子 skill + 快速诊断)/ unified L1 entry, iproxy, connection check, skill routing, diagnostics, simulator, physical device, ping 38321
allowed-tools:
  - mcp__iOSDriver__ui_inspect
  - mcp__iOSDriver__ui_tap_and_inspect
  - mcp__iOSDriver__app_logs_read
---

# iOS 自动化总入口(L1)

基于 iOSDriver MCP Server(`mcp__iOSDriver__*`,封装 iOSExploreServer HTTP)与宿主 iOS App 的 HTTP 端点(`POST http://localhost:38321/`),作为 L1 操作层的统一入口。本 skill **本身不做复杂 UI 操作**,只负责三件事:**连接管理**(模拟器 localhost 直连 / 真机 iproxy USB 转发)、**任务路由**(把请求分发给 `ios-ui-*` 与 `ios-logs` 子 skill)、**快速诊断**(ping、UI 快照、进程日志、端口冲突排查)。

## 目标

解决"开发者要测一个已集成 iOSExploreServer 的 iOS App,但不确定从哪里开始"这一入口问题。具体回答三个问题:

- **怎么连上 App** — 模拟器与真机连接方式不同(localhost vs iproxy),且真机有四个易踩的坑(端口残留、设备 ID 两套体系、env 注入限制、版本判定),本 skill 给一份精简清单。
- **该用哪个子 skill** — 一张路由表把"用户说什么话 → 走哪个子 skill"对清楚,避免 agent 在 `ios-ui-*` 之间反复试。
- **连不上 / 行为异常时怎么查** — 先 ping、再看端口占用、最后读进程日志,给出三段式诊断流程。

**不做**:不构建 / 安装 / 调试 App 进程(走 L0 `ios-debugger-agent`);不直接驱动表单 / 列表 / 手势(走对应 `ios-ui-*` 子 skill)。

## 何时使用

- ✅ 用户说"测一下这个 iOS App"但没指定具体场景(先连上、再问要做什么)
- ✅ 用户要排查 iproxy / 端口 38321 / 连接问题(`curl: (7) Failed to connect`、`Address already in use`、真机返回模拟器旧数据)
- ✅ 用户不确定该用 `ios-ui-*` 还是 L0 `ios-debugger-agent`,需要先判 L0/L1
- ✅ 用户要快速看一眼当前 UI / 截图 / 弹窗状态(诊断,不是任务主体)
- ✅ 用户说"自动化"、"自动化测试"、"连上 App"、"iproxy"、"38321"、"ping App"
- ❌ 不要用于具体的表单填写 / 列表滚动 / 手势(直接走对应 `ios-ui-*`,本 skill 只在最前期不确定时介入)
- ❌ 不要用于构建 / 安装 / 启动模拟器 / LLDB 调试(L0 `ios-debugger-agent`,见"L0 vs L1 选择规则")
- ❌ 不要用于读源码出测试判据(`ios-test-intent`)或执行测试意图闭环(`ios-test-runner`)

## L0 vs L1 选择规则

这是入口最关键的决策:**目标 App 是否已集成 iOSExploreServer**(能 `curl http://localhost:38321/` 成功)。

| 条件 | 用哪一层 | 工具体系 |
|---|---|---|
| App 已集成 iOSExploreServer,`ping` 通 | **L1**(本 skill + `ios-ui-*` + `ios-logs`) | iOSDriver(`mcp__iOSDriver__*`) |
| 需要 build / install / launch / LLDB 调试 | **L0**(`ios-debugger-agent`) | XcodeBuildMCP(`mcp__XcodeBuildMCP__*`) |
| 需要**系统级**日志(整个 App 控制台、其他进程) | **L0**(`start_sim_log_cap` 等) | XcodeBuildMCP |
| 需要**进程内精准**日志(按 source/level 过滤、可断言) | **L1**(`ios-logs` 的 `app.logs.*`) | iOSDriver |
| App**未集成** iOSExploreServer(`curl` 连不上) | **L0**(先构建运行,或退回系统级 UI 自动化) | XcodeBuildMCP |

两套日志能力**互补,非冲突**:L0 抓系统/模拟器级(模拟器友好、覆盖整个控制台),L1 抓进程内精准(可按 `stdout`/`stderr`/`nslog`/`oslog`/`explore`/`bridge` 过滤、可做断言、真机 `oslog` 更全)。需要时同一会话可混用。

## MCP 工具调用机制

iOSDriver MCP Server 提供两类工具:**固定工具**与**动态工具**。理解两者区别能避免"工具不存在"困惑。

### 固定工具(总是可用)

这些工具在 MCP server 启动时已注册,无需 `refresh_tools`:

- `health_check` — 检查连接并**自动加载动态工具**(初次调用时 `dynamicToolCount` 会从 0 变成 32+)
- `refresh_tools` — 手动刷新动态工具(通常不需要,`health_check` 会自动调用)
- `call_action` — 兜底工具,可调用任意 iOSExplore action(如 `{"action":"ui.inspect"}`)
- `wait_and_inspect` — 组合 `ui.waitAny` + `ui.inspect`
- `ui_wait` — 等待 UI 稳定或条件满足
- `ui_tap_and_inspect` — 点击 + 等稳定 + inspect 一次完成

### 动态工具(需先加载)

从 App 的 `/help` 端点读取 action 列表并自动注册为 MCP 工具(action 名 `ui.tap` → 工具名 `ui_tap`)。首次使用前需调用 `health_check`(会自动触发加载)或显式调用 `refresh_tools`。

常见动态工具:`ui_inspect`、`ui_tap`、`ui_input`、`ui_alert_respond`、`ui_scroll`、`ui_screenshot` 等。

### call_action vs 动态工具:何时用哪个

| 场景 | 推荐方式 | 原因 |
|---|---|---|
| 正常 UI 操作(已连接、工具已加载) | 动态工具(`ui_tap`、`ui_input` 等) | 类型安全、参数校验、更好的错误提示 |
| 初次连接验证 | `health_check`(会自动加载动态工具) | 一步到位:ping + 加载工具 |
| 动态工具"不存在"报错 | 先 `call_action`(如 `{"action":"ui.inspect"}`) | 绕过工具注册,直接调 HTTP 端点 |
| 排障或调用未映射的 action | `call_action` | 兜底工具,不依赖 MCP 工具注册 |
| App 新增 action 但 MCP 未同步 | `refresh_tools` 然后用动态工具 | 重新同步工具列表 |

**推荐流程**:首次使用先调 `health_check` → 后续用动态工具(如 `ui_inspect`) → 遇到"工具不存在"时用 `call_action` 应急。

### 常见错误:"ui_inspect tool not found"

**现象**:调用 `mcp__iOSDriver__ui_inspect` 提示工具不存在

**原因**:动态工具未加载(MCP server 启动时 `dynamicToolCount: 0`)

**修复**:
1. 先调用 `health_check`(会自动加载动态工具)
2. 或临时用 `call_action`:
   ```json
   {"action": "ui.inspect", "data": {"maxDepth": 2}}
   ```
3. 验证工具已加载:`health_check` 的 `dynamicToolCount` 应为 32+

## 连接管理

iOSExploreServer 的唯一 HTTP 端点:`POST http://localhost:38321/`(body 是 `{"action": "..."}` JSON)。所有 iOSDriver MCP 工具最终都走这个端点。连接方式取决于 App 跑在模拟器还是真机。

### 模拟器:localhost 直连

模拟器与 Mac 共享 localhost,App 监听 38321 后 Mac 侧直接 `curl` 即可,**不需要 iproxy**。

```bash
# 验证连接(预期 {"code":"ok","data":{"pong":true}})
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
```

宿主 App 的 `iOSExploreServer` 实例在 DEBUG 环境下,由宿主在 `viewDidLoad` / `viewDidAppear` / `applicationDidFinishLaunching` 中调用 `server.start()` 自动启动(具体入口由宿主决定;不需要 autostart 环境变量)。

### 真机:iproxy USB 转发

真机的 38321 端口不暴露给 Mac,必须经 `iproxy` USB 隧道转发:

```bash
# 启动 iproxy 后台守护进程(仓库脚本封装,自动用 lsusb 取 USB UDID)
./scripts/proxy.sh --daemon

# 或手动:iproxy 38321 38321 -u <your-device-udid>
# <your-device-udid> 是 USB UDID(连字符分隔的十六进制串),不是 CoreDevice identifier
```

启动后 `curl http://localhost:38321/` 与模拟器一致。

### 四个必须记住的差异(真机 / 模拟器易踩坑)

1. **设备 ID 两套体系** — XcodeBuildMCP 的 `deviceId`(`list_devices` 返回)用 **CoreDevice identifier**(8-4-4-4-12 形式的 UUID);`iproxy -u` 用 **USB UDID**(连字符分隔的十六进制串)。同一台设备不能混用。
2. **iOS 版本别信 devicectl 的机型字段** — 会缓存串号(iOS 26.5 真机可能显示成 iPhone 11)。判版本只看 `list_devices` 的 `osVersion`。
3. **`build_run_*` 不注入 session env** — 要传启动参数(如回到流程起点),必须用 `launch_app_*(env/launchArgs)`,且先 `stop_app_*` 再 `launch_app_*`(已运行的 App 不会重启、参数不生效)。
4. **`curl` 真机前先确认 38321 是 `iproxy` 在监听** — 模拟器跑过的 App 可能残留成 Mac 进程占住 38321,`curl localhost:38321` 打到的是这个**模拟器残留**(旧 binary、env 也没设),导致真机预期对不上。`lsof -iTCP:38321` 的 COMMAND 列应为 `iproxy`,否则按"端口冲突排查"清残留。

## 路由到子 skill

把请求分发给对应专业 skill。本 skill **不直接调用** 子 skill 里的 UI 工具(如 `ui_input` / `ui_alert_respond` / `ui_scroll`),而是路由 agent 到该 skill,由它执行。

| 用户说什么 / 做什么 | 路由到 | 备注 |
|---|---|---|
| 表单填写、文本输入、开关 / 滑块 / 步进器 / 分段控件、提交 | `ios-ui-form` | 输入走 `ui_input`,控件事件走 `ui_control_sendAction` |
| 弹窗、确认框、action sheet、带输入框的 alert | `ios-ui-alert` | 走 `ui_alert_respond`,不要用 `ui_tap` 点 alert 按钮 |
| 屏幕导航、返回、导航栏左右按钮、controller 层级树 | `ios-ui-nav` | 含 `ui_controllers` 只读取层级 |
| 列表 / 集合视图查找、滚动定位、cell 选中、cell 滑动操作 | `ios-ui-list` | 长列表优先 `ui_scrollToElement` |
| 截图、前后对比、视觉取证 | `ios-ui-shot` | 不含图像 diff(需外部工具) |
| swipe 方向滑动、long press 长按 | `ios-ui-gesture` | 不含 `ui.drag`(不存在) |
| 等待 loading / 动画 / 异步状态稳定 | `ios-ui-wait` | 推荐先 `ui_waitAny` 多条件并发 |
| **异步表单提交后等待成功/失败** | `ios-ui-form` 提交 + `ios-ui-wait` 等待 | 登录/注册/保存场景,先 `ui_tap` 按钮,再用 `wait_and_inspect` 等多判据(targetExists / textExists) |
| 读 App 进程内日志(stdout / stderr / nslog / oslog) | `ios-logs` | 含来源 × 平台可用性矩阵 |
| 读业务源码产出测试意图清单 | `ios-test-intent`(L2) | 离线分析,不操作 App |
| 执行测试意图、跑覆盖报告 | `ios-test-runner`(L2) | 消费 `ios-test-intent` 的产出 |

**路由反模式**:把所有 UI 操作都串在 `ios-automation` 里直接调 `ui_tap` / `ui_input`。正确做法是路由到对应 `ios-ui-*`,让子 skill 处理顺序依赖、稳定等待、业务码判别。

**异步提交场景路由规则**:
- 用户要"登录"、"注册"、"保存"等有网络请求的表单 → 先路由到 `ios-ui-form` 填写表单并点击提交按钮
- 提交后需要判断成功/失败 → 再路由到 `ios-ui-wait`,用 `wait_and_inspect` 或 `ui_waitAny` 等待明确判据(成功: `targetExists:"home_welcome_label"`;失败: `textExists:"错误"`)
- **不要**用 `ui_tap_and_inspect` + 固定 `stableTimeMs` 等异步操作(会读到 loading 中间态、浪费时间、无法区分成功/失败)

## 快速诊断

连接或行为异常时按下列顺序排查。

### 1. ping 验证(最优先)

90% 的"连不上"场景 App 其实已运行,先直接 ping:

```bash
curl -s -X POST http://localhost:38321/ -d '{"action":"ping"}'
# 预期:{"code":"ok","data":{"pong":true}}
```

- ✅ 通 → 连接没问题,问题在 UI 层(路由到对应 `ios-ui-*`)
- ❌ 不通 → 进入步骤 2

**反模式**:每次任务前都跑完整端口 / 进程 / health check 诊断流程,浪费 2-3 秒。**正确**:先 ping,失败了再深度查。

### 2. UI 状态快照(`ui_inspect`)

ping 通但行为异常时,用 `mcp__iOSDriver__ui_inspect` 取当前视图结构(targets / alert / navigationBar),签发 `viewSnapshotID` 给后续 `ui_tap_and_inspect` 用。本 skill 的诊断范围只到"读状态",看到具体 UI 问题后路由给对应 `ios-ui-*`。

### 3. 进程日志(`app_logs_read`)

`mcp__iOSDriver__app_logs_read` 读进程内日志,可按 `sources`(`explore`/`bridge`/`stdout`/`stderr`/`nslog`/`oslog`)和 `minimumLevel` 过滤。读不到某 source 时先看响应里的 `capture.state`(`unavailable` 是"系统不让读",不是"日志没发生";详见 `ios-logs`)。诊断场景典型用法:先 `app_logs_mark` 建检查点,触发问题,再 `app_logs_read`(after=cursor) 看增量。

### 4. 端口冲突排查(lsof / 残留清理)

ping 不通或真机返回模拟器数据时:

```bash
# 1. 看谁占着 38321
lsof -iTCP:38321
# COMMAND 列含义:
#   iproxy     → 真机转发正常
#   <App 进程名> → 模拟器 App 直连(模拟器场景正常;真机场景是残留)
#   (空)       → 没人监听,App 没起或 server 没注册

# 2. 模拟器 App 残留清理(真机场景误占时)
xcrun simctl terminate <your-simulator-udid> <your.app.bundleid>

# 3. 旧 iproxy 停止
./scripts/proxy.sh --stop

# 4. 重启 iproxy(真机场景)
./scripts/proxy.sh --daemon

# 5. 再次 ping 验证
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
```

## 常见错误与判别

### `curl: (7) Failed to connect to localhost port 38321`

- **现象**:curl 报连接拒绝
- **原因**:App 未启动、App 起了但 `server.start()` 没调、或 38321 未监听
- **判别**:`lsof -iTCP:38321` 输出为空 → 没人监听
- **处理**:模拟器 `launch_app_sim`;真机确认 `iproxy` 运行(`./scripts/proxy.sh --status`)且 App 已 `launch_app_device`;宿主 App 的 `server.start()` 调用点正确

### 真机 `curl` 返回模拟器旧数据

- **现象**:真机 `curl` 的响应与真机预期不符(旧 binary、env 未设、返回的是另一个 App 的状态)
- **原因**:模拟器跑过的 App 残留成 Mac 进程占住 38321,真机 `curl` 打到了这个残留
- **判别**:`lsof -iTCP:38321` 的 COMMAND 是 App 进程名而不是 `iproxy`
- **处理**:`xcrun simctl terminate <your-simulator-udid> <your.app.bundleid>` 清残留 → `./scripts/proxy.sh --stop` 停旧 iproxy → `./scripts/proxy.sh --daemon` 重启 → 再 ping

### `iproxy: Address already in use: 38321`

- **现象**:启动 iproxy 立即报端口占用
- **原因**:旧 iproxy 未停,或模拟器 App 残留占用(同上)
- **判别**:`lsof -iTCP:38321` 的 COMMAND 区分(iproxy / App 进程名)
- **处理**:按"端口冲突排查"步骤 3-4

### 启动参数没生效

- **现象**:传了 `--ios-explore-show-login` 等 launchArgs,App 行为不变
- **原因**:`build_run_sim` / `build_run_device` 不注入 session env;已运行的 App 不会重启
- **判别**:看 App 进程是否在 `build_run_*` 前已存在
- **处理**:先 `stop_app_*` 再 `launch_app_*(launchArgs=[...])`(启动参数是 App 专属,本 skill 不写死参数名,由调用方提供)

## 关键参数

本 skill 直接调用的 MCP 工具(allowed-tools):

| 工具 | 含义 | 注意 |
|---|---|---|
| `mcp__iOSDriver__ui_inspect` | 读当前 UI 结构,签发 `viewSnapshotID` | 诊断入口;复杂 UI 调查路由给 `ios-ui-*` |
| `mcp__iOSDriver__ui_tap_and_inspect` | 点击 + 等稳定 + inspect 一次完成 | 用于"点一下看看发生什么"的快速诊断 |
| `mcp__iOSDriver__app_logs_read` | 读进程内日志 | `capture.state` 三态(`enabled` / `notCaptured` / `unavailable`)必看 |

诊断流程涉及的 Bash 命令(curl / lsof / iproxy / xcrun simctl)由 agent 在 Bash 工具里执行,不进 allowed-tools(那是 MCP 工具字段)。

## 相关 skill

- `ios-debugger-agent`(L0) — 需要 build / install / LLDB 调试 / 系统级日志时改用它,见"L0 vs L1 选择规则"
- `ios-ui-*`(L1) — 具体场景路由目标,见"路由到子 skill"
- `ios-logs`(L1) — 进程内日志的完整能力(`app_logs_mark` / 来源 × 平台矩阵 / `unavailable` 语义),本 skill 只用最基础的 `app_logs_read`
- `ios-test-intent`(L2) — 读源码产出测试意图清单(离线分析)
- `ios-test-runner`(L2) — 执行测试意图闭环
