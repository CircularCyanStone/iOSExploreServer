---
name: ios-ui-wait
description: iOS App 异步等待与动态内容稳定(开发验证 + 自动化测试)/ wait, loading, dynamic content, async, polling, idle, targetExists, targetGone, textExists, snapshotChanged, ui_wait, ui_waitAny, wait_and_inspect
allowed-tools:
  - mcp__iOSDriver__ui_wait
  - mcp__iOSDriver__ui_waitAny
  - mcp__iOSDriver__wait_and_inspect
  - mcp__iOSDriver__ui_inspect
---

# iOS 异步等待与动态内容稳定

基于 iOSDriver MCP Server(`mcp__iOSDriver__*`),解决"iOS App 里内容是异步加载 / 动画转场 / 网络请求后才渲染,需要等它到稳定状态再继续操作"这一基础问题。合并自原 `ios-dynamic-content`。核心是三个真实 action:`ui_wait`(单条件等待)、`ui_waitAny`(多条件并发等待,先命中者胜)、`wait_and_inspect`(waitAny + inspect 组合,一次调用拿判定 + 最新结构);当服务端等待因条件复杂度不够用时,退回 `ui_inspect` 轮询兜底。

**重要更正**:旧 skill 把 `ui.wait` / `ui.waitAny` 标成"尚未充分验证、建议手搓 bash 轮询兜底",并列了一个不存在的 `textGone` 模式。按当前 iOSDriver schema(见 `help` 输出),两个 action 均已正式注册、可用,`ui.wait` 的合法 mode 是 `idle` / `targetExists` / `targetGone` / `textExists` / `snapshotChanged`(没有 `textGone`,"等文本消失"要用 `targetGone` 指向承载该文本的 view,或用 `ui_waitAny` 配 `targetGone` 条件)。`ui_inspect` 手搓轮询仍然有效,但定位为"复杂跨命令条件"的兜底,不再是主路径。

## 目标

解决"触发动作(tap / 输入 / 网络请求)后,后续 UI 状态需要时间才到位"的同步问题。典型场景:loading 指示器显示后要等它消失、提交后要等 Success 或 Error 文本之一出现、下拉刷新后要等新内容渲染、push 新屏后要等转场动画结束。关键不是单条命令,而是:

- **等的是"条件达成",不是固定 sleep**:优先用 `ui_wait` / `ui_waitAny` 按条件轮询(条件满足立即返回,不浪费固定 sleep 时间);只在转场动画等"无条件可言"的场景用 `mode:"idle"` + `stableMs` 的稳定窗口。
- **超时是业务结果,不是 bug**:`ui.wait` 超时返回 `code:"ok"` 但 `matched:false`;调用方必须读 `matched` / `matchedConditionId` 判定到底是命中还是超时,不能只看 `code`。
- **多结果分支用 `ui_waitAny`,不要开多个 `ui_wait`**:同一动作后可能 Success / Error / 网络异常三种结局,`ui_waitAny` 一次性表达,`conditions` 数组顺序即优先级,先命中者返回。
- **`snapshotChanged` 用于"不知道等什么,只知道画面会变"**:对照 `viewSnapshotID`,view 树一变就返回;适合 push 后转场结束的检测。
- **服务端等待不万能,`ui_inspect` 轮询兜底**:当等待逻辑涉及跨命令状态(先看 alert 再看 loading)、或条件需要业务计算,退回"循环 `ui_inspect` + 自行判断",旧 skill 的 bash 轮询示例仍有效。

## 何时使用

- ✅ 用户要"等 loading / spinner 消失"
- ✅ 用户要"等某个文本出现"(Success / Error / Welcome back / 空状态提示)
- ✅ 用户要"等某个元素出现 / 消失"(特定 button / cell / 占位图)
- ✅ 用户要"等转场动画结束、画面稳定后再读"(push / modal / 键盘开合)
- ✅ 用户要"在多个可能结果里等第一个发生"(Success vs Error vs 超时)
- ✅ 用户要"等画面发生任意变化"(snapshotChanged,不预设具体目标)
- ✅ 用户说 "等" / "wait" / "loading" / "加载完" / "异步" / "动态内容" / "稳定" / "轮询"
- ❌ 不要用于点按 / 输入本身(走 `ios-ui-form` / `ios-ui-list`),本 skill 只管"动作之后的等待"
- ❌ 不要用于纯截图时机控制(走 `ios-ui-shot`,它内联 `ui_wait` 做短稳定窗口,不归本 skill)
- ❌ 不要用于手势后动画(走 `ios-ui-gesture`,手势 skill 自带 `ui_wait` 短窗口说明)
- ❌ 不要用于 alert 响应(走 `ios-ui-alert` 的 `ui_alert_respond`,本 skill 只能"等 alert 出现",不能点按钮)

