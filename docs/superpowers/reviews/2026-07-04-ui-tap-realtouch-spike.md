# `ui.tap` realTouch 合成触摸 spike 报告

> spike 范围：验证「合成 `UITouch` + `UIEvent` → `UIWindow.sendEvent`」能否让 `ui.tap` 支持手势识别器 / 普通 view 点击 / hit-test 遮挡场景。**本轮只 spike，不改 `ui.tap` 主路径、不加 `dispatchMode` 参数。** spike 产物：`Sources/iOSExploreUIKit/Support/Runtime/UITouch+Synthetic.swift`（`#if DEBUG #if canImport(UIKit)` 双隔离）+ `Tests/iOSExploreServerTests/UITouchSyntheticSpikeTests.swift` + `Examples/SPMExample` 的 `SyntheticTapSpikeRunner`。

## 结论速览

- **iOS 26 上经典「合成 UITouch + 设 `_touchesByKey` + sendEvent」方案失败**，根因是 **UIEvent 架构变化**（不是 ivar 名漂移这种小事）：iOS 26 的 `UIEvent` 移除了 `_touchesByKey` / `_touches` ivar，touches 改由私有 `_eventEnvironment` / `_gsEvent` / `_hidEvent` 管理；`UITouch` 也移除了 `_view`，改用 `_responder` / `_cachedResponderView` / `_warpedIntoView`。
- **4 件事全部失败**：`UITapGestureRecognizer` 不触发、普通 `UIView` 的 `touchesBegan/Ended` 不调用、`UIButton.touchUpInside` 不触发、遮挡场景底层/遮挡层都不触发。但 **hit-test 几何完全正确**（透明遮挡时 `hitTest` 命中遮挡层），失败纯粹在 event 分发层。
- **尝试过的 UIKit 层替代入口 `_initWithEvent:touches:`（template 传 nil）调用成功但不挂载**：`event.allTouches` 返回 nil，touch 没进入 event。根因是 iOS 26 所有「构造带 touches 的 UIEvent」入口（`_initWithEvent:touches:` / `_initWithEnvironment:` / `_setGSEvent:` / `_setHIDEvent:`）都需要一个合法的底层 event 种子（GSEvent / HIDEvent / eventEnvironment），而合成场景从零构造，**无种子可用**。
- **迁移决议（2026-07-04 开发者确认）**：realTouch 合成触摸**否决**，采纳「手势显式 adapter」降级方案（Plan B 第 2 条）。Lookin（`LKS_GestureTargetActionsSearcher.m`）同路径印证。详见下文「迁移建议」。

## 验证环境

| 维度 | 版本 | 说明 |
|------|------|------|
| 模拟器 | iOS 26.3.1（iPhone 17 sim，SDK 26.2） | spike 测试完整跑过（5 个 `@Test`），ivar 名表 + 入口探测 + 4 件事结论来源 |
| 真机 | iOS 26.5（UDID `00008030-001045C136D1402E` / CoreDevice `3AC0C7D6-22F6-572B-8368-4047A14BAB52`） | 两轮独立验证：(1) `xcodebuild test` host-app test 进程内跑 `SyntheticTapSpikeRunner`；(2) XcodeBuildMCP device-app profile + iproxy + curl `debug.syntheticTapSpike` 远程触发。两轮结果逐字段一致（见「真机验证结果」）。机型字段刻意略去（devicectl `Model` 会串号，判版本只用 `osVersion`） |
| Xcode | 17C52（iPhoneSimulator26.2 SDK） | framework Debug/Release + SPM Debug/Release 均编译通过 |

**为什么模拟器结论可以外推真机**：合成触摸是 **UIKit 层操作**（构造 `UITouch`/`UIEvent` 对象 → `UIWindow.sendEvent`），**不走 IOKit / 真实触摸硬件路径**。模拟器和真机的 UIKit binary 同出一套 iOS 26.x SDK，ivar 布局、私有方法表、`sendEvent` 分发逻辑一致。模拟器与真机的 IOKit 差异只影响「真实手指触摸」的硬件采集（IOKit → BackBoard → UIKit），不影响「合成 UIKit event」的内部分发。因此「iOS 26 UIEvent 移除 touches 直接挂载入口」这个 SDK 层事实在真机同样成立。

## UITouch / UIEvent ivar 名表（iOS 26，模拟器 dump）

> 来源：`SyntheticTouch.dumpIvars(of:)` 在 iOS 26.3.1 模拟器枚举。真机 UIKit 同 SDK，预期一致。

### UITouch（55 个 ivar，含 NSObject.isa）

