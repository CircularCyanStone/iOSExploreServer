---
name: ios-test-runner
description: |
  L2 测试执行 skill:消费 ios-test-intent 产出的测试意图清单,逐条驱动 iOS App
  跑、判 pass/fail、汇总覆盖报告 / test runner, run intent manifest, execute
  tests, coverage report, pass fail judge. 把清单里的 pass/fail 判据
  (textExists / targetExists / targetGone / alert)翻译成运行时
  `ui_waitAny.conditions`,用 iOSDriver 现场驱动 UI,由"先命中谁"定成败。

  Use this skill when the user needs to: 执行测试意图, 跑意图清单, 跑测试用例,
  test runner, 执行测试, run intent manifest, 验证测试意图, 生成覆盖报告,
  or "把某个 manifest JSON 跑一遍". Must mention an intent manifest /
  test-intents / 跑意图 / test runner to trigger.

  Based on runtime wait vocabulary + iOS automation execution tools.
  Upstream: ios-test-intent (authors the manifest). This skill is the downstream
  consumer — it operates the app, ios-test-intent does not.
---

# iOS Test Runner(消费意图清单 → 执行 → 覆盖报告)

L2 执行型 skill:把 `ios-test-intent` 产出的"测试意图清单"(`docs/test-intents/<app>-<flow>.json`)逐条跑成测试,判 pass/fail,汇总成覆盖报告 `docs/test-reports/<app>-<flow>-run.json`。核心动作是"读清单 → 现场解析 → 驱动 UI → 判成败 → 记结果"。

**与上游的分工(契约)**:
- `ios-test-intent`:**离线**读源码 → 产出意图 + 判据(不连 App、不调 MCP)。判据只用意图层词汇(`textExists` / `targetExists` / `targetGone` / `alert`),不含 `path` / `accessibilityIdentifier` / `viewSnapshotID`。
- `ios-test-runner`(本 skill):**在线**连 App → 现场把判据解析成 `ui_waitAny.conditions` → 驱动 UI → 由 `matchedID` 判 pass/fail → 报告。

## 目标

解决三类问题:

1. **"意图清单里的判据能不能在真机/模拟器上落地"**:意图层词汇(`textExists:"<欢迎语>"`)不含 path,本 skill 用 `ui_inspect` 现场按文案/角色解析成真实 target,再把判据塞进 `ui_waitAny.conditions`,由"先命中谁"定成败。
2. **"异步提交到底成功了还是失败了"**:用 `ui_waitAny` 把 pass + fail 条件塞同一次调用,命中 `pass:*` 即 pass、命中 `fail:*` 即 fail、超时即 fail(判据没满足)。杜绝固定 `sleep`(会抓 loading 中间态或误判)。
3. **"纯 UI 判据够不着的场景(请求数 / 瞬时 loading 态 / secure 字段)"**:用日志计数(`app_logs_mark` + `app_logs_read`)验证请求数;用二次提交协议间接验证 secure 字段是否保留;瞬时态窗口短于 agent-loop 间隔时诚实标 skipped。

解决的核心痛点:agent 跑自动化时常用固定 `sleep` 或 `snapshotChanged` 即兴判异步结果,容易抓到 loading 中间态或把失败误判成成功。本 skill 把判据来源从"即兴"变成"意图清单契约 + 判据驱动等待"。

## 何时使用

- ✅ 用户要"跑一下 `<app>-<flow>.json` / 执行测试意图 / 跑意图清单"
- ✅ 用户要"把这些测试用例在模拟器/真机上跑一遍并出报告"
- ✅ 用户要"验证 ios-test-intent 产出的判据能不能落地"
- ✅ 用户要"跑完出覆盖报告,看源码分支覆盖了多少"
- ✅ 用户说 "执行测试意图" / "跑意图清单" / "test runner" / "run intent manifest" / "生成覆盖报告"
- ❌ 不要用于从源码**产出**意图清单(改用上游 `ios-test-intent`,它离线读源码不连 App)
- ❌ 不要用于单次操作 App(填表单/点按钮/导航)但不涉及清单消费(改用 `ios-automation` 及其子 skill)
- ❌ 不要用于纯截图(改用 `ios-ui-shot`)

