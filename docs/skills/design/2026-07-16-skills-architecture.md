# iOSExplore Skill 体系架构设计

- **日期**:2026-07-16
- **状态**:设计待评审 → 评审通过后进入实施计划(writing-plans)
- **范围**:`.claude/skills/` 下全部项目级 skill + 全局 `ios-debugger-agent` 的定位梳理 + `docs/skills/` 管理目录建立
- **前置背景**:本仓库的 skill 体系经过多轮迭代后，需要一份正规设计 spec 承载最终分层、命名、生命周期和解耦规则。本文件作为后续所有 skill 构建、精简、测试、废弃的基线。

---

## 1. 为什么要重构(现状问题摘要)

经逐文件审计(13 个项目级 skill + 1 个全局 skill + 全部历史文档),确认以下结构性问题:

1. **两套工具体系混叫同一个前缀**:全局 `ios-debugger-agent` 用 XcodeBuildMCP(构建/运行/调试),13 个项目级 skill 用 iOSDriver(驱动 UI)。都叫 `ios-*`,职责描述重叠,是"搞不清各自干嘛"的根因。
2. **空壳 skill 承诺不存在的能力**:`ios-date-picker`(`ui.datePicker.*`/`ui.picker.*`)、`ios-table-actions`(`ui.table.*`/`ui.collection.*`)、`ios-gestures` 的 `ui.drag`——这些 action 在 iOSDriver MCP 里**根本没有**,skill 实际退化成 `ui.swipe`/`ui.longPress`,却对外宣称专项能力。
3. **与示例 App(SPMExample)耦合集中在 3 个 skill**:`ios-test-runner`(重度,写死模拟器 UDID)、`ios-test-intent`(重度,整篇钉在登录源码)、`ios-automation`(中度,诊断流程写死 `com.coo.SPMExample`)。其余 10 个其实不耦合。SPMExample 实际长期充当 skill 的私有测试夹具,身份错位。
4. **手搓而非 skill-creator**:13 个 frontmatter 都只有 `name`+`description`,缺 `allowed-tools`;10 个英文 skill 用一套手写膨胀模板(单文件 549–745 行,`ios-gestures` 甚至有两组重复小节)。
5. **目标漂移未说清**:前 5 轮是"人手动驱动各场景 skill",第 6 轮转"意图清单→自动跑→覆盖报告"闭环。两种使用哲学并存,关系从未定义。
6. **索引与文档脱节**:`ios-automation-skills-index.md` 认 10 个 skill,实际 13 个;最新最活跃的 `ios-test-intent`/`ios-test-runner` 没进索引;docs 顶层与 `reports/2026-07-13-14-skills-creation-project/` 成片重复。

---

## 2. 设计目标与非目标

### 目标
- **三层职责清晰**:看 skill 所属层即知其工具体系与职责,消除"都叫 ios-*"的混淆。
- **完全通用**:每个 skill 对"任意集成了 iOSExploreServer 的 iOS App"都直接可用,不绑死 SPMExample。
- **可参与**:正文全中文,description 中英混合,开发者能读懂、参与构建与评审。
- **正规化**:全部走 skill-creator 规范(frontmatter 完整、结构精炼、带 evals)。
- **只承诺真实能力**:删空壳、合并重叠,留下的每个 skill 都对应 iOSDriver 真实存在的 action。
- **单一管理入口**:skill 的设计、规范、清单、案例、归档全部收敛到 `docs/skills/`。

### 非目标(本次不做)
- 不改 iOSExploreServer / iOSExploreUIKit / iOSExploreDiagnostics 的**源码与协议**(本次只重组 skill 与文档)。空壳 skill 缺失的 action(`ui.datePicker.*` 等)不在此期实现,直接删 skill。
- 不改 `.mcp.json` 注册的 MCP server(iOSDriver)。
- 不改 iOSExploreServer 的对外 HTTP 协议。
- 不删除 SPMExample 工程本身(它仍是 iOSExploreServer 的集成示例 App)。

---

## 3. 三层职责架构

调用关系单向:`L0 把 App 跑起来 → L1 操作 App UI / 读进程日志 → L2 编排 L1 跑测试闭环`。三层**工具体系**互不重叠(L0 用 XcodeBuildMCP,L1/L2 用 iOSDriver)。

