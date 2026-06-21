
# Agent Instruction 与 Docs 知识库组织规则

## 目标

项目中的 `AGENTS.md` / `CLAUDE.md` 不应作为“百科全书”使用，而应作为：

1. 入口地图
2. 硬性规则
3. 高频命令
4. 文档路由表

详细背景、设计解释、使用案例、架构说明、排障手册等内容应放入结构化的 `docs/` 目录中，作为真实知识库。

---

## 当前仓库适用边界

- 本仓库同时支持 Codex 和 Claude Code。
- `AGENTS.md` 是 Codex 主入口；`CLAUDE.md` 是 Claude Code 主入口（用 `@AGENTS.md` 单源引入，避免双份维护）。
- `.claude/rules/` 是 Claude Code 路径触发规则，同时也可作为 Codex 按路由主动读取的规则源。
- 本仓库为**个人项目**，稳定知识库与 AI 配置（`docs/`、`.claude/`、`AGENTS.md`、`CLAUDE.md`）**正常纳入 git**。（"公司项目阶段不提交"的旧约定不适用于本仓库。）
- 构建方式：SPM 库 `swift build` / `swift test`；framework 工程 `xcodebuild`；测试 App `Examples/SPMExample`（Xcode Run）；真机端到端经 `./scripts/proxy.sh` + `curl`。

---

## 核心原则

### 1. `AGENTS.md` / `CLAUDE.md` 是地图，不是正文

这些文件会在 CLI 或 agent 启动、进入目录、匹配路径时更容易进入上下文。因此它们应该保持短小、明确、可执行。

应该包含：

* 必须遵守的硬规则
* 高频测试 / 构建 / lint 命令
* 当前模块的职责边界
* 重要禁止事项
* “什么情况应该阅读哪个 docs 文件”的路由表

不应该包含：

* 大段架构背景
* 长篇设计原则
* 完整 API 文档
* 大量网络工具调用案例
* 长篇排障流程
* 历史决策背景
* 可以按需读取的正文内容

---

### 2. `docs/` 是真实知识库

`docs/` 用来保存详细、稳定、可维护的知识。

适合放入 `docs/` 的内容包括：

* 项目结构说明
* 模块架构说明
* 设计准则
* 代码规范的详细解释
* 网络工具使用案例
* API 调用示例
* 排障手册
* 领域模型
* 数据流说明
* 历史设计决策
* 反模式与案例分析

推荐结构：

```text
docs/
  architecture/
    index.md
    module-boundaries.md
    data-flow.md

  design/
    principles.md
    frontend.md
    anti-patterns.md

  modules/
    auth.md
    billing.md
    search.md

  tools/
    network-tools.md
    examples.md

  runbooks/
    debugging.md
    release.md
```

---

## 推荐职责划分

### 根目录 `AGENTS.md` / `CLAUDE.md`

用于全局规则和全局地图。

示例：

```md
# Repository agent guide

## Always follow

- Run tests before finishing code changes.
- Do not invent API behavior; check existing docs or source code first.
- Prefer existing abstractions over adding new framework-level patterns.
- Keep changes minimal and scoped to the task.

## Common commands

- Install: `pnpm install`
- Test: `pnpm test`
- Lint: `pnpm lint`
- Typecheck: `pnpm typecheck`

## Documentation map

Read these docs when relevant:

- Overall architecture:
  - `docs/architecture/index.md`

- Module boundaries and dependency direction:
  - `docs/architecture/module-boundaries.md`

- Design principles:
  - `docs/design/principles.md`

- External API calls, retries, rate limits, network tools:
  - `docs/tools/network-tools.md`

- Debugging and incident workflows:
  - `docs/runbooks/debugging.md`
```

---

### 模块级 `AGENTS.md` / `CLAUDE.md`

用于模块局部规则和模块文档入口。

示例：