## 工作原理

**6 步工作流**,每条 intent 走 Step 2–5。所有举例用占位 App `<MyApp>`(虚构),不引任何真实项目类名/行号。若需要真实 App 套用案例,应放在使用者自己的仓库文档或外部资料中,不要作为 skill 本体依赖。

### Step 1 — 加载清单 + 排序

1. 读 `docs/test-intents/<app>-<flow>.json`,拿到 `evals[]`(intent 数组,schema 见 `ios-test-intent` 的"关键产物")。
2. **按依赖排序**(避免共享状态污染):
   - 标了 `depends_on.seed_data` 的成功路径(如 `login-success` 依赖 `<seed-user>`/`<seed-password>`)排在前,**不要**让注册类 intent 先跑改了共享存储(如 `<LoginService>.shared.users` 等价单例)。
   - 跨流程副作用(`cross_flow_verifiable`)按提示排顺序(如"注册→登录"必须注册在前)。
   - MVP 只跑指定子集时,按用户给的顺序,但仍遵守种子依赖。
3. 决定 MVP 范围:用户没指定就**全跑**;指定子集就只跑子集,其余标 `skipped`。

### Step 2 — 核对起始状态 + 清除上一条残留(关键)

每条 intent 执行前做两件事:**回到正确页面** + **清除上一条的 UI 残留**。

**(a) 回到正确页面**:
- 每条 intent 的起点由其 `prompt` 描述(如"在登录页输入...")。执行前先 `ui_inspect` 核对当前页是否符合该起点(看 `navigationBar.title` 或关键 label/button 是否在树里)。
- 若不在起点:成功路径跑完常跳首页且整栈替换 + `hidesBackButton`(无法 `ui_navigation_back`),下一条失败类 intent 必须**重启 App 回起点**。**如需回到某流程起点,由调用方提供 App 专属启动参数**(App 各自的测试工程可能有快捷启动参数,本 skill 不写死任何参数名);或让 App 在 `viewDidLoad` 直接落到起点页。
- 重启 = 停 App 再启动(具体 stop/launch 工具由构建/设备管理 MCP 或 `ios-automation` 连接流程提供;执行时借 L0 完成重启,然后回来继续 Step 3)。

**(b) 清除上一条的 UI 残留(防同文案串味——最容易踩的坑)**:
- 连续失败类 intent(如 `login-user-not-found` → `login-wrong-password`)可能显示同一句错误文案。前一条跑完后 **errorLabel 残留该文本**;下一条点提交后的 loading 期间,errorLabel 仍是旧文本,`ui_waitAny` 第一次轮询就会误匹配成 pass(`elapsedMs≈0` 时序假象),根本没等新请求完成。
- **解法(按可靠性排序)**:
  1. **每条 intent 前重启 App** 回干净起点(errorLabel 初始隐藏)——消除一切残留,最可靠。代价是慢,但准确性优先。
  2. 不愿每条重启时,至少在**点提交前 `ui_inspect` 核对 errorLabel 不可见/无残留文本**,残留就重启。
  3. 退而求其次:同文案失败用 `app_logs_read` 佐证——看是否有**新的**业务日志条目(证明是新请求,非残留匹配)。见 Step 4b 机制 1 + 前置检查。

### Step 3 — 执行 prompt(现场解析,不用清单里的 path)

意图清单**不含 path/identifier**,每条 intent 执行时**现场解析**:

1. `ui_inspect` 拿当前 target 列表 + `viewSnapshotID`。
2. 按 intent 的 `prompt` 用**文案/角色**匹配目标:
   - "输入 `<seed-user>`" → 找 `placeholder` / `accessibilityLabel` 含"用户名"的 textField。
   - "点「登录」" → 找 `text=="登录"` 或 `title=="登录"` 的 button。
   - "用户名留空" → **不输入**(或输入后清空),直接跳到点提交。
