# Skill 体系重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 14 个混叫 `ios-*` 的 skill 重构为三层职责清晰、完全通用、中文 + skill-creator 规范的 12 个 skill,并建立 `docs/skills/` 单一管理入口。

**Architecture:** 按已批准 spec(`docs/skills/design/2026-07-16-skills-architecture.md`)的三层架构:L0 构建调试(`ios-debugger-agent`,XcodeBuildMCP)/ L1 操作(`ios-ui-*` + `ios-logs` + `ios-automation`,iOSDriver)/ L2 测试闭环(`ios-test-*`)。先建管理目录与规范,再做结构性删改合并,再逐个 skill 重写,最后解耦 L2、定位 L0、归档收尾。

**Tech Stack:** Skill markdown(`SKILL.md` frontmatter + `evals/evals.json`)、iOSDriver MCP(`mcp__iOSDriver__*`)、skill-creator、iOSExploreDiagnostics(`app.logs.*`)、SPMExample 作测试 fixture。

## Global Constraints

> 每个 task 的要求都隐含包含本节。执行任何 skill 重写前先读完整规范:`docs/skills/design/2026-07-16-skills-architecture.md`。

**G1. 命名映射(改名时严格对应)**

| 旧目录 | 新目录 |
|---|---|
| ios-navigation | ios-ui-nav |
| ios-list-interaction | ios-ui-list |
| ios-form-filling | ios-ui-form |
| ios-screenshot | ios-ui-shot |
| ios-alert-handling | ios-ui-alert |
| ios-gestures | ios-ui-gesture |
| ios-dynamic-content | ios-ui-wait |
| ios-automation | ios-automation(不变) |
| ios-test-intent | ios-test-intent(不变) |
| ios-test-runner | ios-test-runner(不变) |
| (新建) | ios-logs |
| ios-date-picker | (删除) |
| ios-table-actions | (删除) |
| ios-controller-navigation | (并入 ios-ui-nav 后删除) |

**G2. 语言规则**
- 正文全中文。
- `description` 中英混合:中文说用途 + 英文关键词。改名 skill 的 description 必须含旧名关键词过渡(如 `"原 ios-form-filling"`),过渡期一个迭代后移除。
- frontmatter 字段顺序:`name`、`description`、`allowed-tools`。

**G3. SPMExample 解耦硬规则(SKILL.md 正文禁止出现)**
真实 bundle id(`com.coo.SPMExample`)、真实 UDID(`065CC8DB-…`、`00008030-…`)、测试账号(`test`/`123456`)、SPMExample 专属启动参数作为必备步骤、SPMExample 源码行号/类名作为通用示例。需举例时用占位 `<your.app.bundleid>`、`<your-simulator-udid>`。
> 例外:`evals/evals.json` 可引用 `docs/skills/examples/spmexample-login/` 作 fixture,不算 skill 本体耦合。

**G4. Skill 重写标准流程(每个重写 skill 都执行 STEP R1–R6)**
- **R1** 用 skill-creator 重写 `SKILL.md`:正文中文、中英 description、补 `allowed-tools`(见各 task)、精炼结构 `## 目标` / `## 何时使用` / `## 工作原理` / `## 关键参数` / `## 常见错误与判别` / `## 相关 skill`,目标 ~150–250 行。
- **R2** 解耦:正文过 G3 硬规则 grep。
- **R3** 保留并解耦 `evals/evals.json`(静态结构 case 必有;动态 case 可引 examples fixture)。
- **R4** 验证静态结构(见 G5 命令集,全部 PASS)。
- **R5** (可选)动态 evals:启动 SPMExample 跑该 skill 的核心命令,确认无回归。
- **R6** Commit:`<type>(skills): <描述>`(无 attribution,遵循项目 git-workflow)。

**G5. 通用验证命令集(每个重写 skill 都跑,全 PASS 才算完成)**

```bash
SKILL=<skill-dir>      # 例如 ios-ui-form
F=.claude/skills/$SKILL/SKILL.md
# 1) frontmatter 三字段齐全
grep -E '^(name|description|allowed-tools):' "$F" | wc -l   # 期望 3
# 2) 无 SPMExample 硬编码
grep -nE 'com\.coo\.SPMExample|065CC8DB|00008030' "$F" && echo FAIL || echo OK
# 3) 引用的 action 真实存在(交叉对照 iOSDriver 工具集)
# 4) evals 存在
ls .claude/skills/$SKILL/evals/evals.json
```