> **注意 UI 能力交集**:L0 的 `ios-debugger-agent` 正文也含 UI 操作(`describe_ui`/`tap`/`type_text`/`screenshot`,基于 XcodeBuildMCP 的 accessibility snapshot),与 L1 的 `ios-ui-*`(基于 iOSDriver 的 `ui.*` HTTP 命令)在 UI 能力上有交集,只是工具体系不同。因此需要一条选择规则(见下),不能简单认为"职责互不重叠"。

**L0 vs L1 选择规则**:
- 目标 App **已集成 iOSExploreServer**(能 `curl http://localhost:38321/` 成功)→ 优先 L1 的 `ios-ui-*` + `ios-logs`(更精准、可按 source/level 过滤、可做日志断言)。
- 需要**构建/安装/调试进程**、抓系统级日志,或 App**未集成** iOSExploreServer → 用 L0 的 `ios-debugger-agent`。

| 层 | 工具体系 | 职责(一句话) | 包含 skill |
|---|---|---|---|
| **L0 构建调试** | XcodeBuildMCP(`mcp__XcodeBuildMCP__*`) | 编译、运行、启动、调试 App 进程,捕获系统级日志 | `ios-debugger-agent`(全局) |
| **L1 操作层** | iOSDriver(`mcp__iOSDriver__*`,封装 iOSExploreServer HTTP) | 操作已运行 App 的 UI 与读取进程内日志 | 7 个 `ios-ui-*` + `ios-logs` + 入口 `ios-automation` |
| **L2 测试闭环** | iOSDriver + 离线源码分析 | 读业务源码产出测试判据 → 自动驱动 UI 跑 → 出覆盖报告 | `ios-test-intent` + `ios-test-runner` |

**两套日志能力的关系(互补,非冲突)**:
- L0 `start_sim_log_cap`:系统/模拟器级捕获,模拟器友好,抓整个 App 控制台。
- L1 `app.logs.*`(iOSExploreDiagnostics):App 进程内精准捕获,可按 source/level 过滤、可做断言;真机 `oslog` 更全,模拟器受限(见 §7)。

---

## 4. 重构后 skill 全景(12 个)

### 4.1 当前 → 重构后 映射

| 当前 skill | 处理 | 重构后名称 | 所属层 |
|---|---|---|---|
| ios-navigation(745行) | 留,精简,吸收 controller-nav | `ios-ui-nav` | L1 |
| ios-controller-navigation(133行) | **并入 `ios-ui-nav` 的"controller 层级检查"小节**(能力单一,核心是 `ui.controllers` 读层级树;与 navigation 的屏幕导航操作**不重叠**,但因自标 EXPERIMENTAL、能力单一,不单独成 skill) | —(并入 `ios-ui-nav`) | — |
| ios-list-interaction(719行) | 留,精简 | `ios-ui-list` | L1 |
| ios-form-filling(703行) | 留,精简 | `ios-ui-form` | L1 |
| ios-screenshot(613行) | 留,精简 | `ios-ui-shot` | L1 |
| ios-alert-handling(595行) | 留,精简 | `ios-ui-alert` | L1 |
| ios-gestures(549行) | 留,删 `ui.drag`、删重复小节、精简 | `ios-ui-gesture` | L1 |
| ios-dynamic-content(321行) | 留,补 wait 验证说明 | `ios-ui-wait` | L1 |
| ios-date-picker(158行) | **删**(命令 `ui.datePicker.*`/`ui.picker.*` 不存在) | — | — |
| ios-table-actions(214行) | **删**(命令 `ui.table.*`/`ui.collection.*` 不存在) | — | — |
| ios-automation(400行,入口) | 留,去 SPMExample 硬编码 | `ios-automation` | L1 入口 |
| *(iOSExploreDiagnostics 能力)* | **新增** | `ios-logs` | L1 |
| ios-test-intent(209行) | 留,样例通用化 | `ios-test-intent` | L2 |
| ios-test-runner(280行) | 留,去写死的 UDID/bundle,日志判据加 capture 前置检查 | `ios-test-runner` | L2 |
| ios-debugger-agent(全局) | 留,纳入分层定位,不改名 | `ios-debugger-agent` | L0 |

