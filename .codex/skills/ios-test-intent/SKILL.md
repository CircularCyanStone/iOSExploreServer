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

  Based on runtime wait vocabulary; offline/analytical — does not operate the app
  itself. Output is consumable by iOS automation runner skills.
---

# iOS Test Intent Authoring(读源代码产出测试意图)

离线读 iOS App 的业务源码,产出"测试意图 + 成功/失败判据清单"。判据用 `ios-*` 的等待词汇(`textExists` / `targetExists` / `targetGone` / `alert`)表达,**可直接喂给 `ui_waitAny.conditions` 落地执行**。本 skill 严格只产出**意图层**(测什么、什么算成败),**绝不产出执行层**(不写 `path` / `accessibilityIdentifier` / `viewSnapshotID`,那些由运行时 `ui_inspect` 现场解析)。

读源码时使用当前环境可用的文件阅读、文件枚举和文本搜索能力；若项目已有源码索引，也可先用索引加速符号定位。**不连接 App、不操作 UI**。

## 目标

解决三类问题:

1. **"这个流程到底该测什么、成败长什么样"**:从源码 guard 链与状态机推出每个分支的可观察信号,把"即兴判成败"变成"有源码依据的契约"。
2. **"判据怎么写才能在 UI 重构后仍然稳定"**:判据只允许用可见文案/角色标签(`textExists` / `targetExists` ...),禁止写 `path` / `accessibilityIdentifier` 值——那些是会随重构失效的实现细节。
3. **"哪些是源码陷阱,不能套用通用 iOS 假设"**:失败后字段是否清空、成功是否整栈替换、是否禁用重入,统统以 VC 源码为准,不信"iOS 标准行为"。

解决的核心痛点:agent 跑自动化时常用固定 `sleep` 或 `snapshotChanged` 即兴判异步结果,容易抓到 loading 中间态或把失败误判成成功。把判据来源从"即兴"变成"源码契约"是本 skill 的价值。

## 何时使用

- ✅ 用户要"给某流程设计测试用例 / 列成功失败判据 / 从源码生成测试清单"
- ✅ 用户要"产出测试意图清单,交给 ios-automation / ios-test-runner 执行"
- ✅ 用户要"离线分析某个业务流的分支、边界、陷阱"(不跑 App)
- ✅ 用户说 "测试意图" / "pass criteria" / "fail criteria" / "测试方案" / "读源代码" / "test intent"
- ❌ 不要用于实际跑 App、点按钮、截图(改用 `ios-automation`)
- ❌ 不要用于运行时填表单 / 导航 / 处理弹窗(改用对应执行型 skill:`ios-ui-form` / `ios-ui-nav` / `ios-ui-alert`)
- ❌ 不要用于消费意图清单跑测试并出报告(改用下游 `ios-test-runner`)

## 工作原理

**5 步工作流**,每步说清"读什么、提取什么、产出什么"。所有举例用占位 App `<MyApp>`(虚构),不引任何真实项目类名/行号。若需要真实 App 套用案例,应放在使用者自己的仓库文档或外部资料中,不要作为 skill 本体依赖。

### Step 0 — 圈定 flow 与入口

列出本次要覆盖的业务流(如登录 / 注册 / 重置 / 首页)。每个 flow 定位三件套:入口 `<LoginVC>` + 对应 `<LoginViewModel>` 方法 + `<LoginService>` 方法。产出一张覆盖范围表。用 `Glob` 找源码目录,`Grep` 定位入口方法名。

### Step 1 — 读 Service 层(业务规则、数据真相、时序)

Service 层是业务规则的事实来源,**最先读**。提取四样:

- **校验链与顺序**:每个方法的 `guard` 次序。例(占位 App `<MyApp>`):登录 = 用户存在 → 密码匹配;注册 = 邮箱格式 → 密码长度达标 → 用户未占用;重置 = 密码长度达标 → 用户存在且邮箱匹配。
- **时序常量**:模拟网络延迟的常量(如 `<LoginService>` 的 `networkDelay`,假设 `<约 N 秒>`)——所有走 Service 的分支都"约 N 秒后才出结果"。具体秒数读源码常量,**不要猜**。
- **错误 → 文案映射**:`<AuthError>.errorDescription` 之类的本地化表。注意哪些错误共用同一文案(常见安全设计:登录的"用户不存在"和"密码错"映射成同一句"用户名或密码错误",故意不可区分)。
- **共享可变状态 + 种子数据**:单例(如 `<LoginService>.shared.users`)是否跨流程持久;`init` 是否预置种子账号(`<seed-user>` / `<seed-password>`)。