**G6. iOSDriver 真实 action 清单(引用前交叉对照,不存在则不能写进 skill)**
`ui.tap`/`ui.tap_and_inspect`/`ui.input`/`ui.inspect`/`ui.topViewHierarchy`/`ui.controllers`/`ui.control.sendAction`/`ui.keyboard.dismiss`/`ui.alert.respond`/`ui.navigation.back`/`ui.navigation.tapBarButton`/`ui.scroll`/`ui.scrollToElement`/`ui.swipe`/`ui.longPress`/`ui.screenshot`/`ui.wait`/`ui.waitAny`/`wait_and_inspect`/`app.logs.mark`/`app.logs.read`/`call_action`。**注意:`ui.datePicker.*`/`ui.picker.*`/`ui.table.*`/`ui.collection.*`/`ui.drag` 不存在。**

---

## 阶段 0:前置实测

### Task 1: 实测 oslog/nslog 日志矩阵(为 ios-logs 提供真实数据)

**Files:**
- Create: `docs/skills/design/log-matrix-measured.md`

**Why:** spec §7 明确"不能写死平台断言",必须模拟器 + 真机各实测一次填矩阵。本 task 产出的数据供 Task 12(ios-logs)引用。

- [ ] **Step 1: 模拟器实测**

启动 SPMExample 模拟器(已全开 4 个 capture)。模拟器与 Mac 共享 localhost:

```bash
curl -s -X POST http://localhost:38321/ -d '{"action":"ping"}'          # 确认 ok
MARK=$(curl -s -X POST http://localhost:38321/ -d '{"action":"app.logs.mark"}')
# 触发各类日志(SPMExample debug action)
curl -s -X POST http://localhost:38321/ -d '{"action":"debug.emitOSLog","data":{"message":"m-oslog"}}'
curl -s -X POST http://localhost:38321/ -d '{"action":"debug.emitNSLog","data":{"message":"m-nslog"}}'
curl -s -X POST http://localhost:38321/ -d '{"action":"debug.emitStdout","data":{"message":"m-stdout"}}'
# 读各 source,记录 capture.state 与是否有 entries
curl -s -X POST http://localhost:38321/ -d '{"action":"app.logs.read","data":{"sources":["oslog"],"limit":50}}'
curl -s -X POST http://localhost:38321/ -d '{"action":"app.logs.read","data":{"sources":["nslog"],"limit":50}}'
curl -s -X POST http://localhost:38321/ -d '{"action":"app.logs.read","data":{"sources":["stdout"],"limit":50}}'
```

- [ ] **Step 2: 真机实测**

经 iproxy(先 `lsof -iTCP:38321` 确认是 iproxy 在监听),重复 Step 1 命令(同样 localhost:38321)。

- [ ] **Step 3: 记录矩阵**

把每个 source × {模拟器,真机} 的 `capture.state`(enabled/notCaptured/unavailable)与"是否读到 entries"写入 `docs/skills/design/log-matrix-measured.md`,格式:

```markdown
# 实测日志矩阵(2026-07-16)

| source | 模拟器 capture.state | 模拟器可读 | 真机 capture.state | 真机可读 |
|---|---|---|---|---|
| explore | | | | |
| bridge | | | | |
| stdout | | | | |
| stderr | | | | |
| nslog | | | | |
| oslog | | | | |
```

- [ ] **Step 4: Commit**

```bash
git add docs/skills/design/log-matrix-measured.md
git commit -m "docs(skills): 实测 oslog/nslog 模拟器与真机日志矩阵"
```

---

## 阶段 1:管理目录与规范基建

### Task 2: 建立 docs/skills/ 管理目录与规范

**Files:**
- Create: `docs/skills/README.md`
- Create: `docs/skills/inventory.md`
- Create: `docs/skills/conventions/skill-template.md`
- Create: `docs/skills/conventions/naming.md`
- Create: `docs/skills/conventions/decoupling.md`
- Create: `docs/skills/conventions/lifecycle.md`

**Interfaces:**
- Produces: 四份 conventions 文档是后续所有 skill 重写的依据;`inventory.md` 是 12 个 skill 的状态真相源。

- [ ] **Step 1: 写 conventions/skill-template.md**

内容 = G2 语言规则 + G4 的 R1 结构骨架 + 一个完整 frontmatter 示例(含 `name`/`description`/`allowed-tools`)。这是 skill-creator 重写时套用的中文模板。

- [ ] **Step 2: 写 conventions/naming.md**

内容 = G1 命名映射表 + 三层前缀规则(`ios-ui-*`/`ios-logs`/`ios-test-*`/`ios-automation`/`ios-debugger-agent`)+ "Claude Code skill 以目录名为 skill 名,不支持子目录分组"的依据。

- [ ] **Step 3: 写 conventions/decoupling.md**

内容 = G3 硬规则全文 + "skill 本体解耦 ≠ evals 不能用 SPMExample fixture"的澄清 + 占位符约定(`<your.app.bundleid>` 等)。

- [ ] **Step 4: 写 conventions/lifecycle.md**

