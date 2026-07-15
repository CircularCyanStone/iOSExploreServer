---
name: ios-test-runner
description: |
  Execution skill that closes the "test intent → run → coverage report" loop.
  Consumes a test-intent manifest produced by `ios-test-intent`
  (e.g. `docs/test-intents/spmexample-login.json`) and runs each intent against
  a live iOS app: resolves intent-stated pass/fail criteria (textExists /
  textContains / targetExists / targetGone / alert) into runtime
  `ui_waitAny.conditions`, drives the UI with iOSDriver, judges pass/fail by
  which condition fires first, and emits a coverage report.

  Use this skill when the user needs to: 执行测试意图, 跑意图清单, 跑测试用例,
  test runner, 执行测试, run intent manifest, 验证测试意图, 生成覆盖报告,
  or "把 spmexample-login.json 跑一遍". Must mention an intent manifest /
  test-intents / 跑意图 / test runner to trigger.

  Based on iOSDriver MCP Server wait vocabulary + ios-automation execution tools.
  Upstream: ios-test-intent (authors the manifest). This skill is the downstream
  consumer — it operates the app, ios-test-intent does not.
---

# iOS Test Runner（消费意图清单 → 执行 → 覆盖报告）

## Purpose

把 `ios-test-intent` 产出的"测试意图清单"（`docs/test-intents/*.json`）**自动消费、逐条执行、判 pass/fail、汇总成覆盖报告**，从而打通"意图 → 执行 → 报告"闭环。

解决什么问题：意图清单里的判据只用 `textExists` / `targetExists` 这类**意图层词汇**，不含 `path` / `accessibilityIdentifier` / `viewSnapshotID`（那些是会随重构失效的实现细节）。本 skill 在**运行时**用 `ui_inspect` 现场把"角色+文案"解析成真实 target，再把判据翻译成 `ui_waitAny.conditions`，由"先命中谁"定 pass/fail。这样意图清单 stays 稳定，执行层适配 UI 变化。

**与上游的分工（关键）**：
- `ios-test-intent`：**离线**读源码 → 产出意图 + 判据（不连 App、不调 MCP）。
- `ios-test-runner`（本 skill）：**在线**连 App → 消费判据 → 执行 → 报告。
- 判据是两层之间的**契约**：意图层只写可见文案/角色，执行层负责现场解析。

## When to Use

**触发**（用户要这些时用本 skill）：
- "跑一下 `spmexample-login.json` / 执行测试意图 / 跑意图清单"
- "把这些测试用例在模拟器上跑一遍并出报告"
- "验证 ios-test-intent 产出的判据能不能落地"

**不触发**（去别的 skill）：
- 从源码**产出**意图清单 → `ios-test-intent`（上游）
- 单次操作 App（填表单/点按钮/导航）但不涉及清单消费 → `ios-automation` 及其子 skill
- 单纯截图 → `ios-screenshot`

## Prerequisites

- **iOSDriver MCP Server** 已连接，App 已运行（模拟器共享 localhost:38321，真机走 iproxy）。
  开跑前先 `curl -X POST http://localhost:38321/ -d '{"action":"ping"}'` 确认。
- 一份意图清单（`docs/test-intents/*.json`），schema 见 `ios-test-intent` 的 Output Format。
- App 处于清单第一个 intent 的**起始状态**（如登录页）。runner 不假设状态——执行前先 `ui_inspect` 核对当前页，必要时导航/重启回到起点。

## Capabilities — 6 步工作流

> 本 skill 是**执行型**：核心动作是"读清单 → 逐条跑 → 记结果"。每条 intent 走 Step 2–5。

### Step 1 — 加载清单 + 排序

1. 读 `docs/test-intents/<flow>.json`，拿到 `evals[]`。
2. **按依赖排序**（重要，避免单例共享状态污染）：
   - 标了 `depends_on.seed_data` 的成功路径（如 `login-success` 依赖 test/123456）排在前，**不要**让注册类 intent 先跑改了 `AuthService.shared.users`。
   - 跨流程副作用（`cross_flow_verifiable`）按提示排顺序（如"注册→登录"必须注册在前）。
   - MVP 只跑指定子集时，按用户给的顺序，但仍遵守种子依赖。
3. 决定 MVP 范围：用户没指定就**全跑**；指定子集（如"跑这 5 条"）就只跑子集，其余标 `skipped`。

### Step 2 — 核对起始状态 + 清除上一条残留（关键）

每条 intent 执行前做两件事：**回到正确页面** + **清除上一条的 UI 残留**。