## 工作原理

等待时序:**触发动作 → 选择等待模式 → (命中 / 超时) → 读 matched / matchedConditionId → 重新 inspect 基于新 snapshot 继续**。等待返回的只是"条件是否达成",不返回最新控件树;后续操作必须重新 `ui_inspect`(snapshot 变了,旧 `viewSnapshotID` 作废)。

### 1. 单条件等待(`ui_wait`)

五种 mode,每种所需字段不同:

| mode | 等什么 | 必需字段 | 典型用途 |
|---|---|---|---|
| `idle` | UI 连续稳定 `stableMs` 毫秒 | `stableMs`(默认 300) | 转场动画 / 键盘开合后的稳定窗口 |
| `targetExists` | 某 view 出现 | `accessibilityIdentifier` 或 `path` | 等 button / cell / 占位图出现 |
| `targetGone` | 某 view 消失 | `accessibilityIdentifier` 或 `path` | 等 loading spinner / progressView 消失 |
| `textExists` | 任意 view 的 text 含指定片段 | `text` | 等 Success / Error / Welcome 文本 |
| `snapshotChanged` | view 树相对参照发生变化 | `viewSnapshotID`(来自上次 `ui_inspect`) | push 后转场结束、不预设具体目标 |

通用参数:`timeoutMs`(0–30000,默认 3000)、`intervalMs`(50–5000,默认 100)、`includeHidden`(默认 false,是否算隐藏 view)。响应:`code:"ok"`、`data.matched`(bool)、`data.elapsedMs`。

**没有 `textGone`**:等文本消失要么用 `targetGone` 指向承载该文本的 view(需要 a11y id),要么用 `ui_waitAny` 的 `targetGone` 条件,要么退回 `ui_inspect` 轮询自己判文本。

### 2. 多条件并发等待(`ui_waitAny`)

`conditions` 数组(1–16 项),每项 `{id, mode, ...mode 必需字段}`,顺序即优先级(同时命中时返回靠前的)。顶层共享 `timeoutMs` / `intervalMs` / `stableMs` / `includeHidden`。响应:`matched`(bool)、`matchedID`(命中的 condition id)、`matchedIndex`、`elapsedMs`。

典型三路分支(提交后等 Success / Error / 超时):

```
ui_waitAny(
  conditions: [
    {id:"success", mode:"textExists", text:"Success"},
    {id:"error",   mode:"textExists", text:"Error"},
    {id:"loading_done", mode:"targetGone", accessibilityIdentifier:"loading.spinner"}
  ],
  timeoutMs: 15000,
  intervalMs: 200
)
```

三个 condition 共享同一个 15 秒预算 + 200ms 轮询;第一个命中立即返回。超时返回 `matched:false`,`matchedID` 为 `nil`。

### 3. 组合助手 `wait_and_inspect`

`wait_and_inspect` = `ui_waitAny` + `ui_inspect` 一次调用。先按 conditions 轮询,命中或超时后**再调一次 `ui_inspect`** 返回最新 `targets` / `alert` / `navigationBar` + `viewSnapshotID`。参数与 `ui_waitAny` 同(`conditions` / `timeoutMs` / `intervalMs` / `stableMs` / `includeHidden`),外加 `inspectOptions`(只接受 `ui_inspect` 的真实字段:`maxDepth` / `accessibilityIdentifier` / `textLimit` / `maxTargets` 等,不能塞 `detailLevel` 或 `conditions`)。

适合"等待后立刻要基于新 snapshot 继续"的场景,省一轮推理。超时也会尽量返回最新的 observation,不会因超时丢掉 inspect 结果。

### 4. `ui_inspect` 轮询兜底

服务端等待表达不了的复杂条件,退回手搓轮询(旧 skill 的 bash 示例依然有效,但**优先用 `ui_wait` / `ui_waitAny`**,网络往返少一个数量级):

