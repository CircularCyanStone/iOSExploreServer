# Skill 中文模板(skill-creator 套用)

> 本文是 skill-creator 重写/新建每个 skill 时的**统一模板**。所有 `.claude/skills/<skill>/SKILL.md` 必须按此结构产出。规范依据:`docs/skills/design/2026-07-16-skills-architecture.md` §6 与 plan `2026-07-16-skills-refactor.md` 的 G2/G4 R1。

---

## 1. 语言规则(G2 全文)

| 元素 | 规则 | 说明 |
|---|---|---|
| **正文** | 全中文 | 开发者能读懂、参与构建与评审。代码块、命令、MCP 工具名、frontmatter 字段名保持英文原样。 |
| **`description`** | 中英混合 | 中文说清用途 + 英文关键词保证英文 prompt 下触发率。纯中文 description 在英文 prompt 下触发率下降,混合最稳。 |
| **改名 skill 的过渡关键词** | description 必须含旧名关键词(如 `"原 ios-form-filling"`),过渡期一个迭代后移除 | 避免改名导致旧触发失效。 |
| **frontmatter 字段顺序** | `name` → `description` → `allowed-tools`(严格三字段,顺序固定) | skill-creator 规范。缺 `allowed-tools` 视为不合规。 |

### 1.1 description 中英混合示例

```
iOS App 表单填写与控件操作 / form filling, text input, switch, slider, stepper, segmented, keyboard
读取 iOS App 进程内日志 / app logs, stdout, stderr, nslog, oslog, debug, mark, read
iOS App 弹窗检测与响应(原 ios-alert-handling)/ alert, action sheet, dialog, confirm
```

**反例**(不要这样写):
- 纯英文长句:`"This skill handles iOS form filling..."`
- 纯中文:`"处理 iOS 表单填写"`
- 缺旧名过渡关键词的改名 skill:`"iOS App 表单填写"`(改名后应含 `"原 ios-form-filling"`)

---

## 2. frontmatter 完整示例

```yaml
---
name: ios-ui-form
description: iOS App 表单填写与控件操作(原 ios-form-filling)/ form filling, text input, switch, slider, stepper, segmented, keyboard, submit
allowed-tools:
  - mcp__iOSDriver__ui_input
  - mcp__iOSDriver__ui_tap
  - mcp__iOSDriver__ui_tap_and_inspect
  - mcp__iOSDriver__ui_control_sendAction
  - mcp__iOSDriver__ui_keyboard_dismiss
  - mcp__iOSDriver__ui_inspect
  - mcp__iOSDriver__ui_scrollToElement
---
```

**要点**:
- `name` 必须与目录名一致(目录 = `ios-ui-form`,name 必须是 `ios-ui-form`)。Claude Code skill 以目录名为 skill 名,详见 `naming.md`。
- `allowed-tools` 列出该 skill 正文实际调用的 MCP 工具,工具名必须来自 iOSDriver 真实工具集(见 plan G6)或 XcodeBuildMCP(L0)。不允许写不存在的工具(如 `mcp__iOSDriver__ui_datePicker_setDate`、`mcp__iOSDriver__ui_drag` 均不存在)。
- 字段顺序固定:`name` → `description` → `allowed-tools`。

---

## 3. 正文结构骨架(R1 全文)

每个 skill 正文按以下六个 `##` 小节产出,**目标 150–250 行**(精炼,不堆参数表)。删除当前手搓模板里膨胀的重复参数表与冗长示例。

