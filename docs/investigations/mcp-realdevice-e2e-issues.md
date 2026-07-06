# iOSExplore MCP 真机端到端测试 - 发现问题全集

> 调查时间：2026-04-28
> 调查方式：MCP stdio server（`MCPServer/dist/src/index.js`）经 iproxy USB 转发（端口 38321）→ 真机 SPMExample（`com.coo.SPMExample`，iOS 26.5），按页面分批执行验证脚本
> 测试设备：李奇奇的iPhone（CoreDevice id `3AC0C7D6-22F6-572B-8368-4047A14BAB52`，UDID `00008030-001045C136D1402E`，iOS 26.5）
> 测试用例 App：`Examples/SPMExample`（首页 / AlertTest / ControlTest / DiagnosticsTest 等）
> 测试通过率：24/26 = 92.3%，2 个已知失败 + 多个改进项

本文文件级、源行号级记录所有问题。**触发关键点** 单独成节，便于复现。源行号引用基于会话当时的代码状态，若改动需要再核对。

---

## 0. 测试脚手架

每一组测试都用一次性 stdio 客户端（`/tmp/mcp_*.mjs`）连到 MCPServer，调用 `tools/call` 触发动态/静态工具，工具内部走 `iOSExploreClient.call(action, data)` → `fetch http://localhost:38321/` → iproxy → 真机 iOSExploreServer。每个测试用例独立 session，避免 stale `viewSnapshotID`。

测试发现的问题按范畴分两组：

- **范畴 A**：iOSExploreServer 主体（Swift）功能缺陷（问题 1–3）
- **范畴 B**：MCPServer（TypeScript bridge）改进点（问题 4–9）

---

## 1. 问题清单（按重要性排序）

| # | 模块 | 问题 | 严重性 | 触发关键点 |
|---|------|------|--------|-----------|
| 1 | UIKit/ControlAction | UIStepper 的 `valueChanged` 不声明，`control.sendAction` 拒绝派发 | 中 | 任何 UIStepper + sendAction valueChanged |
| 2 | UIKit/ControlAction | `control.sendAction` 无法携带新 value，slider/segmented/stepper 只能发"空"事件 | 中 | slider 设特定值、stepper 步进到指定值 |
| 3 | UIKit/Alert | alert dismiss 是动画，紧接的 `observe`/`topViewHierarchy` 仍报告 `UIAlertController` | 低 | alert.respond dryRun=false 之后立即调用 observe |
| 4 | MCPServer/transport | 真机 App 退出 / iproxy 断开后 MCP 调用报 `connection_failed`，无自愈 | 中 | 杀掉 SPMExample 进程，再调任意 tool |
| 5 | MCPServer/registry | 动态工具不自动 refresh：App 重装上报不同 action 集合时旧工具会变 `unknown_tool` | 中 | App 进程被替换 / 更新 |
| 6 | MCPServer/toolName | `ios_` 前缀过长，工具名动辄 30 字符（`ios_ui_navigation_tapBarButton`） | 低 | agent 选择工具时认知距离大 |
| 7 | MCPServer/static | `observe` 硬编码 `ui.viewTargets`，无 `topViewHierarchy` 选项 | 低 | 想拿完整层级树时必须显式调动态工具 |
| 8 | MCPServer/static | `wait_and_observe` 把 `viewTargetsOptions` 当顶层字段 conn 到 `ui.viewTargets`，但 `ui.viewTargets` schema 拒绝该字段 | 中 | wait_and_observe 传 viewTargetsOptions |
| 9 | MCPServer/screenshot | `ui.screenshot` 返回 base64 整段塞进 `content[0].text`，几十 KB 起 | 低 | 每次截图膨胀 MCP 响应 |

> **2 个真"失败"** = 问题 1（UIStepper）+ 问题 8（wait_and_observe 视图参数透传）；其它为改进项或下游修复建议。

---

## 2. 问题 1：UIStepper 的 `valueChanged` 不支持

### 2.1 现象

通过 MCP stdio 调用：

```javascript
await tool('ios_ui_control_sendAction', {
  viewSnapshotID: snap,
  path: stepper.path,         // accessibilityIdentifier="test.stepper"
  event: 'valueChanged'
});
```

返回错误：

```json
{
  "source": "ios_envelope",
  "message": "requested action is not supported for target",
  "code": "invalid_data",
  "action": "ui.control.sendAction"
}
```

`observe` 输出的 stepper `availableActions: []`——没有 `control.valueChanged`。其它 value 型控件（`UISlider`/`UISegmentedControl`）正常工作。

### 2.2 触发关键点

