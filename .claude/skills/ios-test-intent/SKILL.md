---
name: ios-test-intent
description: |
  Offline source-analysis skill: reads iOS app business code (Service / ViewModel /
  ViewController) and produces a test-intent contract — per-scenario pass_criteria /
  fail_criteria expressed in the ios-* wait vocabulary (textExists / targetExists /
  targetGone / alert), ready to feed into ui_waitAny.conditions. Emits NO path /
  identifier / viewSnapshotID (those are resolved at runtime by ui_inspect).

  Use this skill when the user needs to author a test plan, list pass/fail criteria,
  or derive a test-intent checklist FROM SOURCE CODE (not by running the app).

  Must explicitly mention 测试意图, pass criteria, fail criteria, 测试方案, 读源代码,
  or test intent to trigger.

  Based on iOSDriver MCP Server wait vocabulary; offline/analytical — does not operate
  the app itself. Output is consumable by the ios-* automation skills.
---

# iOS Test Intent Authoring（读源代码产出测试意图）

## Purpose

读 iOS App 的业务源代码，产出"测试意图 + 成功/失败判据清单"：每个场景该测什么、成功长什么样（`pass_criteria`）、失败长什么样（`fail_criteria`）。判据用 `ios-*` 的等待词汇（`textExists` / `targetExists` / `targetGone` / `alert`）表达，**可直接喂给 `ui_waitAny.conditions` 落地执行**。

本 skill 严格只产出**意图层**——"测什么、什么算成败"；**绝不产出执行层**——不写 `path`、`accessibilityIdentifier`、`viewSnapshotID`，那些由运行时 `ui_inspect` 解析。

解决什么问题：agent 跑自动化时"成功/失败判据"常常即兴判断（比如用固定 `sleep` 或 `snapshotChanged`），结果在异步场景抓到 loading 中间态、或把失败误判成成功。把判据来源从"即兴"变成"有源码依据的契约"，是本 skill 的价值。

## When to Use

**触发**（用户要这些时用本 skill）：
- "给某流程设计测试用例 / 列成功失败判据 / 从源码生成测试清单"
- "产出测试意图清单，交给 ios-automation 执行"
- "离线分析某个业务流的分支、边界、陷阱"

**不触发**（去别的 skill）：
- 实际跑 App、点按钮、截图 → `ios-automation`
- 运行时填表单 / 导航 / 处理弹窗 → 对应执行型 skill（`ios-form-filling` 等）

## Prerequisites

- 能读到目标 App 的业务源码（Service / ViewModel / ViewController 三层）。
- 可选：项目已建 codegraph 索引，加速符号定位（`codegraph_explore`）。
- **不需要**：连 App、38321 端口、模拟器、真机——这是离线分析型 skill。

## Capabilities — 5 步工作流

> 本 skill **不调用任何 MCP 命令、不操作 App**。它的工作是"读源代码 → 产出意图清单"。按下面 5 步走，每步说清"读什么、提取什么、产出什么"。

### Step 0 — 圈定 flow 与入口

列出本次要覆盖的业务流（如登录 / 注册 / 重置 / 首页）。每个 flow 定位三件套：入口 `ViewController` + 对应 `ViewModel` 方法 + `Service` 方法。产出一张覆盖范围表。

### Step 1 — 读 Service 层（业务规则、数据真相、时序）

Service 层是业务规则的事实来源，**最先读**。提取四样：

- **校验链与顺序**：每个方法的 `guard` 次序。例（SPMExample）：`login` = 用户存在 → 密码匹配；`register` = 邮箱格式 → 密码≥6 → 用户未占用；`resetPassword` = 密码≥6 → 用户存在且邮箱匹配。
- **时序常量**：`networkDelay`（SPMExample = 1.5s）——所有走 Service 的分支都"约 1.5s 后才出结果"。
- **错误→文案映射**：`AuthError.errorDescription`（如 `invalidCredentials → "用户名或密码错误"`）。注意哪些错误共用同一文案（`login` 的"用户不存在"和"密码错"都映射成 `invalidCredentials`，故意不可区分）。
- **共享可变状态 + 种子数据**：单例 `AuthService.shared.users` 字典 + `init` 预置账号（test / 123456）。