内容 = EXPERIMENTAL 挂账上限规则(标 EXPERIMENTAL 的 skill 必须在 1 个迭代内补测试,否则降级合并或删除——针对 date-picker/table-actions 这类空壳长期挂账的教训)+ 废弃标准。

- [ ] **Step 5: 写 inventory.md**

12 个 skill 清单表,列:skill 名 / 层 / 工具体系 / `allowed-tools` 概要 / 健康度(healthy/needs-test)/ 状态(active/deprecated/removed)。`date-picker`/`table-actions`/`controller-navigation` 标 removed 并注明原因。

- [ ] **Step 6: 写 README.md**

三层架构总览(抄 spec §3 表格)+ L0/L1 选择规则 + 指向 inventory/conventions/examples 的导航。这是"看一个文件懂全貌"的入口。

- [ ] **Step 7: 验证 + Commit**

```bash
ls docs/skills/{README.md,inventory.md,conventions/*.md}   # 6 个文件都在
git add docs/skills/README.md docs/skills/inventory.md docs/skills/conventions/
git commit -m "docs(skills): 建立 docs/skills 管理目录与四份规范"
```

---

## 阶段 2 + 3a:结构性删改合并

### Task 3: L1 改名、删空壳、合并 controller-nav、清理 gestures

**Files:**
- Rename: 7 个目录(G1 映射)
- Rename: `.claude/skills/ios-automation/skill.md` → `SKILL.md`
- Delete: `.claude/skills/ios-date-picker/`, `.claude/skills/ios-table-actions/`
- Merge then Delete: `.claude/skills/ios-controller-navigation/` → 内容并入 `ios-ui-nav` 后删
- Modify: `.claude/skills/ios-ui-gesture/SKILL.md`(删 drag + 重复小节)

**Why:** 先做机械结构整理,后续重写 task 才有正确的目录名可用。controller-nav 必须在 `ios-ui-nav`(由 navigation 改名而来)存在后才能并入。

- [ ] **Step 1: 改名 7 个目录**

```bash
cd .claude/skills
git mv ios-navigation ios-ui-nav
git mv ios-list-interaction ios-ui-list
git mv ios-form-filling ios-ui-form
git mv ios-screenshot ios-ui-shot
git mv ios-alert-handling ios-ui-alert
git mv ios-gestures ios-ui-gesture
git mv ios-dynamic-content ios-ui-wait
cd ../..
```

- [ ] **Step 2: 统一 ios-automation 文件名**

```bash
git mv .claude/skills/ios-automation/skill.md .claude/skills/ios-automation/SKILL.md
```

- [ ] **Step 3: 删 2 个空壳**

```bash
git rm -r .claude/skills/ios-date-picker .claude/skills/ios-table-actions
```

- [ ] **Step 4: 把 controller-nav 的 ui.controllers 内容并入 ios-ui-nav**

读 `.claude/skills/ios-controller-navigation/SKILL.md`,提取其中 `ui.controllers` 的用途说明、调用示例、参数说明。把这些作为新小节"## controller 层级检查(`ui.controllers`)"追加到 `.claude/skills/ios-ui-nav/SKILL.md`(此时 ios-ui-nav 还是旧 navigation 内容,追加即可;Task 4 重写时会整合)。然后:

```bash
git rm -r .claude/skills/ios-controller-navigation
```

- [ ] **Step 5: 清理 ios-ui-gesture(删 drag + 重复小节)**

编辑 `.claude/skills/ios-ui-gesture/SKILL.md`:删除所有 `ui.drag` 相关内容(命令不存在);删除重复的第二组 `## Parameters Reference`/`## Best Practices`/`## Limitations`/`## Related Skills`(审计发现 line ~159 与 ~318 各一份)。

- [ ] **Step 6: 验证结构**

```bash
# 7 个新目录存在
ls .claude/skills/ | grep -E '^ios-ui-'
# 旧目录与空壳不存在
ls .claude/skills/ | grep -E 'date-picker|table-actions|controller-navigation|ios-navigation$|ios-form-filling' && echo FAIL || echo OK
# ui.controllers 已迁入 ios-ui-nav
grep -l 'ui.controllers' .claude/skills/ios-ui-nav/SKILL.md && echo OK
# 文件名统一
find .claude/skills -iname 'skill.md' -not -name 'SKILL.md'   # 应无输出
```

- [ ] **Step 7: Commit**

```bash
git add -A .claude/skills
git commit -m "refactor(skills): L1 改名 ios-ui-*、删空壳、controller-nav 并入 ios-ui-nav、清理 gestures"
```

---

## 阶段 3b:L1 操作层逐个重写(每个独立提交)

> 以下 Task 4–10 均按 **G4 标准流程 R1–R6** 执行。每个 task 只列该 skill 的特有参数(`allowed-tools`、解耦点、内容要求)与验证,不重复 R1–R6 通用步骤。

### Task 4: 重写 ios-ui-nav

