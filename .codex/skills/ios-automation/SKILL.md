---
name: ios-automation
description: iOS App 自动化测试 L1 统一入口。用于已接入 App 内 HTTP 自动化端点的 App 连接验证、模拟器/真机上下文判断、UI 检查、截图、日志读取和路由到 ios-ui-* / ios-logs / ios-test-* skills。Use when an agent needs an open-source, client-neutral entry point for iOS app automation over a debug HTTP automation endpoint.
---

# iOS 自动化操作统一入口(L1)

基于 iOSDriver MCP Server(封装目标 App 的 HTTP 自动化端点)与宿主 iOS App 的 HTTP 端点(`POST http://localhost:38321/`),作为 L1 操作层的统一入口。本 skill **本身不做复杂 UI 操作**,只负责三件事:**MCP 依赖检测**、**快速连接验证**(`health_check`)、**任务路由**(把请求分发给 `ios-ui-*` 与 `ios-logs` 子 skill)。连接问题路由到 `ios-connection`。

## 目标

解决"开发者/测试人员要操作一个已接入 App 内 HTTP 自动化端点的 iOS App,但不确定从哪里开始"这一入口问题。具体回答三个问题:

- **MCP 可用吗** — 检测 iOSDriver MCP 与构建/设备管理 MCP 是否已配置,不可用时给出配置提示并停止执行。
- **App 能连上吗** — 用 `health_check` 快速验证,成功继续路由,失败路由到 `ios-connection` 处理连接问题。
- **该用哪个子 skill** — 一张路由表把"用户说什么话 → 走哪个子 skill"对清楚,避免 agent 在 `ios-ui-*` 之间反复试。

**不做**:不构建 / 安装 / 调试 App 进程(走构建/设备管理 MCP 或项目中的 L0 构建调试流程);不直接驱动表单 / 列表 / 手势(走对应 `ios-ui-*` 子 skill);不处理 iproxy 管理 / 端口冲突 / 深度诊断(走 `ios-connection`)。

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
- ✅ 用户不确定该用 `ios-ui-*` 还是 L0 构建调试能力,需要先判 L0/L1
- ✅ 用户要快速看一眼当前 UI / 截图 / 弹窗状态(诊断,不是任务主体)
- ❌ 用户说"连不上 App"、"iproxy"、"端口 38321"、"Address already in use" → 路由到 `ios-connection`
- ❌ 用户要排查真机/模拟器连接差异、端口冲突 → 路由到 `ios-connection`

### 不适用场景
- ❌ 不要用于具体的表单填写 / 列表滚动 / 手势(直接走对应 `ios-ui-*`,本 skill 只在最前期不确定时介入)
- ❌ 不要用于构建 / 安装 / 启动模拟器 / LLDB 调试(走构建/设备管理 MCP 或项目 L0 流程,见"L0 vs L1 选择规则")
- ❌ 不要用于读源码出测试判据(`ios-test-intent`)或执行测试意图闭环(`ios-test-runner`)

## L0 vs L1 选择规则

这是入口最关键的决策:**目标 App 是否已接入 App 内 HTTP 自动化端点**(能通过 `health_check` 连接)。

| 条件 | 用哪一层 | 工具体系 |
|---|---|---|
| App 已接入 HTTP 自动化端点,`health_check` 通 | **L1**(本 skill + `ios-ui-*` + `ios-logs`) | iOSDriver |
| 需要 build / install / launch / LLDB 调试 | **L0**(构建/设备管理流程) | 构建/设备管理 MCP |
| 需要**系统级**日志(整个 App 控制台、其他进程) | **L0**(如模拟器系统日志采集能力) | 构建/设备管理 MCP |
| 需要**进程内精准**日志(按 source/level 过滤、可断言) | **L1**(`ios-logs` 的 `app.logs.*`) | iOSDriver |
| App**未接入** HTTP 自动化端点(`health_check` 连不上) | **L0**(先构建运行,或退回系统级 UI 自动化) | 构建/设备管理 MCP |

两套日志能力**互补,非冲突**:L0 抓系统/模拟器级(模拟器友好、覆盖整个控制台),L1 抓进程内精准(可按 `stdout`/`stderr`/`nslog`/`oslog`/`explore`/`bridge` 过滤、可做断言、真机 `oslog` 更全)。需要时同一会话可混用。

## MCP 依赖检测

本 skill 需要两个 MCP Server:

1. **iOSDriver MCP** (L1 层,已接入 HTTP 自动化端点的 App)
2. **构建/设备管理 MCP** (L0 层,构建/启动/调试;例如 Xcode 构建自动化 MCP)

### 启动时检测流程

执行本 skill 时必须按以下顺序检测 MCP 可用性:

1. **检测构建/设备管理 MCP** — 尝试列出模拟器或已连接设备
2. **检测 iOSDriver MCP** — 尝试调用 `health_check`
3. **工具调用本身不存在或无法发起** — 这才是 MCP Server 未配置或不可用;停止执行,提示用户参考 `ios-mcp-setup` skill 完成安装与配置,配置完成后重启当前 MCP 客户端并重新执行本 skill
4. **`health_check` 返回 `ok:false` 且错误来源是 `transport` / `connection_failed`** — iOSDriver MCP Server 已经可调用,但 App 的 `http://localhost:38321/` 端点当前不可达;不要说"MCP 不可用"或"真机不通",应路由到 `ios-connection` 启动/重启 App、确认 iproxy,然后重试 `health_check`
5. **两者都可用且 `health_check.ok == true`** — 继续执行快速连接验证流程

