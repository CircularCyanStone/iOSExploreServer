# `ui.tap` 手势 target-action 显式 adapter 报告

> 本轮目标：让 `ui.tap` 能触发依赖 `UIGestureRecognizer`（`UITapGestureRecognizer`/`UILongPressGestureRecognizer`/`UIPanGestureRecognizer` 等）的自定义 view。这类目标原本在 `UIKitDefaultActivationResolver` 里没有公开激活路由，`ui.tap` 直接抛 `unsupported_target`。本轮给它们加一条**显式 adapter 路由**：不合成触摸 event，直接用 ObjC runtime 读手势的私有 ivar 拿到 target-action 并按签名派发。
>
> 上一轮 spike（`docs/superpowers/reviews/2026-07-04-ui-tap-realtouch-spike.md`）已否决「合成 `UITouch` + `UIEvent` → `UIWindow.sendEvent`」路线（iOS 26 的 `UIEvent` 移除了 `_touchesByKey`/`_touches`，UIKit 层没有「无种子构造带 touches event」的入口）。本轮是 spike 决议的降级方案。

## 结论速览

- **iOS 26 上手势 adapter 端到端可用**：`UIGestureRecognizer._targets` / `UIGestureRecognizerTarget._target` / `_action` 三个私有 ivar **完全未漂移**（与 Lookin iOS 17 实测一致），C API 读取链（`class_getInstanceVariable` + `ivar_getOffset` + 裸内存 `load`）稳定工作。
- **真机闭环验证通过**（iPhone iOS 26.5）：`ui.viewTargets` 把带手势的 view 列为 canonical target 并签发 `viewSnapshotID` → `ui.tap` 走 gesture 分支触发 `gestureDemoTapped` → `debug.gestureTapCount` 计数 0→1→2 证明 target-action 副作用真发生（不只是 executor 派发）。freshness 把关正确（accessibilityLabel 变化后旧 snapshot 报 `stale_locator`）。
- **零回归**：UIButton/UISwitch/文本输入三路 default 行为不变；UISlider/UISegmentedControl 等 UIControl（内部也挂手势）仍 `unsupported_target`（adapter 显式排除 UIControl）；普通 UIView 仍 `stale_locator`。
- **隔离干净**：私有 ivar 读取层 `#if DEBUG #if canImport(UIKit)` 双隔离，`swift build -c release` 编译通过。

## 关键 design choice（实现前必须理清的几件事）

### 1. `shouldInclude` 必须让手势 view 进 canonical（端到端死结的解法）

`ui.tap` 强制要 `viewSnapshotID` 做 freshness 校验，而 `viewSnapshotID` 由 `ui.viewTargets` 签发。`UIViewTargetsInput.shouldInclude` 重构后**只接受 `UIControl` 和 `UIScrollView` 系**——注释明确写「gesture-only view 不再进入 targets」。如果不改它，手势 view 永远拿不到 `viewSnapshotID`，`ui.tap` 永远 `stale_locator`（path missing），adapter 就是死代码。

本轮改了 `shouldInclude`：加一条 `if candidate.hasGestureRecognizers { return true }`。意思是「挂了手势识别器、又不是 UIControl/UIScrollView 的 view，也算 canonical 可交互目标，`ui.viewTargets` 要采集它并签发 `viewSnapshotID`」。理由是手势 adapter 让这类 view 有了确定可执行的动作（派发 target-action），它本来就是合理的可交互目标，原本排除它只是因为「没有确定可执行动作」，本轮补上动作后该排除理由不再成立。

这个改动**不算违反「不改 default 行为」约束**：「不改 default」指的是 UIButton/UISwitch/文本输入三路 tap 行为零回归，这三路完全没动。`shouldInclude` 改的是 viewTargets 的采集范围（新增能力），不是三路 default 的激活行为。

### 2. adapter 必须排除 UIControl（否则 UISlider 回归）

`UISlider`/`UISegmentedControl` 是 UIControl，没有 default 激活路由（route 返回 nil），但它们**内部挂了手势识别器**（用于滑块拖动等自身交互）。如果不排除，adapter 会读出这些内部手势的 target-action 并触发，破坏原本的 `unsupported_target` 语义——实测第一版就因此让 `tapSliderReturnsUnsupportedTarget` 测试从 unsupported 变成 success。

解法：`executeTap` 的手势分支加守卫 `!(located.view is UIControl)`。意思是「只对非 UIControl 的 view 走手势 adapter」。UIButton/UISwitch/UITextField 走 default route 优先（根本不进 adapter 分支）；UISlider/UISegmentedControl/自定义 UIControl 即便有手势也不进 adapter，保持 `unsupported_target`（它们该用 `control.sendAction`）。