产出：服务端分支清单 + 统一时序 + 副作用（是否写 `users`）。

### Step 2 — 读 ViewModel 层（客户端即时校验链）

ViewModel 是客户端校验入口。提取 `guard` 顺序，并**严格区分两类分支**：

- **客户端即时分支**（不进 Service、不触发 1.5s 延迟）：登录的"用户名空 / 密码空"；注册的"用户名空 → 邮箱空 → 密码空 → 两次密码一致"。判据标 `timing: "立即（客户端校验）"`。
- **服务端异步分支**（走 Service、约 1.5s 后返回）：注册的邮箱格式 / 密码≥6 / 用户未占用；重置的密码≥6 / 邮箱匹配。标 `timing: "约 1.5s 后（服务端）"`。

> ⚠️ **顺序陷阱**：注册的"两次密码一致"是客户端立即校验，但"邮箱格式""密码≥6"在服务端。判据必须按真实顺序与时序标，标错了执行层就会等错信号。

### Step 3 — 读 ViewController 层（状态机、异步行为、行为陷阱）

最后读 VC，提取 UI 行为：

- **UI 状态机**：`idle` →（tap）→ `loading` →（成功 nav / 失败 error）。
- **重入守卫**：`isLoading` 在 `Task` 外**同步置位**（`guard !isLoading`），双击第二次直接 return → 产出"双击守卫"intent。
- **loading 期间按钮行为**：标题清空 `""` + `isEnabled=false` + spinner 转 → 产出"loading 期间按钮禁用"intent。
- **成功导航方式**：SPMExample 用 `setViewControllers([homeVC])` **整栈替换** + `HomeViewController.hidesBackButton = true` → 产出"成功后无法 back"判据（`targetGone` 导航返回按钮）。
- ⚠️ **失败后字段是否清空——必须读源码确认，绝不套用"iOS 标准行为"假设**。SPMExample 的 `loginButtonTapped` 失败分支只调 `showError`，**不清空密码框**（`LoginViewController.swift:230-232`）。这与某些通用文档声称的"登录失败标准会清空密码框"相反。**本 skill 以源码为准** → 产出"失败后密码框保留"intent。这正是本 skill 要防范的典型陷阱（见 Best Practices C）。

### Step 4 — 映射成 pass_criteria / fail_criteria（词汇表固定）

把每个分支翻成一个 `intent` 对象。判据只允许用下列词汇：

| 词汇 | 用法 | 映射到 ui_waitAny |
|---|---|---|
| `textExists` | 出现某可见文案（片段匹配） | `mode="textExists", text=<value>` |
| `textContains` | 文案包含某片段（与 textExists 等价，语义偏好"包含"） | 同上 |
| `targetExists` | 某元素出现，用"角色+可见标签"描述（如"「退出登录」红色按钮"） | `mode="targetExists"` |
| `targetGone` | 某元素/文案消失 | `mode="targetGone"` |
| `alert` | 弹窗出现（运行时用 `ui_inspect` 的 `alert.available==true`） | 运行时解析 |

**禁用词**（进判据 `value` 就错）：`path`、`root/0/1`、`accessibilityIdentifier` 值（`home_logout_button` 等）、`viewSnapshotID`。`identifier` 只允许记录在 `source_refs` 供运行时参考——它是实现细节、会随重构失效；可见文案才是稳定契约。每条判据带 `description`（人话理由）+ `timing`。

### Step 5 — 追踪跨流程副作用（共享存储）

单例 `AuthService.shared.users` 跨流程持久（内存级）。把副作用标进 intent：

- 注册成功 → `users` 增项 → 后续"用新账号登录"可验证。标 `depends_on.seed_data` + `cross_flow_verifiable: "注册→登录"`。
- 重置密码成功 → `users[username].password` 改写 → "旧密码失效 + 新密码生效"可跨流程验证。
- 预置 `test/123456` 是所有成功路径的种子，标 `depends_on.seed_data`。