**(a) 回到正确页面**：
- 登录类 intent 起始须在登录页（`navigationBar.title == "登录"` 或见到"欢迎登录"标题 + "登录"按钮）。
- 若不在起点：成功路径跑完会跳首页，下一条失败类 intent 必须**回到登录页**——用 `ui_navigation_back`（若能返回）或重启 App。
- 登录成功后整栈替换 + `hidesBackButton`，**无法 back** → 失败类 intent 必须重启 App（`stop_app_sim` + `launch_app_sim` 带 `--ios-explore-show-login`）回登录页。

**(b) 清除上一条的 UI 残留（防止同文案串味——最容易踩的坑）**：
- 连续失败类 intent（如 `login-user-not-found` → `login-wrong-password`）都显示同一句"用户名或密码错误"。前一条跑完后 **errorLabel 残留该文本**；下一条点登录后的 loading 期间（~1.5s）errorLabel 仍是旧文本，`wait_and_inspect` 第一次轮询就会误匹配成 pass（`elapsedMs=0` 时序假象），根本没等新请求完成。
- 根因：`LoginViewController.loginButtonTapped` 只 `updateLoadingState`，**不清 errorLabel**；新请求失败后才覆盖文本（同文案，看不出区别）。
- **解法（按可靠性排序）**：
  1. **每条 intent 前重启 App** 回干净登录页（errorLabel 初始 `isHidden=true`）——消除一切残留，最可靠。代价是慢（每条 ~5s），但 MVP 阶段准确性优先。
  2. 不愿每条重启时，至少在**点提交前 `ui_inspect` 核对 errorLabel 不可见**，残留就重启。
  3. 退而求其次：同文案失败用 `app.logs.read` 佐证——看是否有**新的**"开始登录请求"日志条目（证明是新请求，非残留匹配）。
- **同文案失败类 intent 之间，强烈建议重启**——纯 UI 文本判据无法区分"新一次失败"与"上一条残留"。

### Step 3 — 执行 prompt（现场解析，不用清单里的 path）

意图清单**不含 path/identifier**，所以每条 intent 执行时**现场解析**：

1. `ui_inspect` 拿当前 target 列表 + `viewSnapshotID`。
2. 按 intent 的 `prompt` 用**文案/角色**匹配目标：
   - "输入 test" → 找 `placeholder=="用户名"` 或 `accessibilityLabel` 含"用户名"的 textField。
   - "点「登录」" → 找 `text=="登录"` 或 `title=="登录"` 的 button。
   - "用户名留空" → **不输入**（或输入后清空），直接跳到点登录。
3. 用 `ui_input`（`mode:"replace"`）逐字段填，`submit:true` 收键盘。
4. 点提交按钮：**用 `ui_tap`（普通点击），不要用 `ui_tap_and_inspect`**——异步提交用 tap_and_inspect 的 `stableTimeMs` 会抓到 loading 中间态（详见 Step 4）。

> **为什么现场解析而不是预录 path**：path（`root/0/0/4`）会随 UI 重构变；可见文案（"登录"、"用户名"）是稳定契约。runner 只信任文案/角色，path 仅在单次 inspect 生命周期内有效。

### Step 4 — 翻译判据 → ui_waitAny.conditions（核心）

把 `pass_criteria` + `fail_criteria` 都翻成 `ui_waitAny.conditions[]` 的条目，**塞进同一个调用**，先命中谁就定 pass/fail。映射表：

| 判据词汇 | 翻译成 condition | 备注 |
|---|---|---|
| `textExists('X')` | `{mode:"textExists", text:"X", id:"pass:textExists:X"}` | `textExists` 本身是片段匹配 |
| `textContains('X')` | `{mode:"textExists", text:"X", id:"..."}` | 与 textExists 等价（ui_waitAny 无独立 contains 模式） |
| `targetExists('「退出登录」红色按钮')` | 先 `ui_inspect` 按描述解析到 `path`/`identifier` → `{mode:"targetExists", path:<解析结果>, id:"..."}` | **必须在当次 inspect 生命周期内解析**；解析不到则该条件省略并记 notes |
| `targetGone('导航返回按钮')` | 解析"该消失的元素"的定位 → `{mode:"targetGone", path/identifier:<...>, id:"..."}` | 若元素本就不在初始树里（如成功后才该消失的返回按钮），用 `navigationBar.backAvailable==false` 间接判，或 inspect 后用其 identifier |
| `alert` | **ui_waitAny 无 alert 模式** → 特殊处理（见下） | 作 fail_criterion 时是"不该弹却弹了" |