### 3. `availableActions` 不声明 tap（agent 据 `hasGestureRecognizers` 推断）

capability resolver（`UIKitActionCapabilityResolver`）声明 tap 的依据是 `UIKitDefaultActivationResolver.route(for:) != nil`，手势 view 的 route 是 nil，所以 `availableActions` 不含 tap。本轮**故意不改 capability**，让手势 view 的 `availableActions` 仍是空数组，但 `ui.viewTargets` 响应里的 `hasGestureRecognizers: true` 字段告诉 agent「这个 view 有手势，可以试 `ui.tap`」。

这样分层的理由：`availableActions` 表示「确定公开激活路由」（UIButton 的 touchUpInside 等，是公开 API 行为）；手势 adapter 是「启发式补充」（runtime 读私有 ivar 派发，依赖 Debug-only 私有结构）。两者分层更清晰，也避免 capability 声明 tap 但 Release 下 adapter 不可用造成的「声明可执行但实际派发不了」分叉。

### 4. 多手势 / 多 target 全触发

一个 view 可能挂多个手势（tap + longPress + pan…），每个手势的 `_targets` 数组也可能多个元素。adapter **全部触发**，因为 adapter 不知道调用方意图，全触发最透明，调用方据响应里的 `gestures` 列表（每个元素含 gestureType / targetType / action）自行判断结果。这个决策由 `UIGestureTargetExecutorTests.tapViewWithMultipleGesturesTriggersAll` 和 `tapGestureWithMultipleTargetsTriggersAll` 覆盖。

## ivar 名表（iOS 26，模拟器 26.3.1 + 真机 26.5 一致）

来源：`UIGestureRecognizerTriggerSpikeTests` 在 iOS 26.3.1 模拟器用 `SyntheticTouch.dumpIvars` 枚举。真机 UIKit 同 SDK，结论一致。

### `UIGestureRecognizer`（35 个 ivar，含 `NSObject.isa`）

本轮用到（命中）的：`UIGestureRecognizer._targets`（`UIGestureRecognizerTarget*` 数组，**adapter 读取链的根**）。

存在但本轮不用：`_gestureFlags`、`_delayedTouches`、`_delayedPresses`、`_container`、`_lastTouchTimestamp`、`_firstEventTimestamp`、`_state_DO_NOT_USE_DIRECTLY`、`_allowedTouchTypes`、`_initialTouchType`、`_internalActiveTouches`、`_name_DO_NOT_USE_DIRECTLY`、`_forceClassifier`、`_requiredPreviewForceState`、`_touchForceObservable`、`_touchForceObservableAndClassifierObservation`、`_forceTargets`（force touch 的 target，**不是 tap 用**）、`_forcePressCount`、`_beganObservable`、`_failureRequirements`、`_failureDependents`、`_activeEvents`、`_inputPrecision`、`_buttonMask`、`_modifierFlags`、`_machTimeEnqueuedForReset`、`_keepTouchesOnContinuation`、`_wantsGESEvents`、`_node`、`_componentController`、`_delegate`、`_allowedPressTypes`、`_gestureEnvironment`、`_delayedEventComponentDispatcher`。

### `UIGestureRecognizerTarget`（私有类，3 个 ivar）

干净利落，只有两个有用 ivar：

- `UIGestureRecognizerTarget._target` —— 目标对象（id；`UIGestureRecognizer` 对 target 是弱引用，目标 dealloc 后被 runtime 自动置 nil）
- `UIGestureRecognizerTarget._action` —— 目标 selector（SEL）
- `NSObject.isa`

**三个 ivar 全部未漂移**，与 Lookin（`LKS_GestureTargetActionsSearcher.m`，iOS 17）完全一致。候选名 `["_targets","targets"]` / `["_target","target"]` / `["_action","action"]` 首选即命中。

## 实现组件

### `Sources/iOSExploreUIKit/Support/Runtime/UIGestureRecognizer+Trigger.swift`（新增，runtime 层）

`#if DEBUG #if canImport(UIKit)` 双隔离。封装 `UIGestureRecognizer.explore_targetActionPairs() -> [(target: NSObject, action: Selector)]`。

