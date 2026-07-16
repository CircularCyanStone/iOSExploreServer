# iOSExplore Skill 体系(看一个文件懂全貌)

> 本文件是 `.claude/skills/` 与全局 `ios-debugger-agent` 的**统一管理入口**。从本文件出发,可以理解:skill 体系为什么这样分、每个 skill 在哪一层、写/改 skill 看哪些规范、哪些 skill 已废弃。规范依据:`design/2026-07-16-skills-architecture.md`(以下简称 spec)。

---

## 1. 三层架构总览(抄 spec §3)

调用关系单向:**L0 把 App 跑起来 → L1 操作 App UI / 读进程日志 → L2 编排 L1 跑测试闭环**。三层**工具体系**互不重叠(L0 用 XcodeBuildMCP,L1/L2 用 iOSDriver)。

| 层 | 工具体系 | 职责(一句话) | 包含 skill |
|---|---|---|---|
| **L0 构建调试** | XcodeBuildMCP(`mcp__XcodeBuildMCP__*`) | 编译、运行、启动、调试 App 进程,捕获系统级日志 | `ios-debugger-agent`(全局) |
| **L1 操作层** | iOSDriver(`mcp__iOSDriver__*`,封装 iOSExploreServer HTTP) | 操作已运行 App 的 UI 与读取进程内日志 | 7 个 `ios-ui-*` + `ios-logs` + 入口 `ios-automation` |
| **L2 测试闭环** | iOSDriver + 离线源码分析 | 读业务源码产出测试判据 → 自动驱动 UI 跑 → 出覆盖报告 | `ios-test-intent` + `ios-test-runner` |

**两套日志能力的关系(互补,非冲突)**:
- L0 `start_sim_log_cap`:系统/模拟器级捕获,模拟器友好,抓整个 App 控制台。
- L1 `app.logs.*`(iOSExploreDiagnostics):App 进程内精准捕获,可按 source/level 过滤、可做断言;真机 `oslog` 更全,模拟器受限(详见 `ios-logs` 正文与 `design/log-matrix-measured.md`)。

---

## 2. L0/L1 选择规则(抄 spec §3)

> **注意 UI 能力交集**:L0 的 `ios-debugger-agent` 正文也含 UI 操作(`describe_ui` / `tap` / `type_text` / `screenshot`,基于 XcodeBuildMCP 的 accessibility snapshot),与 L1 的 `ios-ui-*`(基于 iOSDriver 的 `ui.*` HTTP 命令)在 UI 能力上有交集,只是工具体系不同。因此需要一条选择规则,不能简单认为"职责互不重叠"。

**选择规则**:

- 目标 App **已集成 iOSExploreServer**(能 `curl http://localhost:38321/` 成功)→ **优先 L1** 的 `ios-ui-*` + `ios-logs`(更精准、可按 source/level 过滤、可做日志断言)。
- 需要**构建/安装/调试进程**、抓系统级日志,或 App **未集成** iOSExploreServer → **用 L0** 的 `ios-debugger-agent`。

详细定位见 `l0-build-debug.md`(plan Task 16 产出)。

---

## 3. 12 个 skill 全景(完整状态见 `inventory.md`)

### 3.1 L0(1 个,XcodeBuildMCP)
- `ios-debugger-agent` — 构建/运行/调试 App 进程,系统级日志。

### 3.2 L1 操作层(9 个,iOSDriver)
- `ios-automation` — 总入口:连接管理、iproxy、路由到子 skill、快速诊断。
- `ios-ui-nav` — 屏幕导航、返回、导航栏按钮;含 controller 层级树读取(`ui.controllers`,吸收原 `ios-controller-navigation`)。
- `ios-ui-list` — 列表/集合视图查找、滚动、选中。
- `ios-ui-form` — 文本输入、开关、滑块、步进器、分段、提交。
- `ios-ui-alert` — alert / action sheet / dialog 检测与响应。
- `ios-ui-shot` — 截图、视觉验证、前后对比。
- `ios-ui-gesture` — swipe、long press(**不含 drag**;`ui.drag` 不存在)。
- `ios-ui-wait` — 等待动态内容 / loading / 异步状态。
- `ios-logs` — 读 App 进程内日志(`app.logs.mark` / `app.logs.read`),含来源可用性矩阵与 `unavailable` 语义(**planned**,plan Task 12 创建)。