**Files:** Modify `.claude/skills/ios-ui-nav/SKILL.md`, `evals/evals.json`

- **allowed-tools:** `mcp__iOSDriver__ui_inspect`, `mcp__iOSDriver__ui_tap`, `mcp__iOSDriver__ui_tap_and_inspect`, `mcp__iOSDriver__ui_navigation_back`, `mcp__iOSDriver__ui_navigation_tapBarButton`, `mcp__iOSDriver__ui_controllers`, `mcp__iOSDriver__ui_screenshot`
- **description 过渡关键词:** 含 `"原 ios-navigation"`、`"原 ios-controller-navigation"`。
- **内容要点:** 屏幕导航/返回/导航栏按钮;**必须整合 Task 3 Step 4 并入的 `ui.controllers` controller 层级检查小节**(这是 R1,确保能力不丢)。从原 745 行精简到 ~200–250 行。
- [ ] 按 R1–R4 执行;G5 验证(设 `SKILL=ios-ui-nav`)+ 额外:`grep 'ui.controllers' $F` 非空。
- [ ] R6 Commit:`refactor(skills): 重写 ios-ui-nav(中文+skill-creator,含 ui.controllers)`

### Task 5: 重写 ios-ui-list

**Files:** Modify `.claude/skills/ios-ui-list/SKILL.md`, `evals/evals.json`

- **allowed-tools:** `mcp__iOSDriver__ui_inspect`, `mcp__iOSDriver__ui_scroll`, `mcp__iOSDriver__ui_scrollToElement`, `mcp__iOSDriver__ui_swipe`, `mcp__iOSDriver__ui_tap`, `mcp__iOSDriver__ui_tap_and_inspect`
- **description 过渡关键词:** `"原 ios-list-interaction"`。
- **内容要点:** 列表/集合查找、scrollToElement、滚动、选中。719 行精简到 ~200。
- [ ] R1–R4 + G5(`SKILL=ios-ui-list`)+ R6 Commit:`refactor(skills): 重写 ios-ui-list`

### Task 6: 重写 ios-ui-form

**Files:** Modify `.claude/skills/ios-ui-form/SKILL.md`, `evals/evals.json`

- **allowed-tools:** `mcp__iOSDriver__ui_input`, `mcp__iOSDriver__ui_tap`, `mcp__iOSDriver__ui_tap_and_inspect`, `mcp__iOSDriver__ui_control_sendAction`, `mcp__iOSDriver__ui_keyboard_dismiss`, `mcp__iOSDriver__ui_inspect`, `mcp__iOSDriver__ui_scrollToElement`
- **description 过渡关键词:** `"原 ios-form-filling"`。
- **解耦点:** 原仅有 1 句"iOS 26.2+ (matches SPMExample deployment target)"(审计 line 669)——改为通用 `"iOSExploreServer 要求 iOS 15+ / 部署目标视宿主 App 而定"`,不提 SPMExample。
- **内容要点:** 文本输入(replace/append)、Unicode/emoji、UISwitch/UISlider/UIStepper/UISegmentedControl、键盘管理、提交。703 行精简到 ~200。
- [ ] R1–R4 + G5(`SKILL=ios-ui-form`)+ R6 Commit:`refactor(skills): 重写 ios-ui-form`

### Task 7: 重写 ios-ui-alert

**Files:** Modify `.claude/skills/ios-ui-alert/SKILL.md`, `evals/evals.json`

- **allowed-tools:** `mcp__iOSDriver__ui_inspect`, `mcp__iOSDriver__ui_alert_respond`, `mcp__iOSDriver__ui_input`, `mcp__iOSDriver__ui_tap_and_inspect`
- **description 过渡关键词:** `"原 ios-alert-handling"`。
- **内容要点:** alert 检测(available 标志)、三种响应(index/title/role)、文本框 alert、action sheet、嵌套/连续 alert。595 行精简到 ~200。
- [ ] R1–R4 + G5(`SKILL=ios-ui-alert`)+ R6 Commit:`refactor(skills): 重写 ios-ui-alert`

### Task 8: 重写 ios-ui-shot

**Files:** Modify `.claude/skills/ios-ui-shot/SKILL.md`, `evals/evals.json`

- **allowed-tools:** `mcp__iOSDriver__ui_screenshot`, `mcp__iOSDriver__ui_inspect`
- **description 过渡关键词:** `"原 ios-screenshot"`。
- **内容要点:** PNG 截图、base64、metadata、前后对比、流程文档。613 行精简到 ~150。
- [ ] R1–R4 + G5(`SKILL=ios-ui-shot`)+ R6 Commit:`refactor(skills): 重写 ios-ui-shot`

### Task 9: 重写 ios-ui-gesture

**Files:** Modify `.claude/skills/ios-ui-gesture/SKILL.md`, `evals/evals.json`