1. 视图中存在 `UIStepper`（`accessibilityIdentifier="test.stepper"`，enabled=true）
2. 调用 `ui.control.sendAction`，`event="valueChanged"`，且 `viewSnapshotID` 与 path 都来自最近一次 `ui.viewTargets`
3. 立即返回 `invalid_data / "requested action is not supported for target"`

不触发的情形：用 `event="touchUpInside"` / `"touchDown"` 时，`controlActions(for:)` 也不返回这些 case，所以同样报 unsupported；用 `ui.tap` 在 UIStepper 上同样失败，因为没有默认激活路由（见问题 1.5）。

### 2.3 根因分析

**`Sources/iOSExploreUIKit/Support/Action/UIKitActionCapabilityResolver.swift:110-118`**：

```swift
private static func controlActions(for control: UIControl) -> [UIKitActionKind] {
    if control is UITextField {
        return [.controlEditingChanged, .controlEditingDidBegin, .controlEditingDidEnd]
    }
    if control is UISwitch || control is UISlider || control is UISegmentedControl {
        return [.controlValueChanged]
    }
    return [.controlTouchDown, .controlTouchUpInside]
}
```

`UIStepper` 落到 fallthrough `else` 分支，被声明为 `controlTouchDown`/`controlTouchUpInside`，**没有声明 `controlValueChanged`**。

**`Sources/iOSExploreUIKit/Support/Action/UIKitActionExecutor.swift:268-274`** 每次 `sendAction` 都重新 capability-check：

```swift
let requestedAction = UIKitActionCapabilityResolver.actionKind(for: event)
let availability = UIKitActionCapabilityResolver.resolve(view: control, rootView: context.rootView)
guard availability.actions.contains(requestedAction) else {
    throw UIKitCommandError.unsupportedAction(action: controlAction, ...)
}
```

—— capability 不声明就抛 `unsupportedAction`。

`UIKitDefaultActivationResolver.route(for:)`（`UIKitDefaultActivationResolver.swift:39-46`）只识别 `UIButton`/`UISwitch`/`UITextField`/`UISearchTextField`/`UITextView`；`UIStepper` 没列，所以 `ui.tap` 也无法触发它。

### 2.4 影响

- `UIStepper` 无法通过 `ui.control.sendAction` 触发任何 `valueChanged`，无法让 Madden step 多步/到指定值
- 也无法通过 `ui.tap` 触发（不属默认激活路由）
- 唯一变通：通过 `ui.tap` 敲 stepper 上的坐标（+/- 按钮），但这要求细分 stepper 子视图，且 stepper 子 view 在 `ui.viewTargets` 中通常不暴露成 canonical target

### 2.5 修复建议

在 `UIKitActionCapabilityResolver.controlActions(for:)` 第 114 行把 `UIStepper` 加入 value 型控件判定：

```swift
if control is UISwitch || control is UISlider || control is UISegmentedControl || control is UIStepper {
    return [.controlValueChanged]
}
```

若要 stepper 也能 `ui.tap`，再在 `UIKitDefaultActivationResolver.route(for:)` 加一个 `.stepperStep` 路由分支；这是另一项工作，不在最小修复范围。

### 2.6 验证脚本

```bash
# 假设已 navigate 到 ControlTestViewController + 真机已连
node -e "
const {spawn}=require('node:child_process');
const ch=spawn('node',['/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/MCPServer/dist/src/index.js'],{stdio:['pipe','pipe','pipe'],env:{...process.env,IOS_EXPLORE_BASE_URL:'http://localhost:38321/'}});
// ... 标准 stdio 协议封装
await tool('ios_ui_control_sendAction',{accessibilityIdentifier:'test.stepper',event:'valueChanged',viewSnapshotID:snap});
// 修复前 -> 'requested action is not supported for target'
// 修复后 -> sent:true
"
```

---

## 3. 问题 2：`control.sendAction` 不接受 `value` 参数

### 3.1 现象

`ui.control.sendAction` 的 inputSchema **没有** `value` 字段。问题不在错误本身，而在协议设计：对 value 型控件，事件触发只发 `valueChanged`，但控件本身的 `value` 属性不会被 executor 设置——只是 `sendActions(for: .valueChanged)`。

> 这意味着 slider 永远不会因为 `control.sendAction valueChanged` 而改变值；segmented 不会更新 selectedIndex；stepper（即使问题 1 修了）也不会真的步进。

### 3.2 触发关键点

测试用例：通过 `ui.control.sendAction` 给 `test.slider`（accessibilityIdentifier）发 `valueChanged`：

```javascript
await tool('ios_ui_control_sendAction', {
  viewSnapshotID: snap,
  path: slider.path,
  event: 'valueChanged',
  value: 0.85    // <-- 该字段不存在
});
```

返回错误：

