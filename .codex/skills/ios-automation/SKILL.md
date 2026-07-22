---
name: ios-automation
description: iOS App 自动化测试 L1 统一入口。用于已接入 App 内 HTTP 自动化端点的 App 连接验证、模拟器/真机上下文判断、UI 检查、截图、日志读取和路由到 ios-ui-* / ios-logs / ios-test-* skills。Use when an agent needs an open-source, client-neutral entry point for iOS app automation over a debug HTTP automation endpoint.
---

# iOS 自动化操作统一入口(L1)

基于 iOSDriver MCP Server(封装目标 App 的 HTTP 自动化端点)与宿主 iOS App 的 HTTP 端点(`POST http://localhost:38321/`),作为 L1 操作层的统一入口。本 skill **本身不做复杂 UI 操作**,只负责三件事:**MCP 依赖检测**、**快速连接验证**(`health_check`)、**任务路由**(把请求分发给 `ios-ui-*` 与 `ios-logs` 子 skill)。连接问题路由到 `ios-connection`。

入口只回答三个问题：MCP 工具是否可用、App 端点是否可达、当前任务应路由到哪个专业 skill。它不直接执行复杂 UI、日志排障、构建安装或端口管理。

## L0 vs L1 选择规则

这是入口最关键的决策:**目标 App 是否已接入 App 内 HTTP 自动化端点**(能通过 `health_check` 连接)。

| 条件 | 用哪一层 | 工具体系 |
|---|---|---|
| App 已接入 HTTP 自动化端点,`health_check` 通 | **L1**(本 skill + `ios-ui-*` + `ios-logs`) | iOSDriver |
| 需要 build / install / launch / LLDB 调试 | **L0**(构建/设备管理流程) | 构建/设备管理 MCP |
| 需要**系统级**日志(整个 App 控制台、其他进程) | **L0**(如模拟器系统日志采集能力) | 构建/设备管理 MCP |
| 需要**进程内精准**日志(按 source/level 过滤、可断言) | **L1**(`ios-logs` 的 `app.logs.*`) | iOSDriver |
| 已确认 App **未接入** HTTP 自动化端点，或无法启动带端点的构建 | **L0**(先集成/构建,或退回系统级 UI 自动化) | 构建/设备管理 MCP |

两套日志能力互补：L0 覆盖系统或模拟器控制台，L1 读取 App 当前进程内可按 source/level 过滤的日志。L1 的 `oslog` / `nslog` 是否可读必须以 `ios-logs` 规定的运行时 `capture.state` 为准，不能按真机或模拟器预设。

## MCP 依赖检测

L1 UI 或日志任务必须有 iOSDriver MCP。只有任务还需要构建、安装、启动 App 或判断设备上下文时，才额外要求构建/设备管理 MCP；App 已运行的纯 UI 任务不为此做无关依赖检测。

### 启动时检测流程

执行本 skill 时必须按以下顺序检测 MCP 可用性:

1. 调用 iOSDriver `health_check`。
2. 工具不存在或调用无法发起：转 `ios-mcp-setup`，修复 iOSDriver 配置后重连客户端。
3. 返回 `connection.status == "app_endpoint_unreachable"`，或 `connection.error` / `app.ping.error` 显示 transport `connection_failed`：iOSDriver 已加载，App 端点不可达；把原始结果和已知设备上下文交给 `ios-connection`，不要在入口展开端口分诊。
4. 返回 `ok:true`：按用户目标路由到一个主场景 skill。
5. 任务需要构建、启动或设备选择时，再检查构建/设备管理 MCP；工具缺失或所需 workflow 未加载时转 `ios-mcp-setup`。

当检测到 MCP 不可用时,**不要尝试使用 curl 等底层命令或脚本替代 MCP 工具**。MCP 配置必须由用户手动完成,Agent 无法代劳。

## 快速连接验证

入口只保留可交接的连接结论：`health_check` 原始结果、用户指定或已可靠识别的设备类型，以及任务是否需要启动 App。设备类型未知时标记为未知，由 `ios-connection` 读取真实设备列表和工具清单；不要在入口猜测。

