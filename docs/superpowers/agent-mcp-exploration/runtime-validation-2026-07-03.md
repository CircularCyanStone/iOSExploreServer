# Agent MCP 运行验证记录（2026-07-03）

> 日期：2026-07-03
> 关联：[README.md](./README.md) / [2026-07-02 历史基线](./runtime-validation-2026-07-02.md) / [curl 闭环协议](./curl-json-loop-protocol.md)
>
> 目的：navigationBar 可达性、`ui.tap` 结构化默认激活、`ui.waitAny`、`ui.alert.respond` query-only 边界全部落地后，用 SPMExample 在模拟器上真跑一遍 `observe → act → wait → re-observe` 完整闭环，核对协议 / 源码 / help schema / 测试是否一致。结论以真实 curl 输出为准，不只看代码。
>
> 与 [2026-07-02 基线](./runtime-validation-2026-07-02.md) 的关键区别：那一轮 navigationBar 不可达，无法进入 `ControlTestViewController`，`ui.tap` / `ui.input` 等只能在主页有限验证；本轮 `ui.navigation.tapBarButton` 已通，整条闭环在子页跑通，并暴露出两个只有真机跑才会发现的 bug（均已修）。

## 1. 环境

- iPhone 17 模拟器（iOS 26.x，Booted，UDID `065CC8DB-…`）
- SPMExample（`com.coo.SPMExample`），本地 SPM 依赖 core + `iOSExploreUIKit`
- **server 启动方式**：`ViewController` 默认不 `server.start()`（绑在「启动 Server」按钮）。本轮给 `viewDidLoad` 末尾加了 `AUTO_START_SERVER=1` 环境变量门控的临时自动启动钩子（env 门控，默认行为不变），用 `launch_app_sim(env)` 带该 env 启动。**验证完已 `git checkout` 恢复，grep 确认无 `RUNTIME-VALIDATION-TEMP` 残留。**
- Mac 直连模拟器：`curl http://127.0.0.1:38321/`（模拟器与 Mac 共享网络栈，无需 iproxy）。
- 构建工具：XcodeBuildMCP（`build_run_sim` / `launch_app_sim` / `snapshot_ui` / `screenshot`）。本会话只启用了 simulator workflow + `snapshot_ui`/`screenshot`，**未启用 `tap`/`gesture` 等 UI automation 工具**——所以「启动 Server」按钮无法用工具点击，才走 env 钩子自启。

## 2. help schema 核对

`curl help`：

- **total actions = 20**（core 4：ping/echo/info/help + **14 个 `ui.*`** + SPMExample 自注册 greet/device）。`ui.*` 数量与 `registerUIKitCommands` 注册的 14 个一致。
- `ui.screenshot` 的 description = `截屏 (PNG base64) + 降采样（可选视觉证据，不签发 viewSnapshotID）`——本轮已修正过时的「+ 签发 snapshot」措辞，help schema 与 `UIScreenshotCollector`（不签发 viewSnapshotID）实际行为一致。

## 3. 完整闭环真实输出（主页 → ControlTest 子页）

| 步骤 | 命令 | 真实结果 | 判定 |
|---|---|---|---|
| observe | `ui.viewTargets` | `viewSnapshotID=snap-1`；`navigationBar.rightItems[0]` = `example.controlTest`（placement=right, index=0, title=控件测试, isEnabled=true） | ✅ viewTargets 签发 snapshot + 暴露 navigationBar |
| act(导航) | `ui.navigation.tapBarButton` right/0 | `performed:true`，`topBefore:ViewController → topAfter:ControlTestViewController` | ✅ 真实 push 进子页 |
| observe(子页) | `ui.viewTargets` | `test.button/switch/textfield` 有 `tap`；`test.slider/segmented` **只有 `control.valueChanged` 无 `tap`** | ✅ availableActions 与默认激活路由设计一致 |
| act(tap button) | `ui.tap test.button` + fresh snap | `activated:true, activationRoute:control.touchUpInside, event:touchUpInside` | ✅ |
| act(tap switch) | `ui.tap test.switch` + fresh snap | `activated:true, activationRoute:switch.toggle`（修复前 `currentValue` 异常，见 §4.2） | ✅（修复后） |
| act(精确事件) | `ui.control.sendAction test.button event=touchUpInside` | `sent:true, event:touchUpInside, isEnabled:true` | ✅ |
| wait(多分支) | `ui.waitAny` 等 test.button 出现 | `satisfied:true, matchedID:btn, matchedIndex:0, matchedMode:targetExists, attempts:1, elapsedMs:0` | ✅ 字段与协议完全一致 |
| wait(快照变化) | `ui.wait snapshotChanged` + viewSnapshotID | 接受 viewSnapshotID，无变化时正确返回 `wait_timeout` | ✅ |
| 弹窗查询 | `ui.alert.respond dryRun=true` | `alert_unavailable`（当前无 UIAlertController） | ✅ query-only |
| 截图 | `ui.screenshot` | 响应 keys = `[format,height,image,pixelScale,scale,width]`，**无 viewSnapshotID** | ✅ 不签发 |
| freshness | 用上一轮旧 snap 调 tap | `stale_locator`（固定提示 call ui.viewTargets first） | ✅ 过期 snapshot 被正确拒绝 |

## 4. 发现并修复的问题

### 4.1 curl 协议 `ui.navigation.tapBarButton` 示例多了 `dryRun`（文档 bug）

**现象**：按 [curl-json-loop-protocol.md](./curl-json-loop-protocol.md) 原示例发：

```bash
curl ... -d '{"action":"ui.navigation.tapBarButton","data":{"placement":"right","index":0,"title":"控件测试","dryRun":false,"waitAfterMs":400}}'
→ {"code":"invalid_data","message":"unknown command input field 'dryRun'"}
```