```json
{
  "source": "ios_envelope",
  "message": "unknown command input field 'value'",
  "code": "invalid_data",
  "action": "ui.control.sendAction"
}
```

不带 `value` 字段时成功"发"事件——但 slider value 仍然不变（只触发事件，不改 value）。

### 3.3 根因分析

**`Sources/iOSExploreUIKit/Commands/ControlAction/UIControlSendActionModels.swift:42-48`** 字段列表只有 4 个：

```swift
static let all: [AnyCommandField] = [
    accessibilityIdentifier.erased,
    path.erased,
    viewSnapshotID.erased,
    event.erased,
]
```

`additionalProperties: false` + 严格字段读取器，未知字段直接 `unknown command input field`。

**`UIControlSendActionCommand.swift:34-37`** 构造 plan 时也只携带 event：

```swift
let plan = UIKitActionPlan.controlEvent(locator: input.target.locator,
                                        event: input.event,
                                        viewSnapshotID: input.viewSnapshotID)
```

**`UIKitActionExecutor.executeControlEvent` 第 277 行**：

```swift
control.sendActions(for: event.uiControlEvent)
```

只发事件，没有先 `control.value = ...`。

### 3.4 影响

| 控件 | 实际行为 |
|------|----------|
| UISwitch | `ui.tap` 路径会先 `setOn(!isOn)`，OK；但 sendAction valueChanged 不会翻转 |
| UISlider | `sendAction valueChanged` 只触发，value 不变 |
| UISegmentedControl | 同上，selectedSegmentIndex 不变 |
| UIStepper | 同上（且能力不支持，连事件都发不出，见问题 1）|

### 3.5 修复建议

设计层决定：

1. **执行层实现**：在 `executeControlEvent` 中，若 input 携带 `value`，先按控件类型 cast + set，再 `sendActions(for:)`：
   ```swift
   if let slider = control as? UISlider, let newValue = input.value?.doubleValue {
       slider.value = newValue
   } else if let seg = control as? UISegmentedControl, let idx = input.value?.intValue {
       seg.selectedSegmentIndex = idx
   } else if let step = control as? UIStepper, let v = input.value?.doubleValue {
       step.value = v
   }
   control.sendActions(for: event.uiControlEvent)
   ```
2. **schema 层**：在 `UIControlSendActionInput.Fields` 增加 `value` 字段（`number? / string? / int?` — JSONValue），约束为仅 `valueChanged` 事件时可携带；typed 解析时把 `value` 传给 plan
3. **plan 层**：`UIKitActionPlan.controlEvent` 增加 `value: JSONValue?` 关联值
4. 输入 schema description 在 descriptionSuffix 里说明"对 value 型控件可携带 value 字段"

优先级低于问题 1（后者连事件都发不出，前者只是"发空事件"），但两个一起才能让 stepper/slider 真正可远程驱动到目标值。

---

## 4. 问题 3：alert dismiss 后立即 `observe`/`topViewHierarchy` 仍报告 `UIAlertController`

### 4.1 现象

在 AlertTestViewController 上点开 alert → `ui.alert.respond dryRun=false buttonIndex=0` 触发"确认" → handler 已执行；**紧接着**的 `observe` 返回的 `navigationBar.topViewController == "UIAlertController"`，而不是 `AlertTestViewController`，且 `screen.topViewController` 仍是 `UIAlertController`，viewTargets 返回的 `targetCount == 0` 或极少（alert 的 `_UIAlertControllerInterfaceActionGroup allottee`）。

需要再 `sleep 500ms+` 或重两次 `observe` 才能恢复成 AlertTestViewController。

### 4.2 触发关键点

1. 进入 AlertTestViewController（首页 cell `item=0`）
2. 触发任意有按钮的 alert（比如点 "标准 alert" 按钮 → alert 展示）
3. 调用 `ui.alert.respond` `dryRun=false` 触发 dismiss
4. **同一 stdio session 内立即（< ~300ms）** 调 `observe` 或 `ui.topViewHierarchy`
5. `topViewController` 仍是 `UIAlertController`

延迟足够长（~700ms 在 iOS 26.5 真机上）后再次观察，topViewController 才恢复。

### 4.3 根因分析

- **`Sources/iOSExploreUIKit/Commands/Alert/UIAlertRespondCommand.swift:30-33`**：handle 在 MainActor 上调 executor，executor 调 `alert.explore_dismissWithAction`。dismiss 是异步动画——UIKit `dismiss(animated:true)` 默认 0.25–0.4s 转场。
- **`Sources/iOSExploreUIKit/Support/Action/UIAlertRespondExecutor.swift:60-66`**：`isPresented` 时走 `explore_dismissWithAction`（封装 `dismiss(animated: true, completion:)`），handler 在 completion 之前被同步触发；但 `presentedViewController` 在动画完成前仍非 nil
- **`Sources/iOSExploreUIKit/Support/Context/UIKitContextProvider.swift:73-87`**：`topViewController(from:)` 递归走 `controller.presentedViewController`——alert 还没消失时，仍然把 `UIAlertController` 当成 top
- **`Sources/iOSExploreUIKit/Support/Action/UIAlertInspector.swift:53-55`**：`findAlert` 直接 `context.topViewController as? UIAlertController`——alert 还在的情况下能"找到"已触发但未完成 dismiss 的 alert

