# 2026-07-04 refactor review Codex 独立评估

评估方法：先用 CodeGraph 定位相关符号，再按条目用 `rg` 验证定义、生产调用方、测试调用方和文档契约。下面的行号均来自当前 checkout。

## 断言验证

### §3.1.1 `UIAlertRespondExecutor` Release 分支错误码

判定：**真实成立**。

证据：

- `Sources/iOSExploreUIKit/Support/Action/UIAlertRespondExecutor.swift:27-32`：`dryRun=false` 在 `#if DEBUG` 外直接 `throw UIKitCommandError.alertButtonRequired(action: action)`。
- `Sources/iOSExploreUIKit/UIKitCommandError.swift:271-278`：`alertButtonRequired` 的对外 message 是 `alert has multiple buttons; specify buttonTitle, buttonIndex, or role`，语义是“多按钮未指定选择条件”。
- `Sources/iOSExploreUIKit/Support/Action/UIAlertRespondExecutor.swift:101-104`：Debug 分支内真正的 `alertButtonRequired` 场景是多按钮且未传 `buttonTitle` / `buttonIndex` / `role`。Release 分支复用它会把“非 Debug 不支持触发私有路径”伪装成“参数少了按钮选择器”。

补充：`docs/superpowers/agent-mcp-exploration/agent-usage-protocol.md:369` 当前已经把 Release 回退也写进 `alert_button_required` 说明里，这说明这个错误不只在源码里，也已经污染了使用协议文档。修复时要同步改代码和文档。

### §3.1.2 `hitTestFailed` / `hitMismatch` 死代码

判定：**真实成立**。

证据：

- `Sources/iOSExploreUIKit/UIKitCommandError.swift:97-122`：两个工厂仍描述旧的 hit-test tap 路径：目标点没有命中 view、中心点命中不同 view。
- `Tests/iOSExploreServerTests/UIKitCommandErrorTests.swift:50-62`：这两个工厂只在错误映射测试里被引用。
- `rg -n "hitTestFailed|hitMismatch" Sources --glob '!**/UIKitCommandError.swift'` 无输出，生产代码没有调用方。
- 当前 tap 执行链是默认激活路由：`Sources/iOSExploreUIKit/Support/Action/UIKitActionExecutor.swift:123-148` 先 locate + snapshot 校验，再由 `UIKitDefaultActivationResolver.route(for:)` 决定 route；没有 hit-test 坐标路径。

### §3.1.3 `fingerprints(in:includeHidden:digest:)` 整树指纹死代码

判定：**真实成立**。

证据：

- `Sources/iOSExploreUIKit/Support/Snapshot/UIKitFingerprintCollector.swift:390-407`：`fingerprints(in:includeHidden:digest:)` 会无筛选地整树收集。
- `Sources/iOSExploreUIKit/Support/Snapshot/UIKitFingerprintCollector.swift:410-453`：私有 `collect(...)` 只被该整树函数递归调用。
- `rg -n "fingerprints\\(" Sources Tests --glob '!**/UIKitFingerprintCollector.swift'` 无输出，外部没有调用该整树入口。
- 当前 `snapshotChanged` 使用筛选版：`Sources/iOSExploreUIKit/Support/Snapshot/UIKitFingerprintCollector.swift:290-306` 的 `collectFingerprints(rootView:query:digest:)`，实际调用见 `Sources/iOSExploreUIKit/Support/Wait/UIWaitExecutor.swift:232-236`。
- 当前 `ui.viewTargets` 签发快照不是调用整树入口，而是对已输出目标逐个 `fingerprint(for:)`：`Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsCollector.swift:56-63`。

### §3.1.4 `unsupportedTarget` 文案和错误码过期

判定：**真实成立**。

证据：

- `Sources/iOSExploreUIKit/UIKitCommandError.swift:124-135`：注释仍写“第一版无法派发非 UIControl 的真实 tap”，返回 `.invalidData`，message 仍是 `tap dispatch is only supported for UIControl in this version`。
- `Sources/iOSExploreUIKit/Support/Action/UIKitDefaultActivationResolver.swift:26-45`：当前默认激活只支持 `UIButton`、`UISwitch`、`UITextField` / `UISearchTextField` / `UITextView`；`UISlider`、`UISegmentedControl`、未知自定义 `UIControl` 都返回 nil。
- `Sources/iOSExploreUIKit/Support/Action/UIKitActionExecutor.swift:134-137`：route 为 nil 时抛 `unsupportedTarget`。因此 slider / segmented 这类 UIControl 会拿到“只支持 UIControl”的错误文案，确实误导。
- `Tests/iOSExploreServerTests/UIKitCommandErrorTests.swift:65-69`：测试把 `.invalidData` 和旧 message 锁死。
- `Tests/iOSExploreServerTests/UIKitActionExecutorTests.swift:89-104`、`109-124`：测试名称和失败记录写“unsupported_target”，但断言实际仍是 `.invalidData`。这进一步证明源码契约和测试命名已经漂移。