页面没跳转（仍 ViewController）。

**根因**：`UINavigationBarButtonInput`（`Sources/iOSExploreUIKit/Commands/Navigation/UINavigationBarButtonModels.swift`）的 schema 只有 `placement / index / title / accessibilityIdentifier / waitAfterMs`，**不接受 `dryRun`**。curl 协议文档的示例错误地带了 `dryRun`（疑似从 `ui.alert.respond` 示例串味）。

**修复**：删除 `curl-json-loop-protocol.md` 该示例里的 `,"dryRun":false`。grep 确认全仓仅此一处。

### 4.2 ControlTest `switchChanged()` 自翻转（SPMExample demo bug，非库 bug）

**现象**：`ui.tap test.switch`（初始 off）返回：

```json
{"activated":true,"activationRoute":"switch.toggle","previousValue":false,"currentValue":false}
```

`currentValue` 等于 `previousValue`，看似 toggle 没生效。

**根因（执行链）**：库 executor（`UIKitActionExecutor.executeTap` switch 分支）逻辑正确：

1. `previous = switch.isOn` → `false`
2. `switch.setOn(!previous)` = `setOn(true)` → 开关变 on（`setOn` 本身不触发 handler）
3. `switch.sendActions(.valueChanged)` → **同步**调用 App 的 `switchChanged()`
4. App handler 读 `on = switch.isOn` = `true`（库刚设的），又 `switch.setOn(!on)` = `setOn(false)` → **把开关翻回了 off**
5. executor 读 `currentValue = switch.isOn` = `false`（被 handler 翻回）

即：库正确 toggle 到 true 并触发了 valueChanged，但 SPMExample 的 `ControlTestViewController.switchChanged()` 多了一行 `toggleSwitch.setOn(!on, animated: true)`，把库设的值又翻回去。同页 `slider/segmented/stepper` 的 handler 都只「读值更新显示」，唯独 switch 多了自翻转——与库的 `switch.toggle` 叠加就是「翻过去又翻回来」。

**库无错的佐证**：`Tests/iOSExploreServerTests/UIKitActionExecutorTests.swift:52` 的 `tapSwitchTogglesAndSendsValueChanged` 用裸 `UISwitch`（无 handler）锁定：`isOn=false` → tap 后 `previousValue==false / currentValue==true`。库的语义被测试锁定，这次异常纯属 demo handler 副作用。

**修复**：去掉 `ControlTestViewController.switchChanged()` 里多余的 `setOn(!on)`，对齐其他 handler（只读值更新显示，不改开关本身）。

**修复后复验**（连续 tap 两次）：

```
第 1 次 tap: previousValue:false → currentValue:true   ✅ off→on
第 2 次 tap: previousValue:true  → currentValue:false  ✅ on→off（来回切正常）
```

## 5. 边界发现

- **freshness 很敏感**：用上一次 `ui.viewTargets` 签发的 viewSnapshotID，经过几轮工具往返后再 tap，会判 `stale_locator`。这是协议在工作（页面已变 → 拒绝旧 snapshot），但也说明 Agent 必须「viewTargets 后立即动作」，不能跨多轮复用旧 snap。正确用法是在同一调用序列里 `viewTargets → 立即 tap`。
- **`ui.wait snapshotChanged` 检测变化依赖 snapshot 未被淘汰**：用一个几轮前签发、之后又经历了多次 viewTargets 的 snap 做参照，可能因 store LRU/陈旧而无法比对，轮询到 `wait_timeout`。要验证「检测到变化」应就近先 viewTargets 拿 fresh snap，再触发变化，再用该 snap 等。

## 6. 与 2026-07-02 历史基线对比

| 维度 | 2026-07-02 基线 | 2026-07-03 本轮 |
|---|---|---|
| navigationBar | 不可达（采不到 + tap 拒绝） | `ui.navigation.tapBarButton` 真实跳转进子页 ✅ |
| `ui.tap` | 坐标/hit-test 语义，对 UIBarButtonItem 失败 | 结构化默认激活，button→touchUpInside / switch→toggle / input→focus ✅ |
| 进入 ControlTest 页 | **被阻断**（无法验证子页控件） | 完整跑通 6 类控件 ✅ |
| 多结果等待 | 只有单条件 `ui.wait` | `ui.waitAny` 命中返回 matchedID 等 ✅ |
| 弹窗 | query-only（同本轮） | query-only 边界保持，文档明确 ✅ |
| 测试基线 | SPM 185 / framework 258 | **SPM 210 / framework 310** |
| 暴露的 bug | navigationBar 不可达（已修） | curl 协议 dryRun + ControlTest switch 自翻转（均已修） |

## 7. 结论

- 14 个 `ui.*` 命令在真实 App 上闭环可用：`observe(viewTargets) → act(navigation.tapBarButton / tap / control.sendAction) → wait(waitAny / snapshotChanged) → re-observe → verify` 全程通畅。
- help schema、协议文档、源码、测试四者在本轮验证后一致：screenshot 不签发 viewSnapshotID、navigation.tapBarButton 字段、switch.toggle 语义均有源码 + 测试 + 真机输出三方佐证。
- 本轮修了 2 个只有真机跑才会暴露的问题（curl 协议 `dryRun` 字段、ControlTest switch 自翻转），均非库核心逻辑 bug。
- 剩余：动作后 final observation 仍由 Agent 显式 `viewTargets` 完成（`ui.waitAny` 不自动返回页面，归属评估见 [../specs/2026-07-03-final-observation-after-action.md](../specs/2026-07-03-final-observation-after-action.md) 方案 B）。