3. 把同一屏上的文本字段合并为一次 `ui_input({viewSnapshotID, fields:[...]})` 批量填写;每个 field 默认 `mode:"replace"`、`submit:false`。只有目标被键盘遮挡、业务依赖 Return / Done / Search / 结束编辑,或任务明确验证键盘状态时,才在对应 field 使用 `submit:true` 或额外调用 `ui_keyboard_dismiss`。
4. 点提交按钮:用 `ui_tap`(普通点击)。**判成败靠紧接着的 `ui_waitAny`**(见 Step 4),不要在 tap 里等稳定——异步提交的 loading 中间态会被误判。

> **为什么现场解析而不是预录 path**:path(`root/0/0/4`)会随 UI 重构变;可见文案("登录"、"用户名")是稳定契约。runner 只信任文案/角色,path 仅在单次 inspect 生命周期内有效。

### Step 4 — 翻译判据 → ui_waitAny.conditions(核心)

把 `pass_criteria` + `fail_criteria` 都翻成 `ui_waitAny.conditions[]`,**塞进同一个调用**,先命中谁就定 pass/fail。映射表:

| 判据词汇 | 翻译成 condition | 备注 |
|---|---|---|
| `textExists('X')` / `textContains('X')` | `{mode:"textExists", text:"X", id:"pass:textExists:X"}` | `textExists` 本身是片段匹配;textContains 无独立 mode,与之等价 |
| `targetExists('「退出登录」红色按钮')` | 先 `ui_inspect` 按描述解析到 `path`/`identifier` → `{mode:"targetExists", path:<解析结果>, id:"..."}` | **必须在当次 inspect 生命周期内解析**;解析不到则该条件省略并记 notes |
| `targetGone('导航返回按钮')` | 解析"该消失的元素"的定位 → `{mode:"targetGone", path/identifier:<...>, id:"..."}` | 若元素本就不在初始树里,用 `navigationBar.backAvailable==false` 间接判 |
| `alert` | **ui_waitAny 无 alert 模式** → 特殊处理(见下) | 作 fail_criterion 时是"不该弹却弹了" |

**condition 的 `id` 命名规约**:`<pass|fail>:<mode>:<value简写>`,让 `matchedID` 一眼看出命中的是哪条判据、是 pass 还是 fail。

**判 pass/fail 的依据是 `ui_waitAny` 返回的 `matchedID`**:
- 命中 `pass:*` → **pass**。
- 命中 `fail:*` → **fail**。
- 超时无命中(`matched:false`,`matchedID` 为 nil)→ **fail**(判据没满足),notes 说明等了什么没来。

**alert 判据特殊处理**(`ui_waitAny` 只有 `idle`/`targetExists`/`targetGone`/`textExists`/`snapshotChanged`,没有 alert):
- 作 **fail_criterion**("成功路径不应弹窗"):`ui_waitAny` 返回后,**追加一次 `ui_inspect`**,看 `alert.available`。`true` → 记 fail_criterion `alert` 命中;`false` → 该 fail 条件未触发(符合预期)。
- 作 **pass_criterion**(罕见,"期望弹某窗"):同样靠 inspect 的 `alert.available + alert.title/buttons` 判,配合 `ui_alert_respond`(走 `ios-ui-alert`)关闭后继续。

**异步 vs 同步(继承 `ios-ui-form` 范式)**:
- `timing:"立即"`(客户端校验):`ui_tap` 后直接 `ui_waitAny(conditions:[pass+fail], timeoutMs:2000)`。错误文案几乎瞬间出现。
- `timing:"约 N 秒后"`(走 Service):`ui_tap` 后 `ui_waitAny(conditions:[pass+fail], timeoutMs: <N秒+余量>)`。**严禁固定 `sleep`**——sleep 短了抓 loading 中间态,长了白等;判据驱动才准。

### Step 4b — 三类进阶判据机制 + 日志断言前置检查(关键)