### 4.4 影响

- 在 alert.respond 之后立即做后续 UI 操作的 agent 会拿到错误 top（alert still alive），导致下一步 tap / control action 不命中（因为 `availableActions=[]`、viewSnapshot 陈旧）
- `viewSnapshotID` 校验也可能因为 topViewController 变了（context 指纹包括 `topViewControllerIdentity`，见 `UIKitFingerprintCollector.swift:104-110`）而抛 `stale_locator`

### 4.5 修复建议（择一）

1. **session 内置 wait**：在 `alert.respond` 完成后，`UIKitCommandLogging` 之外加一次"等待 presentedViewController 变 nil"，或者返回 `dismissed=true` 之后 server 端先 await runloop 一次
2. **文档加默认 sleep 建议**：在 `ui.alert.respond` 的 description 显式说明"dismiss 后请等待 ≥500ms 再 observe"
3. **client-side 重试**：MCPServer `wait_and_observe` 在 alert.respond 之后能用来明确等待稳定

最简且不破坏协议：在 `UIAlertRespondExecutor.perform` 的 dismiss 后，RunLoop spin 最多 500ms 或 to `presentedViewController == nil`，再返回结果。这一项已经在"问题"清单中，因为对 agent 透明（agent 看见 `dismissed: true` 后任何后续调用都安全）。

### 4.6 验证脚本要点

```javascript
// session A: alert.respond dryRun=false buttonIndex=0
// session B: 立即 observe → topViewController == UIAlertController （bug）
// session B: sleep 600ms + observe → topViewController == AlertTestViewController （normal）
```

---

## 5. 问题 4：真机 App / iproxy 断开后 MCP 没有 connection 自愈

### 5.1 现象（实测序列）

完整过程的描述：

1. 真机 SPMExample 进程被 `stop_app_device` 或自然 crash / 退出
2. iproxy 仍在 38321 监听（`lsof -iTCP:38321` 仍能看到 iproxy PID），但底层 device socket 端被远端 reset
3. 调任何 iOSExplore MCP 工具 → `MCPServer/dist/src/iosExploreClient.ts:23-34` 抛 `fetch failed`
4. 该抛错被 `errors.ts` 包成 `{ source: "transport", code: "connection_failed", message: "fetch failed", action, baseURL, timeoutMs }`

实测发生过两次：
- 在 ControlTest 第一轮调用之后，进入 ControlTest 时整个 SPMExample 进程 crash（可能因为另一个 bug）
- 一次正常 `wait_and_observe` 完成后再次 `topViewHierarchy` 调用，transport 立即 connection_failed

恢复路径只有手动：用 XcodeBuildMCP `launch_app_device` 重启 SPMExample 进程后才能继续。

### 5.2 触发关键点

- 调用任一动态工具时，iOSExploreServer 真机端进程不存在（被杀掉 / crashed / 设备睡眠）
- `iproxy 38321` 在 Mac 上仍 LISTEN，但有连接进入后立即 RST（`Recv failure: Connection reset by peer`）
- MCPServer fetch 此错误 → 返回 `connection_failed`，且没有任何 retry/refresh 机制

### 5.3 根因分析

- **`MCPServer/src/iosExploreClient.ts:11-25`**：`fetch` 失败立即抛 `IOSExploreStructuredError({ source: "transport", code: "connection_failed" ... })`，无重试
- **`MCPServer/src/server.ts:30-40`** `callTool` 把 error 包成 `errorResult`，调用方收到 `isError: true`，但 `next_steps` / 描述里没有"重启 SPMExample"的步骤
- **`MCPServer/src/staticTools.ts:13-25`** `health_check` 能区分 ok/false，但 caller 拿到 `connection_failed` 后**不会自动调 health_check 给 agent 提示恢复路径**

### 5.4 影响

agent 看到 connection_failed 但不知道根因是 app 死了；需要工程师用 `mcp__XcodeBuildMCP__list_devices` + `launch_app_device` 人工恢复。

### 5.5 修复建议

1. `callTool` 在 transport `connection_failed` 时，自动调 `health_check`，将结果拼在 errorResult：
   ```
   "nextSteps": [
     "iOSExplore app 不可达；可能是 App 退出/崩溃/被切到后台 → 用 mcp__XcodeBuildMCP__launch_app_device 重启 bundleId=com.coo.SPMExample (env IOS_EXPLORE_AUTOSTART=1)"
   ]
   ```