spike 实际用到（命中）的：
- `_phase`（`UITouchPhase`，int）
- `_tapCount`（int）
- `_locationInWindow` / `_previousLocationInWindow`（CGPoint）
- `_timestamp`（double）
- `_window`（UIWindow*）
- `_cachedResponderView`（UIView*，**iOS 26 用它代替旧 `_view`**）

存在但 spike 未用：`_responder`、`_warpedIntoView`、`_gestureRecognizers`、`_touchIdentifier`、`_pathIndex`、`_pathIdentity`、`_hidEvent`、`_touchFlags`、`_movementMagnitudeSquared`、`_edgeType`、`_edgeAim`、`_precision`、`_preciseLocationInWindow`、`_precisePreviousLocationInWindow`、`_pressure`、`_previousPressure`、`_maxObservedPressure`、`_maximumPossiblePressure`、`_majorRadiusTolerance`、`_pathMajorRadius`、`_zGradient`、`_rollAngle`、`_previousRollAngle`、`_altitudeAngle`、`_azimuthAngleInCADisplay`、`_azimuthAngleInWindow`、`_forceStage`、`_needsForceUpdate`、`_hasForceUpdate`、`_needsRollUpdate`、`_hasRollUpdate`、`_eaten`、`_forwardingRecord`、`_touchPredictor`、`_updateCorrelationToken`、`_displacement`、`_initialTouchTimestamp`、`__expectedToBecomeDrag`、`__phaseChangeDelegate`、`__windowServerHitTestWindow`、`__authenticationMessage`、`__hitTestSecurityAnalysis`、`_touchAuthenticationRecord`、`_pointerSenderID`、`_pointerSource`、`_senderID`、`_type`。

**关键缺失**：`_view`（iOS ≤17 经典入口，iOS 26 已移除）、`_gestureView`、`_isFirstTouch*`（并入 `_touchFlags` 位域）、`_path`（iOS 13~17 的 `UITouchPath*`，iOS 26 改 `_pathIndex` + `_pathIdentity` 数值引用）。

### UIEvent（16 个 ivar，含 NSObject.isa）

`_gsEvent`、`_hidEvent`、`_hasValidModifiers`、`_mzModifierFlags`、`_mzClickCount`、`_buttonMask`、`_cachedScreen`、`_eventObservers`、`_hitTestObservers`、`_isInteractionBehaviorInactive`、`_lastPointerSenderID`、`_timestamp`、`_eventEnvironment`、`_trackpadFingerDownCount`、`__initialTouchTimestamp`。

**关键缺失（合成方案死结所在）**：`_touchesByKey`（iOS ≤17 的 dict 入口）、`_touches` / `_touchSet`（旧 set 入口）。iOS 26 的 touches 改由 `_eventEnvironment`（私有 `UIEventEnvironment`）+ `_gsEvent`（GraphicsServices C 结构）持有。

## UIEvent 方法表探测（iOS 26）

`SyntheticTouch.dumpMethods(of: UIEvent.self, containing:["touch","set","add","environ","gsevent","hid"])` 探测到的关键入口（149 个中合成相关的）：

- `_initWithEvent:touches:` —— iOS 26 的「构造带 touches event」私有 init。签名推断 `- (instancetype)_initWithEvent:(UIEvent *)template touches:(NSSet *)touches`。**spike 尝试 template=nil，调用成功但 `allTouches` 返回 nil，未挂载**。
- `_initWithEnvironment:` —— 用 `UIEventEnvironment` 构造，需 eventEnvironment 种子。
- `_setGSEvent:` / `_setHIDEvent:` —— 设底层 GSEvent / HIDEvent，需种子对象。
- `_setTimestamp:` —— 设 timestamp（次要）。
- `allTouches` / `touchesForView:` / `touchesForWindow:` / `_touchesForGestureRecognizer:` / `coalescedTouchesForTouch:` / `predictedTouchesForTouch:` —— 读 touches（公开/半公开）。
- `_isTouchRoutingPolicyBased` —— iOS 26 触摸路由策略标记。

**判断**：iOS 26 没有UIKit 层「从零构造带 touches 的 UIEvent」的入口；所有入口都依赖一个合法底层 event 种子。

## 4 件事逐条结论（模拟器 iOS 26.3.1，合成 `explore_sendSyntheticTap`）