纯 `ui_waitAny` 文本/目标等待覆盖不到时,用以下机制。intent 的 `notes` 提示需要这些机制时启用。

#### 日志断言前置检查(用 app.logs.read 做断言前必做)

**凡是用 `app_logs_read` 的日志条目做测试断言(机制 1 的 logCount、同文案残留佐证等),必须先确认对应 source 的 `capture.state == "enabled"`**:

1. 先调 `app_logs_mark`,响应 `data.capture` 含 6 个 source(`explore`/`bridge`/`stdout`/`stderr`/`nslog`/`oslog`)的状态快照。
2. 读你要断言的那个 source 的 `capture.state`:
   - `enabled` → 该 source 可作有效日志判据,继续。
   - `notCaptured` → 配置没开,该 source **不能**作判据(读到的空 entries 是"没开"不是"没执行");要打开对应 capture 配置再重启 App,或改用 `bridge`(宿主 App 通过桥接日志 API 主动写,最稳定)。
   - `unavailable` → 配置开了但系统不让读(看 `reason`),该 source **不能**作判据;改用 `bridge`/`stdout`。
3. **只有 `enabled` 的 source 才能作有效日志判据**;`notCaptured`/`unavailable` 的 source 上读到的"空"不能当"代码没执行"的证据。
4. **模拟器上 `oslog` 判据自动降级**:模拟器 `oslog` 通常 `enabled`,但真机 `OSLogStore` 可能 `unavailable`(系统进程级读取限制,iOS 版本相关)。不要按平台写死断言——以实际 `capture.state` 为准。`oslog` 不可用时改用 `bridge`(要求被测 App 在关键点通过桥接日志 API 主动写),或 `stdout`(`print`)。

详见 `ios-logs` skill的"来源 × 平台可用性矩阵"与"`unavailable` 语义"。

#### 机制 1:app.log 计数判据(logCount)

**适用**:验证"仅触发 N 次请求"(如双击守卫)。UI 看不到请求次数,只能靠日志。

1. **前置检查**:先 `app_logs_mark`,确认目标 source(如 `oslog` 或 `bridge`)的 `capture.state=="enabled"`(见上)。`notCaptured`/`unavailable` 则该机制不可用,改 source 或标 skipped。
2. **打点**:保存 `app_logs_mark` 返回的 `cursor`。
3. **执行操作**:如快速双击提交按钮。
4. **读日志**:`app_logs_read(after:<cursor>, sources:["<已确认 enabled 的 source>"], limit:50)`。
5. **数关键词条数**:在 `entries[]` 里找目标 `category` + `message` 片段,数匹配条数。
6. **对照预期**:条数 == 预期值(如双击守卫预期 1)→ pass;多了 → fail(守卫失效)。

> App 用 Swift `Logger(subsystem:category:)` → 走 `oslog` source;用桥接日志 API → 走 `bridge` source;用 `print` → 走 `stdout` source。源不明确时优先要求 App 用 `bridge`(最稳定,纯内存路径不依赖系统日志实现)。

#### 机制 2:瞬时态捕获(loading 窗口)

**适用**:验证"提交期间按钮禁用/spinner 可见"等瞬时态(~1s 级窗口)。

**限制(必须知道)**:分离的 `ui_tap` → `ui_inspect` 两步调用之间有 **2–4s agent-loop 间隔**(tap 结果返回 → 推理 → 发 inspect),会错过亚秒级 loading 窗口。本 skill 的 6 个 MCP 工具不含服务端合并 tap+inspect 的 action,因此:

- 若被测 App 的 loading 窗口足够长(>2s),分离调用可能捕获:`ui_tap` 后立即 `ui_inspect`,读 button `isEnabled`/`title`、spinner `isHidden`,核对 loading 态。
- 若窗口 <1s(如纯客户端同步 loading),分离调用几乎必定错过——将 intent 标 `skipped` + 原因"瞬时态窗口短于 agent-loop 间隔,需服务端合并调用工具"。

