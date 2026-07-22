---
name: ios-test-runner
description: |
  L2 测试执行 skill:消费 ios-test-intent 产出的测试意图清单,逐条驱动 iOS App
  跑、判 pass/fail、汇总覆盖报告 / test runner, run intent manifest, execute
  tests, coverage report, pass fail judge. 把清单里的 pass/fail 判据
  (textExists / targetExists / targetGone)翻译成运行时 `ui_waitAny.conditions`,
  alert 通过 ui.inspect 观察；用 iOSDriver 现场驱动 UI，并按全部 pass / 任一
  fail 的契约判定结果。

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
- `ios-test-runner`(本 skill):**在线**连 App → 现场把原生等待判据解析成 `ui_waitAny.conditions`、把 alert 解析成 inspect 观察 → 驱动 UI → 收齐全部 pass 或命中任一 fail → 报告。

## 目标

解决三类问题:

1. **"意图清单里的判据能不能在真机/模拟器上落地"**:意图层词汇(`textExists:"<欢迎语>"`)不含 path,本 skill 用 `ui_inspect` 现场按文案/角色解析成真实 target,再把判据塞进 `ui_waitAny.conditions`,由"先命中谁"定成败。
2. **"异步提交到底成功了还是失败了"**:用 `ui_waitAny` 在同一总期限内竞争等待剩余 pass + 全部 fail；命中 pass 只记录该判据，全部 pass 收齐才通过，任一 fail 命中或超时则失败。杜绝固定 `sleep`(会抓 loading 中间态或误判)。
3. **"纯 UI 判据够不着的场景(请求数 / 瞬时 loading 态 / secure 字段)"**:按需读取进阶 reference；日志计数、间接验证和中间态观察都必须有明确证据边界，当前工具无法可靠观察时诚实标 skipped。

解决的核心痛点:agent 跑自动化时常用固定 `sleep` 或 `snapshotChanged` 即兴判异步结果,容易抓到 loading 中间态或把失败误判成成功。本 skill 把判据来源从"即兴"变成"意图清单契约 + 判据驱动等待"。

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

把可原生等待的 `pass_criteria` + `fail_criteria` 翻成 `ui_waitAny.conditions[]`。映射表:

| 判据词汇 | 翻译成 condition | 备注 |
|---|---|---|
| `textExists('X')` | `{mode:"textExists", text:"X", id:"pass:textExists:X"}` | `textExists` 本身是片段匹配 |
| `targetExists('「退出登录」红色按钮')` | 先 `ui_inspect` 按描述解析到 `path`/`identifier` → `{mode:"targetExists", path:<解析结果>, id:"..."}` | **必须在当次 inspect 生命周期内解析**;解析不到则该条件省略并记 notes |
| `targetGone('导航返回按钮')` | 解析"该消失的元素"的定位 → `{mode:"targetGone", path/identifier:<...>, id:"..."}` | 若元素本就不在初始树里,用 `navigationBar.backAvailable==false` 间接判 |
| `alert` | **ui_waitAny 无 alert 模式** → 特殊处理(见下) | 作 fail_criterion 时是"不该弹却弹了" |

**condition 的 `id` 命名规约**:`<pass|fail>:<mode>:<value简写>`,让 `matchedID` 一眼看出命中的是哪条判据、是 pass 还是 fail。

**判定循环**:

1. 为每条判据生成稳定且唯一的 id；同一轮把 fail 条件放在剩余 pass 条件之前，使同时命中时优先暴露失败。
2. 调用 `wait_and_inspect`，从 `result.wait.matchedID` 分支。命中 `fail:*` 立即 fail；命中 `pass:*` 只把该项加入已满足集合，再用剩余总时间等待其他 pass。
3. 所有必需 pass 都已满足，且 alert 等独立 fail 观察也未命中，才判整体 pass。不得把第一条 `pass:*` 命中当成整体通过。
4. `result.wait.code == "wait_timeout"` 表示期限内没有新判据命中，按 fail 记录；`result.observation` 只用于说明当时 UI，不代表成功。各轮共享一个总 deadline，不能每次重新获得完整 timeout。