```markdown
# <skill 中文名>

<1–2 句话说明这个 skill 做什么、基于哪个工具体系。>

## 目标

<这个 skill 解决什么实际问题。3–5 行,聚焦"开发者为什么要用它"。>

## 何时使用

<触发条件清单。明确"用户说什么话/遇到什么场景应该用它"。同时给出**不要用它**的场景(指向更合适的 skill)。>

- ✅ 用户要 ...
- ✅ 用户说 "..." / "..." / "..."
- ❌ 不要用于 ...(改用 `<其他 skill>`)

## 工作原理

<核心机制说明。这个 skill 调用的 iOSDriver action / XcodeBuildMCP 工具、它们返回什么、按什么顺序调用。用编号步骤或流程文字描述,不要贴大段代码。>

1. ...
2. ...
3. ...

## 关键参数

<这个 skill 用到的 action 的关键入参,用表格或短列表。只列"作者需要记住"的参数,不抄全部 schema。>

| 参数 | 含义 | 注意 |
|---|---|---|
| `xxx` | ... | ... |

## 常见错误与判别

<这是最重要的一节。列该 skill 常见的失败模式、对应业务码/HTTP 状态、与相似错误的区分方法。每条给"现象 → 原因 → 处理"。>

- **现象**:...
  - **原因**:...
  - **判别**:看响应里的 `code` / `capture.state` / ... 字段
  - **处理**:...

## 相关 skill

<指向同一层或上下游的 skill,说明何时切换。>

- `<skill-name>` — 何时改用它
- `<skill-name>` — 上游/下游关系
```

### 3.1 骨架要点

- **小节顺序固定**,不要增删。每节有明确职责,避免当前膨胀模板的"参数表两份""Best Practices 重复"等问题。
- **目标行数 150–250**:重写时从旧 skill(动辄 549–745 行)精简到这个区间。超出通常是重复或冗余示例。
- **常见错误与判别**是 skill 的核心价值:旧 skill 大量缺失"怎么判断到底发生了什么",新 skill 必须补齐。
- **相关 skill** 必须给"切换条件",不能只列名字。

---

## 4. evals 配套(R3)

每个 skill 必须有 `.claude/skills/<skill>/evals/evals.json`,包含两类 case:

| 类型 | 是否依赖运行 App | 内容 | 解耦要求 |
|---|---|---|---|
| **静态结构 evals**(必有) | 否 | frontmatter 三字段齐全、正文无 SPMExample 硬编码、引用的 action 在 iOSDriver 真实存在 | 严格通用,过 `decoupling.md` 全部硬规则 |
| **动态回归 evals**(需要时) | 是 | 用 SPMExample 作为参考 fixture,驱动 UI 跑核心命令 | 可引用 `docs/skills/examples/spmexample-login/` 作 fixture,**不算 skill 本体耦合** |

详见 `decoupling.md` 第 3 节"evals 解耦澄清"。

---

## 5. 重写标准流程(G4 R1–R6 摘要)

每个重写 skill 都执行(plan G4 原文):

| 步骤 | 动作 |
|---|---|
| **R1** | 用 skill-creator 按本模板重写 `SKILL.md`(中文正文 + 中英 description + `allowed-tools` + 六小节结构,150–250 行) |
| **R2** | 解耦:正文过 `decoupling.md` G3 硬规则 grep,全部 PASS |
| **R3** | 保留并解耦 `evals/evals.json`:静态结构 case 必有,动态 case 可引 examples fixture |
| **R4** | 跑 `plan G5` 通用验证命令集,全部 PASS |
| **R5** | (可选)动态 evals:启动 SPMExample 跑该 skill 的核心命令,确认无回归 |
| **R6** | Commit:`<type>(skills): <描述>`(无 attribution) |

G5 验证命令集见 plan `2026-07-16-skills-refactor.md` 第 51–63 行,此处不重复。

---

## 6. 与其他 conventions 的关系

| 文件 | 管什么 | 本模板的衔接点 |
|---|---|---|
| `naming.md` | 目录名/skill 名/前缀规则 | `name` 字段与目录名一致;`allowed-tools` 的 MCP 前缀随层不同 |
| `decoupling.md` | SPMExample 解耦硬规则 + 占位符 + evals 澄清 | "关键参数"与"工作原理"里举例时必须用占位符,不能用真实 bundle id/UDID |
| `lifecycle.md` | EXPERIMENTAL 挂账上限、废弃标准 | 新建 skill 默认 active + healthy,不要默认标 EXPERIMENTAL(除非有明确未验证项) |