> 扩展提示:若后续 iOSDriver 工具集加入服务端合并 tap+inspect action(一次 HTTP 内先 tap 再 inspect,消除 agent-loop 间隔),可可靠捕获亚秒级窗口。在此之前,机制 2 对短窗口诚实标 skipped,不硬造 pass。

#### 机制 3:二次提交协议(secure 字段保留验证)

**适用**:验证"失败后密码框未被清空"。secure 字段 `ui_inspect` 不暴露 text,只能间接判。

1. **第一次提交**:输入 `<seed-user>`/`<错误密码>` → 点登录 → 等出现失败文案(确认走了 Service)。
2. **第二次提交(不重输密码)**:直接再点登录。
3. **区分两条路径**:
   - **密码还在**(符合源码)→ 通过客户端 guard(password 非空)→ 进 Service → 约延迟后再次报失败文案。
   - **密码被清空**(与源码不符)→ 客户端 guard 拦截 → 立即报"请输入密码"(或 App 对应的空密码提示)。
4. **判据**:`ui_waitAny(conditions:[{mode:"textExists", text:"<空密码提示文案>", id:"fail:textExists:请输入密码"}], timeoutMs:3000)`:
   - **超时**(空密码提示没出现)→ 密码还在、走了 Service → **pass**。
   - **命中**(空密码提示出现)→ 密码被清空 → **fail**。
5. **日志佐证(强验证,需前置检查)**:用机制 1 数"开始登录请求"条数——预期 **2**(两次都走了 Service)。只有 1 条说明第二次被客户端 guard 拦截。

> "失败文案"在第一次失败后已残留在 errorLabel 上,不能用它的出现判第二次(会立即匹配残留)。改用**空密码提示的缺席**(超时)作反向判据。

### Step 5 — 记录单条结果

每条 intent 记:
```json
{
  "id": "login-success",
  "status": "pass|fail|skipped",
  "matched_criterion": "pass:textExists:<欢迎语>",
  "duration_ms": 3200,
  "business_points_covered": ["<LoginViewModel>.<login>", "<LoginService>.<login>", "<navigateToHome>"],
  "notes": "约 1.5s 后首页欢迎语出现;alert 未触发(符合预期)"
}
```
- `skipped` 用于:判据在执行层落不了地(如瞬时态窗口短于 agent-loop 间隔)、日志 source 的 `capture.state` 非 enabled 且无替代 source、MVP 范围外、前置依赖未满足。**必须写明 skip 原因**,不要硬造 pass。

### Step 6 — 汇总覆盖报告

整体报告写到 `docs/test-reports/<app>-<flow>-run.json`:
```json
{
  "run_at": "2026-07-15T15:10:00Z",
  "app": "<your-app>",
  "simulator": "<name> (<udid>)",
  "manifest": "docs/test-intents/<app>-<flow>.json",
  "total": 5,
  "passed": 4,
  "failed": 1,
  "skipped": 0,
  "pass_rate": 0.8,
  "business_points_covered": ["..."],
  "results": [ /* Step 5 的单条结果 */ ]
}
```
- `pass_rate = passed / (passed + failed)`(skipped 不计入分母,单列)。
- `business_points_covered`:聚合所有 pass intent 的 `business_points`,看源码分支覆盖了多少。

## 关键参数

### `ui_waitAny`(判 pass/fail 的核心)

| 参数 | 含义 | 注意 |
|---|---|---|
| `conditions` | 条件数组 1–16 项,每项 `{id, mode, ...}` | 顺序即优先级;pass + fail 同塞;`id` 用 `<pass|fail>:<mode>:<value>` 规约 |
| `timeoutMs` | 共享超时 0–30000 | 立即校验 ~2000;异步走 Service 取 `<延迟>+余量` |
| `intervalMs` | 共享轮询间隔 50–5000 | 默认 100;网络等待 200–500 足够 |