- **allowed-tools:** `mcp__iOSDriver__ui_swipe`, `mcp__iOSDriver__ui_longPress`, `mcp__iOSDriver__ui_inspect`
- **description 过渡关键词:** `"原 ios-gestures"`。
- **内容要点:** 方向 swipe、可变距离、自定义时长 long press、cell swipe action。**不含 drag**(Task 3 已删,确认正文无 `ui.drag` 残留:`grep 'ui.drag' $F` 应无输出)。549 行精简到 ~150。
- [ ] R1–R4 + G5(`SKILL=ios-ui-gesture`)+ 额外 `grep -c 'ui.drag' $F` 为 0 + R6 Commit:`refactor(skills): 重写 ios-ui-gesture(去 drag)`

### Task 10: 重写 ios-ui-wait

**Files:** Modify `.claude/skills/ios-ui-wait/SKILL.md`, `evals/evals.json`

- **allowed-tools:** `mcp__iOSDriver__ui_wait`, `mcp__iOSDriver__ui_waitAny`, `mcp__iOSDriver__wait_and_inspect`, `mcp__iOSDriver__ui_inspect`
- **description 过渡关键词:** `"原 ios-dynamic-content"`。
- **内容要点:** 等待元素出现/消失、多条件等待、超时、loading 处理。**补 wait/waitAny 的真实用法说明**(原 skill 标 "not fully tested",此处据 G6 真实 action 写清)。321 行精简到 ~150。
- [ ] R1–R4 + G5(`SKILL=ios-ui-wait`)+ R6 Commit:`refactor(skills): 重写 ios-ui-wait`

### Task 11: 重写 ios-automation(L1 总入口)+ 补 evals

**Files:** Modify `.claude/skills/ios-automation/SKILL.md`;Create `.claude/skills/ios-automation/evals/evals.json`

- **allowed-tools:** `mcp__iOSDriver__ui_inspect`, `mcp__iOSDriver__ui_tap_and_inspect`, `mcp__iOSDriver__app_logs_read`(诊断用)
- **解耦点(中度,重点处理):**
  - 正文 line 144/186/209 的 `xcrun simctl terminate <UDID> com.coo.SPMExample` → 改占位 `xcrun simctl terminate <simulator-udid> <your.app.bundleid>`。
  - line 126/128/141 的 lsof 诊断示例 "检测到 SPMExample 监听" → 改通用 "检测到目标 App 监听"。
  - line 381 DEBUG 自动启动说明指向 SPMExample `viewDidAppear` → 改通用 "宿主 App 在 viewDidLoad/viewDidAppear 调用 `server.start()`"。
  - line 368 登录示例 `ui.input(username="test", password="123456")` → 改占位凭证。
- **内容要点:** 连接管理(模拟器 localhost / 真机 iproxy)、路由到 L1 子 skill、快速诊断、L0/L1 选择规则(抄 spec §3)。
- [ ] **R3 特殊:** 该 skill 现无 evals,新建 `evals/evals.json`,至少含 2 个静态结构 case(frontmatter 三字段、iproxy/连接诊断流程描述正确)+ 1 个动态 case(ping 38321)。
- [ ] R1–R4 + G5(`SKILL=ios-automation`)+ R6 Commit:`refactor(skills): 重写 ios-automation 入口(解耦+补 evals)`

### Task 12: 新建 ios-logs

**Files:** Create `.claude/skills/ios-logs/SKILL.md`, `.claude/skills/ios-logs/evals/evals.json`

**Interfaces:**
- Consumes: Task 1 产出的 `docs/skills/design/log-matrix-measured.md`(实测矩阵数据)。

- **allowed-tools:** `mcp__iOSDriver__app_logs_mark`, `mcp__iOSDriver__app_logs_read`
- **frontmatter description:** `"读取 iOS App 进程内日志 / app logs, stdout, stderr, nslog, oslog, debug, mark, read"`
- **正文必备小节:**
  - `app.logs.mark` / `app.logs.read` 用法(参数 after/limit/sources/minimumLevel)。
  - 6 个 source 表(explore/bridge/stdout/stderr/nslog/oslog + 默认开关 + 开启 capture 配置)。
  - **来源 × 平台矩阵**:直接引用 Task 1 实测结果;`oslog`/`nslog` 行不写死"模拟器不可用",措辞为"取决于系统是否允许读 OSLogStore,实测见矩阵,以 `capture.state` 为准"。
  - **`unavailable` 语义专节**:`enabled`/`notCaptured`/`unavailable` 三态;强调 `unavailable` ≠ "日志没发生"。