```md
# Billing module agent guide

## Module responsibility

This module owns invoices, subscriptions, payment retries, refunds, and billing ledger behavior.

## Must follow

- Do not change billing ledger semantics without reading `docs/modules/billing.md`.
- Preserve idempotency for payment retries.
- Do not bypass existing payment provider adapters.
- Run `pnpm test billing` before finishing billing-related changes.

## Read when relevant

- Billing domain model:
  - `docs/modules/billing.md`

- Module boundaries:
  - `docs/architecture/module-boundaries.md`

- External API and retry behavior:
  - `docs/tools/network-tools.md`

## Local conventions

- Public APIs live in `src/public/`.
- Internal adapters live in `src/adapters/`.
- Tests should be colocated as `*.test.ts`.
```

---

## “地图”应该怎么写

不要只列文件名：

```md
- `docs/tools/network-tools.md`
```

更好的写法是写清楚触发条件：

```md
- If adding or modifying external HTTP calls, retry behavior, timeout handling, API clients, or rate-limit logic, read `docs/tools/network-tools.md` before editing.
```

推荐格式：

```text
场景 / 路径 / 关键词 / 行为约束 -> 应阅读的文档
```

示例：

```md
## Read-when-needed map

- Changing files under `modules/auth/**`
  → Read `docs/modules/auth.md`

- Touching login, sessions, OAuth, JWT, cookies, or permissions
  → Read `docs/modules/auth.md`

- Adding or modifying external HTTP calls
  → Read `docs/tools/network-tools.md`

- Refactoring across modules
  → Read `docs/architecture/module-boundaries.md`

- Adding a new UI component
  → Read `docs/design/frontend.md`

- Changing retry, timeout, rate-limit, or circuit-breaker behavior
  → Read `docs/tools/network-tools.md`
```

本仓库的 iOS 定制示例：

```md
## Read-when-needed map

- Changing `EWork/**`
  → Read `docs/architecture/ework-architecture.md`

- Touching DI, `ServiceInterfaces`, or `AppModuleRegister`
  → Read `docs/tools/di-container.md`

- Touching app launch, lifecycle, plugin registration, or event dispatch
  → Read `docs/architecture/coo-orchestrator.md`

- Touching RPC, signing, token, or request definitions
  → Read `docs/tools/network-tools.md`

- Touching legacy OC/Swift MVC code under `ShangHangEWork/Sources/**`
  → Read `docs/architecture/legacy-sources.md`

- Changing build or test instructions
  → Read `docs/runbooks/build-and-test.md`
```

---

## 内容放置判断标准

使用下面的判断规则：

### 放在 `AGENTS.md` / `CLAUDE.md`

当内容满足以下条件之一：

* agent 每次进入该目录都必须知道
* 是硬性规则
* 是禁止事项
* 是高频命令
* 是模块职责边界
* 是文档导航入口
* 是很短的关键约束

示例：

```md
- Do not call payment provider APIs directly; use `PaymentProviderAdapter`.
- Run `pnpm test billing` before finishing billing changes.
- If touching subscription lifecycle logic, read `docs/modules/billing.md`.
```

---

### 放在 `docs/`

当内容满足以下条件之一：

* 解释性内容较长
* 是背景知识
* 是设计理念
* 是案例集合
* 是完整 API 说明
* 是排障流程
* 只在特定任务中需要阅读
* 不需要每次自动进入上下文

示例：

```text
docs/modules/billing.md
docs/tools/network-tools.md
docs/design/principles.md
docs/architecture/data-flow.md
```

---

### 放在 `.claude/rules/`

适用于 Claude Code 专用的路径触发规则。

适合放：

* 只对某类文件生效的规则
* 只对某个路径生效的规则
* 不希望全局注入上下文的局部规则

示例：

```text
.claude/rules/
  api-rules.md
  react-component-rules.md
  network-tool-rules.md
```

例如：

```md
---
paths:
  - "src/api/**/*.ts"
  - "modules/**/api/**/*.ts"
---

# API rules

- Validate request input before calling services.
- Do not expose internal error messages to clients.
- Use existing response helpers.
```

---

## Codex CLI 与 Claude Code 的区别

### Codex CLI

Codex CLI 会读取并合并相关路径上的 `AGENTS.md` 文件。

例如：

```text
repo/
  AGENTS.md
  modules/billing/
    AGENTS.md