每个 condition 的 mode 必需字段:`textExists` 需 `text`;`targetExists`/`targetGone` 需 `accessibilityIdentifier` 或 `path`(由 `ui_inspect` 现场解析);`idle` 无额外字段;`snapshotChanged` 需 `viewSnapshotID`。**没有 alert mode**——alert 靠 `ui_waitAny` 后追加 `ui_inspect` 的 `alert.available` 兜底。

### `ui_inspect`(现场解析 + alert 兜底)

`accessibilityIdentifier` 精确筛 / `accessibilityIdentifierPrefix` 前缀筛;响应 `targets[]` 含 `path`/`type`/`text`/`availableActions`,`alert` 含 `available`/`title`/`buttons`,`navigationBar` 含 `title`/`backAvailable`。`viewSnapshotID` 仅在当次生命周期内有效。

### `app_logs_mark` / `app_logs_read`(日志断言)

| 参数 | 含义 | 注意 |
|---|---|---|
| `app_logs_mark` 无入参 | 建 cursor + 6 source 的 `capture` 快照 | 每次重启后重新 mark,旧 cursor 跨重启失效 |
| `app_logs_read.after` | 上一次 mark/read 的 cursor | 增量读必传;省略 = 非增量读最近 `limit` 条 |
| `app_logs_read.sources` | 来源过滤 | 合法值 6 个:`explore`/`bridge`/`stdout`/`stderr`/`nslog`/`oslog`;**断言前先看对应 source 的 `capture.state`** |
| `app_logs_read.limit` | 最多返回条数 | 1...500,默认 100;`oslog` 噪音多时用 500 |

响应每次都回传 `capture`(6 source 状态快照),可作自检。

## 常见错误与判别

### 日志判据不做 capture 前置检查(最严重,本 skill 新增)

- **现象**:用 `app_logs_read` 数某 source 条数做 pass/fail 判据,读到空就判"代码没执行/请求没发"
- **原因**:该 source 的 `capture.state` 是 `notCaptured`(配置没开)或 `unavailable`(系统不让读),日志其实写了,当前进程读不到
- **判别**:`app_logs_mark` / `app_logs_read` 的 `data.capture` 里该 source 的 `state`;只有 `enabled` 才能作有效判据
- **处理**:`notCaptured` 改 `registerDiagnosticsCommands` 配置打开对应 capture 再重启 App;`unavailable` 看 `reason`,改用 `bridge`(App 关键点通过桥接日志 API 主动写)或 `stdout`;**模拟器 `oslog` 通常 enabled,真机可能 unavailable——不要按平台写死,以实际 `capture.state` 为准**;降级后仍无法获取日志则该 intent 标 `skipped` + 原因

### 同文案失败类 intent 之间不重启(状态污染)

- **现象**:`login-user-not-found` 跑完后,`login-wrong-password` 在 loading 期间(`elapsedMs≈0`)被误判成 pass
- **原因**:两条显示同一句错误,前一条的 errorLabel 残留;`ui_waitAny` 第一次轮询就匹配到旧文本
- **判别**:`matchedID` 命中时 `elapsedMs` 接近 0(没等新请求);或提交后立即命中
- **处理**:同文案失败类 intent 之间**重启 App** 回干净起点(最可靠);不重启时用 `app_logs_read`(需前置检查)佐证有新业务日志条目;或提交前 `ui_inspect` 核对 errorLabel 无残留

### 把超时当 bug / 把 `matched:false` 当成功

- **现象**:`ui_waitAny` 返回后直接继续,以为"返回 = 命中"
- **原因**:超时也返回 `code:"ok"`,只在 `matched:false` + `matchedID` 为 nil 体现
- **判别**:读 `matched`/`matchedID`;`elapsedMs` 接近 `timeoutMs` = 超时
- **处理**:超时按 fail 处理(判据没满足);`ui_waitAny` 后追加 `ui_inspect` 看当前到底是什么状态

### 用固定 sleep 等异步结果(退化)