- [ ] **Step 1:** 用 skill-creator 按 R1 生成,正文中文,矩阵数据从 log-matrix-measured.md 抄入。
- [ ] **Step 2:** 新建 `evals/evals.json`:静态结构 case + 动态 case(mark → emit → read sources:["stdout"] 能读到)。
- [ ] **Step 3:** G5 验证(`SKILL=ios-logs`)+ `grep 'capture.state' $F` 非空 + `grep 'unavailable' $F` 非空。
- [ ] **Step 4:** Commit

```bash
git add .claude/skills/ios-logs
git commit -m "feat(skills): 新建 ios-logs(进程日志读取+模拟器真机矩阵+unavailable 语义)"
```

---

## 阶段 4:L2 测试闭环通用化

### Task 13: ios-test-intent 通用化

**Files:** Modify `.claude/skills/ios-test-intent/SKILL.md`, `evals/evals.json`

- **allowed-tools:** (离线分析,无 iOSDriver 调用)`Read`, `Glob`, `Grep`(读 App 源码用)
- **解耦点(重度):**
  - 整篇样例基于 SPMExample 登录源码(`AuthService`/`LoginViewModel`/`LoginViewController`、行号 230-232/274/43)→ 改为**通用占位 App 示例**(虚构 `<MyApp>` 的 `<LoginService>`/`<LoginViewModel>`,不引真实类名行号)。
  - 种子数据 `test/123456`(line 62/105/135/136/147)→ 占位 `<seed-user>`/`<seed-password>`。
  - 产物路径 `docs/test-intents/spmexample-login.json`(line 165/169)→ 通用 `docs/test-intents/<app>-<flow>.json`。
  - 风险表"SPMExample 反例"列(line 175-179)→ 通用化表述。
  - **方法论保留**(读 Service/ViewModel/VC 产出 pass/fail 判据,输出 textExists/targetExists/targetGone/alert 词汇)。
- **evals 解耦:** 5 条用例全部耦合 SPMExample → 改占位 App 路径与凭证。
- [ ] R1–R4 + G5(`SKILL=ios-test-intent`)+ 额外 `grep -E 'AuthService|LoginViewController|spmexample' $F` 应只在"指向 examples 案例"的引用处出现,不在通用示例处。
- [ ] R6 Commit:`refactor(skills): ios-test-intent 通用化(样例占位化,方法论保留)`

### Task 14: ios-test-runner 通用化 + 日志判据 capture 前置检查

**Files:** Modify `.claude/skills/ios-test-runner/SKILL.md`, `evals/evals.json`

- **allowed-tools:** `mcp__iOSDriver__ui_waitAny`, `mcp__iOSDriver__ui_inspect`, `mcp__iOSDriver__ui_tap`, `mcp__iOSDriver__ui_input`, `mcp__iOSDriver__app_logs_read`, `mcp__iOSDriver__app_logs_mark`
- **解耦点(重度):**
  - description 点名 `spmexample-login.json`、触发语 `"把 spmexample-login.json 跑一遍"` → 改通用 `"<app>-<flow>.json"`。
  - line 62 种子 `test/123456`、`AuthService.shared.users` → 占位。
  - line 74/249 启动参数 `--ios-explore-show-login` 作为固定回登录手段 → 改为"如需回到某流程起点,由调用方提供 App 专属启动参数",不写死。
  - **line 203/204 报告样例写死 `"app":"SPMExample"`、`"simulator":"iPhone 17 (065CC8DB-…)"`** → 占位 `"app":"<your-app>"`、`"simulator":"<name> (<udid>)"`。
  - line 274/278 实跑报告路径 `docs/test-reports/spmexample-login-run.json` → 通用 `docs/test-reports/<app>-<flow>-run.json`。
- **日志判据增强(关键):** 新增小节"日志断言前置检查"——用 `app.logs.read` 做断言前,必须先确认对应 source 的 `capture.state == "enabled"`;模拟器上 `oslog` 判据自动降级(跳过或改用 `bridge`/`stdout`,要求被测 App 关键点 `ExploreAppLog.emit`)。引用 ios-logs 的矩阵。
- **evals 解耦:** 全部用例改占位 App + 凭证。
- [ ] R1–R4 + G5(`SKILL=ios-test-runner`)+ 额外 `grep -E '065CC8DB|com.coo.SPMExample|--ios-explore-show-login' $F` 无输出。
- [ ] R6 Commit:`refactor(skills): ios-test-runner 通用化(去 UDID/bundle + 日志判据 capture 前置检查)`

### Task 15: 迁移 SPMExample 登录案例到 examples/

**Files:**
- Move: `docs/test-intents/spmexample-login.json` → `docs/skills/examples/spmexample-login/intent.json`
- Move: `docs/test-reports/spmexample-login-run.json` → `docs/skills/examples/spmexample-login/run-report.json`
- Create: `docs/skills/examples/spmexample-login/README.md`(说明这是"如何对真实 App 套用 test-intent/runner"的参考案例)
- Keep: `docs/test-intents/`、`docs/test-reports/` 目录保留(通用目录)