诊断统一（模拟器 iOS 26.3.1 与真机 iOS 26.5 实测一致）：`sendEventCalls=2`（began + ended 都调了）、`attachedTouchCount=-1`（`event.allTouches` 返回 nil，touch 没进入 event）、`missing=["event.subtype"]`（`_subtype`/`subtype` ivar 在 iOS 26 已移除，次要字段，不影响主结论）。关键证据：`setFields["event.touches"]="_initWithEvent:touches:"` 说明 `_initWithEvent:touches:` selector **响应并调用了**，但 `allTouches` 仍返回 nil——**selector 调用成功 ≠ touches 真正挂载**，这是 iOS 26 UIEvent 障碍的直接证据。

| # | 场景 | 结论 | 现象 |
|---|------|------|------|
| 1 | `UITapGestureRecognizer` | ❌ 失败 | `counter.fired=false`。sendEvent 分发空 event，gestureEnvironment 收不到 touch，识别器状态机不推进。 |
| 2 | 普通 `UIView` 的 `touchesBegan/Ended` | ❌ 失败 | `beganCount=0`、`endedCount=0`。sendEvent 没把 touch 投递到 hit-test view 的 touches 回调。 |
| 3 | 透明遮挡命中遮挡层 | ❌ 失败（但 hit-test 正确） | `hitTest=UIView`（命中遮挡层 overlay，几何正确）；但 `overlay.fired=false`、`bottom.fired=false`——event 分发层失败，两层都不触发。**合成 tap 没有绕过 hit-test 遮挡**（不掩盖布局 bug），但也没能触发任何层。 |
| 4 | `UIButton.touchUpInside` | ❌ 失败 | `fired=false`。UIControl 的 touch tracking（`beginTracking`→`endTracking`→发 `.touchUpInside`）依赖收到真实 touch，合成 touch 没进入 event，tracking 不启动。 |

**hit-test 几何始终正确**（遮挡场景命中 overlay 层），证明问题不在坐标计算或 view 解析，而在 event 内部没有合法 touches 可分发。

## 稳定性判断

- **ivar 名漂移**：iOS 26 的 touch 字段（`_phase` / `_locationInWindow` / `_timestamp` / `_tapCount` / `_window`）仍可按候选名探测命中，`_view` → `_cachedResponderView` 这类漂移**补候选名即可适配**，维护成本可控（和 alert 的 `_dismissWithAction:` 同量级）。
- **UIEvent touches 挂载**：这是**架构级变化**，不是名漂移。iOS 26 移除 `_touchesByKey` / `_touches` 后，UIKit 层没有「无种子构造带 touches event」的稳定入口。要让合成 event 携带合法 touches，必须逆向 `_gsEvent`（GraphicsServices 的 C 结构，随 iOS 版本剧烈漂移）或 `_eventEnvironment`（私有 `UIEventEnvironment` 的内部布局），维护成本**远高于** alert 单 selector，且每次 iOS 大版本都要重新逆向。
- **可复现性**：模拟器上 100% 复现（5 测试稳定失败），现象一致。

## 迁移建议

> **决议（2026-07-04，开发者确认）**：realTouch 合成触摸路径**否决**（spike 已证 iOS 26 不可行，根因见上文「4 件事逐条结论」）；**采纳 Plan B 第 2 条「手势显式 adapter」作为下一轮方向**，下一轮提示词随本 spike 交接。

**外部印证**：Lookin（LookinServer `LKS_GestureTargetActionsSearcher.m`）走同一路——`[recognizer valueForKey:@"_targets"]` 枚举 `UIGestureRecognizerTarget *` 数组，每个元素 `[targetBox valueForKey:@"_target"]` 取目标对象、`object_getIvar(targetBox, class_getInstanceVariable([targetBox class], "_action"))` 取 SEL，全程 `@try/@catch` 防 crash。Lookin 只做 **search**（列 target-action 给 Mac 端展示），不 invoke；本项目需额外按 selector 签名 invoke，而 `UINavigationBarButtonExecutor.invoke`（`method_getNumberOfArguments` 读实参个数 → switch 2/3/4 派发 0/1/2 参 action）已有现成范本可直接复用，`UIAlertAction+Trigger.swift` 是 KVC + `object_getIvar` + Debug-only 隔离的 runtime 层封装范本。维护成本与 alert 同量级（按 iOS 版本适配 `_targets` / `_target` / `_action` 三个 ivar 名，不改派发逻辑）。

**realTouch 合成触摸否决理由**：iOS 26 上合成触摸卡在 UIEvent touches 挂载这一架构级障碍，绕过它需要逆向 GSEvent / eventEnvironment，投入大、随版本漂移剧烈、且 spike 已证明 UIKit 层入口（`_initWithEvent:touches:` template=nil）不工作。

### 降级方案（Plan B）