**净结果:14 个 → 12 个**(删 2 空壳 + 合并 1 + 新增 `ios-logs`)。

### 4.2 重构后清单(按层)

**L0(1 个,XcodeBuildMCP)**
- `ios-debugger-agent` — 构建/运行/调试 App 进程,系统级日志。

**L1 操作层(9 个,iOSDriver)**
- `ios-automation` — 总入口:连接管理、iproxy、路由到子 skill、快速诊断。
- `ios-ui-nav` — 屏幕导航、返回、导航栏按钮;含 controller 层级树读取(`ui.controllers`,吸收原 controller-navigation)。
- `ios-ui-list` — 列表/集合视图查找、滚动、选中。
- `ios-ui-form` — 文本输入、开关、滑块、步进器、分段、提交。
- `ios-ui-alert` — alert/action sheet/dialog 检测与响应。
- `ios-ui-shot` — 截图、视觉验证、前后对比。
- `ios-ui-gesture` — swipe、long press(不含 drag)。
- `ios-ui-wait` — 等待动态内容/loading/异步状态。
- `ios-logs` — 读 App 进程内日志(`app.logs.mark`/`app.logs.read`),含来源可用性矩阵。

**L2 测试闭环(2 个,iOSDriver + 源码分析)**
- `ios-test-intent` — 离线读 App 业务代码,产出 per-scenario pass/fail 判据清单。
- `ios-test-runner` — 消费判据清单,驱动 UI 跑测试,出覆盖报告。

---

## 5. 命名与分组规则

- **L1 操作层**用两个子前缀区分能力类型:
  - `ios-ui-*`(7 个):纯 UI 操作(tap/input/alert/nav/list/shot/gesture/wait)。
  - `ios-logs`(1 个):进程日志读取(非 UI,单独命名)。
  - `ios-automation`:L1 总入口(不加 `-ui-`,因为统领 UI + 日志)。
- **L2**:`ios-test-*`。
- **L0**:`ios-debugger-agent`(保留原名;它是全局 skill,改名影响其他项目,本次不动)。
- **过渡**:改名后旧名触发短期失效,通过在新 description 里保留旧名关键词(如 `"原 ios-form-filling"`)缓解,过渡期一个迭代后移除。
- Claude Code skill 以目录名为 skill 名,子目录(除 `evals/` 等约定子目录)不会被识别为独立 skill,**不支持用子目录分组**;因此分组靠命名前缀 + `docs/skills/inventory.md`,不靠目录嵌套。

---

## 6. 语言与 skill-creator 规范

### 语言
- **正文全中文**(开发者能读懂、参与构建)。
- **description 中英混合**:中文说清用途 + 英文关键词保证触发。示例:
  - `"iOS App 表单填写与控件操作 / form filling, text input, switch, slider, stepper"`
  - `"读取 iOS App 进程内日志 / app logs, stdout, stderr, nslog, oslog, debug"`
  - 纯中文 description 在英文 prompt 下触发率下降,混合最稳。

### skill-creator 规范(每个 skill 必须满足)
- frontmatter 含 `name`、`description`,**补 `allowed-tools`**(列出该 skill 用的 MCP 工具,如 `mcp__iOSDriver__ui_input`, `mcp__iOSDriver__ui_tap_and_inspect`)。
- 正文用精炼结构(目标 ~150–250 行/skill):Purpose → When to use → How it works → 关键参数 → 常见错误与判别 → Related skills。删除当前膨胀的重复参数表与冗长示例。
- 保留并解耦每个 skill 的 `evals/evals.json`。
- 用 skill-creator 生成/重写,不手搓。

### evals 策略(skill 本体解耦 ≠ evals 不能用 SPMExample)
- **静态结构 evals**(每个 skill 必须有,不依赖运行 App):检查 frontmatter 含 `allowed-tools`、正文无 SPMExample 硬编码(§8 硬规则全过)、引用的 action 在 iOSDriver 真实存在。
- **动态回归 evals**(需要真实运行的 App):仓库内唯一可用的是 SPMExample,作为**参考 fixture** 由 `docs/skills/examples/spmexample-login/` 提供;evals 引用 examples 里的案例**不算 skill 本体耦合**。
- 即:`ios-ui-form` 的 `SKILL.md` 正文不许出现 `test/123456`,但它的动态 evals 可以驱动 SPMExample 表单验证输入流程——前者管 skill 通用性,后者是测试夹具。本次**不新建"占位 App"**(仓库内无其他集成 App,成本不值)。