产出:服务端分支清单 + 统一时序 + 副作用(是否写共享存储)。

### Step 2 — 读 ViewModel 层(客户端即时校验链)

ViewModel 是客户端校验入口。提取 `guard` 顺序,并**严格区分两类分支**:

- **客户端即时分支**(不进 Service、不触发网络延迟):登录的"用户名空 / 密码空";注册的"用户名空 → 邮箱空 → 密码空 → 两次密码一致"。判据标 `timing: "立即(客户端校验)"`。
- **服务端异步分支**(走 Service、约 `networkDelay` 后返回):注册的邮箱格式 / 密码长度 / 用户未占用;重置的密码长度 / 邮箱匹配。标 `timing: "约 N 秒后(服务端)"`。

> ⚠️ **顺序陷阱**:注册的"两次密码一致"通常是客户端立即校验,但"邮箱格式""密码长度"可能在服务端。判据必须按真实顺序与时序标,标错了执行层就会等错信号(把立即报错等成 N 秒后,反之亦然)。

### Step 3 — 读 ViewController 层(状态机、异步行为、行为陷阱)

最后读 VC,提取 UI 行为:

- **UI 状态机**:`idle` →(tap 提交)→ `loading` →(成功 nav / 失败 error)。
- **重入守卫**:`isLoading` 在异步 `Task` 外**同步置位**(`guard !isLoading`),双击第二次直接 return → 产出"双击守卫"intent。
- **loading 期间按钮行为**:标题清空成 `""` + `isEnabled=false` + spinner 转 → 产出"loading 期间按钮禁用"intent。
- **成功导航方式**:读 VC 的导航调用——是 `navigationController.push` 还是 `setViewControllers([homeVC])` 整栈替换 + `hidesBackButton = true`?整栈替换场景 → 产出"成功后无法 back"判据(`targetGone` 导航返回按钮)。
- ⚠️ **失败后字段是否清空——必须读源码确认,绝不套用"iOS 标准行为"假设**。读 VC 的"登录提交方法"(如 `<LoginVC>` 的 `<loginButtonTapped>` 等价物)失败分支:只调 `showError` 不清空密码框?还是显式 `passwordTextField.text = ""`?**本 skill 以源码为准**。通用文档可能声称"登录失败标准会清空密码框",但每个 App 行为不同,凭空假设是典型陷阱(见"常见错误与判别" C)。

### Step 4 — 映射成 pass_criteria / fail_criteria(词汇表固定)

把每个分支翻成一个 `intent` 对象。判据只允许用下列词汇:

| 词汇 | 用法 | 映射到 ui_waitAny |
|---|---|---|
| `textExists` | 出现某可见文案(片段匹配) | `mode="textExists", text=<value>` |
| `textContains` | 文案包含某片段(与 textExists 等价,语义偏好"包含") | 同上 |
| `targetExists` | 某元素出现,用"角色+可见标签"描述(如"「退出登录」红色按钮") | `mode="targetExists"` |
| `targetGone` | 某元素/文案消失 | `mode="targetGone"` |
| `alert` | 弹窗出现(运行时用 `ui_inspect` 的 `alert.available==true`) | 运行时解析 |

**禁用词**(进判据 `value` 就错):`path`、`root/0/1`、`accessibilityIdentifier` 值(如 `home_logout_button`)、`viewSnapshotID`。`accessibilityIdentifier` 只允许记录在 `source_refs` 供运行时参考——它是实现细节、会随重构失效;可见文案才是稳定契约。每条判据带 `description`(人话理由)+ `timing`。

### Step 5 — 追踪跨流程副作用(共享存储)

单例(如 `<LoginService>.shared.users`)跨流程持久(内存级)。把副作用标进 intent:

- 注册成功 → 存储增项 → 后续"用新账号登录"可验证。标 `depends_on.seed_data` + `cross_flow_verifiable: "注册→登录"`。
- 重置密码成功 → 存储里该用户的密码改写 → "旧密码失效 + 新密码生效"可跨流程验证。
- 预置 `<seed-user>` / `<seed-password>` 是所有成功路径的种子,标 `depends_on.seed_data`。

## 关键产物

每个 `intent` 对象字段(复用项目 `evals.json` schema,最小扩展):

