# Skill 清单(状态真相源)

> 本文是 `.claude/skills/` 下全部 skill 的**权威状态表**。任何 skill 重写/新建/删除后必须同步更新本文件。规范依据:`docs/skills/design/2026-07-16-skills-architecture.md` §4.2;生命周期字段定义见 `conventions/lifecycle.md`。

---

## 1. 15 个保留 skill(按层)

> **状态总览(阶段 6 收尾)**:15 个 skill 全部重写/新建完成,spec §11 / plan G5 六条验证命令全 PASS(无空壳目录残留、`ui.controllers` 已迁入 `ios-ui-nav`、无 SPMExample 硬编码、`allowed-tools` 齐全、文件名统一为 `SKILL.md`、`ios-logs` 含 `capture.state` + `unavailable`)。健康度按 inventory §5 规则转 `healthy`。

| skill | 层 | 工具体系 | `allowed-tools` 概要 | 健康度 | 状态 | 备注 |
|---|---|---|---|---|---|---|
| `ios-debugger-agent` | **L0 构建调试** | XcodeBuildMCP | `build_run_sim` / `build_run_device` / `launch_app_*` / `start_sim_log_cap` / `describe_ui` | healthy | active | 全局 skill(`~/.claude/skills/`);完整定位与 L0/L1 选择规则见 `l0-build-debug.md`(规则原文抄自 `README.md` §2);本体仅在发现具体错误时改(Task 16 已只读检查,结论见 `l0-build-debug.md` §7) |
| `ios-automation` | **L1 入口** | iOSDriver + XcodeBuildMCP | `health_check` / `ui_inspect` / `ui_tap_and_inspect` / `app_logs_read` / `list_devices` | healthy | active | L1 总入口;精简职责:MCP检测、快速连接验证、任务路由;连接问题路由到 ios-connection、MCP配置路由到 ios-mcp-setup(2026-07-20 拆分) |
| `ios-mcp-setup` | **L1 入口** | 无(配置指引) | 无(纯文档 skill) | healthy | active | MCP 配置指引;从 ios-automation 拆分(2026-07-20);处理 iOSDriver MCP 与 XcodeBuildMCP 的安装、配置、验证;首次使用或工具不可用时路由到此 |
| `ios-connection` | **L1 入口** | iOSDriver + XcodeBuildMCP | `health_check` / `ui_inspect` / `list_devices` / `launch_app_*` / `stop_app_*` / `build_run_*` | healthy | active | 连接管理与诊断;从 ios-automation 拆分(2026-07-20);处理模拟器/真机差异、iproxy、设备同步、端口冲突、5种常见错误判别 |
| `ios-ui-nav` | **L1 操作层** | iOSDriver | `ui_inspect` / `ui_tap` / `ui_tap_and_inspect` / `ui_navigation_back` / `ui_navigation_tapBarButton` / `ui_controllers` / `ui_screenshot` / `ui_wait` / `call_action`(`ui.tabBar.selectTab`) | healthy | active | 原 `ios-navigation`,吸收原 `ios-controller-navigation` 的 `ui.controllers` 能力(plan Task 3 Step 4 + Task 4);**TabBar 切换**走 controller 层命令 `ui.tabBar.selectTab`(按 index/title 定位 + 可选触发 delegate,经 `call_action` 调用),用法见 `ios-ui-nav` SKILL.md §4 |
| `ios-ui-list` | **L1 操作层** | iOSDriver | `ui_inspect` / `ui_scroll` / `ui_scrollToElement` / `ui_swipe` / `ui_tap` / `ui_tap_and_inspect` / `ui_wait` | healthy | active | 原 `ios-list-interaction` |
| `ios-ui-form` | **L1 操作层** | iOSDriver | `ui_input` / `ui_tap` / `ui_tap_and_inspect` / `ui_control_sendAction` / `ui_keyboard_dismiss` / `ui_inspect` / `ui_scrollToElement` / `ui_screenshot` | healthy | active | 原 `ios-form-filling`;已删正文对 SPMExample deployment target 的提法;2026-07-19 新增 §7 UISearchBar 操作专节(输入/搜索/取消/清空完整流程 + 4 个场景示例 + 4 类常见错误处理 + SPMExample `SearchBarTestViewController` 测试页) |
| `ios-ui-picker` | **L1 操作层** | iOSDriver | `call_action`(`ui.datePicker.setDate` / `ui.picker.selectRow`) / `ui_inspect` / `ui_tap_and_inspect` / `ui_screenshot` | healthy | active | 2026-07-17 新建;`UIDatePicker` / `UIPickerView` 不在 `ui.inspect` 能力表(`ui.control.sendAction` 不支持设值),走专用命令设 date / selectRow 并触发 valueChanged / didSelectRow delegate;用法见 `ios-ui-picker` SKILL.md |
| `ios-ui-alert` | **L1 操作层** | iOSDriver | `ui_inspect` / `ui_alert_respond` / `ui_input` / `ui_tap_and_inspect` / `ui_wait` / `ui_screenshot` | healthy | active | 原 `ios-alert-handling` |
| `ios-ui-shot` | **L1 操作层** | iOSDriver | `ui_screenshot` / `ui_inspect` / `ui_wait` | healthy | active | 原 `ios-screenshot` |
| `ios-ui-gesture` | **L1 操作层** | iOSDriver | `ui_swipe` / `ui_longPress` / `ui_inspect` / `ui_wait` | healthy | active | 原 `ios-gestures`;**不含 drag**(`ui.drag` 不存在,Task 3 Step 5 删除) |
| `ios-ui-wait` | **L1 操作层** | iOSDriver | `ui_wait` / `ui_waitAny` / `wait_and_inspect` / `ui_inspect` | healthy | active | 原 `ios-dynamic-content`;补 wait/waitAny 真实用法(原 skill 标 not fully tested) |
| `ios-logs` | **L1 操作层** | iOSDriver | `app_logs_mark` / `app_logs_read` | healthy | active | 进程内日志读取;正文含来源可用性、`capture.state` 与 `unavailable` 语义 |
| `ios-test-intent` | **L2 测试闭环** | 离线源码分析 | `Read` / `Glob` / `Grep`(读 App 源码,**无 iOSDriver 调用**) | healthy | active | Task 13 通用化(方法论保留,样例占位化) |
| `ios-test-runner` | **L2 测试闭环** | iOSDriver + 源码分析 | `ui_waitAny` / `ui_inspect` / `ui_tap` / `ui_input` / `app_logs_read` / `app_logs_mark` | healthy | active | Task 14 解耦(去 UDID/bundle 硬编码)+ 加日志判据 capture 前置检查 |