---

## 7. 日志能力(`ios-logs`)设计

`ios-logs` 是 L1 中与 `ios-ui-*` 平级的能力,封装 `iOSExploreDiagnostics` 的两个命令。

### 命令
- `app.logs.mark` — 建立日志检查点,返回 `cursor`。
- `app.logs.read` — 增量读取进程内日志,参数 `after`(cursor)/`limit`(1–500)/`sources`/`minimumLevel`。

### 6 个 source

| source | 含义 | 默认 | 开启方式 |
|---|---|---|---|
| `explore` | iOSExploreServer 内部日志 | 开 | `captureExploreLogs`(默认 true) |
| `bridge` | App 调 `ESAppLogger.emit(...)` 主动写 | 开 | `enableBridge`(默认 true,最稳定) |
| `stdout` | `print` 等 | 关 | `captureStdout` |
| `stderr` | 错误输出(level 固定 error) | 关 | `captureStderr` |
| `nslog` | `NSLog` | 关 | `captureNSLog` |
| `oslog` | `os_log` / Swift `Logger` | 关 | `captureOSLog` |

### 来源 × 平台 可用性矩阵(必须写进 skill)

| source | 模拟器 | 真机 | 依据 |
|---|---|---|---|
| `explore` / `bridge` | ✅ 可用 | ✅ 可用 | 纯内存,不依赖系统 |
| `stdout` / `stderr` | ✅ 可用 | ✅ 可用 | fd 接管(dup2),进程级 |
| `nslog` | ⚠️ 依赖系统实现 | ⚠️ 依赖系统实现 | 依赖 `NSLog` 是否落到 stderr 或可被 `OSLogStore` 读取,由系统实现决定;以 `capture.state` 为准 |
| `oslog` | ⚠️ 依赖系统权限 | ⚠️ 依赖系统权限 | 依赖系统是否允许当前进程读 `OSLogStore`(需 iOS 15+/macOS 12+);**源码无模拟器特殊分支**,以 `capture.state` 为准 |

> **⚠️ 不要把"模拟器/真机"写成确定的平台断言**。`ESUnifiedLogCapture.swift` 的 oslog 逻辑只判断"系统是否允许当前进程读 `OSLogStore` + iOS 15+/macOS 12+",**没有模拟器特殊分支**;模拟器跑的是真实 iOS 内核,`OSLogStore(.currentProcessIdentifier)` 能否读取取决于系统权限而非"模拟器一定不行"。实施前必须在模拟器与真机各实测一次 `app.logs.read`(sources:`["oslog"]`、`["nslog"]`)填入实际观察;skill 正文统一教 agent 读 `capture.state` 判断,不按平台假设。

### `unavailable` 语义(必须强调)
`app.logs.mark`/`read` 返回的 `capture` 字段有三态:
- `enabled` — 已安装正在写,可读。
- `notCaptured` — 配置没开(非失败,需打开对应 capture 重启 App)。
- `unavailable` — **配置开了但系统/安装不允许(如模拟器读 OSLogStore 被拒)。这不等于"日志没发生",而是"系统不让当前进程读"。**

**skill 必须教 agent**:读不到某 source 时,先看 `capture.state`,不要把 `unavailable`/`notCaptured` 误判成"代码没执行"。

### 与 L2 的衔接
`ios-test-runner` 用 `app.logs.read` 做断言时,必须前置检查对应 source 的 `capture.state`:
- 只有 `enabled` 的 source 才能作为有效日志判据。
- 模拟器上 `oslog` 判据自动降级(跳过或改用 `bridge`/`stdout`,要求被测 App 在关键点 `ESAppLogger.emit`)。

---

## 8. 与示例 App(SPMExample)解耦规则

**身份重申**:SPMExample 是 iOSExploreServer 的**集成示例 App**,不是任何 skill 的私有测试夹具。

### 硬规则(skill 本体禁止出现)
- 真实 bundle id(`com.coo.SPMExample`)。
- 真实模拟器 UDID / USB UDID(如 `065CC8DB-...`、`00008030-...`)。
- 测试账号(`test`/`123456`)。
- SPMExample 专属启动参数作为固定流程(如把 `--ios-explore-show-login` 写成必备步骤)。
- SPMExample 源码具体行号/类名作为 skill 通用示例。