| 字段 | 类型 | 含义 |
|---|---|---|
| `id` | string | 场景稳定标识(如 `login-success`) |
| `flow` | string | 所属业务流(`login` / `register` / `reset` / `home`) |
| `intent` | string | 一句话场景名(测什么) |
| `prompt` | string | 自然语言场景描述(可喂给执行层当测试 prompt) |
| `business_points` | string[] | 覆盖的业务符号(如 `<LoginVC>.<loginButtonTapped>`),用于覆盖完整性核对 |
| `files` | string[] | 读过的源码相对路径 |
| `depends_on` | object? | `{ seed_data, shared_state }` 前置依赖 |
| `cross_flow_verifiable` | string? | 可跨流程验证的副作用描述 |
| `pass_criteria` | Criterion[] | 成功判据(全部满足 = 本场景 pass) |
| `fail_criteria` | Criterion[] | 失败判据(任一出现 = 本场景 fail,或反向场景的 pass 信号) |
| `timing` | string? | 整体时序提示("立即" / "约 N 秒后") |
| `known_defect` | boolean? | 源码行为语义错误时置 true(判据仍断言**当前实际行为**,但提醒人工裁决) |
| `source_refs` | string[]? | 关键源码定位(`file:line` 或 `file:symbol`),供过时检测 |

`Criterion` 子对象:`mode`(textExists / textContains / targetExists / targetGone / alert) / `value`(可见文案或角色标签,alert 无文案时 null) / `description` / `timing`。

**样例(占位 App `<MyApp>` 登录成功)**:

```json
{
  "id": "login-success",
  "flow": "login",
  "intent": "种子账号 <seed-user>/<seed-password> 登录成功,整栈跳首页且无法返回",
  "prompt": "在登录页输入种子账号 <seed-user> / <seed-password>,点「登录」;预期约 N 秒后整栈替换到首页,导航无返回按钮。",
  "business_points": [
    "<LoginViewModel>.<login>(username/password 非空校验通过)",
    "<LoginService>.<login>(命中种子账号、密码匹配、networkDelay 延迟)",
    "<LoginVC>.<loginButtonTapped> → <navigateToHome>(setViewControllers 整栈替换)"
  ],
  "files": [
    "Login/ViewModels/<LoginViewModel>.swift",
    "Login/Services/<LoginService>.swift",
    "Login/ViewControllers/<LoginVC>.swift"
  ],
  "depends_on": { "seed_data": "<LoginService>.init 预置 <seed-user>/<seed-password>" },
  "pass_criteria": [
    {"mode": "textExists", "value": "<欢迎语文案>", "description": "首页欢迎语出现,证明整栈跳转成功", "timing": "约 N 秒后"},
    {"mode": "targetGone", "value": "导航返回按钮", "description": "hidesBackButton=true,无法 back 回登录页"}
  ],
  "fail_criteria": [
    {"mode": "alert", "value": null, "description": "成功路径不应出现任何弹窗"},
    {"mode": "textContains", "value": "<失败文案>", "description": "失败文案未出现"},
    {"mode": "targetExists", "value": "「登录」按钮重新启用且仍停留在登录页", "description": "loading 结束但未跳转——请求失败"}
  ],
  "timing": "约 N 秒后出结果",
  "source_refs": [
    "<LoginService>.swift:<login 方法>",
    "<LoginVC>.swift:<navigateToHome 方法>"
  ]
}
```

多条 intent 聚合成 `evals.json` 的 `evals[]`,落地到 `docs/test-intents/<app>-<flow>.json`(如 `docs/test-intents/<myapp>-login.json`)。占位 App 没有真实路径;真实 App 套用模板时把尖括号占位符全替换成项目里的实际符号与文案。

## 常见错误与判别

六类典型陷阱,以占位 App `<MyApp>` 的反例说明(每类都对应 Step 1–5 的某个提取点)。

### A. 把"实现"当"规约"测

- **现象**:把 `<LoginService>.<resetPassword>` 失败时显示的"用户名或密码错误"(语义实际是"用户不存在或邮箱不匹配")照抄成断言。
- **原因**:这是源码的语义缺陷,不是业务规则;照抄就把 bug 当规约。
- **判别**:读 Service 错误 → 文案映射时,看到文案与错误类型语义不一致即识别。
- **处理**:区分**业务规则**(照测)与**实现缺陷**(标 `known_defect: true`,判据仍断言当前实际行为以保证确定性,`description` 提示"疑似缺陷,人工裁决")。

