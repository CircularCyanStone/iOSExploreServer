# L0 构建调试定位(`ios-debugger-agent`)

> 本文件是三层架构(spec §3)里 **L0 构建调试层** 的定位文档。它回答四个问题:`ios-debugger-agent` 是什么、负责什么、和 L1 的 UI 能力有何交集、什么时候该用它而不是 L1。规范依据:`design/2026-07-16-skills-architecture.md` §3;三层全景见 `README.md`。

---

## 1. 它是什么

`ios-debugger-agent` 是一个**全局 skill**,位于 `~/.claude/skills/ios-debugger-agent/`(不在本仓库的 `.claude/skills/`)。它跨项目存在,改它会影响其他仓库,因此本仓库只写定位,不轻易改本体(见末尾「全局 skill 本体检查结论」)。

- **工具体系**:XcodeBuildMCP(`mcp__XcodeBuildMCP__*`)。
- **一句话职责**:把 App 编译、安装、跑起来,挂在调试器上,并捕获系统级日志。
- **所属层**:L0 构建调试层(三层里唯一用 XcodeBuildMCP 的层)。

它与 L1 操作层(项目级 `.claude/skills/ios-ui-*` + `ios-logs` + 入口 `ios-automation`,用 iOSDriver)的**工具体系互不重叠**,但 **UI 能力有交集**(见 §3)。

---

## 2. L0 负责/不负责什么

### 负责

1. **构建**:编译当前 scheme(`build_sim` / `build_device`)。
2. **安装 + 启动**:一次性 `build_run_sim` / `build_run_device`,或仅安装 `install_app_*` + 仅启动 `launch_app_*`(后者可注入 `env` / `launchArgs`,这是 `build_run_*` 不做的)。
3. **调试进程**:LLDB 附着、断点、栈/变量检查(`debug_attach_sim` / `debug_breakpoint_*` / `debug_stack` / `debug_variables` / `debug_lldb_command`)。
4. **系统级日志**:`start_sim_log_cap` / `stop_sim_log_cap`——模拟器/系统侧捕获整个 App 控制台(含 stdout/stderr/系统日志),模拟器友好。
5. **会话配置**:`session_set_defaults` 设工程/scheme/设备,`session_show_defaults` 核对,`list_sims`/`list_devices`/`discover_projs`/`list_schemes` 发现目标。

### 不负责(交给 L1)

- **操作已运行 App 的精细 UI**:`ui_inspect` 的 `viewSnapshotID` 指纹签发、`ui_tap`/`ui_input`/`ui_alert_respond`/`ui_navigation_*`/`ui_scroll*`/`ui_swipe`/`ui_longPress` 等 HTTP 命令——这些是 L1 `ios-ui-*` 的领域,基于 iOSExploreServer 的 `ui.*` 协议。
- **App 进程内精准日志**:`app.logs.mark` / `app.log.read`(可按 source/level 过滤、可做断言)——L1 `ios-logs` 的领域(iOSExploreDiagnostics)。

---

## 3. 与 L1 的 UI 能力交集(为什么需要选择规则)

L0 也含 UI 操作,但**工具体系不同**:

| 维度 | L0 `ios-debugger-agent` | L1 `ios-ui-*` |
|---|---|---|
| 工具体系 | XcodeBuildMCP | iOSDriver(封装 iOSExploreServer HTTP) |
| UI 快照 | `snapshot_ui`(accessibility snapshot,给 elementRef;旧名 `describe_ui` 已改名) | `ui_inspect`(给 `viewSnapshotID` 指纹,带 availableActions/cell indexPath) |
| 点击/输入 | `tap` / `type_text` | `ui_tap` / `ui_input` / `ui_tap_and_inspect` |
| 手势/截图 | `gesture` / `screenshot` / `swipe` / `long_press` | `ui_swipe` / `ui_longPress` / `ui_screenshot` |
| 弹窗/导航 | 无专项命令(靠 `tap` 通用) | `ui_alert_respond` / `ui_navigation_back` / `ui_navigation_tapBarButton` |
| 前提 | 只要 App 能在模拟器/真机跑起来 | **必须已集成 iOSExploreServer**(能 `curl http://localhost:38321/`) |