### 解耦动作(定点)
| skill | 动作 |
|---|---|
| `ios-test-runner` | 正文报告样例改占位(`<your-simulator-udid>`、`<your.app.bundleid>`);SPMExample 登录完整真实案例移到 `docs/skills/examples/spmexample-login/` |
| `ios-test-intent` | 方法论保留(读 Service/VM/VC 产出判据),通用示例改占位 App;SPMExample 登录作为案例移到 examples |
| `ios-automation` | 诊断清理命令改占位 bundle id;登录示例改通用占位 |
| 其余 10 个 | 无耦合,无需动 |

### SPMExample 案例的归属
SPMExample 登录流程(意图清单 + 实跑报告)作为"如何对真实 App 套用 test-intent/runner"的**完整参考案例**,放在 `docs/skills/examples/spmexample-login/`,不进 skill 本体。这样既保留来之不易的实测数据,又不污染 skill 通用性。

同时,现存的 `docs/test-intents/spmexample-login.json` 与 `docs/test-reports/spmexample-login-run.json` 随案例迁入 `docs/skills/examples/spmexample-login/`;`docs/test-intents/`、`docs/test-reports/` 原目录保留为通用目录(后续非 SPMExample 的意图清单/报告也写这里)。

---

## 9. `docs/skills/` 管理目录结构

`docs/skills/` 作为 skill 体系**唯一**管理入口(本设计已建 `design/`、`conventions/`、`examples/` 骨架,实施时补齐其余文件)。

```
docs/skills/
├── README.md                 # 三层架构总览 + skill 索引 + 状态表(看这一个文件懂全貌)
├── inventory.md              # 全部 skill 清单:层/工具/健康度/测试状态/废弃记录
├── design/
│   └── 2026-07-16-skills-architecture.md   # 本文件
├── conventions/
│   ├── skill-template.md     # skill-creator 中文模板(正文中文+中英 description+allowed-tools)
│   ├── naming.md             # 命名/分组前缀规则
│   ├── decoupling.md         # 与示例 App 解耦硬规则(对应 §8)
│   └── lifecycle.md          # EXPERIMENTAL 挂账上限与废弃标准(解决空壳长期挂账)
├── examples/
│   └── spmexample-login/     # SPMExample 登录真实案例(意图清单+实跑报告)
```

---

## 10. 迁移阶段(实施计划展开时的骨架)

1. **基建**:建 `docs/skills/` 全部子目录与占位文件;写 conventions(skill-template/naming/decoupling/lifecycle)与 README/inventory。
2. **删合**:删 `ios-date-picker`、`ios-table-actions`;`ios-controller-navigation` 并入 `ios-ui-nav`(**必须迁移 `ui.controllers` 的使用场景与示例**,验证 `grep 'ui.controllers' .claude/skills/ios-ui-nav/SKILL.md` 非空,避免能力丢失);从 gestures 删 drag 与重复小节。
3. **L1 操作层重构**——拆两步,每个 skill 独立提交、独立过 evals:
   - **3a 改名 + 删空壳动作**(机械):目录改名(navigation→`ios-ui-nav` 等)、删 date-picker/table-actions、统一主文件名为 `SKILL.md`(`ios-automation` 现为小写 `skill.md`,改名)、从 gestures 删 drag 与重复小节。
   - **3b 逐个 skill 重写**(主体工作量):7 个 `ios-ui-*` + `ios-automation` + 新建 `ios-logs`,按 skill-creator 规范、正文中文、中英 description、补 allowed-tools、精简到 ~150–250 行、解耦 SPMExample;`ios-logs` 含 §7 矩阵。**`ios-automation` 现无 evals,此步补一个轻量 evals**(连接诊断/路由类 case)。