1. **维持现状**：`ui.tap` 保持 default 模式（`UIKitDefaultActivationResolver`：UIButton→`touchUpInside`、UISwitch→翻转+`valueChanged`、文本输入→`becomeFirstResponder`），自定义手势 view 继续 `unsupported_target`。这是 spike 前的既定行为，零回归。
2. **手势场景走显式 adapter**（✅ **已选为下一轮方向**）：给依赖 `UITapGestureRecognizer` 的自定义 view 加一条**显式 adapter**——不合成触摸，而是直接调 `gestureRecognizer.view` 上已注册的 target-action（runtime 枚举 `UIGestureRecognizer._targets` / 用 KVC 读 `_target` + `_action`），按 selector 签名派发（复用 `UINavigationBarButtonExecutor.invoke` 的 0/1/2 参签名适配）。这条路**不需要合成 event**，绕开 iOS 26 UIEvent 障碍，维护成本和 alert 同量级。
3. **真实触摸走系统级注入**：若产品上必须「真实手指级」触摸（highlighted 状态、连续手势），改走 XCUITest / `xcrun devicectl` 的系统事件注入（绕过 UIKit 合成），或接受「真实手指」不在本工具职责内（本工具定位是 Debug 探索，不是自动化点击器）。

### 不建议的方向

- **逆向 GSEvent 构造**（`GSEventCreate` 等 GraphicsServices 私有 C API）：理论可行（越狱社区有先例），但 GSEvent 是不透明 C 结构，每个 iOS 版本布局漂移比 UIKit ivar 剧烈得多，维护成本不可接受，且 GSEvent 构造可能需要 entitlement（Debug 工具拿不到）。spike 阶段不投入。

## 卡点 + 已尝试路径

| 路径 | 结果 |
|------|------|
| 设 `_touchesByKey` ivar（dict: token → NSSet） | ❌ iOS 26 无此 ivar |
| 设 `_touches` / `_touchSet` ivar | ❌ iOS 26 无此 ivar |
| `_initWithEvent:touches:`（template=nil） | ⚠️ 调用成功（无 crash，ObjC nil 消息安全），但 `allTouches` 返回 nil，touch 未挂载 |
| 补 `_cachedResponderView` / `_responder` / `_warpedIntoView` 代替 `_view` | ✅ 命中（`_cachedResponderView`），touch 字段补全，但 event touches 仍挂不上 |
| `dumpMethods` 探测 UIEvent 替代入口 | 发现 `_initWithEvent:touches:` / `_initWithEnvironment:` / `_setGSEvent:` / `_setHIDEvent:`，**全部需要底层 event 种子** |

**未尝试（需种子，spike 无来源）**：`_initWithEnvironment:`（需 eventEnvironment 对象）、`_setGSEvent:`（需 GSEvent C 结构）、`_setHIDEvent:`（需 HIDEvent 对象）。这三者都需要一个「真实事件源」作为种子，而合成场景从零构造，没有种子——这是死结的本质。

## 真机验证结果（iOS 26.5，iPhone 11 iPhone12,1）

通过 `xcodebuild test -destination 'id=00008030-001045C136D1402E' -allowProvisioningUpdates`（host-app test：test 在 SPMExample 真实进程里直接调 `SyntheticTapSpikeRunner`，绕过 devicectl 部署）拿到真机结果：

```
[REAL-DEVICE-SPIKE] iOS 26.5
gesture=false plainBegan=0 plainEnded=0 overlay=false bottom=false button=false
hitTest=UIView attached=-1 missing=["event.subtype"]
```

**与模拟器结论完全一致**（iOS 26.x UIKit 同 SDK binary，合成 event 不走 IOKit，外推成立）：
- 4 件事全失败（gesture / plain / 遮挡 / button 都不触发）；
- `hitTest=UIView`（透明遮挡时几何命中遮挡层，正确）；
- `attached=-1`（`event.allTouches` 返回 nil，touch 没挂进 event）——根因确认是 iOS 26 UIEvent touches 挂载机制变化，非 IOKit 差异。

### 第二路径交叉验证（XcodeBuildMCP device-app + curl `debug.syntheticTapSpike`）

为排除 host-app test 单一路径的偶然性，用 `AGENTS.md` 的 XcodeBuildMCP 闭环独立复现：`build_run_device`（profile `device-app`，CoreDevice id `3AC0C7D6-...`）→ `stop_app_device` → `launch_app_device(env={IOS_EXPLORE_AUTOSTART:1, IOS_EXPLORE_SYNTHETIC_TAP_TEST:1})` → `iproxy 38321 38321 -u 00008030-001045C136D1402E` → `curl -X POST http://localhost:38321/ -d '{"action":"debug.syntheticTapSpike"}'`。`debug.probe` 先返回 `{"alive":true,"build":"spike-2026-07-04-probe"}` 确认真机跑的是新 binary，随后 `debug.syntheticTapSpike` 返回：