### B. 幻觉不存在的元素

- **现象**:凭空写"记住我 复选框"——登录页根本没有。
- **原因**:套用其他 App 的常识,没回源码核对。
- **判别**:每条判据 `value` 必须可回溯到一个源码出处(`.text=` / `setTitle` / `alert.addAction(title:)`),并在 `source_refs` 留痕。
- **处理**:无法回溯的断言禁止产出;先 `Grep` 源码确认元素/文案存在再写。

### C. iOS"标准行为"冒充本 App 行为(最隐蔽)

- **现象**:通用文档称"登录失败清空密码框",但 `<LoginVC>` 的失败分支不清空(或反之,显式清空)。
- **原因**:把通用 iOS 习惯当本 App 规约,没读 VC 失败分支源码。
- **判别**:Step 3 读 VC 提交方法失败分支,看是否调用 `passwordTextField.text = ""`;**绝不假设**。
- **处理**:失败后字段是否清空、按钮是否禁用、是否整栈替换,**一律以 VC 源码为准,禁止引入通用 iOS 假设**;按实际行为产出判据(不清空 → "失败后密码框保留"intent 用间接信号验证;清空 → "失败后密码框被清空"intent 验证立即报"请输入密码")。

### D. 异步时序幻觉

- **现象**:把客户端"用户名空"(立即)当成"约 N 秒后才报",或反之。
- **原因**:Step 2 没严格区分客户端立即校验 vs 服务端异步分支。
- **判别**:ViewModel 是否在调 Service 前 return?是 → 立即;否 → 约 `networkDelay` 后。
- **处理**:客户端校验标 `timing: "立即(客户端校验)"`,服务端分支标 `timing: "约 N 秒后(服务端)"`。

### E. 源码变了,方案过时

- **现象**:重构后 `<HomeVC>` 改了欢迎语文案,旧判据全失效。
- **原因**:产出物是源码快照,源码一变就过时。
- **判别**:每个 intent 的 `source_refs`(`file:line` 或 `file:symbol`)供 diff 触发的过时检测。
- **处理**:声明"产出物是源码快照,源码变更后需重跑";执行层(下游 `ios-test-runner`)发现 `source_refs` 对不上当前源码时降级或告警。

### F. 单例共享状态污染

- **现象**:注册/重置改了 `<LoginService>.shared.users`,后续登录用例种子被污染。
- **原因**:单例不可重置,跨流程用例共享同一内存状态。
- **判别**:Step 5 标 `depends_on.shared_state` + `cross_flow_verifiable`。
- **处理**:凡依赖共享存储的 intent 显式标依赖;提示执行层"单例不可重置,跨流程用例需排序或隔离"。

## 相关 skill

- `ios-test-runner` — **下游消费者**:把本 skill 产出的意图清单跑成测试 + 出覆盖报告。本 skill 止步于产出 JSON,不执行。
- `ios-automation` — L1 总入口;不确定走哪个子 skill 时先问它。
- `ios-ui-wait` — `textExists` / `targetExists` / `targetGone` / `idle` 等待词汇的运行时语义来源。
- `ios-ui-alert` — `alert` 判据词汇的运行时解析来源。
- `ios-ui-form` — 输入步骤的运行时工具来源(异步提交判定已就绪)。

> 本 skill 不操作 App,不进 `ios-automation` 的运行时路由表;它产出意图契约,由上述执行型 skill 消费。

**真实 App 套用案例**:如需保留具体项目的意图清单、实跑报告、账号、bundle id、设备信息或启动参数,请放在该项目自己的文档或测试数据目录中。本 skill 本体只描述通用方法,不依赖任何真实 App 案例。

## 限制

- 不保证 App 实际 UI 文案与源码一致(源码写"欢迎回来",运行时可能被改)——执行层仍需 `ui_inspect` 校验。
- 不覆盖纯视觉/动画质量(颜色、过渡美感等)。
- 需源码可读;混淆/闭源 App 不适用。
- 单例共享状态的跨流程依赖需人工标注执行顺序,本 skill 只标 `cross_flow_verifiable` 提示。

## 覆盖率口径

- 覆盖率以**源码分支覆盖率**为准(把 Service / VM / VC 的每个 guard / 状态分支映射到 intent,无遗漏),**不是**端到端通过率。
- skill 自测用例:`docs/skills/evals/ios-test-intent/evals.json`(静态结构 case + 占位 App 方法 case)。