**condition 的 `id` 命名规约**：`<pass|fail>:<mode>:<value简写>`，让 `matchedID` 一眼看出命中的是哪条判据、是 pass 还是 fail。

**alert 判据的特殊处理**：
`ui_waitAny` 的 mode 只有 `idle/targetExists/targetGone/textExists/snapshotChanged`，**没有 alert**。所以：
- 作 **fail_criterion**（"成功路径不应弹窗"）：`ui_waitAny` 返回后，**追加一次 `ui_inspect`**，看 `alert.available`。若 `true` → 记 fail_criterion `alert` 命中。若 `false` → 该 fail 条件未触发（符合预期）。
- 作 **pass_criterion**（罕见，"期望弹某窗"）：同样靠 inspect 的 `alert.available + alert.title/buttons` 判，配合 `ui_alert_respond` 关闭后继续。

**异步 vs 同步（继承 ios-form-filling 范式，不要退化）**：
- `timing: "立即"`（客户端校验）：`ui_tap` 后直接 `wait_and_inspect(conditions=[pass+fail], timeoutMs: 2000)`。错误文案几乎瞬间出现。
- `timing: "约 1.5s 后"`（走 Service）：`ui_tap` 后 `wait_and_inspect(conditions=[pass+fail], timeoutMs: 5000)`（1.5s networkDelay + 余量）。**严禁固定 `sleep`**——sleep 短了抓 loading 中间态，长了白等；判据驱动才准。
- **判 pass/fail 的依据是 `ui_waitAny` 返回的 `matchedID`**（或 `wait_and_inspect` 等价的命中信息）：
  - 命中 `pass:*` → **pass**，`matched_criterion` 记该 id。
  - 命中 `fail:*` → **fail**，`matched_criterion` 记该 id。
  - 超时无命中 → **fail**（判据没满足），`matched_criterion: "timeout"`，notes 说明等了什么没来。
  - 命中的是 alert（靠 Step 4 的 inspect 兜底）→ 按该 alert 属 pass 还是 fail 定。

### Step 5 — 记录单条结果

每条 intent 记：
```json
{
  "id": "login-success",
  "status": "pass|fail|skipped",
  "matched_criterion": "pass:textExists:欢迎回来！",
  "duration_ms": 3200,
  "business_points_covered": ["LoginViewModel.login", "AuthService.login", "navigateToHome"],
  "notes": "约 1.5s 后首页欢迎语出现；alert 未触发（符合预期）"
}
```
- `duration_ms`：从点提交到 condition 命中的墙钟（用工具返回的时间戳或自测）。
- `skipped` 用于：判据在执行层落不了地（如双击守卫需配合 `app.logs.read` 看请求次数，纯 UI 判据不够）、或 MVP 范围外、或前置依赖未满足。**必须写明 skip 原因**，不要硬造 pass。

### Step 6 — 汇总覆盖报告

整体报告写到 `docs/test-reports/<flow>-run.json`：
```json
{
  "run_at": "2026-07-15T15:10:00Z",
  "app": "SPMExample",
  "simulator": "iPhone 17 (065CC8DB-...)",
  "manifest": "docs/test-intents/spmexample-login.json",
  "total": 5,
  "passed": 4,
  "failed": 1,
  "skipped": 0,
  "pass_rate": 0.8,
  "business_points_covered": ["..."],
  "results": [ /* Step 5 的单条结果 */ ]
}
```
- 算 `pass_rate = passed / (passed + failed)`（skipped 不计入分母，单列）。
- `business_points_covered`：聚合所有 pass intent 的 `business_points`，用于看源码分支覆盖了多少。

## 判据翻译速查（SPMExample 登录实战）

| Intent | pass 条件（ui_waitAny） | fail 条件（ui_waitAny） | timeout |
|---|---|---|---|
| login-success | `textExists:"欢迎回来！"` | `textExists:"用户名或密码错误"` | 5000ms（异步） |
| login-empty-username | `textExists:"请输入用户名"` | `textExists:"用户名或密码错误"` | 2000ms（立即） |
| login-empty-password | `textExists:"请输入密码"` | `textExists:"用户名或密码错误"` | 2000ms（立即） |
| login-user-not-found | `textContains:"用户名或密码错误"` | `textExists:"请输入用户名"` | 5000ms（异步） |
| login-wrong-password | `textContains:"用户名或密码错误"` | （无强 fail） | 5000ms（异步） |