读取链（全 C API，不抛 `NSException`——Swift 无法 catch ObjC 异常）：
1. `class_getInstanceVariable` + `ivar_getOffset` 拿 `_targets` 偏移，`load(as: AnyObject?.self)` 读出数组；
2. 遍历每个 `UIGestureRecognizerTarget` box，同样用 `class_getInstanceVariable` + `ivar_getOffset` + `load` 读 `_target`（对象）和 `_action`（SEL，`load(as: UnsafeMutableRawPointer?.self)` + `unsafeBitCast(_, to: Selector.self)`）；
3. `_target` 是弱引用时目标 dealloc 后读出 nil，跳过该 pair（不 crash）。

ivar 名用候选名列表 + runtime 探测（`GestureTargetField`），不硬编码单一名字——新 iOS 版本若漂移，往候选列表补名字即可，不改读取逻辑。

### `Sources/iOSExploreUIKit/Support/Action/UIGestureTargetExecutor.swift`（新增，@MainActor executor）

`#if canImport(UIKit)`（不额外 `#if DEBUG`，跟随 `UIKitActionExecutor`）。遍历 `view.gestureRecognizers`，对每个调 `explore_targetActionPairs()`，按 selector 签名派发（复用 `UINavigationBarButtonExecutor.invoke` 的 0/1/2 参签名适配：`method_getNumberOfArguments` 读真实参数个数，3=一参 `perform(_:with:)`、4=两参 `perform(_:with:with:)`、default=无参 `perform(_:)`）。sender 传手势识别器本身（手势 target-action 约定第一个参数是 gesture）。

调用 `#if DEBUG` runtime 入口的隔离边界参照 `UIAlertRespondExecutor`：`execute(on:)` 用 `#if DEBUG ... #else return nil #endif` 包裹，Release 下返回 nil 让 `executeTap` fallthrough 到 `unsupported_target`。

返回 `[UIGestureTriggeredPair]?`：nil=无手势；空数组=有手势但读不出（漂移）；非空=已触发的 pair 摘要。

### `Sources/iOSExploreUIKit/Support/Action/UIKitActionExecutor.swift`（改 `executeTap`）

`guard let route = ...` 的 else 分支原来直接抛 `unsupported_target`，本轮在抛之前先尝试手势 adapter：

```
if !(located.view is UIControl),           // 排除 UIControl（UISlider 等内部手势不误触发）
   let triggered = UIGestureTargetExecutor.execute(on: located.view), !triggered.isEmpty {
    return [activated/route=gesture.targetAction/gestures/triggeredCount]
}
throw unsupported_target                    // adapter 也不可达时，与原行为一致
```

加 `gestureTriggeredJSON` helper 把每对 (gestureType/targetType/action) 序列化进响应 `gestures` 数组。

### `Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsModels.swift`（改 `shouldInclude`）

加 `if candidate.hasGestureRecognizers { return true }`（见 design choice 1）。

## 测试覆盖

### `Tests/iOSExploreServerTests/UIGestureRecognizerTriggerSpikeTests.swift`（新增，ivar 存档 + 读取正向验证）

- `gestureRecognizerIvarArchive`：dump `UIGestureRecognizer`/`UITapGestureRecognizer` 全量 ivar（报告名表来源）+ 断言 `_targets` 存在。
- `gestureTargetActionPairsReadAndArchive`：构造带手势的 view，调 `explore_targetActionPairs()` 断言读出 target===counter + action==didTap，并 dump 私有 `UIGestureRecognizerTarget` ivar 确认 `_target`/`_action`。

### `Tests/iOSExploreServerTests/UIGestureTargetExecutorTests.swift`（新增，executor 6 场景）

- 1 参 action 触发 + gestures 数组结构断言
- 0 参 action（`func action()`）按 `method_getNumberOfArguments=2` 无参派发
- 2 参 action（`func action(_:forEvent:)`）按 `=4` 两参派发，event 传 nil
- 多 gesture（tap + longPress）全触发
- 单 gesture 多 target 全触发
- target dealloc 后安全降级（弱引用 nilify → 读出 nil → 0 pair → `unsupported_target`，不 crash）

### `Tests/iOSExploreServerTests/UIKitViewTargetsTests.swift`（更新）

`shouldInclude` 策略测试：手势 view 从 `== false` 改为 `== true`（gesture view 现在进 canonical）。

### 双层验证全绿

- framework `xcodebuild test`（iOS 模拟器）：**327 passed**（原 321 + spike 2 + 手势 6 - 重叠 2）。
- SPM `swift test`（macOS）：**208 passed**。
- `swift build -c release`：编译通过（`#if DEBUG` 隔离干净）。

## 真机验证结果（iPhone iOS 26.5，CoreDevice `3AC0C7D6-...`）