## Output Format

复用项目已有的 `evals.json` schema，最小扩展。每个 `intent` 对象字段：

| 字段 | 类型 | 含义 |
|---|---|---|
| `id` | string | 场景稳定标识（如 `login-success`） |
| `flow` | string | 所属业务流（`login`/`register`/`reset`/`home`） |
| `intent` | string | 一句话场景名（测什么） |
| `prompt` | string | 自然语言场景描述（可喂给执行层当测试 prompt） |
| `business_points` | string[] | 覆盖的业务符号（如 `LoginViewController.loginButtonTapped`），用于覆盖完整性核对 |
| `files` | string[] | 读过的源码相对路径 |
| `depends_on` | object? | `{ seed_data, shared_state }` 前置依赖 |
| `cross_flow_verifiable` | string? | 可跨流程验证的副作用描述 |
| `pass_criteria` | Criterion[] | 成功判据（全部满足 = 本场景 pass） |
| `fail_criteria` | Criterion[] | 失败判据（任一出现 = 本场景 fail，或反向场景的 pass 信号） |
| `timing` | string? | 整体时序提示（"立即" / "约 1.5s 后"） |
| `known_defect` | boolean? | 源码行为语义错误时置 true（判据仍断言**当前实际行为**，但提醒人工裁决） |
| `source_refs` | string[]? | 关键源码定位（`file:line` 或 `file:symbol`），供过时检测 |

`Criterion` 子对象：`mode`(textExists/textContains/targetExists/targetGone/alert) / `value`(可见文案或角色标签，alert 无文案时 null) / `description` / `timing`。

**样例（登录成功，基于 SPMExample 真实源码）**：

```json
{
  "id": "login-success",
  "flow": "login",
  "intent": "预置账号 test/123456 登录成功，整栈跳首页且无法返回",
  "prompt": "在登录页输入预置账号 test / 123456，点「登录」；预期约 1.5s 后整栈替换到首页，导航无返回按钮。",
  "business_points": [
    "LoginViewModel.login（username/password 非空校验通过）",
    "AuthService.login（test 命中、密码匹配、1.5s networkDelay）",
    "LoginViewController.loginButtonTapped → navigateToHome（setViewControllers 整栈替换）"
  ],
  "files": [
    "Login/ViewModels/LoginViewModel.swift",
    "Login/Services/AuthService.swift",
    "Login/ViewControllers/LoginViewController.swift"
  ],
  "depends_on": { "seed_data": "AuthService.init 预置 test/123456" },
  "pass_criteria": [
    {"mode": "textExists", "value": "欢迎回来！", "description": "首页欢迎语出现，证明整栈跳转成功", "timing": "约 1.5s 后"},
    {"mode": "targetGone", "value": "导航返回按钮", "description": "hidesBackButton=true，无法 back 回登录页"}
  ],
  "fail_criteria": [
    {"mode": "alert", "value": null, "description": "成功路径不应出现任何弹窗"},
    {"mode": "textContains", "value": "用户名或密码错误", "description": "失败文案未出现"},
    {"mode": "targetExists", "value": "「登录」按钮重新启用且仍停留在登录页", "description": "loading 结束但未跳转——请求失败"}
  ],
  "timing": "约 1.5s 后出结果",
  "source_refs": [
    "AuthService.swift:43 login",
    "LoginViewController.swift:274 navigateToHome setViewControllers"
  ]
}
```

多条 intent 聚合成 `evals.json` 的 `evals[]`。完整登录清单见 `docs/test-intents/spmexample-login.json`。

## Usage Examples