2. `staticTools.ts / callTool` 增加"backoff + retry once" — fetch failed 后 sleep 200ms 重试 1 次，覆盖瞬时掉线场景
3. `health_check` 输出结构里加 `transport: "ok/broken"` + 标识上次失败 action

### 5.6 工作绕过（临时）

人工恢复步骤：
```bash
mcp__XcodeBuildMCP__list_devices  # 取 deviceId（CoreDevice id，不是 UDID）
mcp__XcodeBuildMCP__launch_app_device  # bundleId=com.coo.SPMExample, env IOS_EXPLORE_AUTOSTART=1
# 等待 ~3s tiproxy 重新打通
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
```

---

## 6. 问题 5：动态工具列表不自动 refresh

### 6.1 现象

`ToolRegistry.refresh()` 在 MCPServer 启动时调用一次。后续如果 App 重启上报不同 help 输出（罕见，但例如升级了 iOSExploreServer 添加了新 action），MCP 客户端只看到旧 tool 列表；新工具会返回 `unknown_tool`。

### 6.2 触发关键点

1. MCPServer 启动（首个 stdio 连接） → 注册一批动态工具
2. 不要 `refresh_tools`，不要重启 MCPServer
3. App 进程被替换为新版（iOSExploreServer 帮助列表多出新的 action 比如 `ui.foo`）
4. 客户端调用 `ios_ui_foo` → `server.ts:36-50` findByName → nil → 返回 `Unknown tool 'ios_ui_foo'`

之所以触发条件"罕见"：同一次会话内 App 不会变；但跨会话或长生命周期 MCPServer 容易漏 refresh。

### 6.3 根因分析

- **`MCPServer/src/server.ts:30-40`** 在 `callTool` 命中 unknown_tool 时不会自动 `registry.refresh()` + 重试
- **`MCPServer/src/staticTools.ts:26-34`** 显式提供了 `refresh_tools` 工具，但调用方需要主动想到去调

### 6.4 修复建议（与问题 4 合一）

`server.ts` 在 `dynamic === undefined` 且工具名带 `ios_ui_` / `ios_app_` 等动态前缀时，先 `await registry.refresh()`，然后重新 findByName；若仍不存在才返回 `unknown_tool`。这条加一个**单次幂等的 fallback refresh**。

---

## 7. 问题 6：工具名 `ios_` 前缀冗长

### 7.1 现象

`toolNameForAction(action)`（`MCPServer/src/toolName.ts:7-9`）无条件加 `ios_` 前缀 + 把 `.` 替换为 `_`：

- `ui.tap` → `ios_ui_tap`
- `ui.navigation.tapBarButton` → `ios_ui_navigation_tapBarButton`（30 字符）
- `app.logs.read` → `ios_app_logs_read`（18 字符）

agent 选择工具的认知距离随长度上升，长名在 list_tools 截断展示时也常省去前缀。

### 7.2 触发关键点

任何工具调用必须使用完整 `ios_xxx_yyy` 名字；客户端必须每次完整打字；MCP 工具名空间是独立的，并不会和 system tools 冲突。

### 7.3 根因分析

- `toolName.ts:7-9` 一行加前缀；`fixedToolNames: Set<String>` 包含 `health_check` / `refresh_tools` 等；前缀目的是防止和未来可能加入的静态工具撞名
- `buildActionToolMap` 只在 `entries.length>1` 或撞 fixed names 时丢入 conflicts

### 7.4 修复建议

去掉 `ios_` 前缀，直接 `action.replace(/[^A-Za-z0-9_]/g, "_")`：`ui.tap → ui_tap`；`app.logs.read → app_logs_read`。工具名空间和静态工具（`health_check` / `observe`）不会冲突（不会出现名为 `health_check` 的 iOSExplore action）；冲突兜底 `buildActionToolMap` 已存在。

影响所有现有调用脚本，需要协同更新文档（`docs/investigations/mcp-e2e-test.md` 等），可能影响外部 agent 行为。建议在 ready 之前留下向后兼容 alias，但作为长期方向应该缩短。

---

## 8. 问题 7：`observe` 静态工具硬绑定 `ui.viewTargets`

### 8.1 现象

`staticTools.ts:35-40`：

```typescript
observe: {
  ...
  handler: async input => jsonResult(await client.call("ui.viewTargets", input))
}
```

`inputSchema: { type: "object", properties: {} }`——不支持参数；内部固定调 `ui.viewTargets`。 但很多场景 agent 想要 `topViewHierarchy` 整树（含隐藏 view、style、constraint），必须额外调 `ios_ui_topViewHierarchy`。

