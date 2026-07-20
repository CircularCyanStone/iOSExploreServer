---
name: ios-automation
description: iOS App 自动化操作统一入口。当用户说"查看 iOS App"、"真机测试"、"模拟器测试"、"连不上 App"、"iproxy"、"端口 38321"、"检查登录页面"、"App 日志"、"截图看看布局"时使用此 skill。处理开发调试、自动化测试、连接管理(iproxy/localhost)、快速诊断。Use for iOS app inspection, device/simulator testing, connection troubleshooting, iproxy setup, UI state checks, app logs.
allowed-tools:
  - mcp__iOSDriver__ui_inspect
  - mcp__iOSDriver__ui_tap_and_inspect
  - mcp__iOSDriver__app_logs_read
---

# iOS 自动化操作统一入口(L1)

基于 iOSDriver MCP Server(`mcp__iOSDriver__*`,封装 iOSExploreServer HTTP)与宿主 iOS App 的 HTTP 端点(`POST http://localhost:38321/`),作为 L1 操作层的统一入口。本 skill **本身不做复杂 UI 操作**,只负责三件事:**连接管理**(模拟器 localhost 直连 / 真机 iproxy USB 转发)、**任务路由**(把请求分发给 `ios-ui-*` 与 `ios-logs` 子 skill)、**快速诊断**(ping、UI 快照、进程日志、端口冲突排查)。

## 目标

解决"开发者/测试人员要操作一个已集成 iOSExploreServer 的 iOS App,但不确定从哪里开始"这一入口问题。具体回答三个问题:

- **怎么连上 App** — 模拟器与真机连接方式不同(localhost vs iproxy),且真机有四个易踩的坑(端口残留、设备 ID 两套体系、env 注入限制、版本判定),本 skill 给一份精简清单。
- **该用哪个子 skill** — 一张路由表把"用户说什么话 → 走哪个子 skill"对清楚,避免 agent 在 `ios-ui-*` 之间反复试。
- **连不上 / 行为异常时怎么查** — 先 ping、再看端口占用、最后读进程日志,给出三段式诊断流程。

**不做**:不构建 / 安装 / 调试 App 进程(走 L0 `ios-debugger-agent`);不直接驱动表单 / 列表 / 手势(走对应 `ios-ui-*` 子 skill)。

## 何时使用

### 开发调试场景
- ✅ 用户说"帮我看看登录界面"/"检查一下这个按钮"(开发期验证)
- ✅ 用户说"实时监控 App 行为"/"看看当前页面状态"(开发期反馈)
- ✅ 用户说"截个图看看布局"/"查看当前 UI 结构"(开发期诊断)
- ✅ 用户说"检查一下日志有没有报错"(开发期排查)

### 自动化测试场景
- ✅ 用户说"测一下这个 iOS App"但没指定具体场景(先连上、再问要做什么)
- ✅ 用户说"自动化测试"/"验证"/"跑测试"(自动化测试)

### 连接管理与诊断
- ✅ 用户要排查 iproxy / 端口 38321 / 连接问题(`curl: (7) Failed to connect`、`Address already in use`、真机返回模拟器旧数据)
- ✅ 用户不确定该用 `ios-ui-*` 还是 L0 `ios-debugger-agent`,需要先判 L0/L1
- ✅ 用户要快速看一眼当前 UI / 截图 / 弹窗状态(诊断,不是任务主体)
- ✅ 用户说"连上 App"、"iproxy"、"38321"、"ping App"

### 不适用场景
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

iOSDriver MCP Server 提供**固定工具**(启动时已注册,如 `health_check` / `call_action` / `ui_wait`)与**动态工具**(首次使用前需加载,如 `ui_inspect` / `ui_tap` / `ui_input`)。

**推荐流程**: 首次使用先调 `health_check`(自动加载动态工具) → 后续用动态工具 → 遇到"工具不存在"时用 `call_action` 应急(如 `{"action":"ui.inspect"}` 绕过工具注册直接调 HTTP)。

## 连接管理

iOSExploreServer 的唯一 HTTP 端点:`POST http://localhost:38321/`(body 是 `{"action": "..."}` JSON)。所有 iOSDriver MCP 工具最终都走这个端点。连接方式取决于 App 跑在模拟器还是真机。