```

当 agent 在 `modules/billing/` 中工作时，根目录和模块目录的 `AGENTS.md` 都可能进入上下文。

但 Codex CLI 不会因为 `AGENTS.md` 中写了 `docs/modules/billing.md` 就自动把该文档正文合并进上下文。

因此，`AGENTS.md` 应写成地图，指引 agent 在需要时主动读取对应 docs 文件。

---

### Claude Code

Claude Code 会读取相关的 `CLAUDE.md` 文件。

如果 `CLAUDE.md` 中使用：

```md
@docs/tools/network-tools.md
```

那么该文件内容会在运行时被展开并加载进上下文。

因此，`@` 只应该用于短小、每次都必须加载的内容，不应大量导入长文档。

普通文字引用不会自动展开：

```md
Read `docs/tools/network-tools.md` when modifying network calls.
```

这种写法只是地图指引，不会自动把文档合并进上下文。

---

## 推荐迁移策略

### 第一步：压缩现有 `AGENTS.md` / `CLAUDE.md`

把每个模块文件中的内容分成三类：

1. 必须保留在 instruction 文件中的硬规则
2. 应迁移到 `docs/` 的解释性正文
3. 应迁移到 `.claude/rules/` 的路径触发规则

---

### 第二步：迁移长内容到 `docs/`

以下内容优先迁移：

* 超过 20–30 行的设计说明
* 大量工具使用案例
* 长篇项目结构描述
* 模块背景说明
* 排障步骤
* API 返回结构解释
* 历史设计原因

---

### 第三步：在 `AGENTS.md` / `CLAUDE.md` 中建立路由表

迁移后，原文件不删除知识入口，而是改成：

```md
If the task touches <condition>, read <docs/path.md>.
```

例如：

```md
- If changing billing retry behavior, read `docs/modules/billing.md`.
- If adding a new network call, read `docs/tools/network-tools.md`.
- If moving code between modules, read `docs/architecture/module-boundaries.md`.
```

---

### 第四步：限制 `@import`

Claude Code 中，避免这样做：

```md
@docs/architecture/index.md
@docs/design/principles.md
@docs/tools/network-tools.md
@docs/modules/billing.md
```

除非这些文件非常短，并且每次任务都必须加载。

更推荐：

```md
## Read when relevant

- Architecture overview: `docs/architecture/index.md`
- Design principles: `docs/design/principles.md`
- Network tools: `docs/tools/network-tools.md`
- Billing domain model: `docs/modules/billing.md`
```

---

## 最终目标结构

```text
repo/
  AGENTS.md
  CLAUDE.md

  docs/
    architecture/
      index.md
      module-boundaries.md
      data-flow.md

    design/
      principles.md
      frontend.md
      anti-patterns.md

    modules/
      auth.md
      billing.md
      search.md

    tools/
      network-tools.md
      examples.md

    runbooks/
      debugging.md
      release.md

  modules/
    auth/
      AGENTS.md
      CLAUDE.md
      src/

    billing/
      AGENTS.md
      CLAUDE.md
      src/

  .claude/
    rules/
      api-rules.md
      react-component-rules.md
      network-tool-rules.md
```

---

## 一句话原则

`AGENTS.md` / `CLAUDE.md` 是启动时进入上下文的路由器。
`docs/` 是不默认进入上下文的真实知识库。
`.claude/rules/` 是 Claude Code 中按路径触发的局部规则。
`@import` 是显式把文件内容合并进上下文，应谨慎使用。

不要让 instruction 文件变成百科全书；让它们成为高质量地图。

## 重构提示词
请按照以下规则重构本仓库的 AGENTS.md / CLAUDE.md / docs 结构：

1. 保留 AGENTS.md / CLAUDE.md 中的硬规则、高频命令、模块边界、禁止事项和文档路由表。
2. 将长篇项目结构说明、设计准则、工具使用案例、排障流程、API 示例迁移到 docs/。
3. 在 AGENTS.md / CLAUDE.md 中使用 “If the task touches X, read docs/Y.md” 的格式建立地图。
4. 不要使用 @import 大量导入长文档；@import 只用于每次都必须加载的短文件。
5. 对 Claude Code 专用、按路径生效的规则，迁移到 .claude/rules/ 并添加 paths frontmatter。
6. 最终目标是：instruction 文件短小、明确、可执行；docs 目录承载详细知识。