4. **L2 通用化**:`ios-test-intent`/`ios-test-runner` 样例占位化,日志判据加 capture 前置检查,SPMExample 案例移到 examples。
5. **L0 定位**:在 `docs/skills/` 里写清 `ios-debugger-agent` 的 XcodeBuildMCP 职责、与 L1 的 UI 能力交集、以及 §3 的 L0/L1 选择规则。skill 本体仅在发现具体错误时改,否则只补文档定位。
6. **收尾**:归档 docs 顶层散报告;废弃旧 `ios-automation-skills-index.md`,以 `docs/skills/README.md`+`inventory.md` 替代;更新 `AGENTS.md`/`CLAUDE.md` 中 skill 索引段落指向新位置。

每阶段独立可验证:阶段产物 = 可加载的 skill + 通过的 evals + 更新的 inventory 状态。

---

## 11. 验收标准

- `.claude/skills/` 下每个 skill:frontmatter 含 `name`/`description`/`allowed-tools`;正文中文;无 SPMExample 硬编码(§8 硬规则全过 grep);引用的 action 全部在 iOSDriver MCP 真实存在。
- 不存在 `ios-date-picker`/`ios-table-actions` 目录;`ios-controller-navigation` 目录不存在且 `ui.controllers` 能力已迁入 `ios-ui-nav`。
- 所有 skill 主文件名统一为 `SKILL.md`(`ios-automation` 现为小写 `skill.md`,改名)。
- `ios-logs` 存在且含来源×平台矩阵与 `unavailable` 语义(矩阵不写死平台断言)。
- `docs/skills/README.md` + `inventory.md` 列出全部 12 个 skill 及状态;docs 顶层无一次性测试报告散落。
- 旧 `ios-automation-skills-index.md` 已废弃或删除。
- 每个保留 skill 有 `evals/`:静态结构 evals 必过(含 `allowed-tools`、无 §8 硬编码、action 真实);动态回归 evals 可引用 `docs/skills/examples/spmexample-login/` 作 fixture,不算 skill 本体耦合;`ios-automation` 补 evals。

验证命令(实施后):
```bash
# 无空壳/已合并目录残留
ls .claude/skills/ | grep -E 'date-picker|table-actions|controller-navigation' && echo "FAIL: 应删目录仍在" || echo "OK"
# controller-nav 合并未丢 ui.controllers 能力
grep -r 'ui.controllers' .claude/skills/ios-ui-nav/SKILL.md && echo "OK" || echo "FAIL: ui.controllers 未迁移"
# 无 SPMExample 硬编码(只扫 SKILL.md 正文,不扫 evals;不扫 123456 因动态 fixture 允许)
grep -rn -E 'com\.coo\.SPMExample|065CC8DB|00008030' .claude/skills/*/SKILL.md && echo "FAIL: 仍有耦合" || echo "OK"
# allowed-tools 齐全(find -iname 避免 SKILL.md/skill.md 大小写重复匹配)
find .claude/skills -iname SKILL.md | while read f; do grep -L 'allowed-tools' "$f"; done
# 文件名统一(应无输出)
find .claude/skills -iname 'skill.md' -not -name 'SKILL.md'
```

---

## 12. 风险与回退

- **改名导致旧触发失效**:靠 description 保留旧名关键词过渡;过渡期一个迭代后移除。回退:git 恢复旧目录名。
- **evals 解耦**:动态回归仍用 SPMExample 作参考 fixture(放 examples/),不新建"占位 App"(仓库内无其他集成 App,新建成本不值);skill 本体通用性由静态结构 evals 保证。
- **`ios-logs` 在模拟器 oslog 不可用被误判为 skill 缺陷**:skill 正文显式声明模拟器限制,`unavailable` 语义单列,避免误判。
- **删空壳后若有用户依赖**:date-picker/table-actions 自标 NOT TESTED/EXPERIMENTAL 且命令不存在,实际无人能成功调用,删除无功能损失。

---

## 附:决策记录(本次 brainstorming 已确认)

1. **主线**:分两层(L1 操作 / L2 测试闭环)各自通用,不互相耦合。L0 构建调试单列。
2. **语言**:正文中文 + 中英混合 description。
3. **空壳/重叠**:删空壳 + 合并重叠(用户确认)。
4. **L0 纳入**:全局 `ios-debugger-agent` 纳入分层定位(用户确认)。
5. **命名**:语义前缀分组(方案 A,L1 细化为 `ios-ui-*` + `ios-logs`)。
6. **日志**:新增 `ios-logs`,含模拟器/真机可用性矩阵与 `unavailable` 语义。