```
gesture=false plainBegan=0 plainEnded=0 overlay=false bottom=false button=false hitTest=UIView attached=-1 missing=["event.subtype"]
```

与 host-app test 路径结果**逐字段一致**。两条独立验证路径（`xcodebuild test` host-app 进程内 + XcodeBuildMCP 真实 App + curl 远程 action）互相印证，结论可信。

至此 spike 闭环：**iOS 26 上经典「合成 UITouch + sendEvent」方案在真机和模拟器一致地失败**。迁移建议（不建议当前做 `dispatchMode:"realTouch"`、降级走显式手势 adapter）成立。

### 真机验证踩坑记录（给后续 agent）

- **logic test 上不了真机**：framework test target（`iOSExploreServerTests`）是 logic test，`xcodebuild test -destination 'id=device'` 报「Tool-hosted testing is unavailable on device destinations. Select a host application」。真机必须走 host-app test（`SPMExampleTests` 有 `TEST_HOST`）。
- **devicectl install/launch 不可靠**：手动 `devicectl device install + launch` 遇到旧进程残留占 38321、新 binary 不被信任等问题。**改用 `xcodebuild test -allowProvisioningUpdates`**（build + 覆盖装 host app + 装 profile + 启动 + 注入 test 一条龙）。
- **设备首次要信任开发者证书**：iOS 安全机制，任何命令都绕不过。设备 设置 → 通用 → VPN与设备管理 → 信任 `873346225@qq.com`（一次性）。报错信息明确：`Developer App Certificate is not trusted`。
- **增量 build 缓存**：改 ViewController 后，`xcodebuild build` 偶发不重编 device 产物；`touch` 源文件强制重编。最终用 `xcodebuild test` 一次 build + 跑，规避此问题。
- **Mac 上模拟器残留 SPMExample 占 38321（本轮重新验证时遇到的核心坑，最可能是之前「真机一直卡住」的真凶）**：之前 `sim-app` profile 跑过没关的模拟器 SPMExample（Mac 进程，监听 Mac localhost 38321）会残留。真机验证时 `curl localhost:38321` **打到的是这个模拟器残留 App**（旧 binary、不是真机、env 也没设 `IOS_EXPLORE_SYNTHETIC_TAP_TEST`），结果自然对不上真机预期。固定排查：curl 真机前先 `lsof -iTCP:38321 -sTCP:LISTEN`，确认监听进程是 `iproxy` 而非 `SPMExampl`；若被占，`xcrun simctl terminate 065CC8DB-8978-46C5-82D6-C96625B608D8 com.coo.SPMExample`（或 `pkill -f "CoreSimulator/Devices/065CC8DB.*SPMExample"`）清理后再起 iproxy。`iproxy` 启动若立即报 `Address already in use: 38321` 就是这个原因。

## 产物清单

- `Sources/iOSExploreUIKit/Support/Runtime/UITouch+Synthetic.swift` —— 合成触摸 Debug 扩展（`SyntheticTouch` enum + `SyntheticTapDiagnostics` public struct + `UIWindow.explore_sendSyntheticTap`），`#if DEBUG #if canImport(UIKit)` 双隔离，Release 不编译（已 `swift build -c release` + framework Release build 验证）。
- `Tests/iOSExploreServerTests/UITouchSyntheticSpikeTests.swift` —— 5 个 spike 测试：`syntheticTapIvarArchive`（正向，验证 ivar 探测逻辑可工作）+ 4 个场景测试（**特性测试 characterization test**：反向断言锁定「iOS 26 合成触摸不工作」现象，套件保持绿；若未来 iOS 修复使任一测试失败 → 提示重新评估 `realTouch` 迁移）。framework `test_sim` 319 全绿（原 314 主路径 + ivar 存档 + 4 特性测试）。
- `Examples/SPMExample/SPMExample/ViewController.swift` —— 真机 spike 入口（`SyntheticTapSpikeRunner` + `--ios-explore-synthetic-tap-test` + `debug.syntheticTapSpike` server action），`#if DEBUG` 隔离。
- 现有 SPM 208 + framework 314 主路径测试零回归（spike 不碰 `ui.tap` 主路径 / `UIKitActionExecutor` / `UIKitDefaultActivationResolver`）；framework 含新 spike 测试共 319 全绿。Release 编译干净（`swift build -c release` 通过：macOS 不 canImport UIKit，合成代码隔离成空壳）。