> **健康度说明**:`healthy` = 结构完整(中文正文 + 中英 description + `allowed-tools` frontmatter + 解耦自检)+ spec §11 / plan G5 六条验证命令全 PASS。动态回归验证(真机/模拟器跑 SPMExample 登录案例)由 `examples/spmexample-login/` 提供 fixture,不计入 skill 本体耦合(见 `conventions/decoupling.md`)。

---

## 2. 已删除 skill(`removed`,历史记录)

以下 3 个 skill 已在本次重构决策中删除(spec §4.1、§12 风险与回退第 4 条、plan Task 3),`inventory.md` 保留行作历史,不允许重建(理由见 `conventions/naming.md` §6)。

| skill | 原层 | 删除原因 | 决策依据 |
|---|---|---|---|
| `ios-date-picker` | (原 L1) | 承诺的 `ui.datePicker.*` / `ui.picker.*` action 在 iOSDriver MCP 根本不存在,skill 自标 NOT TESTED,实际无法成功调用 | spec §1 问题 2、§4.1、plan Task 3 Step 3。**2026-07-17 更新**:`ui.datePicker.setDate` / `ui.picker.selectRow` 已在 iOSExploreServer 实现,作为 `ios-ui-picker` 重建(见 §1);本行保留为历史删除记录,`ios-date-picker` 旧名不再使用 |
| `ios-table-actions` | (原 L1) | 承诺的 `ui.table.*` / `ui.collection.*` action 在 iOSDriver MCP 不存在,同上空壳 | spec §1 问题 2、§4.1、plan Task 3 Step 3 |
| `ios-controller-navigation` | (原 L1) | 能力单一(核心是 `ui.controllers` 读层级树),自标 EXPERIMENTAL 长期未补测试;`ui.controllers` 能力已并入 `ios-ui-nav`(plan Task 3 Step 4,Task 4 Step R1 整合) | spec §4.1、plan Task 3 Step 4 |

> 删除无功能损失:`ios-date-picker` / `ios-table-actions` 承诺的命令不存在,实际无人能成功调用(spec §12 第 4 条);`ios-controller-navigation` 的 `ui.controllers` 能力完整迁入 `ios-ui-nav`,验证命令 `grep 'ui.controllers' .claude/skills/ios-ui-nav/SKILL.md` 必须非空(spec §11)。

---

## 3. 按工具体系分组(快速索引)

### 3.1 XcodeBuildMCP(L0)

- `ios-debugger-agent`(全局)

### 3.2 iOSDriver(L1 操作层 + L2 测试闭环)

| 类型 | skill |
|---|---|
| 入口 | `ios-automation` / `ios-mcp-setup` / `ios-connection` |
| UI 操作 | `ios-ui-nav` / `ios-ui-list` / `ios-ui-form` / `ios-ui-picker` / `ios-ui-alert` / `ios-ui-shot` / `ios-ui-gesture` / `ios-ui-wait` |
| 进程日志 | `ios-logs` |
| 测试闭环 | `ios-test-intent`(离线) / `ios-test-runner`(在线) |

### 3.3 离线源码分析(L2)

- `ios-test-intent`(用 `Read` / `Glob` / `Grep`,**不调用 iOSDriver**)

---

## 4. 计数核对

- **保留**:`1 (L0) + 12 (L1,含入口) + 2 (L2) = 15` 个(spec §4.2;2026-07-17 新增 `ios-ui-picker`;2026-07-20 新增 `ios-connection` + `ios-mcp-setup`)
- **删除**:`ios-date-picker` + `ios-table-actions` + `ios-controller-navigation` = 3 个
- **净结果**:`14 → 12`(删 2 空壳 + 合并 1 + 新增 `ios-logs`,spec §4.1 末段);2026-07-17 新增 `ios-ui-picker`(`ui.datePicker.setDate` / `ui.picker.selectRow` 已实现),`12 → 13`;2026-07-20 从 `ios-automation` 拆分 `ios-connection` + `ios-mcp-setup`(连接管理 + MCP配置),`13 → 15`

---

## 5. 更新规则

- 每次 skill 重写/新建/删除后必须更新本文件(plan Task 3 / Task 4–14 / Task 18 都涉及)。
- 状态转移规则见 `conventions/lifecycle.md` §5(状态不能"卡住",`experimental` 与 `deprecated` 都有 1 迭代上限)。
- `allowed-tools` 列与 skill 正文实际 frontmatter 必须一致(由 plan G5 命令 1 验证)。