- [ ] **Step 1: 移动案例文件**

```bash
mkdir -p docs/skills/examples/spmexample-login
git mv docs/test-intents/spmexample-login.json docs/skills/examples/spmexample-login/intent.json
git mv docs/test-reports/spmexample-login-run.json docs/skills/examples/spmexample-login/run-report.json
```

- [ ] **Step 2: 写案例 README**

说明:这是 SPMExample 登录流程的完整 intent + 实跑报告,作为 test-intent/runner 的真实参考案例;skill 本体通用,本案例不属于 skill 耦合。

- [ ] **Step 3: 更新 test-intent/runner 对案例的引用**

Task 13/14 已把 skill 正文引用通用化;确认 `evals` 里如需引用真实案例,指向新路径 `docs/skills/examples/spmexample-login/`。

- [ ] **Step 4: Commit**

```bash
git add docs/skills/examples/ docs/test-intents/ docs/test-reports/
git commit -m "docs(skills): SPMExample 登录案例迁移到 docs/skills/examples/"
```

---

## 阶段 5:L0 定位

### Task 16: ios-debugger-agent 定位文档

**Files:**
- Create: `docs/skills/l0-build-debug.md`(L0 定位与选择规则)
- Modify: `~/.claude/skills/ios-debugger-agent/SKILL.md`(仅补一行 cross-ref,不改职责;若发现具体错误才改本体)

> 注意:`ios-debugger-agent` 在**全局** `~/.claude/skills/`,不在项目 `.claude/skills/`。它是全局 skill,改动影响其他项目——本次只在项目 docs 里写定位,本体仅在发现具体错误时改。

- [ ] **Step 1: 写 docs/skills/l0-build-debug.md**

内容:`ios-debugger-agent` 用 XcodeBuildMCP 负责 build/run/install/debug App 进程 + 系统级日志;与 L1 `ios-ui-*` 的 UI 能力交集说明;**L0/L1 选择规则**(抄 spec §3:已集成 iOSExploreServer→L1;需构建/调试/未集成→L0);列出它的关键工具(`build_run_sim`/`build_run_device`/`launch_app_*`/`start_sim_log_cap`/`describe_ui`)。

- [ ] **Step 2: 在 docs/skills/README.md 与 inventory.md 中登记 L0**

README 三层架构表与 inventory 已含 L0(Task 2),确认 `ios-debugger-agent` 行的工具体系=XcodeBuildMCP、定位指向 `l0-build-debug.md`。

- [ ] **Step 3: (谨慎)检查全局 ios-debugger-agent 本体**

读 `~/.claude/skills/ios-debugger-agent/SKILL.md`,若发现具体错误(如引用不存在的工具)才改;否则不动。把检查结论写入 `l0-build-debug.md` 末尾。

- [ ] **Step 4: Commit**(只 commit 项目内文件,不 commit 全局)

```bash
git add docs/skills/l0-build-debug.md docs/skills/README.md docs/skills/inventory.md
git commit -m "docs(skills): 补 L0 ios-debugger-agent 定位与 L0/L1 选择规则"
```

---

## 阶段 6:收尾

### Task 17: 归档 docs 顶层散报告

**Files:**
- Move → `docs/skills/archive/`: `alert-test-complete-report.md`, `input-alert-control-test-report.md`, `final-two-commands-test-report.md`, `skills-test-report.md`, `skill-design-final.md`, `skills-improvement-recommendations.md`, `skills-improvements-applied.md`, `renaming-report.md`, `ALL-TESTS-COMPLETE-SUMMARY.md`, `100-PERCENT-COVERAGE-FINAL.md`, `final-command-coverage.md`, `TASK-COMPLETION-SUMMARY.md`, `testing-summary.md`, `command-gap-analysis.md`, `ios-automation-skills-index.md`(旧索引,废弃)
- Keep in `docs/`: `agent_instructions.md`(规则文档)、`QUICK_START.md`(评估:若内容仍有效则保留并更新指向,否则归档)
- Create: `docs/skills/archive/README.md`
- Keep不动: 仓库根 `reports/`(非 docs/reports/)

- [ ] **Step 1: 归档**

```bash
mkdir -p docs/skills/archive
for f in alert-test-complete-report input-alert-control-test-report \
         final-two-commands-test-report skills-test-report skill-design-final \
         skills-improvement-recommendations skills-improvements-applied renaming-report \
         ALL-TESTS-COMPLETE-SUMMARY 100-PERCENT-COVERAGE-FINAL final-command-coverage \
         TASK-COMPLETION-SUMMARY testing-summary command-gap-analysis \
         ios-automation-skills-index; do
  git mv "docs/$f.md" docs/skills/archive/ 2>/dev/null
done
```

- [ ] **Step 2: 写 archive/README.md**

