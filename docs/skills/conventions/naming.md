# Skill 命名与分组规则

> 本文规定 `.claude/skills/` 下全部 skill 的目录名、`name` 字段、前缀分组规则。规范依据:`docs/skills/design/2026-07-16-skills-architecture.md` §5 与 plan `2026-07-16-skills-refactor.md` 的 G1。

---

## 1. 命名映射表(G1 全文)

重构严格按下表对应改名,**新名是权威**,旧名在 description 里保留一个迭代作过渡关键词(见 `skill-template.md` §1)。

| 旧目录 | 新目录 | 处理 |
|---|---|---|
| `ios-navigation` | `ios-ui-nav` | 留,精简,吸收 controller-nav |
| `ios-list-interaction` | `ios-ui-list` | 留,精简 |
| `ios-form-filling` | `ios-ui-form` | 留,精简 |
| `ios-screenshot` | `ios-ui-shot` | 留,精简 |
| `ios-alert-handling` | `ios-ui-alert` | 留,精简 |
| `ios-gestures` | `ios-ui-gesture` | 留,删 `ui.drag`、删重复小节、精简 |
| `ios-dynamic-content` | `ios-ui-wait` | 留,补 wait 验证说明 |
| `ios-automation` | `ios-automation` | 不变;主文件 `skill.md` → `SKILL.md` |
| `ios-test-intent` | `ios-test-intent` | 不变 |
| `ios-test-runner` | `ios-test-runner` | 不变 |
| (新建) | `ios-logs` | 新建(L1 进程日志读取) |
| `ios-date-picker` | — | **删除**(`ui.datePicker.*`/`ui.picker.*` 不存在) |
| `ios-table-actions` | — | **删除**(`ui.table.*`/`ui.collection.*` 不存在) |
| `ios-controller-navigation` | — | **删除**,`ui.controllers` 能力并入 `ios-ui-nav` |

**净结果**:14 个 → 12 个(删 2 空壳 + 合并 1 + 新增 `ios-logs`)。

---

## 2. 三层前缀规则

每个 skill 的**目录名**与 frontmatter 的 **`name` 字段**必须使用对应层的前缀。前缀决定 skill 的工具体系与职责范围。

| 层 | 前缀/命名模式 | 工具体系 | 含义 |
|---|---|---|---|
| **L0 构建调试** | `ios-debugger-agent`(固定名) | XcodeBuildMCP(`mcp__XcodeBuildMCP__*`) | 编译、运行、启动、调试 App 进程,捕获系统级日志 |
| **L1 操作层** | `ios-ui-*` | iOSDriver(`mcp__iOSDriver__*`,封装 iOSExploreServer HTTP) | 纯 UI 操作(tap / input / alert / nav / list / shot / gesture / wait) |
| **L1 操作层(日志)** | `ios-logs`(单数,不带 `-ui-`) | iOSDriver(`mcp__iOSDriver__app_logs_*`) | 进程内日志读取,非 UI,单独命名 |
| **L1 操作层(总入口)** | `ios-automation`(不带 `-ui-`,因为统领 UI + 日志) | iOSDriver | 连接管理、iproxy、路由到子 skill、快速诊断 |
| **L2 测试闭环** | `ios-test-*` | iOSDriver + 离线源码分析 | 读业务源码产出测试判据 → 自动驱动 UI 跑 → 出覆盖报告 |

### 2.1 L1 用两个子前缀区分能力类型

- **`ios-ui-*`**(7 个):纯 UI 操作。命名模式 `ios-ui-<能力简称>`(如 `ios-ui-nav`、`ios-ui-form`、`ios-ui-shot`)。
- **`ios-logs`**(1 个):进程日志读取,非 UI,**不带 `-ui-`**。
- **`ios-automation`**:L1 总入口,统领 UI + 日志,**不带 `-ui-`**,因为它的职责是路由而不是单点 UI 能力。

### 2.2 不要发明新前缀

新增 skill 必须落到上表已有前缀下;如需新前缀(例如引入全新工具体系),必须先更新本文件 + `design/2026-07-16-skills-architecture.md`,再写 skill。**不允许出现 `ios-picker-*`、`ios-table-*`、`ios-vc-*` 这类本次已废弃或虚构的前缀。**

---

## 3. 不支持子目录分组(依据)

**Claude Code skill 以目录名为 skill 名**;`<skill-dir>/SKILL.md` 是唯一入口文件。除 `evals/`、`references/` 等 skill 内部约定子目录外,**子目录不会被识别为独立 skill**。

因此本仓库的分组**不靠目录嵌套**(没有 `.claude/skills/ui/nav/...`、`.claude/skills/l1/form/...` 这样的树),而是靠:

1. **命名前缀**(`ios-ui-*` / `ios-logs` / `ios-test-*` / `ios-automation` / `ios-debugger-agent`)—— 见上表。
2. **`docs/skills/inventory.md`**——12 个 skill 的权威状态表(层 / 工具体系 / 健康度 / 状态)。
3. **`docs/skills/README.md`**——三层架构总览 + 导航。

依据:`docs/skills/design/2026-07-16-skills-architecture.md` §5 末段。

---

## 4. 主文件名规则

- 所有 skill 主文件统一命名为 **`SKILL.md`**(大写)。
- `ios-automation` 现为小写 `skill.md`,在 plan Task 3 Step 2 改名为 `SKILL.md`。
- 验证命令(plan §11 / Task 18):
  ```bash
  find .claude/skills -iname 'skill.md' -not -name 'SKILL.md'   # 应无输出
  ```

---

## 5. 改名过渡规则

改名后旧名触发短期失效,过渡措施:

1. **description 保留旧名关键词**:如 `ios-ui-form` 的 description 必须含 `"原 ios-form-filling"`(见 `skill-template.md` §1)。
2. **过渡期一个迭代**:一个迭代后(由 plan 阶段决定)从 description 移除旧名关键词。
3. **回退**:git 恢复旧目录名(风险低,改名纯目录操作)。

依据:spec §5 倒数第二段;§12 风险与回退第 1 条。

---

## 6. 命名反例(不要这样命名)

| 反例 | 为什么错 | 正确做法 |
|---|---|---|
| `ios-picker` / `ios-date-picker` | 本次已删,action 不存在 | 不要重建;日期选择器用 `ios-ui-form`(步进器/滑块同档)或 `ios-ui-wait`(等动画结束)的能力覆盖 |
| `ios-table-actions` / `ios-collection` | 本次已删,action 不存在 | 不要重建;列表/集合视图操作归 `ios-ui-list` |
| `ios-vc-nav` / `ios-controller-nav` | 本次已合并到 `ios-ui-nav` | 不要新建;controller 层级检查(`ui.controllers`)在 `ios-ui-nav` 里 |
| `ios-form` / `ios-nav` / `ios-shot` | 缺 `ui-` 中缀,L1 UI 操作层前缀不对 | 必须 `ios-ui-*` |
| `ios-log`(单数)/ `ios-app-logs` | 命名不对齐 spec §5 | 必须 `ios-logs` |
| `ios-tests` / `ios-test` | L2 前缀是 `ios-test-*`,必须有具体后缀 | `ios-test-intent` / `ios-test-runner`,或申请新前缀(见 §2.2) |