补充：`docs/architecture/index.md:124` 和 `docs/tools/network-tools.md:119` 已经对外写了无默认 tap 时返回 `unsupported_target`，但 `Sources/iOSExploreServer/Models.swift:185-216` 没有对应 enum case。这是报告没有充分展开的契约漂移，优先级应高于单纯文案修正。

### M1 `UIKitLocator` 与 `UIKitViewLookupTarget`

判定：**部分成立**。

成立部分：

- 两者确实同构。`Sources/iOSExploreUIKit/Support/Locator/UIKitLocator.swift:15-20` 和 `Sources/iOSExploreUIKit/Support/Locator/UIKitViewLookupModels.swift:8-12` 都只有 `accessibilityIdentifier(String)` / `path([Int])` 两个 case。
- `logSummary` 也基本重复：`UIKitLocator.swift:22-31` 与 `UIKitViewLookupModels.swift:24-32`。
- `UIKitLocator.parse` 只是调用 `UIKitViewLookupTarget.parse` 后映射：`UIKitLocator.swift:44-50`。

不成立部分：

- “`UIKitLocator` 生产代码 0 真实使用”不成立。`Sources/iOSExploreUIKit/Support/Action/UIKitActionPlan.swift:30-39` 的 tap/controlEvent action plan 直接持有 `UIKitLocator`；`Sources/iOSExploreUIKit/Support/Action/UIKitActionExecutor.swift:123-127`、`206-211` 使用它执行定位；`Sources/iOSExploreUIKit/Support/Locator/UIKitLocatorResolver.swift:43-57` 和 `96-103` 以它作为真实 resolver 输入。
- `Sources/iOSExploreUIKit/Support/Locator/UIKitViewLookupModels.swift:42-52` 的 `locator` 桥接属性说明当前生产路径是 `UIKitViewLookupTarget` 解析请求后转换成 `UIKitLocator` 再执行。

结论：这里是重复抽象问题，不是死代码问题。可以考虑合并，但不能按“0 使用”直接删除。

### M8 `UIKitSnapshotContext.init(digest:)` + `digest`

判定：**真实成立**。

证据：

- `Sources/iOSExploreUIKit/Support/Snapshot/UIKitSnapshotStore.swift:138-142`：`digest` 属性标为兼容旧诊断调用，返回 `topViewControllerIdentity`。
- `Sources/iOSExploreUIKit/Support/Snapshot/UIKitSnapshotStore.swift:154-159`：`init(digest:)` 也是兼容旧调用方的单摘要初始化器。
- `rg -n "UIKitSnapshotContext\\(digest:" Sources Tests` 无输出。
- 对 `digest` 的 `rg` 命中均是 `UIKitFingerprintCollector.digest(topViewController:)` 或 `UIKitTargetSemanticDigest.digest(for:)`，未发现 `UIKitSnapshotContext.digest` 的生产或测试调用。当前真实构造走 `UIKitSnapshotContext(windowIdentity:topViewControllerIdentity:)`，如 `Sources/iOSExploreUIKit/Support/Snapshot/UIKitFingerprintCollector.swift:102-111`。

### M10 `UIScrollStepResult` 注释与实际相反

判定：**真实成立**。

证据：

- `Sources/iOSExploreUIKit/Support/Action/UIScrollGeometry.swift:6-11` 文件顶部已经写明 `ui.scrollToElement` 改用 `scrollRectToVisible` 后不再调用本类型，`step / delta / reachedExtent` 当前仅 `ui.scroll` 使用。
- 同文件 `Sources/iOSExploreUIKit/Support/Action/UIScrollGeometry.swift:67-71` 却仍写 `UIScrollStepResult` 是 `ui.scroll / ui.scrollToElement` 共享。
- `Sources/iOSExploreUIKit/Support/Action/UIScrollToElementExecutor.swift:8-14` 明确使用 `UIScrollView.scrollRectToVisible`，并解释为什么不走循环小步 scroll。
- `Sources/iOSExploreUIKit/Support/Action/UIScrollToElementExecutor.swift:51-54` 是实际滚动调用点，未使用 `UIScrollGeometry.step` 或 `UIScrollStepResult`。