### 3.3 L2 测试闭环(2 个,iOSDriver + 源码分析)
- `ios-test-intent` — 离线读 App 业务代码,产出 per-scenario pass/fail 判据清单。
- `ios-test-runner` — 消费判据清单,驱动 UI 跑测试,出覆盖报告。

> 已删除 3 个空壳/重叠 skill(`ios-date-picker` / `ios-table-actions` / `ios-controller-navigation`)的原因见 `inventory.md` §2。

---

## 4. 文件导航

### 4.1 想做什么 → 看哪里

| 我想…… | 看哪个文件 |
|---|---|
| 看三层架构全貌、L0/L1 选择规则 | 本文件 + `design/2026-07-16-skills-architecture.md` §3 |
| 看全部 skill 当前状态(健康度、状态、`allowed-tools` 概要) | `inventory.md` |
| 写/重写一个 skill,看模板与正文结构 | `conventions/skill-template.md` |
| 给 skill 改名/起名/选前缀 | `conventions/naming.md` |
| 判断 skill 正文是否过度耦合 SPMExample | `conventions/decoupling.md` |
| 判断一个 EXPERIMENTAL skill 该不该删/合/留 | `conventions/lifecycle.md` |
| 看 SPMExample 登录的真实参考案例(intent + run-report) | `examples/spmexample-login/`(plan Task 15 产出) |
| 看日志来源×平台矩阵实测数据 | `design/log-matrix-measured.md` |
| 看本次重构的整体设计背景与决策记录 | `design/2026-07-16-skills-architecture.md` |

### 4.2 目录结构(spec §9)

```
docs/skills/
├── README.md                 # 本文件(看一个文件懂全貌)
├── inventory.md              # 全部 skill 清单:层/工具/健康度/状态/废弃记录
├── design/
│   ├── 2026-07-16-skills-architecture.md   # 设计 spec(权威)
│   └── log-matrix-measured.md              # 实测日志矩阵(供 ios-logs 引用)
├── conventions/
│   ├── skill-template.md     # skill-creator 中文模板(正文中文+中英 description+allowed-tools)
│   ├── naming.md             # 命名/分组前缀规则
│   ├── decoupling.md         # 与示例 App 解耦硬规则 + 占位符 + evals 澄清
│   └── lifecycle.md          # EXPERIMENTAL 挂账上限 + 废弃标准
├── examples/
│   └── spmexample-login/     # SPMExample 登录真实案例(intent + run-report,plan Task 15)
├── l0-build-debug.md         # L0 ios-debugger-agent 定位与选择规则(plan Task 16)
└── archive/                  # docs 顶层散报告 + 旧设计文档归档(plan Task 17)
```

> `l0-build-debug.md` 已由 plan Task 16 产出;`archive/` 尚未创建,由 plan Task 17 产出。本 README 提前在导航中列出,方便后续 task 直接更新。

---

## 5. 写/改 skill 的快速入口

1. **起名**:`conventions/naming.md` §2 选前缀 → §1 查命名映射。
2. **写正文**:`conventions/skill-template.md` §2 拿 frontmatter 示例 → §3 套六小节骨架。
3. **解耦自检**:`conventions/decoupling.md` §5 跑清单。
4. **生命周期判断**:新建默认 `active` + `healthy`;确有未验证项才标 `experimental`,并写明 1 迭代验证计划(`conventions/lifecycle.md` §2–§3)。
5. **更新清单**:在 `inventory.md` 里登记(或更新健康度/状态)。
6. **验证命令**:plan `2026-07-16-skills-refactor.md` 的 G5 通用验证命令集(每个重写 skill 都跑,全 PASS 才算完成)。

---

## 6. 关键决策摘要(详见 spec §12 与"附:决策记录")

1. **主线**:L1 操作 / L2 测试闭环各自通用,不互相耦合;L0 构建调试单列。
2. **语言**:正文中文 + 中英混合 description。
3. **空壳/重叠**:删空壳 + 合并重叠(`ios-date-picker` / `ios-table-actions` / `ios-controller-navigation`)。
4. **L0 纳入**:全局 `ios-debugger-agent` 纳入分层定位(改名影响其他项目,保留原名)。
5. **命名**:语义前缀分组(L1 细化为 `ios-ui-*` + `ios-logs`)。
6. **日志**:新增 `ios-logs`,含来源×平台矩阵与 `unavailable` 语义(实测数据见 `design/log-matrix-measured.md`)。
7. **evals**:静态结构 evals 严格通用;动态回归 evals 可用 SPMExample 作参考 fixture(放 `examples/spmexample-login/`),**不算 skill 本体耦合**。