1. **"给 SPMExample 登录流程产出测试意图清单"** → 按 Step 0–5 读 `AuthService` / `LoginViewModel` / `LoginViewController`，产出 9–10 条 intent（成功、各类失败、loading 行为、双击守卫、无法返回）。产物见 `docs/test-intents/spmexample-login.json`。
2. **"给重置密码流程列边界陷阱"** → 读 `resetPassword`，发现失败文案复用"用户名或密码错误"（语义实际是"用户不存在或邮箱不匹配"），产出带 `known_defect: true` 的 intent——判据仍断言当前实际文案，但提示人工裁决。
3. **"把意图清单交给 ios-automation 执行"** → 本 skill **止步于产出 JSON**；下游把每条 `pass_criteria`/`fail_criteria` 翻译成 `ui_waitAny.conditions` 运行（执行层的 `path`/`identifier` 由运行时 `ui_inspect` 解析）。

## Best Practices — 6 类风险防范

| 风险 | SPMExample 反例 | 防范写法 |
|---|---|---|
| **A. 把"实现"当"规约"测** | `resetPassword` 失败显示"用户名或密码错误"（语义缺陷）。照抄成断言就是测 bug 当规约。 | 区分**业务规则**（照测）与**实现缺陷**（标 `known_defect:true`，判据仍断言当前实际行为以保证确定性，`description` 提示"疑似缺陷，人工裁决"）。 |
| **B. 幻觉不存在的元素** | 凭空写"记住我 复选框"——登录页根本没有。 | 每条判据 `value` 必须可回溯到一个源码出处（`.text=` / `setTitle` / `alert.addAction(title:)`），并在 `source_refs` 留痕；无法回溯的断言禁止产出。 |
| **C. iOS"标准行为"冒充本 App 行为** | 通用文档称"登录失败清空密码框"，但 SPMExample 不清空（`LoginViewController.swift:230-232`）。 | 失败后字段是否清空、按钮是否禁用、是否整栈替换，**一律以 VC 源码为准，禁止引入通用 iOS 假设**。本案例即反面教材。 |
| **D. 异步时序幻觉** | 把客户端"用户名空"（立即）当成"1.5s 后才报"。 | 时序必须从 ViewModel 判定（是否在调 Service 前 return）；客户端校验标"立即"，服务端分支标"约 networkDelay 后"。 |
| **E. 源码变了、方案过时** | 重构后 `HomeViewController` 改了欢迎语文案，旧判据全失效。 | 每个 intent 带 `source_refs`（`file:line`），供 diff 触发的过时检测；声明"产出物是源码快照，源码变更后需重跑"。 |
| **F. 单例共享状态污染** | 注册/重置改了 `AuthService.shared.users`，后续登录用例种子被污染。 | 凡依赖 `users` 的 intent 标 `depends_on.shared_state` + `cross_flow_verifiable`；提示执行层"单例不可重置，跨流程用例需排序或隔离"。 |

## Limitations

- 不保证 App 实际 UI 文案与源码一致（源码写"欢迎回来"，运行时可能被改）——执行层仍需 `ui_inspect` 校验。
- 不覆盖纯视觉/动画质量（颜色、过渡美感等）。
- 需源码可读；混淆/闭源 App 不适用。
- 单例共享状态的跨流程依赖需人工标注执行顺序，本 skill 只标 `cross_flow_verifiable` 提示。

## Related Skills

- **ios-automation** — 执行入口，消费本 skill 产出的意图清单。
- **ios-dynamic-content** — `textExists` / `idle` 等待词汇来源。
- **ios-alert-handling** — `alert` 判据词汇来源。
- **ios-form-filling** — 输入步骤词汇来源（异步提交判定已就绪）。

> 本 skill 不操作 App，不进 `ios-automation` 的运行时路由表；它产出意图契约，由上述执行型 skill 消费。

## Test Coverage

- 覆盖率以**源码分支覆盖率**为准（把 Service/VM/VC 的每个 guard/状态分支映射到 intent，无遗漏），**不是**端到端通过率。
- skill 自测用例：`evals/evals.json`。

## Production Readiness

✅ **分析型 skill，无运行时副作用**（不连 App、不调 MCP、不改系统）。

产出物是源码快照，需人工评审后再用于执行；源码变更后需重跑。