### 模拟器:localhost 直连

模拟器与 Mac 共享 localhost,App 监听 38321 后 Mac 侧直接使用 `health_check` 验证连接即可,**不需要 iproxy**。

宿主 App 的 `iOSExploreServer` 实例在 DEBUG 环境下,由宿主在 `viewDidLoad` / `viewDidAppear` / `applicationDidFinishLaunching` 中调用 `server.start()` 自动启动(具体入口由宿主决定;不需要 autostart 环境变量)。

### 真机:iproxy USB 转发

真机的 38321 端口不暴露给 Mac,必须经 `iproxy` USB 隧道转发。本 skill 提供一键管理脚本 `scripts/iproxy-manager.sh`,自动处理安装、启动、端口清理、设备检测。

#### 真机测试标准流程(Agent 自动执行)

Agent 执行本 skill 时自动完成以下步骤:

1. **启动 iproxy** — 检查安装状态、启动服务、清理端口冲突
2. **同步设备配置** — 调用 `list_devices` 获取已连接设备,自动更新 `deviceId` 到 session defaults。多设备时提示用户选择。
3. **智能启动 App** — `health_check` 检测 App 是否运行,未运行则调用 `launch_app_device`。启动失败时根据错误类型给出明确提示(未安装/证书未信任/其他错误)。
4. **验证连接** — 多次 `health_check` 确认稳定,失败时自动诊断(`iproxy-manager.sh status`)。

脚本自动处理: iproxy 安装、残留清理、UDID 获取、状态诊断。

### 真机/模拟器四个关键差异

1. **设备 ID 两套体系** — XcodeBuildMCP 的 `deviceId`(`list_devices` 返回)用 **CoreDevice identifier**(8-4-4-4-12 形式的 UUID);`iproxy -u` 用 **USB UDID**(连字符分隔的十六进制串)。同一台设备不能混用。脚本自动处理 UDID 获取,无需手动区分。
2. **iOS 版本别信 devicectl 的机型字段** — 会缓存串号(iOS 26.5 真机可能显示成 iPhone 11)。判版本只看 `list_devices` 的 `osVersion`。
3. **`build_run_*` 不注入 session env** — 要传启动参数(如回到流程起点),必须用 `launch_app_*(env/launchArgs)`,且先 `stop_app_*` 再 `launch_app_*`(已运行的 App 不会重启、参数不生效)。
4. **`curl` 真机前先确认 38321 是 `iproxy` 在监听** — 模拟器跑过的 App 可能残留成 Mac 进程占住 38321,`curl localhost:38321` 打到的是这个**模拟器残留**(旧 binary、env 也没设),导致真机预期对不上。用 `iproxy-manager.sh status` 检查,会自动提示占用进程类型。

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

### 4. 端口冲突排查

ping 不通或真机返回模拟器数据时,使用管理脚本一键诊断:

使用 `iproxy-manager.sh status` 检查端口占用情况、USB 设备状态、服务可用性,并获得修复建议。

## 常见错误与判别

### `curl: (7) Failed to connect to localhost port 38321`

- **原因**:App 未启动、App 起了但 `server.start()` 没调、或 38321 未监听
- **一键诊断**: `iproxy-manager.sh status`
- **处理**: 模拟器检查 App 是否已启动;真机先 `iproxy-manager.sh start`,再检查 App 是否已 `launch_app_device`

### 真机 `curl` 返回模拟器旧数据

- **原因**:模拟器跑过的 App 残留成 Mac 进程占住 38321(见"四个必须记住的差异"第 4 点)
- **一键修复**: `iproxy-manager.sh restart`(自动清理残留 → 停止旧 iproxy → 启动新 iproxy → 验证)

### `iproxy: Address already in use: 38321`

- **原因**:旧 iproxy 未停,或模拟器 App 残留占用
- **一键修复**: `iproxy-manager.sh restart`

### 启动参数没生效

- **原因**:`build_run_sim` / `build_run_device` 不注入 session env;已运行的 App 不会重启(见"四个必须记住的差异"第 3 点)
- **处理**:先 `stop_app_*` 再 `launch_app_*(launchArgs=[...])`

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