补充：`Sources/iOSExploreUIKit/Support/Action/UIScrollExecutor.swift:8-11` 也还写“共享原语（供 `ui.scrollToElement` 复用）”，这个注释同样过期，报告只点了 `UIScrollStepResult`，遗漏了 executor 顶部注释。

## 方案评估

### §4.2 `ui.tap` 合成触摸事件

我的判断：**方向可以作为 spike，不能直接排入正式迁移；报告“先 spike 再迁移、给 `ui.tap` 加 `dispatchMode:"realTouch"` 双模式”的节奏合理。**

可行性：

- 当前 `ui.tap` 的公开 API 短板是真实的。`UIKitDefaultActivationResolver.swift:26-45` 只覆盖按钮、开关、文本输入；手势 view、slider、segmented、自定义 control 都没有默认触发路由。
- 用 `UITouch` + `UIEvent` + `UIWindow.sendEvent` 的思路在 Debug-only 工具语境下可以尝试，因为项目已经接受私有 API / runtime 维护成本；现有 runtime 层也已经形成模式：`Sources/iOSExploreUIKit/Support/Runtime/UIAlertController+TriggerAction.swift:1-5` 用 `#if DEBUG` + `#if canImport(UIKit)` 隔离，`UIAlertAction+Trigger.swift:59-130` 把 swizzle、关联对象、KVC 和 block 调用封装在 extension 里，命令层不散写私有细节。
- 但 UIKit 没有公开稳定的“从 App 内构造真实触摸事件”API。旧设计文档也明确写过不可靠：`docs/superpowers/specs/iOSExploreServer-ui-tap-final-refactor-plan.md:252-264`、`1038-1046`。现在项目基调变了，这条可以从“不做”改成“允许 spike”，但不能跳过 spike。

iOS 17 / 18 / 26 真机风险：

- 最大风险不是 `sendEvent`，而是 `UITouch` / touch-type `UIEvent` 的私有 ivar、初始化状态和生命周期是否能被当前系统接受。报告提到的 `_locationInWindow`、`_phase`、`_timestamp`、`_view`、`_window`、`_tapCount` 这类 KVC/ivar 路径都可能随 iOS 版本变化。
- iOS 26 本仓库已有一个可比风险案例：`UIAlertController+TriggerAction.swift:26-30` 记录 iOS 26 alert 按钮位于私有 `_UIInterfaceAction*` representation 容器，普通 view 遍历拿不到按钮 view；同文件也明确 `_dismissWithAction:` selector 名漂移是维护成本。这说明私有 UIKit 结构确实会漂移，`ui.tap` 的 ivar spike 必须按版本探测。
- spike 应至少验证四件事：能否触发 `UITapGestureRecognizer`；能否触发被 hit-test 命中的普通 view；透明遮挡时是否与真人点击一致命中遮挡层；`UIButton`/`UISwitch` 旧默认模式是否仍保持兼容。

落地节奏：

- `dispatchMode:"default" | "realTouch"` 合理。`default` 保留现在的结构化默认激活，稳定、可预测、适合 Agent 默认行为；`realTouch` 明确表示走私有触摸注入，失败时可以返回单独错误码，不会把现有 `ui.tap` 契约一次性改成不稳定行为。
- `realTouch` 不应默认开启；建议第一步只加 spike 和实验性内部 executor，不改 `help` 的主推荐路径。等 iOS 17/18/26 真机矩阵通过后，再暴露到命令 schema。
- 新 runtime 文件应放在 `Sources/iOSExploreUIKit/Support/Runtime/`，用 `#if DEBUG` 包裹；命令层只调用类似 `UIRealTouchExecutor` 的稳定入口，不直接写 ivar 名。

方案 C（XCTest `_XCEventGenerator`）：

- “否决”方向成立，但报告里的“真机不可用”表述过粗。XCUITest 本身可以在真机上由 Mac 侧测试 runner 驱动 App；当前仓库也只有 UI test target import XCTest，见 `Examples/SPMExample/SPMExampleUITests/SPMExampleUITests.swift:8-28`。
- 对本项目的否决理由应写成：`iOSExploreServer` 是嵌入 App 进程的 Debug server，不能把 App 内运行的库实现建立在 XCTest 私有类 `_XCEventGenerator` 上；这会把命令能力绑到测试 runner / XCTest 私有框架 / 开发者工具环境，和“Mac curl -> App 内 HTTP server -> 真机 App 自执行”的闭环不一致。也就是说，不是“XCUITest 不能跑真机”，而是“把 XCTest 私有事件生成器链进 App 内 server 不适合作为本库能力”。