- 等的是跨命令的复合状态(先有 alert、alert 关掉后 loading、loading 完看新内容)
- 条件需要业务计算(对比两次 inspect 的 targets 差异、计数特定 cell)
- 调试期想看每一轮 inspect 的原始 targets

典型兜底:每 300–500ms 一次 `ui_inspect`,自己解析 `targets`,命中即停;总时长封顶(自己设 timeout,别无限循环)。

### 5. loading 指示器处理

loading spinner 通常带 a11y id(如 `loading.spinner` / `HUD.progress`),用 `targetGone` 等它消失最稳;没 a11y id 时改用 `textExists` 等它常带的 "Loading..." 文本(但 `textExists` 只能等出现,等消失要退回 `ui_inspect` 轮询自己找文本)。**等 loading 消失 ≠ 内容已加载**:loading 消失后建议再 `ui_wait(mode:"idle", stableMs:300)` 给渲染留时间,或直接 `wait_and_inspect` 一步拿新 snapshot。

## 关键参数

### `ui_wait`

| 参数 | 含义 | 注意 |
|---|---|---|
| `mode` | 五选一:`idle` / `targetExists` / `targetGone` / `textExists` / `snapshotChanged` | 默认 `idle`;**没有 `textGone`** |
| `timeoutMs` | 业务超时,0–30000,默认 3000 | 命中即返回;超时返回 `matched:false` |
| `intervalMs` | 轮询间隔,50–5000,默认 100 | 越短越及时但越耗 CPU / 网络 |
| `stableMs` | `idle` 模式连续稳定的毫秒数,0–10000,默认 300 | 非 idle 模式无效 |
| `text` | `textExists` 要等文本片段 | 子串匹配,不是全等 |
| `accessibilityIdentifier` / `path` | `targetExists` / `targetGone` 定位目标 | 二选一 |
| `viewSnapshotID` | `snapshotChanged` 的参照快照 | 来自上次 `ui_inspect` |
| `includeHidden` | 是否算隐藏 view,默认 false | 隐藏 loading 也算消失时才开 |

### `ui_waitAny`

| 参数 | 含义 | 注意 |
|---|---|---|
| `conditions` | 条件数组,1–16 项 | 每项 `{id, mode, ...}`;顺序即优先级 |
| `timeoutMs` | 共享超时,0–30000,默认 3000 | 所有 condition 共用 |
| `intervalMs` | 共享轮询间隔,50–5000,默认 100 | 同上 |
| `stableMs` | `idle` 条件的稳定窗口,0–10000,默认 300 | 只对 `idle` 条件生效 |
| `includeHidden` | 共享,默认 false | 影响 `idle` / `textExists` / `targetExists` / `targetGone` |

每个 condition 的 mode 必需字段与 `ui_wait` 一致:`targetExists` / `targetGone` 需 `accessibilityIdentifier` 或 `path`;`textExists` 需 `text`;`snapshotChanged` 需 `viewSnapshotID`;`idle` 无额外字段。

### `wait_and_inspect`

同 `ui_waitAny` 入参,再加 `inspectOptions`(只接 `ui_inspect` 字段)。返回 `ui_waitAny` 结果 + 最新 `ui_inspect` 结果。

### `ui_inspect`(轮询兜底用)

关键参数:`accessibilityIdentifier`(精确筛)、`accessibilityIdentifierPrefix`(前缀筛)、`includeHidden`、`maxDepth`、`maxTargets`(默认 200,上限 512)、`textLimit`(默认 80)。响应 `targets[]` 含 `path` / `type` / `text` / `accessibilityIdentifier` / `availableActions` 等。

## 常见错误与判别

### 把超时当 bug(最常见)

- **现象**:`ui_wait` / `ui_waitAny` 返回后,调用方以为"返回 = 成功",直接继续操作
- **原因**:超时也返回 `code:"ok"`,只在 `data.matched` 为 `false`(或 `matchedID` 为 `nil`)上体现
- **判别**:读 `matched` / `matchedID`;`matched:false` + `elapsedMs` 接近 `timeoutMs` = 超时
- **处理**:超时按业务处理(重试 / 报错 / 退回 inspect 看当前到底什么状态);不要假设命中

### 用了不存在的 `textGone` mode

