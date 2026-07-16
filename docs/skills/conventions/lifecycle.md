# Skill 生命周期与 EXPERIMENTAL 挂账上限

> 本文规定 skill 从新建到废弃的状态标准,重点解决"空壳 skill 长期标 EXPERIMENTAL 占位"的教训。规范依据:`docs/skills/design/2026-07-16-skills-architecture.md` §1 问题 2、§4.1 处理列、§12 风险与回退第 4 条。

---

## 1. 状态字段(`inventory.md` 用)

`docs/skills/inventory.md` 用两个字段标记每个 skill 的状态:

| 字段 | 取值 | 含义 |
|---|---|---|
| **健康度** | `healthy` | 正文中文 + skill-creator 规范、`allowed-tools` 齐全、静态 evals 通过、动态 evals(如有)无回归 |
| | `needs-test` | 已完成结构重写,但缺关键验证(如动态 evals 未跑、真实 action 未交叉对照) |
| | `empty-shell`(废弃态专用) | 承诺的 action 在 iOSDriver 不存在,skill 实际不可用 |
| **状态** | `active` | 当前推荐使用 |
| | `experimental` | 标 EXPERIMENTAL,挂账上限见 §2,**默认不推荐新任务用它** |
| | `planned` | 已在 spec §4.2 立项,尚未创建目录 |
| | `deprecated` | 已废弃但目录还在(过渡期) |
| | `removed` | 已从 `.claude/skills/` 删除,仅在 `inventory.md` 保留历史记录 |

---

## 2. EXPERIMENTAL 挂账上限(核心规则)

### 2.1 规则全文

**任何 skill 标 `experimental` 必须在 1 个迭代内补齐测试**;到期未补的,按以下顺序降级处理:

1. **能力单一且可并入其他 skill** → 降级合并到目标 skill(例:`ios-controller-navigation` 并入 `ios-ui-nav`)。
2. **承诺的能力在 iOSDriver 不存在** → **直接删除**,不保留空壳(例:`ios-date-picker`、`ios-table-actions`)。
3. **能力存在但未验证** → 补动态 evals 后转 `active`,或降级合并到能力更全的 skill。

**不允许**:长期标 `experimental` 占位、不做任何验证、又不删除。这是本次重构的核心教训。

### 2.2 教训来源(spec §1 问题 2)

本次重构前,仓库存在 3 个空壳/半空壳 skill:

| skill | 状态 | 问题 | 处理 |
|---|---|---|---|
| `ios-date-picker`(158 行) | NOT TESTED | 承诺 `ui.datePicker.*` / `ui.picker.*` action,**这些 action 在 iOSDriver 根本不存在** | 删除 |
| `ios-table-actions`(214 行) | NOT TESTED | 承诺 `ui.table.*` / `ui.collection.*` action,**这些 action 在 iOSDriver 不存在** | 删除 |
| `ios-controller-navigation`(133 行) | EXPERIMENTAL | 能力存在(`ui.controllers` 可用)但单一,实际能力与 `navigation` 不重叠,长期未补测试 | 合并到 `ios-ui-nav` |

这 3 个 skill **长期挂账**的原因是当初创建时未交叉对照 iOSDriver 真实 action 清单(plan G6),承诺了不存在的能力。本次重构把"交叉对照真实 action"写入 `skill-template.md` §2,把"挂账上限"写入本文件,避免重蹈。

### 2.3 为什么不允许长期 EXPERIMENTAL

- **误导调用方**:其他 agent 看到目录存在,以为能力可用,实际调用必然失败。
- **污染 inventory**:`inventory.md` 列出多少 skill,就该有多少可用的能力;空壳让清单失真。
- **降低重构门槛**:留着空壳=下次还得处理;早删早轻松。

---

## 3. 新建 skill 的默认状态

**新建 skill 默认 `active` + `healthy`**,不要默认标 `experimental`。只有以下情况才标 `experimental`:

- 该 skill 调用的某个 action 尚未在模拟器 + 真机各实测一次(如 `ios-logs` 的 `oslog` / `nslog` 来源矩阵,见 `design/log-matrix-measured.md`)。
- 该 skill 的方法论待案例验证(如 `ios-test-intent` 的"读源码产出判据"流程)。

标 `experimental` 必须**同时**写明:

1. 哪个具体能力未验证(不是"整个 skill 不靠谱")。
2. 1 个迭代内的验证计划(具体到"在哪个 App / 哪个场景跑一次")。
3. 到期未验证的降级路径(合并到哪个 skill,或删除)。

---

## 4. 废弃标准

### 4.1 何时废弃(`deprecated`)

skill 满足以下任一条件进入 `deprecated`:

- 能力已被其他 skill 完全覆盖(重复)。
- 调用的 action 被 iOSDriver 弃用(目前无此情况,但留口)。
- 命名不符合 `naming.md` §2 且无法直接改名(例如需要拆分)。

`deprecated` 状态保留**一个迭代**作过渡:

- description 加 `"已废弃,改用 <新 skill>"` 关键词。
- 一个迭代后从 `.claude/skills/` 删除,状态转 `removed`。

### 4.2 何时直接删除(`removed`)

skill 满足以下任一条件**直接删除**(不经 deprecated 过渡):

- 承诺的 action 在 iOSDriver 不存在(空壳)。
- 能力已被合并到其他 skill 且原目录内容完整迁出。

删除后:

- `.claude/skills/<skill>/` 目录整个移除。
- `inventory.md` 保留该 skill 行,状态 `removed`,并在"原因"列写明删除依据(供未来回顾)。
- `design/2026-07-16-skills-architecture.md` §4.1 的处理列已注明删除原因,作为决策依据。

### 4.3 已删除 skill 的历史记录

本次重构已删除的 3 个 skill 在 `inventory.md` 保留为 `removed` 状态(不抹除历史):

| skill | 删除原因 | 决策依据 |
|---|---|---|
| `ios-date-picker` | `ui.datePicker.*` / `ui.picker.*` 不存在 | spec §1 问题 2、§4.1 |
| `ios-table-actions` | `ui.table.*` / `ui.collection.*` 不存在 | spec §1 问题 2、§4.1 |
| `ios-controller-navigation` | 能力单一(`ui.controllers` 读取),并入 `ios-ui-nav` | spec §4.1、plan Task 3 Step 4 |

---

## 5. 状态转移图

```
   新建 ───────────────────► active
                          │
                          │(发现未验证项)
                          ▼
                       experimental ──── 1 迭代内补测试 ───► active
                          │
                          │(到期未补,降级路径 1/2/3)
                          ├── 能力单一可并 ─► deprecated(1 迭代)──► removed
                          ├── action 不存在 ─────────────────► removed
                          └── 待验证未跑 ──► deprecated(1 迭代)──► removed 或 合并
```

**关键**:状态不能"卡住"。`experimental` 与 `deprecated` 都有 1 迭代上限,到期必须落到 `active` 或 `removed`。

---

## 6. 重构后的预期终态

按 plan Task 1–18 执行完毕后,`inventory.md` 应达到的终态:

- **12 个 skill 全部 `active`**(`ios-debugger-agent` / 7 个 `ios-ui-*` / `ios-logs` / `ios-automation` / 2 个 `ios-test-*`)。
- **3 个 skill 标 `removed`**(`ios-date-picker` / `ios-table-actions` / `ios-controller-navigation`),作为历史记录保留。
- **0 个 `experimental`**(除非有明确未验证项并写明 1 迭代验证计划)。
- **0 个 `deprecated`**(过渡期已过)。

健康度 `healthy` 与 `needs-test` 的具体分布由各 skill 重写 task 的验证结果决定(plan Task 4–14 各自的 G5 命令集),不在本文件预设。