**alert 判据特殊处理**(`ui_waitAny` 没有 alert mode):有稳定标题/消息时可先用 `textExists` 等待，再用同次 `wait_and_inspect.observation.alert` 确认文本确实属于 alert；没有稳定文本时，在同一总 deadline 内做有界 `ui_inspect` 轮询并检查 `alert.available/title/message/buttons`。alert fail 一旦命中立即失败；alert pass 命中后只记录该判据，仍需完成其余必需 pass。

**异步 vs 同步(继承 `ios-ui-form` 范式)**:
- `timing:"立即"`(客户端校验):`ui_tap` 后直接 `ui_waitAny(conditions:[pass+fail], timeoutMs:2000)`。错误文案几乎瞬间出现。
- `timing:"约 N 秒后"`(走 Service):`ui_tap` 后 `ui_waitAny(conditions:[pass+fail], timeoutMs: <N秒+余量>)`。**严禁固定 `sleep`**——sleep 短了抓 loading 中间态,长了白等;判据驱动才准。

### Step 4b — 条件化判据

只有意图明确要求日志计数、短暂中间态或 secure 字段保留时，才读取 [references/advanced-criteria.md](references/advanced-criteria.md)。这些机制不能替代明确业务终态；日志判据还必须遵循 `ios-logs` 的 capture 状态、完整 cursor 和分页规则。

### Step 5 — 记录单条结果

每条 intent 记:
```json
{
  "id": "login-success",
  "status": "pass|fail|skipped",
  "matched_criteria": ["pass:textExists:<terminal-text>", "pass:targetGone:<baseline-target>"],
  "duration_ms": 3200,
  "business_points_covered": ["<LoginViewModel>.<login>", "<LoginService>.<login>", "<navigateToHome>"],
  "notes": "约 1.5s 后首页欢迎语出现;alert 未触发(符合预期)"
}
```
- `skipped` 用于:判据在当前观测能力下无法可靠落地、日志 source 的 `capture.state` 非 enabled 且无替代 source、MVP 范围外、前置依赖未满足。**必须写明 skip 原因**,不要硬造 pass。

### Step 6 — 汇总覆盖报告