当检测到 MCP 不可用时,**不要尝试使用 curl 等底层命令或脚本替代 MCP 工具**。MCP 配置必须由用户手动完成,Agent 无法代劳。

## 快速连接验证

入口阶段做连接检查和设备类型识别:

1. **连接验证**:
   - 调用 iOSDriver 的 `health_check`
   - **成功** → App 已运行且可连接,继续任务路由(见"路由到子 skill")
   - **失败** → 路由到 `ios-connection` 处理连接问题

2. **设备上下文传递**:
   - 将识别的设备类型（真机/模拟器）作为上下文信息
   - 后续操作需要重启App时,真机走`launch_app_device`,模拟器走`launch_app_sim`
   - 若上下文未知,由 `ios-connection` 通过构建/设备管理 MCP 的设备列表和当前配置判别;不要只凭一次 `health_check` 失败断言"真机不通"

3. **动态工具暴露兜底**:
   - `health_check.ok == true` 且 `dynamicToolCount > 0` 表示 App 的 help 已读到,动态工具加载链路是通的
   - 部分 MCP 客户端会延迟展示动态工具。若当前只看到 `health_check` / `call_action`,不要立即判断其他工具不存在;先使用客户端提供的工具发现能力精确查找 `ui_inspect` / `ui_input` / `ui_tap` / `wait_and_inspect`
   - 精确检索后仍未暴露固定工具时,再使用 `call_action` 兜底: `action:"ui.inspect"` / `action:"ui.input"` / `action:"ui.tap"`,并在报告里记录"宿主未展示对应固定工具,已用 call_action 转发"
   - 当前 iOSDriver 也提供固定桥接工具 `ui_inspect` / `ui_input` / `ui_tap`,优先用固定工具;只有精确检索失败时才用 `call_action`

**不在此处理** iproxy 启动、设备同步、端口冲突等复杂场景,这些全部由 `ios-connection` 负责。

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
| WKWebView JavaScript 执行、DOM 操作 | `ios-ui-webview` | 走 `ui_webView_eval`(script / function 两种模式) |
| 读 App 进程内日志(stdout / stderr / nslog / oslog) | `ios-logs` | 含来源 × 平台可用性矩阵 |
| UIDatePicker / UIPickerView 设值 | `ios-ui-picker` | 走 `ui.datePicker.setDate` / `ui.picker.selectRow`(非 inspect 能力) |
| 读业务源码产出测试判据清单 | `ios-test-intent`(L2) | 离线分析,不操作 App |
| 执行测试意图、跑覆盖报告 | `ios-test-runner`(L2) | 消费 `ios-test-intent` 的产出 |

**路由反模式**:把所有 UI 操作都串在 `ios-automation` 里直接调 `ui_tap` / `ui_input`。正确做法是路由到对应 `ios-ui-*`,让子 skill 处理顺序依赖、稳定等待、业务码判别。

**异步提交场景路由规则**:
- 用户要"登录"、"注册"、"保存"等有网络请求的表单 → 先路由到 `ios-ui-form` 填写表单并点击提交按钮
- 提交后需要判断成功/失败 → 再路由到 `ios-ui-wait`,用 `wait_and_inspect` 或 `ui_waitAny` 等待明确判据
  - **成功判据示例**: 等待业务成功页的稳定 accessibility identifier,或等待成功文案出现
  - **失败判据示例**: 等待错误标签的稳定 accessibility identifier,或等待错误文案出现
  - 两个条件塞进 `ui_waitAny` 的 `conditions` 数组，先命中哪个就是哪个结果
- **不要**用 `ui_tap_and_inspect` + 固定 `stableTimeMs` 等异步操作（会读到 loading 中间态、浪费时间、无法区分成功/失败）

## 关键参数

本 skill 入口阶段会用到这些能力。不同客户端可能以固定工具、动态工具或 `call_action` 转发形式暴露它们:

| 工具 | 含义 | 注意 |
|---|---|---|
| `health_check` | 验证 App 是否运行并可连接 | 快速连接验证的唯一工具 |
| `ui_inspect` | 读当前 UI 结构,签发 `viewSnapshotID` | 用于快速诊断,复杂调查路由给 `ios-ui-*` |
| `call_action` | 动态工具未直接展示时兜底转发 action | 例如 `action:"ui.inspect"`;只作兜底,成功后仍按子 skill 语义继续 |
| `ui_tap_and_inspect` | 点击 + 等稳定 + inspect 一次完成 | 用于"点一下看看发生什么"的快速诊断 |
| `app_logs_read` | 读进程内日志 | 快速诊断用,完整能力见 `ios-logs` |
| 设备列表能力 | 列出模拟器或已连接设备 | MCP 依赖检测和设备上下文判断用 |

## 相关 skill

- `ios-mcp-setup`(L1 入口) — MCP 配置指引。MCP 工具不可用时提示用户参考此 skill 完成手动配置
- `ios-connection`(L1 入口) — 连接管理、iproxy、真机/模拟器差异、端口冲突诊断。`health_check` 失败或用户说"连不上"时路由到此
- 构建/设备管理 MCP（L0） — 需要 build / install / LLDB 调试 / 系统级日志时改用它,见"L0 vs L1 选择规则"
- `ios-ui-*`(L1) — 具体场景路由目标,见"路由到子 skill"
- `ios-logs`(L1) — 进程内日志的完整能力(`app_logs_mark` / 来源 × 平台矩阵 / `unavailable` 语义),本 skill 只用最基础的 `app_logs_read`
- `ios-test-intent`(L2) — 读源码产出测试意图清单(离线分析)
- `ios-test-runner`(L2) — 执行测试意图闭环