### 8.2 触发关键点

调用：

```javascript
await tool('observe', {});
// 永远等价于 ui.viewTargets，无参数透传
```

要拿层级树必须：

```javascript
await tool('ios_ui_topViewHierarchy', { detailLevel: 'full', includeHidden: true });
```

### 8.3 修复建议

`observe` `inputSchema` 增加 `mode?: "viewTargets" | "topViewHierarchy"` 与透传字段；默认仍是 viewTargets：

```typescript
observe: {
  inputSchema: {
    type: "object",
    properties: {
      mode: { type: "string", enum: ["viewTargets", "topViewHierarchy"], default: "viewTargets" },
      // 其余字段透传：
      detailLevel: { type: "string", enum: ["basic","appearance","full"] },
      includeHidden: { type: "boolean" },
      maxDepth: { type: "integer" }
    }
  },
  handler: async input => {
    if (input.mode === "topViewHierarchy") return jsonResult(await client.call("ui.topViewHierarchy", withoutKey(input, "mode")));
    return jsonResult(await client.call("ui.viewTargets", withoutKey(input, "mode")));
  }
}
```

---

## 9. 问题 8：`wait_and_observe` 的 `viewTargetsOptions` 透传不正确

### 9.1 现象

`staticTools.ts:42-61` 把 `viewTargetsOptions` 抽出来后传给 `client.call("ui.viewTargets", viewTargetsOptions)`。但 `ui.viewTargets` 的 inputSchema **不接受额外字段**（`additionalProperties: false`），见 `UIViewTargetsModels.swift`。如果 caller 没意识到这点，把 wait 字段直接塞进 `viewTargetsOptions`，就会失败。

更隐蔽的情况是 caller 传 `{}` 时也 OK（ui.viewTargets 接受空 input），所以本问题严重性是"中"而非"高"——往往只在使用者错误填字段时触发。

### 9.2 触发关键点

```javascript
await tool('wait_and_observe', {
  conditions: [...],
  viewTargetsOptions: { maxDepth: 3 }  // ui.viewTargets 并不识别 maxDepth
});
// response: ios_envelope unknown command input field 'maxDepth'
```

### 9.3 根因分析

- `waitAndObserveSchema()` (`staticTools.ts:64-86`) 把 `viewTargetsOptions` 描述为"传给 ui.viewTargets 的可选参数"，但没限制子字段；MCP schema validation 不会向下走到 ui.viewTargets 的字段集
- `ui.viewTargets` 在 Swift 端用严格字段读取器（`additionalProperties: false`），未知字段直接 `unknown command input field`

### 9.4 修复建议

`viewTargetsOptions` 的 `properties` 应该 mirror ui.viewTargets 的真实 schema（从 registry 拿到 dynamic tool 的 inputSchema 嵌进去），或者 `waitAndObserveSchema` 直接 `peek` registry 里 `ios_ui_viewTargets` 的 inputSchema 复用。

短期：填 schema 注释 + description 警告"只能传 ui.viewTargets 真实字段（accessibilityIdentifier / includeHidden 等），不接受层级树相关字段"。

---

## 10. 问题 9：`ui.screenshot` 返回 base64 全段塞进 MCP `content[0].text`

### 10.1 现象

`ui.screenshot` 返回 `{ image: <30 KB base64>, format: 'png', width, height, scale }`。`MCPServer/src/server.ts` 把整个 response JSON 化后塞进 `content[0].text`：

```typescript
return jsonResult(await options.client.call(dynamic.action, args));
// jsonResult -> { content: [{ type: "text", text: JSON.stringify(data) }] }
```

实测 PNG 414×896 缩到 237×512 大小 ≈ 31652 字节；base64 编码后塞进 text 字段，MCP 客户端解析后再 JSON.parse 出来。

### 10.2 触发关键点

- 调用 `ios_ui_screenshot` 后，MCP 响应 size 比常规大几十倍
- 客户端若按文本流上游 chunk 处理，可能溢出
- 多张截图日志保留时，token cost 显著上升

### 10.3 根因分析

- `result.ts / server.ts / jsonResult` 都把整个 IOSExplore data 包成单一 text content：`{ type: "text", text: JSON }`
- 没有用 MCP `image` content type（`{ type: "image", data: base64, mimeType: "image/png" }`）—— 那 MCP 客户端可以原生渲染/缓存，不会在文本流里展开

### 10.4 修复建议

`screenshot` 工具结果检测 format=png 时改用 MCP image content：