交集意味着:L0 也能点、能输、能截图,因此**不能简单认为「L0 只管构建、L1 只管 UI,职责互不重叠」**。需要下面的选择规则。

---

## 4. L0/L1 选择规则(抄 spec §3)

**判据是「App 是否已集成 iOSExploreServer」**,不是「要不要碰 UI」:

- 目标 App **已集成 iOSExploreServer**(能 `curl http://localhost:38321/` 成功,返回 `{"code":"ok","data":{"pong":true}}`)
  → **优先 L1** 的 `ios-ui-*` + `ios-logs`。
  - 理由:更精准(`ui_inspect` 的 `viewSnapshotID` 带陈旧校验、cell 用 indexPath 定位)、可按 source/level 过滤日志、可做日志断言、有 `ui_alert_respond`/`ui_navigation_*` 等专项命令。
- 需要**构建/安装/调试进程**、抓**系统级日志**,或 App **未集成** iOSExploreServer
  → **用 L0** 的 `ios-debugger-agent`。
  - 典型场景:第一次把 App 跑起来、App 还没集成 server、要下断点查崩溃、要看 Xcode 控制台全量输出。

### 典型组合(本项目)

本仓库的 `Examples/SPMExample` **已集成** iOSExploreServer,所以常态是 **L0 起进程 + L1 操作 UI/读日志**:

1. L0:`session_use_defaults_profile("sim-app")` → `build_run_sim()`(或 `device-app` profile 走真机 + `iproxy`)。
2. L1:`curl http://localhost:38321/` 确认 `pong` → 走 `ios-automation` 入口路由到 `ios-ui-*` / `ios-logs`。

真机还需运行 `iproxy 38321 38321` 做 USB 转发,模拟器与 Mac 共享 localhost 不需要。本项目的三个 profile(`sim-app` / `sim-fw` / `device-app`)与四个易踩的坑(设备 ID 两套、机型字段串号、`build_run_*` 不注入 env、curl 前先 `lsof` 确认是 iproxy)详见 `AGENTS.md`「XcodeBuildMCP 运行配置」与「四个必须记住的差异」,此处不重复。

---

## 5. L0 关键工具清单

| 用途 | 模拟器 | 真机 |
|---|---|---|
| 构建 + 安装 + 启动 | `build_run_sim` | `build_run_device` |
| 仅启动(可带 env/launchArgs) | `launch_app_sim` | `launch_app_device` |
| 仅安装 | `install_app_sim` | `install_app_device` |
| 仅构建 | `build_sim` | `build_device` |
| 系统级日志 | `start_sim_log_cap` / `stop_sim_log_cap`(⚠️ 需 `enabledWorkflows` 含 `logging`,本仓库当前未启用) | (真机日志另走 `iproxy` + L1 `app.logs.*`) |
| UI 快照(交集能力) | `snapshot_ui`(旧名 `describe_ui` 已改名) | 同模拟器 |
| UI 交互(交集能力) | `tap` / `type_text` / `gesture` / `screenshot` | 同模拟器 |
| LLDB 调试 | `debug_attach_sim` / `debug_breakpoint_add` / `debug_stack` / `debug_variables` / `debug_lldb_command` | (真机调试见 XcodeBuildMCP device 配置) |
| 发现/配置 | `list_sims` / `list_devices` / `discover_projs` / `list_schemes` / `session_set_defaults` / `session_show_defaults` | 同 |

> `build_run_*` 与 `launch_app_*` 的关键差异(本项目踩过坑):**`build_run_*` 不注入 session default 的 `env`**;要驱动 autostart 或传启动参数,必须用 `launch_app_*(env/launchArgs)`,且已运行的 App 不会重启,需先 `stop_app_*` 再 `launch_app_*`。

---

## 6. 两套日志能力的关系(互补,非冲突)

L0 和 L1 各有一套日志能力,定位不同,不冲突:

- **L0 `start_sim_log_cap`**:系统/模拟器级捕获,抓**整个 App 控制台**(stdout/stderr/系统日志),模拟器友好。粒度粗,适合「App 有没有报错、控制台整体输出」。
- **L1 `app.logs.*`(iOSExploreDiagnostics)**:App 进程内**精准**捕获,可按 source(`stdout`/`stderr`/`nslog`/`oslog`/`explore`/`bridge`)与 level 过滤、可做断言。粒度细,适合「这条业务路径有没有打日志、按来源判别」。真机 `oslog` 更全,模拟器可能受系统可见性限制。

选哪套同样服从 §4 的总规则:已集成 server → 优先 L1 的 `app.log.*`(可断言、可过滤);未集成或要看全量控制台 → L0 `start_sim_log_cap`。

---

## 7. 全局 skill 本体检查结论(只读检查,未改动全局文件)

本节是 Task 16 对 `~/.claude/skills/ios-debugger-agent/SKILL.md` 的**只读检查结论**。按 brief 约束,本 task **不修改、不 commit 全局文件**,只把发现记录在此,供后续决定是否单独开 task 修。

### 检查结果:无「引用不存在的工具」级别的硬错误,有两处需复核

1. **所有引用的工具都对应真实 XcodeBuildMCP 能力**:`build_run_sim` / `launch_app_sim` / `list_sims` / `get_sim_app_path` / `get_app_bundle_id` / `tap` / `type_text` / `gesture` / `screenshot` / `start_sim_log_cap` / `stop_sim_log_cap` 均为真实命令,职责描述与工具实际行为一致。**未发现** 类似已删空壳 skill(`ios-date-picker` 引用 `ui.datePicker.*`)那样的「承诺不存在的能力」。

2. **(已确认并修复)UI 快照工具名 `describe_ui`→`snapshot_ui`**:当前 XcodeBuildMCP 版本的 UI 语义快照工具注册名是 **`snapshot_ui`**(返回带 elementRef 的 rs/1 运行快照),`describe_ui` 已不存在(版本改名,经当前会话工具集确认)。本次 followup 已把全局 skill 的 `describe_ui` 全部改为 `snapshot_ui`;本文档 §3/§5 也已统一为 `snapshot_ui`(注明旧名)。

3. **(命名精度,非硬错误)`session-set-defaults` 连字符**:全局 skill 写 `mcp__XcodeBuildMCP__session-set-defaults`(连字符),实际注册名是下划线 `session_set_defaults`。Claude Code 对 MCP 工具名解析较宽松,实战可用,但与注册名不一致。若日后统一精度,改成下划线更准确。

4. **(范围缺口,非错误)全局 skill 只覆盖模拟器**:全局 skill 正文只讲 `build_run_sim` / `launch_app_sim` / `list_sims`,**未覆盖真机**(`build_run_device` / `launch_app_device` / `iproxy` USB 转发)与 **LLDB 调试**(`debug_attach_sim` 等)。这是范围比本定位文档窄,不是「错误」——全局 skill 面向所有项目,保持精简合理;真机与调试在本仓库由 `AGENTS.md`「XcodeBuildMCP 运行配置」补齐。无需改全局 skill。

**结论(本次 followup 已修)**:全局 `ios-debugger-agent/SKILL.md` 的过时工具名已修——`describe_ui`→`snapshot_ui`(已确认版本改名)、`session-set-defaults`→`session_set_defaults`(下划线);另发现 `start_sim_log_cap`/`stop_sim_log_cap` 在当前配置未暴露(`enabledWorkflows` 未含 `logging`),已在全局 skill 加标注提示改用 L1 `ios-logs`。本仓库的 L0 定位以本文档为准。

---

## 8. 相关文件

- 三层架构总览 + L0/L1 选择规则:`README.md` §1–§2
- 12 个 skill 权威状态表(含 L0 行):`inventory.md` §1
- 设计 spec(权威,§3 是选择规则出处):`design/2026-07-16-skills-architecture.md`
- 本项目真机/模拟器跑法与四个坑:`AGENTS.md`「XcodeBuildMCP 运行配置」+「四个必须记住的差异」