注明:这些是 skill 体系历次迭代的一次性产物;仓库根 `reports/2026-07-13-14-skills-creation-project/` 与 `reports/2026-07-14-skills-creation/` 是另一份副本(权威源以 `docs/skills/design/` 的 spec 与本 archive 为准);`ios-automation-skills-index.md` 已被 `docs/skills/README.md` + `inventory.md` 取代。

- [ ] **Step 3: 评估 QUICK_START.md**

读 `docs/QUICK_START.md`:若其 skill 索引/启动指引仍有效 → 更新指向 `docs/skills/` 并保留;若已过时 → `git mv` 到 archive。

- [ ] **Step 4: 验证 + Commit**

```bash
ls docs/*.md   # 应只剩 agent_instructions.md(和可能的 QUICK_START.md)
git add -A docs
git commit -m "docs(skills): 归档 docs 顶层散报告到 docs/skills/archive,废弃旧索引"
```

### Task 18: 更新 AGENTS/CLAUDE skill 索引 + 最终验收

**Files:** Modify `AGENTS.md`, `CLAUDE.md`(skill 索引段指向 `docs/skills/`)

- [ ] **Step 1: 更新 AGENTS.md / CLAUDE.md 的 skill 表**

把"Claude Code Skills(自动化测试入口)"表的内容更新:指向 `docs/skills/README.md` 与新 skill 名(`ios-ui-*`/`ios-logs`/`ios-test-*`/`ios-automation`);移除已删 skill(date-picker/table-actions/controller-navigation)。保留 ios-automation 统一入口描述。

- [ ] **Step 2: 跑 spec §11 全部验证命令**

```bash
# 无空壳/已合并目录残留
ls .claude/skills/ | grep -E 'date-picker|table-actions|controller-navigation' && echo FAIL || echo OK
# ui.controllers 已迁入 ios-ui-nav
grep -r 'ui.controllers' .claude/skills/ios-ui-nav/SKILL.md && echo OK || echo FAIL
# 无 SPMExample 硬编码(扫所有 SKILL.md 正文)
grep -rnE 'com\.coo\.SPMExample|065CC8DB|00008030' .claude/skills/*/SKILL.md && echo FAIL || echo OK
# allowed-tools 齐全(输出为空=全有)
find .claude/skills -iname SKILL.md | while read f; do grep -L 'allowed-tools' "$f"; done
# 文件名统一(输出为空)
find .claude/skills -iname 'skill.md' -not -name 'SKILL.md'
# ios-logs 含矩阵与 unavailable 语义
grep -q 'capture.state' .claude/skills/ios-logs/SKILL.md && grep -q 'unavailable' .claude/skills/ios-logs/SKILL.md && echo OK || echo FAIL
```

全部 OK 才算通过。任何 FAIL 回对应 task 修。

- [ ] **Step 3: 更新 inventory.md 最终状态**

把所有 skill 状态置为 active/healthy(或如实标注 needs-test)。

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md CLAUDE.md docs/skills/inventory.md
git commit -m "docs(skills): 更新 AGENTS/CLAUDE skill 索引指向 docs/skills,完成最终验收"
```

---

## Self-Review(计划自审,执行前)

**1. Spec 覆盖:** 逐条对照 spec——
- 三层架构 → Task 2(README)+ Task 16(L0)✓
- 12 个 skill 清单(删 2/合并 1/新增 1)→ Task 3 + Task 12 ✓
- 命名分组 → G1 + Task 3 ✓
- 语言 + skill-creator 规范 → G2/G4 + Task 4–14 ✓
- SPMExample 解耦 → G3 + Task 6/11/13/14/15 ✓
- ios-logs 日志矩阵 → Task 1(实测)+ Task 12 ✓
- docs/skills/ 结构 → Task 2 + Task 15/16/17 ✓
- evals 两层策略 → G4 R3 + Task 11(补 automation evals)+ Task 12 ✓
- 6 阶段 → 阶段 0–6 全覆盖 ✓

**2. 占位符扫描:** 无 TBD/TODO;每个 skill 重写 task 的"内容要点"是执行指引而非占位(SKILL.md 全文由 skill-creator 在 R1 生成,这是设计意图,非计划缺失)。

**3. 类型/命名一致性:** allowed-tools 全用 `mcp__iOSDriver__<action>` 形式;目录名跨 task 一致(`ios-ui-*`/`ios-logs`/`ios-test-*`);controller-nav 在 Task 3 Step 4 并入、Task 4 整合、Task 18 验证 grep,链路一致。

**4. 依赖顺序:** Task 1(矩阵)→ Task 12(ios-logs)依赖;Task 3(改名,产出 ios-ui-nav)→ Task 4(整合 ui.controllers)依赖;Task 13/14(通用化)→ Task 15(案例迁移引用新路径)依赖。无循环。

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-16-skills-refactor.md`.