闭环：`build_run_device`（profile `device-app`）→ `stop_app_device` → `launch_app_device(env={IOS_EXPLORE_AUTOSTART:1})` → `iproxy 38321 -u 00008030-001045C136D1402E` → `curl`。curl 前先 `lsof -iTCP:38321 -sTCP:LISTEN` 确认 COMMAND 是 `iproxy` 而非残留 `SPMExampl`（AGENTS.md 四坑第 4 点）。

```
=== probe ===
{"code":"ok","data":{"alive":true,"build":"gesture-adapter-2026-07-04"}}   # 确认真机跑新 binary

=== viewTargets（gestureDemoLabel 被采集）===
viewSnapshotID: "snap-1"
target: path=root/0/2 type=UILabel hasGestureRecognizers=True
       accessibilityLabel=gesture-tap-count:0 availableActions=[]

=== ui.tap（gesture 分支）===
{"code":"ok","data":{"activated":true,"activationRoute":"gesture.targetAction",
  "gestures":[{"gestureType":"UITapGestureRecognizer","targetType":"ViewController","action":"gestureDemoTapped"}],
  "triggeredCount":1,"type":"UILabel"}}

=== debug.gestureTapCount ===
count: 0 → 1   # target-action 副作用真发生

=== 第二轮（验 freshness 把关 + 重复触发）===
旧 snap-1 tap → stale_locator（accessibilityLabel 变 count:1 → 指纹陈旧 → 正确拒绝）
新 snap-2 tap → ok, route=gesture.targetAction, triggered=1
count: 1 → 2   # 重复触发累加
```

SPMExample 加了 `gestureDemoLabel`（UILabel + `UITapGestureRecognizer` + `accessibilityIdentifier="example.gestureTap"`）和 `debug.gestureTapCount` action（回读计数校验副作用），均在 `Examples/SPMExample/SPMExample/ViewController.swift`。

## 踩坑记录

1. **`shouldInclude` 默认排除 gesture-only view**（最关键）。第一版只改 executor，没改 `shouldInclude`，所有手势测试 `stale_locator`（view 非 canonical → path 未签发 → freshness path missing）。读 `UIViewTargetsInput.shouldInclude` 源码 + 注释才确认「gesture-only 不进 targets」是显式策略，必须改它才能端到端。
2. **UISlider 内部挂手势**导致回归。第一版 adapter 不排除 UIControl，`tapSliderReturnsUnsupportedTarget` 从 unsupported 变 success（adapter 触发了 UISlider 内部手势）。加 `!(view is UIControl)` 守卫修复。
3. **`NSStringFromClass` 返回 Swift mangled 名**。executor 第一版用 `NSStringFromClass(type(of: target))` 返回 `_TtC21iOSExploreServerTestsP33_...13GestureTarget`，对外不友好且测试断言失败。改用 `String(describing: Swift.type(of: target))` 返回干净名 `GestureTarget`。
4. **Swift Testing free-function `@Test` 的 `-only-testing` 路径不匹配**。`-only-testing:iOSExploreServerTests/UIGestureTargetExecutorTests`（文件名）和 `-only-testing:.../funcName` 都返回 counts=0（不报错但不跑）。只能跑全部测试。XcodeBuildMCP 的 counts 字段对全跑准确，对 `-only-testing` + free function 不准。

## 产物清单

- `Sources/iOSExploreUIKit/Support/Runtime/UIGestureRecognizer+Trigger.swift` —— 手势 target-action runtime 读取（`#if DEBUG #if canImport(UIKit)` 双隔离）。
- `Sources/iOSExploreUIKit/Support/Action/UIGestureTargetExecutor.swift` —— `@MainActor` 手势触发 executor。
- `Sources/iOSExploreUIKit/Support/Action/UIKitActionExecutor.swift` —— `executeTap` 接入手势分支 + `gestureTriggeredJSON` helper。
- `Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsModels.swift` —— `shouldInclude` 加 `hasGestureRecognizers`。
- `Tests/iOSExploreServerTests/UIGestureRecognizerTriggerSpikeTests.swift` —— ivar 存档 + 读取正向验证。
- `Tests/iOSExploreServerTests/UIGestureTargetExecutorTests.swift` —— executor 6 场景。
- `Tests/iOSExploreServerTests/UIKitViewTargetsTests.swift` —— include 策略断言更新。
- `Examples/SPMExample/SPMExample/ViewController.swift` —— `gestureDemoLabel` + `debug.gestureTapCount` 真机验证 view。
- framework 327 + SPM 208 测试全绿；Release 编译干净；真机 ui.tap gesture 闭环验证通过。