- **现象**:`ui_wait(mode:"textGone", ...)` 报 `invalid_data`,mode 不合法
- **原因**:旧 skill 列了 `textGone`,实际 schema enum 没有;合法 mode 只有 `idle` / `targetExists` / `targetGone` / `textExists` / `snapshotChanged`
- **判别**:响应 message 指向 mode 字段
- **处理**:等"文本消失"改用 `targetGone` 指向承载文本的 view(需 a11y id),或 `ui_waitAny` 配 `targetGone` 条件,或退回 `ui_inspect` 轮询自己找文本

### `snapshotChanged` 缺 `viewSnapshotID`

- **现象**:`ui_wait(mode:"snapshotChanged")` 报参数缺失或无效
- **原因**:`snapshotChanged` 必须有参照 `viewSnapshotID`,来自上一次 `ui_inspect`;没参照无法判"变化"
- **判别**:响应 message 指向 `viewSnapshotID`
- **处理**:先 `ui_inspect` 拿 `viewSnapshotID`,再把它原样传给 `ui_wait`;注意 snapshot TTL,超时(默认 120 秒)会过期

### `targetExists` / `targetGone` 既没 id 也没 path

- **现象**:报 `invalid_data`,定位参数缺失
- **原因**:这两个 mode 强制要求 `accessibilityIdentifier` 或 `path` 至少一个;都没有无从定位
- **判别**:响应 message 指向定位字段
- **处理**:补 a11y id 或 path;若目标无 a11y id,退回 `textExists`(按文本)或 `ui_inspect` 轮询自己按 `text` / `type` 找

### 轮询间隔太短把 App 打卡

- **现象**:`intervalMs:50` 频繁 `ui_inspect`,App 主线程被占满,loading 反而更慢
- **原因**:`ui_inspect` 在主线程遍历 view 树,高频轮询会与被等的渲染抢线程
- **判别**:轮询期间 App 卡顿、loading 时间异常拉长
- **处理**:`intervalMs` 用 200–500(默认 100 已经偏快);网络等待场景 500ms 足够

### loading 消失 ≠ 内容已渲染

- **现象**:`targetGone` 命中 loading spinner 消失,立即 tap 新内容却报 `target_not_found`
- **原因**:loading view 移除后,新内容还要一个 runloop 才上树;立即操作时新 snapshot 还没就绪
- **判别**:命中后紧接着的操作报 `target_not_found` / `stale_locator`
- **处理**:loading 消失后再 `ui_wait(mode:"idle", stableMs:300)`,或直接用 `wait_and_inspect` 一步拿到新 snapshot 再操作

### 用 `ui_wait` 等待 alert(误用)

- **现象**:用 `textExists` 等 alert 标题文本,命中了却无法响应按钮
- **原因**:`ui_wait` 只返回 `matched`,不返回 alert 结构;响应 alert 要走 `ui_alert_respond`
- **判别**:等待目标是 `UIAlertController` 弹窗
- **处理**:等 alert 出现可用 `ui_wait(textExists:alert.title)` 或直接 `ui_inspect` 看 `alert.available`;响应按钮必走 `ios-ui-alert` 的 `ui_alert_respond`

## 相关 skill

- `ios-ui-form` / `ios-ui-list` — 触发动作(tap / input / sendAction)归它们;本 skill 只管动作之后的等待
- `ios-ui-nav` — 屏幕切换动画后的稳定等待该 skill 内联 `ui_wait(idle)` 处理;长时异步等待 / loading 归本 skill
- `ios-ui-gesture` — 手势后 ~300ms 动画稳定由手势 skill 自带;本 skill 管 >300ms 的异步等待
- `ios-ui-shot` — 截图前的短稳定窗口由截图 skill 内联;本 skill 不截图
- `ios-ui-alert` — 等 alert 出现可借本 skill 的 `textExists`,但响应 alert 按钮必走 `ui_alert_respond`
- `ios-automation` — L1 总入口;不确定走哪个子 skill 时先问它

**平台约束**:iOSExploreServer 是 Debug-only 开发工具,等待 action 在主线程轮询 view 树,被 `#if DEBUG` 隔离,Release 构建下不可用。`timeoutMs` 硬上限 30000ms(30 秒),`intervalMs` 下限 50ms;`viewSnapshotID` 默认 TTL 120 秒,`snapshotChanged` 参照过期会报错。iOS 不向测试暴露"网络请求完成"或"滚动结束"事件,等待只能基于 view 树可见状态间接判定,无法感知后台任务进度。