## 报告的不足

1. **M1 把重复抽象误报成死代码。** `UIKitLocator` 和 `UIKitViewLookupTarget` 同构是真的，但 `UIKitLocator` 有生产使用，不能按 0 调用方删除。应降级为“重复类型 / 桥接层是否必要”的重构建议。

2. **`unsupported_target` 的问题没有说完整。** 报告说 `unsupportedTarget` 用 `.invalidData` 不准，这成立；但更严重的是活跃文档已经承诺返回 `unsupported_target`（`docs/architecture/index.md:124`、`docs/tools/network-tools.md:119`），测试名称也写 `unsupported_target`（`UIKitActionExecutorTests.swift:89`、`109`），而 `ExploreError` 没有这个 case。这里是代码、测试命名、文档三方契约漂移。

3. **报告中有小的章节编号错误。** `docs/superpowers/reviews/2026-07-04-refactor-review.md:75` 把 alert Release 错误码 bug 写成“§3.1.3”，实际对应 §3.1.1。

4. **方案 C 的否决理由表述不严谨。** 应避免写“XCTest 真机不可用”。更准确的说法是：XCUITest 可驱动真机，但 `_XCEventGenerator` 是测试框架私有实现，不适合作为 App 内嵌 debug server 的运行时依赖。

5. **M10 漏了同类注释。** 除 `UIScrollStepResult` 外，`UIScrollExecutor.swift:8-11` 也还说 scroll 几何原语供 `ui.scrollToElement` 复用。

6. **§3.1.3 的行号在当前 checkout 已不精确。** 报告写 `UIKitFingerprintCollector.swift:356-453`，当前整树入口实际在 `390-453`。问题成立，但引用应更新。

7. **“真实闭环验证”结论不能替代当前评审的本地复跑证据。** 报告声称跑过 SPMExample；本次评估没有复跑它，只能确认源码事实。报告整体可信，但其中“真机实测”类描述仍应保留原报告的证据链或日志，而不是只靠摘要。

## 修复优先级建议

如果让我拍板，第一波建议按下面顺序：

1. **先修 `unsupported_target` 契约漂移和文案。** 这不仅是 message 难看，而是活跃文档已经承诺独立 code，测试名称也按独立 code 命名，但源码仍返回 `.invalidData`。应新增 `ExploreError.unsupportedTarget = "unsupported_target"`，让 `UIKitCommandError.unsupportedTarget` 使用该 code，并把 message 改成“目标没有默认激活路由”，同步更新测试。

2. **修 `ui.alert.respond` Release 分支错误码。** 新增清晰的 Release 禁用错误工厂，或至少复用一个语义正确的 unsupported code。同步修改 `agent-usage-protocol.md`、`curl-json-loop-protocol.md`、`uikit-file-reference.md` 里把 Release 回退解释成 `alert_button_required` 的内容。

3. **删死代码：`hitTestFailed` / `hitMismatch`、整树 `fingerprints` / `collect`、`UIKitSnapshotContext.init(digest:)` / `digest`。** 这些不改变运行行为，能减少旧路径误导。删除前同步删或改对应只测死代码的测试。

4. **修 scroll 注释。** 这是低风险文档/注释修正，但能避免后来的人误以为 `scrollToElement` 还复用 step 结果。

5. **再做 M1 类型合并和其它机械重构。** M1 不是死代码，涉及 ActionPlan、Resolver、Executor、Wait 的类型边界，应该放在纯 bug/死代码之后单独做，避免把清理和行为契约修正混在一起。

6. **最后做 `ui.tap` realTouch spike。** 这是高价值但高风险的能力实验。它依赖前面先把 `unsupported_target` 契约梳理清楚，否则 spike 失败、目标不支持、私有 ivar 漂移会继续挤在 `.invalidData` 里。

一句话总结：这份报告整体可信，主要严重问题基本成立；但它把 M1 夸成死代码、对 XCTest 真机问题表述过粗，并遗漏了 `unsupported_target` 已经成为文档契约但源码尚未实现这一更关键的漂移。