- **现象**:`sleep 3` 后判成败,时而抓到 loading 中间态,时而错过终态
- **原因**:固定 sleep 无法适配真实时序(网络延迟波动)
- **判别**:判据里出现固定 `sleep` 而非 `ui_waitAny` 的 `timeoutMs`
- **处理**:`ui_tap` 后用 `ui_waitAny(conditions:[pass+fail], timeoutMs:<延迟+余量>)`;判据驱动,命中即返回不白等

### 预录 path 写进执行步骤(违背契约)

- **现象**:执行步骤里写死 `path:"root/0/0/4"`,UI 一重构就失效
- **原因**:把实现细节(path)当稳定契约;意图清单本就不含 path
- **判别**:执行步骤出现硬编码 path 值
- **处理**:每条 intent 执行时 `ui_inspect` 按文案/角色当次解析,path 仅在单次 inspect 生命周期内有效

### 瞬时态用分离 tap+inspect 想抓短窗口

- **现象**:点提交后立即 `ui_inspect` 想抓 button disabled 态,总抓到终态
- **原因**:agent-loop 间隔 2–4s,亚秒级 loading 窗口早过去
- **判别**:`ui_inspect` 读到的 button `isEnabled==true` 且 title 已恢复(loading 已结束)
- **处理**:窗口 >2s 可尝试分离调用;窗口 <1s 标 `skipped` + 原因"需服务端合并调用工具"(本 skill 6 工具不含);诚实 skip,不硬造 pass

## 相关 skill

- `ios-test-intent` — **上游**:离线读源码产出意图清单(本 skill 的输入)。本 skill 止步于消费清单执行,不产出清单。
- `ios-logs` — 日志断言的工具与语义来源;`capture.state` 三态、来源 × 平台矩阵见该 skill。本 skill 的日志判据前置检查引用其矩阵。
- `ios-automation` — L1 总入口;stop/launch App、iproxy、连接管理走它(本 skill 的 6 个 MCP 工具不含 stop/launch,重启 App 时借 L0/L1 完成)。
- `ios-ui-form` — 异步提交的"判据驱动等待"范式来源(本 skill Step 4 继承)。
- `ios-ui-wait` — `ui_waitAny` 的 mode/字段语义来源;`textExists`/`targetExists`/`targetGone`/`idle` 词汇语义。
- `ios-ui-alert` — alert 响应(`ui_alert_respond`)走该 skill;本 skill 只能靠 `ui_inspect` 的 `alert.available` 判 alert 是否出现。

> **真实 App 套用案例**:如需保留具体项目的意图清单、实跑报告、账号、bundle id、设备信息或启动参数,请放在该项目自己的文档或测试数据目录中。本 skill 本体只描述通用方法,不依赖任何真实 App 案例。

## 限制

- **纯 UI 判据覆盖不到的 intent → 用 Step 4b 进阶机制补**:请求数用 logCount(机制 1,需日志 `capture.state` 前置检查);secure 字段用二次提交协议(机制 3);瞬时 loading 态受 agent-loop 间隔限制,短窗口标 skipped(机制 2)。
- **本 skill 不直接负责 stop/launch App、`ui_navigation_back`、`ui_alert_respond`**:重启 App 走构建/设备管理 MCP,导航返回和响应 alert 按钮走 `ios-automation` 及其子 skill,再回本 skill 继续。
- **目标解析失败时该条件省略**:`targetExists('某描述')` 在当次 inspect 解析不到,该 condition 省略并在 notes 记"解析失败",不阻塞其余条件。
- **不验证视觉/动画质量**(颜色、过渡美感)——这是意图层的设计边界,runner 继承。
- **模拟器/真机行为可能差异**:报告里记 `simulator` 字段;日志 source 的 `capture.state` 在两平台可能不同,以实际为准。
- **覆盖率以意图清单的 intent 通过率为准**(passed / (passed+failed)),辅以 `business_points_covered` 看源码分支覆盖;skill 自测用例 `docs/skills/evals/ios-test-runner/evals.json`。
- skill 是执行型指导,无独立运行时副作用(不写代码、不改 App);意图清单是源码快照,App 源码/文案变更后需重跑。