整体报告写到 `docs/test-reports/<app>-<flow>-run.json`:
```json
{
  "run_at": "<ISO-8601 timestamp>",
  "app": "<your-app>",
  "execution_target": "<simulator-or-device description>",
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
| `conditions` | 条件数组 1–16 项,每项 `{id, mode, ...}` | 顺序即优先级;fail 在剩余 pass 之前;`id` 用 `<pass|fail>:<mode>:<value>` 规约 |
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

### 日志判据不做 capture 前置检查

- **现象**:用 `app_logs_read` 数某 source 条数做 pass/fail 判据,读到空就判"代码没执行/请求没发"
- **原因**:该 source 的 `capture.state` 是 `notCaptured`(配置没开)或 `unavailable`(系统不让读),日志其实写了,当前进程读不到
- **判别**:`app_logs_mark` / `app_logs_read` 的 `data.capture` 里该 source 的 `state`;只有 `enabled` 才能作有效判据
- **处理**:`notCaptured` 需开启对应 capture 后重启 App;`unavailable` 看 `reason`,改用已启用且符合业务契约的来源;不要按平台预设状态,只信运行时 `capture.state`;仍无法获取所需证据则该 intent 标 `skipped` + 原因

### 同文案失败类 intent 之间不重启(状态污染)

- **现象**:`login-user-not-found` 跑完后,`login-wrong-password` 在 loading 期间(`elapsedMs≈0`)被误判成 pass
- **原因**:两条显示同一句错误,前一条的 errorLabel 残留;`ui_waitAny` 第一次轮询就匹配到旧文本
- **判别**:`matchedID` 命中时 `elapsedMs` 接近 0(没等新请求);或提交后立即命中
- **处理**:同文案失败类 intent 之间**重启 App** 回干净起点(最可靠);不重启时用 `app_logs_read`(需前置检查)佐证有新业务日志条目;或提交前 `ui_inspect` 核对 errorLabel 无残留

### 把超时当成功

- **现象**:`ui_waitAny` 返回后直接继续,以为"返回 = 命中"
- **原因**:把工具调用完成误当成等待条件满足
- **判别**:`wait_and_inspect` 超时返回 `wait.code=="wait_timeout"`,不会返回可供判定的 `matchedID`
- **处理**:超时按 fail 处理(判据没满足);只把可选的 `observation` 用作分诊,不能据此猜成成功

### 用固定 sleep 等异步结果(退化)

- **现象**:`sleep 3` 后判成败,时而抓到 loading 中间态,时而错过终态
- **原因**:固定 sleep 无法适配真实时序(网络延迟波动)
- **判别**:判据里出现固定 `sleep` 而非 `ui_waitAny` 的 `timeoutMs`
- **处理**:`ui_tap` 后按 Step 4 在共享 deadline 内等待剩余 pass + fail；判据驱动,命中即推进或结束

### 预录 path 写进执行步骤(违背契约)

- **现象**:执行步骤里写死 `path:"root/0/0/4"`,UI 一重构就失效
- **原因**:把实现细节(path)当稳定契约;意图清单本就不含 path
- **判别**:执行步骤出现硬编码 path 值
- **处理**:每条 intent 执行时 `ui_inspect` 按文案/角色当次解析,path 仅在单次 inspect 生命周期内有效

### 把短暂中间态当业务终态

- **现象**:点提交后立即 `ui_inspect` 想抓 button disabled 态,总抓到终态
- **原因**:loading 出现/消失只说明过程变化,且短窗口可能在两次工具调用之间完成
- **判别**:判据只有 spinner 或按钮禁用,没有成功/失败的业务结果信号
- **处理**:用业务终态判定结果；只有测试目标本身就是中间态时才按 reference 的能力边界采集,无法可靠观察则标 `skipped`

## 相关 skill

- `ios-test-intent` — **上游**:离线读源码产出意图清单(本 skill 的输入)。本 skill 止步于消费清单执行,不产出清单。
- `ios-logs` — 日志断言的唯一语义来源；使用日志判据时读取其 capture 三态、完整 cursor、分页和证据边界。
- `ios-automation` — L1 总入口；stop/launch App、iproxy、连接管理由入口路由到当前环境可用的设备能力。
- `ios-ui-form` — 异步提交的"判据驱动等待"范式来源(本 skill Step 4 继承)。
- `ios-ui-wait` — `ui_waitAny` 的 mode/字段语义来源;`textExists`/`targetExists`/`targetGone`/`idle` 词汇语义。
- `ios-ui-alert` — alert 响应(`ui_alert_respond`)走该 skill;本 skill 只能靠 `ui_inspect` 的 `alert.available` 判 alert 是否出现。

> **真实 App 套用案例**:如需保留具体项目的意图清单、实跑报告、账号、bundle id、设备信息或启动参数,请放在该项目自己的文档或测试数据目录中。本 skill 本体只描述通用方法,不依赖任何真实 App 案例。

## 限制

- **纯 UI 判据覆盖不到的 intent → 按需读取 Step 4b 的 reference**:只有日志计数、secure 字段或短暂中间态确实是测试目标时才启用；无法建立可靠证据链就标 skipped。
- **本 skill 不直接负责 stop/launch App、`ui_navigation_back`、`ui_alert_respond`**:重启 App 走构建/设备管理 MCP,导航返回和响应 alert 按钮走 `ios-automation` 及其子 skill,再回本 skill 继续。
- **目标解析失败时不得继续判 pass**:`targetExists('某描述')` 在当次 inspect 无法唯一解析时,该 intent 标 `skipped` 或前置失败并记录原因；不能静默省略必需 pass 或 fail 条件。
- **不验证视觉/动画质量**(颜色、过渡美感)——这是意图层的设计边界,runner 继承。
- **模拟器/真机行为可能差异**:报告里记 `execution_target`;日志 source 的 `capture.state` 在不同运行环境可能不同,以实际为准。
- **覆盖率以意图清单的 intent 通过率为准**(passed / (passed+failed)),辅以 `business_points_covered` 看源码分支覆盖。
- skill 是执行型指导,无独立运行时副作用(不写代码、不改 App);意图清单是源码快照,App 源码/文案变更后需重跑。