**静态工具与能力检查**:
- iOSDriver 的稳定公共工具在进程启动后即固定可见，不随 App 是否启动或模块是否注册而变化
- `health_check` / `check_capabilities` 读取 `ping` 和 `help` 只做能力诊断，不刷新工具列表
- UIKit / Diagnostics 静态工具调用返回 `unknown_action` 时，说明 App 当前未注册对应模块，应检查宿主注册入口
- `call_action` 只用于宿主私有、Debug、实验性或尚未静态封装的 action；稳定公共 action 始终优先用静态工具

**不在此处理** iproxy 启动、设备上下文和端口冲突等场景,这些全部由 `ios-connection` 负责。

## 低冗余执行规则

入口阶段只做连接判断和任务路由,不要预读或预调用尚未进入任务路径的子 skill。具体规则:

- **先连通,再加载场景 skill**:`health_check` 的 transport 失败只走 `ios-connection`;成功后再按用户目标加载一个主 skill。不要因为 UI 可能跳转就提前读取 `ios-ui-nav`,也不要因为可能要证据就提前读取 `ios-ui-shot`。
- **结构化优先于视觉证据**:默认用 `ui_inspect` 判断当前页面、字段、按钮和终态。只有用户明确要截图、需要 bug 证据、或结构化结果不足以说明视觉问题时,才加载 `ios-ui-shot` 并调用 `ui_screenshot`。
- **异步动作交给等待 skill**:由动作所属 skill 触发操作，再路由到 `ios-ui-wait` 按明确成功/失败终态等待；入口不维护等待参数和业务判据模板。
- **日志交给日志 skill**:需要动作级日志证据时路由到 `ios-logs`，由它负责 mark、增量读取、capture 状态和结论分层；入口不复制日志读取策略。

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
| **异步表单提交后等待成功/失败** | `ios-ui-form` 提交 + `ios-ui-wait` 等待 | 表单 skill 负责触发，等待 skill 负责终态判定 |
| WKWebView JavaScript 执行、DOM 操作 | `ios-ui-webview` | 走 `ui_webView_eval`(script / function 两种模式) |
| 读 App 进程内日志、增量监控或日志断言 | `ios-logs` | 由运行时 `capture.state` 判断来源可用性 |
| UIDatePicker / UIPickerView 设值 | `ios-ui-picker` | 走 `ui.datePicker.setDate` / `ui.picker.selectRow`(非 inspect 能力) |
| 读业务源码产出测试判据清单 | `ios-test-intent`(L2) | 离线分析,不操作 App |
| 执行测试意图、跑覆盖报告 | `ios-test-runner`(L2) | 消费 `ios-test-intent` 的产出 |

**路由反模式**:把所有 UI 操作都串在 `ios-automation` 里直接调 `ui_tap` / `ui_input`。正确做法是路由到对应 `ios-ui-*`,让子 skill 处理顺序依赖、稳定等待、业务码判别。

## 关键参数

本 skill 入口阶段会用到这些静态能力；工具列表与 App 运行状态无关:

| 工具 | 含义 | 注意 |
|---|---|---|
| `health_check` | 验证 App 是否运行并可连接 | 快速连接验证的唯一工具 |
| `ui_inspect` | 读当前 UI 结构,签发 `viewSnapshotID` | 用于快速诊断,复杂调查路由给 `ios-ui-*` |
| `call_action` | 转发宿主私有/Debug/实验 action | 不替代稳定公共 UIKit / Diagnostics 静态工具 |
| `ui_tap_and_inspect` | 点击 + 等稳定 + inspect 一次完成 | 用于"点一下看看发生什么"的快速诊断 |
| 设备列表能力 | 列出模拟器或已连接设备 | MCP 依赖检测和设备上下文判断用 |

## 相关 skill

- `ios-mcp-setup`(L1 入口) — MCP 配置指引。MCP 工具不可用时提示用户参考此 skill 完成手动配置
- `ios-connection`(L1 入口) — 连接管理、iproxy、真机/模拟器差异、端口冲突诊断。`health_check` 失败或用户说"连不上"时路由到此
- 构建/设备管理 MCP（L0） — 需要 build / install / LLDB 调试 / 系统级日志时改用它,见"L0 vs L1 选择规则"
- `ios-ui-*`(L1) — 具体场景路由目标,见"路由到子 skill"
- `ios-logs`(L1) — 进程内日志的完整能力，包括增量读取、来源选择、capture 三态与分页；本 skill 只负责路由
- `ios-test-intent`(L2) — 读源码产出测试意图清单(离线分析)
- `ios-test-runner`(L2) — 执行测试意图闭环