> alert 类 fail 条件不进 ui_waitAny，靠返回后 `ui_inspect.alert.available` 兜底。

## Usage Examples

1. **"把 spmexample-login.json 跑一遍，只跑 5 条登录 intent"** → Step 1 加载清单选 5 条 → Step 2 确认在登录页 → 逐条 Step 3–5 → Step 6 出 `docs/test-reports/spmexample-login-run.json`。
2. **"验证 ios-test-intent 产出的判据能不能落地"** → 全跑清单，重点看哪些 intent 标 skipped（判据执行层落不了地），把 skip 原因反馈给意图层修正。
3. **"跑完出覆盖报告"** → Step 6 的 `business_points_covered` 对照清单，看哪些源码分支还没被 intent 覆盖。

## Best Practices

1. **判据驱动，不要固定 sleep**。异步提交用 `wait_and_inspect` + 终态判据；固定 sleep 会抓 loading 中间态或误判成败（继承自 ios-form-filling 的核心范式）。
2. **现场解析，不要预录 path**。意图清单不含 path 是设计意图——runner 用 `ui_inspect` 按文案/角色当次解析，path 只在单次 inspect 生命周期内有效。
3. **pass + fail 条件同塞 ui_waitAny**。先命中谁定结果，避免"先等 pass 再查 fail"的两次轮询。
4. **诚实 skip**。判据落不了地的（双击守卫、loading 期间按钮禁用的时序窗口、需配合日志的请求次数）标 skipped + 原因，不要硬造 pass。这些正是要反馈给意图层的信号。
5. **共享状态注意顺序**。成功路径依赖种子数据，注册/重置会改单例——排序时把"依赖种子"的成功路径放前，或跑前重启 App 重置状态。
6. **成功后回不去登录页就重启**。SPMExample 登录成功整栈替换 + hidesBackButton，下一条失败类 intent 必须 `stop_app_sim` + `launch_app_sim`（带 `--ios-explore-show-login`）回登录页，别浪费时间找返回按钮。

7. **同文案失败类 intent 之间重启 App**（状态隔离）。连续的 `login-user-not-found` / `login-wrong-password` 显示同一句错误，errorLabel 残留会让下一条的 wait 在 loading 期间误匹配成 pass（`elapsedMs=0` 时序假象，见 Step 2b）。重启回干净登录页是最可靠的状态隔离；不重启时必须用 `app.logs.read` 佐证是新请求。

## Limitations

- **纯 UI 判据覆盖不到的 intent**：如 `login-double-tap-guard`（要数 AuthService 请求次数）、`login-button-disabled-during-loading`（loading 是 ~1.5s 时序窗口，ui_waitAny 容易错过）——这类标 skipped，建议配合 `app.logs.read`（按 `explore`/`nslog` 来源读"开始登录请求"日志条数）做强验证，纯 UI 判据为辅。
- **目标解析失败时该条件省略**：`targetExists('某描述')` 在当次 inspect 解析不到，该 condition 省略并在 notes 记"解析失败"，不阻塞其余条件。
- **不验证视觉/动画质量**（颜色、过渡美感）——这是意图层的设计边界，runner 继承。
- **模拟器/真机行为可能差异**：报告里记 `simulator` 字段，真机结果另出。

## Related Skills

- **ios-test-intent** — 上游：读源码产出意图清单（本 skill 的输入）。
- **ios-automation** — 执行工具源（ui_inspect/ui_input/ui_tap/ui_waitAny/wait_and_inspect 等），本 skill 直接复用其 MCP 工具映射。
- **ios-form-filling** — 异步提交的 `wait_and_inspect` + 终态判据范式来源（本 skill 的 Step 4 继承）。
- **ios-dynamic-content** — `textExists`/`idle` 等待词汇语义参考。

## Test Coverage

- 覆盖率以**意图清单的 intent 通过率**为准（passed / (passed+failed)），辅以 `business_points_covered` 看源码分支覆盖。
- skill 自测用例：`evals/evals.json`。
- 实跑报告样例：`docs/test-reports/spmexample-login-run.json`。

## Production Readiness

✅ **MVP Ready** —— 已在 SPMExample 模拟器实跑 5 条登录 intent 验证判据可落地（见上述报告）。

runner skill 是执行型指导，无独立运行时副作用（不写代码、不改 App）；它驱动 iOSDriver MCP 工具操作 App 并产报告。意图清单是源码快照，App 源码/文案变更后需重跑。