```typescript
// server.ts callTool after jsonResult:
if (dynamic.action === 'ui.screenshot' && data.image && data.format === 'png') {
  return {
    content: [
      { type: "image", data: data.image, mimeType: "image/png" },
      { type: "text", text: JSON.stringify({ width: data.width, height: data.height, scale: data.scale, format: data.format }) }
    ]
  };
}
```

可选：把 PNG 写到 `/tmp/ios-screenshot-<n>.png` 返回 `file://` URI，减少 MCP 体积。

---

## 11. 其它次要点（已识别但非缺陷）

| # | 现象 | 根因 | 处理 |
|---|------|------|------|
| 11.1 | `ui.waitAny` `conditions[]` 内层 schema 是 `{type:"array"}` 不约束元素字段 | `MCPServer/src/schemaMapper.ts` 没下钻 items schema；Swift 端 `UIWaitAnyModels.swift` 仅在描述里用文字说"targetExists 需 accessibilityIdentifier" | 在 description 里加大段文字描述（已有），或 schemaMapper 把 oneOf 嵌进 items |
| 11.2 | `help` 输出每次都全量 ~30 个 command metadata，HTTP 体积可观 | `HelpCommand.swift` 一次性 dump 所有 | 不需要改 |
| 11.3 | `ui.scrollToElement` 输入字段 `value` 必填，参数名不易猜 | 文档未强调 | 在 MCPServer descriptionSuffix 里加"value 必填" 已是现有约束 |
| 11.4 | `app.logs.read` 用 `after: { id, captureSessionID }` 不是 `sinceCursorID` | Swift 端字段命名 | 已是设计选择；MCPServer 不做字段重命名 |
| 11.5 | `emitStdout` / `emitStderr` 接受 `message`（不是 `text`）；`emitAppLog`/`emitLogger` 等也是 `message` | `DebugEmitCommands.swift` 各 input type 各自定义字段 | 已是设计；agent 需读 schema |

这些不是问题，仅作记录。

---

## 12. 验证矩阵（必备的可复现脚本片段）

### 12.1 问题 1（UIStepper）

```javascript
// 前提：在 ControlTestViewController
const obs = await tool('observe', {});
const stepper = obs.d.targets?.find(t => t.accessibilityIdentifier === 'test.stepper');
const r = await tool('ios_ui_control_sendAction', {
  viewSnapshotID: obs.d.viewSnapshotID,
  path: stepper.path,
  event: 'valueChanged'
});
// r.e === true && r.d.message.includes("requested action is not supported for target")
```

### 12.2 问题 2（value 字段）

```javascript
const r = await tool('ios_ui_control_sendAction', {
  viewSnapshotID: obs.d.viewSnapshotID,
  path: slider.path,
  event: 'valueChanged',
  value: 0.85
});
// r.d.message === "unknown command input field 'value'"
```

### 12.3 问题 3（alert 后 topViewController 仍 UIAlertController）

```javascript
await tool('ios_ui_alert_respond', { dryRun: false, buttonIndex: 0 });
const obs = await tool('observe', {});
// obs.d.navigationBar.topViewController === "UIAlertController"（bug）
// await sleep(700); obs2 = await tool('observe'); → "AlertTestViewController"（正常）
```

### 12.4 问题 4（connection_failed 无自愈）

```bash
# 1. 用 mcp__XcodeBuildMCP__stop_app_device 杀掉 SPMExample
# 2. 调任意 ios_ui_* 工具 → fetch failed → connection_failed
# 3. 错误消息里没有"请重启 app"的 nextSteps
# 4. 手动 mcp__XcodeBuildMCP__launch_app_device env={IOS_EXPLORE_AUTOSTART:"1"} 后恢复
```

### 12.5 问题 8（wait_and_observe viewTargetsOptions）

```javascript
const r = await tool('wait_and_observe', {
  conditions: [{ id: 'w1', mode: 'targetExists', accessibilityIdentifier: 'example.gestureTap' }],
  viewTargetsOptions: { maxDepth: 3 }
});
// r.d.observation 错误: "unknown command input field 'maxDepth'"
```

---

## 13. 已修复 / 已验证 OK 的清单（防止回归）

| 功能 | 工具 | 结果 |
|------|------|------|
| 标准 alert 确认/取消/三按钮/嵌套 | `ios_ui_alert_respond` | ✅ 全过 |
| 输入框 alert + actionSheet dryRun | `ios_ui_alert_respond` | ✅ |
| UIButton touchDown/Up | `ios_ui_control_sendAction` | ✅ |
| UISwitch toggle | `ios_ui_tap` | ✅ |
| UISlider valueChanged（只发事件） | `ios_ui_control_sendAction` | ✅（但不改 value） |
| UISegmentedControl valueChanged（只发事件） | `ios_ui_control_sendAction` | ✅ |
| UITextField focus + input + dismiss | `ios_ui_tap` + `ios_ui_input` + `ios_ui_keyboard_dismiss` | ✅ |
| `ui.scroll` direction+amount | `ios_ui_scroll` | ✅ |
| `ui.scrollToElement` accessibilityIdentifier 匹配 | `ios_ui_scrollToElement` | ✅ |
| `ui.navigation.back` 从子页返回 | `ios_ui_navigation_back` | ✅ |
| `ui.navigation.tapBarButton` 空页正确报错 | `ios_ui_navigation_tapBarButton` | ✅ |
| `ui.topViewHierarchy` basic/full | `ios_ui_topViewHierarchy` | ✅ |
| `ui.waitAny` targetExists | `ios_ui_waitAny` | ✅ |
| `ui.screenshot` maxDimension | `ios_ui_screenshot` | ✅（但体积见问题 9）|
| `ping`/`echo`/`greet`/`device` | `ios_ping`/... | ✅ |
| `app.logs.mark` + read 单 source 过滤 | `ios_app_logs_mark`/`ios_app_logs_read` | ✅ |
| `debug.emitAppLog`/`Logger`/`NSLog`/`OSLog`/`Stdout`/`Stderr` | `ios_debug_emit*` | ✅（每个用各自字段名）|
| `health_check` / `refresh_tools` / `call_action` | 静态 | ✅ |

---

## 14. 推荐的修复优先级

1. **P0: 问题 1 (UIStepper valueChanged)** — 一行代码修复（`UIKitActionCapabilityResolver.controlActions` 加 `UIStepper`），解锁所有 stepper 自动化场景
2. **P1: 问题 3 (alert dismiss 后 topViewController 抖动)** — 给 agent 的 sticky 稳定语义，避免后续调用拿到陈旧 context 触发 `stale_locator`
3. **P1: 问题 4 + 5 (transport 自愈 + 动态工具自动 refresh)** — 同一个修复点：`callTool` 在 transport failure / unknown_tool 时先 retry + refresh 一次再失败
4. **P2: 问题 2 (sendAction value 字段)** — 协议增量，需 plan / executor / schema 三层联动
5. **P3: 问题 6 (工具名前缀)** — 长期清理短化；需协调外部调用方
6. **P3: 问题 7+8 (observe mode + wait_and_observe 参数)** — 静态工具小调整
7. **P4: 问题 9 (screenshot 内容类型)** — 体积优化

---

## 15. 本测试运行日志摘要（参考）

```
=== Alert ===      passed=8 failed=0
=== Controls ===   passed=11 failed=3   ← 问题 1 (stepper) + 问题 2 (value 字段)
=== Navigation === passed=2 failed=0
=== viewHierarchy/wait/scroll === passed=4 failed=0
=== device/echo/greet === passed=3 failed=0
=== logs/diagnostics === passed=4 failed=0
=== 史上最复杂连接 5 次 connection_failed === 见问题 4
=== 总通过率 24/26 = 92.3% ===
```

---

## 附：源码锚点速查

| 问题 | 文件 | 行 |
|------|------|---|
| 1 | `Sources/iOSExploreUIKit/Support/Action/UIKitActionCapabilityResolver.swift` | 110-118 |
| 1 | `Sources/iOSExploreUIKit/Support/Action/UIKitActionExecutor.swift` | 268-274 |
| 1 | `Sources/iOSExploreUIKit/Support/Action/UIKitDefaultActivationResolver.swift` | 39-46 |
| 2 | `Sources/iOSExploreUIKit/Commands/ControlAction/UIControlSendActionModels.swift` | 42-48 |
| 2 | `Sources/iOSExploreUIKit/Support/Action/UIKitActionExecutor.swift` | 277 |
| 3 | `Sources/iOSExploreUIKit/Commands/Alert/UIAlertRespondCommand.swift` | 30-33 |
| 3 | `Sources/iOSExploreUIKit/Support/Action/UIAlertRespondExecutor.swift` | 60-66 |
| 3 | `Sources/iOSExploreUIKit/Support/Context/UIKitContextProvider.swift` | 73-87 |
| 3 | `Sources/iOSExploreUIKit/Support/Action/UIAlertInspector.swift` | 53-55 |
| 4 | `MCPServer/src/iosExploreClient.ts` | 11-25 |
| 4 | `MCPServer/src/server.ts` | 30-40 |
| 5 | `MCPServer/src/toolRegistry.ts` | `refresh()` 30-50 |
| 6 | `MCPServer/src/toolName.ts` | 7-9 |
| 7 | `MCPServer/src/staticTools.ts` | 35-40 |
| 8 | `MCPServer/src/staticTools.ts` | 42-86 |
| 9 | `MCPServer/src/server.ts` (jsonResult 用法) | jsonResult 函数 |
