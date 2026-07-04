# 2026-07-04 iOSExploreServer 重构全面评估报告

> 评估对象：本轮「吸取得物 AI UITester 经验 → Agent MCP 应用探索服务」方向的重构
> 范围：`31d2895..HEAD`（25 个提交，123 个文件，+17275 / -1351 行）
> 评估方法：(1) 主会话用 codegraph 精读核心执行链路；(2) 两个 subagent 独立挖代码质量与基调迁移；(3) 在 `Examples/SPMExample`（iPhone 17 模拟器）真实闭环验证全部 14 个 `ui.*` 命令。
> 评估日期：2026-07-04

---

## 0. TL;DR（先读这段）

| 维度 | 结论 |
|---|---|
| 重构核心成果 | `ui.tap` 结构化默认激活、navigationBar 可达性、`ui.waitAny`、`ui.alert.respond` 私有 API 化，全部**真实闭环跑通** |
| 基调调整落实度 | 「Debug-only 工具、允许私有 API」是本轮最大基调变化，但**只应用到 `ui.alert.respond` 一个命令**，其余 13 个仍停在公开 API 时代 |
| 真实闭环 | 8 类核心能力（observe / tap / input / scroll / navigation×2 / alert dryRun×2 / waitAny）全部验证通过；alert 私有 API `_dismissWithAction:` 闭环干净 |
| 代码质量 | **架构稳**（typed factory 边界守住、错误工厂集中、Debug 隔离干净），但有 **4 个严重问题**（2 处死代码、1 个错误码 bug、1 个文案过期）+ 一批可机械清理的重复样板 |
| 基调迁移首选 | `ui.tap` 合成触摸事件（覆盖手势识别器 / 坐标点击 / hit-test 遮挡）—— 价值最高，风险也最高，**建议先 spike 再迁移** |
| 推荐执行顺序 | ① 修 alert 错误码 bug → ② 删死代码 → ③ 修 tap 错误文案 → ④ 提取重复样板 → ⑤ `ui.tap` 合成触摸 spike |

> 名词约定：本报告里「**基调迁移**」= 把某个命令的实现从「公开 UIKit API」改成「私有 API / runtime 技巧（KVC、method swizzle、合成事件等）」，因为项目从「要打包到生产环境、只能用公开 API」变成了「Debug-only 开发工具、允许用私有 API」。所有依赖私有 API 的代码必须用 `#if DEBUG` 隔离，确保不进 Release 二进制。

---

## 1. 重构范围与基调调整回顾

### 1.1 重构脉络（从提交历史）

本轮重构起点是 `31d2895`（merge origin/main）之后，agent 围绕「吸取得物 AI UITester 经验」做了四个大改造：

1. **`ui.tap` 结构化默认激活**（锚点 2026-07-03）：废弃旧「坐标点击 / hit-test / nearest UIControl fallback」语义，改为「`UIKitDefaultActivationResolver` 三路默认激活」（UIButton→`touchUpInside`、UISwitch→toggle+`valueChanged`、文本输入→`becomeFirstResponder`），其它目标返回 `unsupported`。
2. **navigationBar 可达性**：`ui.viewTargets` / `ui.topViewHierarchy` 响应追加 `navigationBar` 摘要；新增 `ui.navigation.tapBarButton` 按 `placement+index` 触发 `UIBarButtonItem`，executor 用 `method_getNumberOfArguments` 读 selector 真实参数个数适配 0/1/2 参签名。
3. **`ui.waitAny`**：与 `ui.wait` 共享 `ConditionProbe` 五模式判断原语，一次轮询等待多结局，命中后只回 `matchedID/matchedIndex/matchedMode`。
4. **`ui.alert.respond` 私有 API 化**：`dryRun=false` 通过私有 `_dismissWithAction:` 让系统像真人点按钮一样 dismiss + 调 handler；新增 `Support/Runtime/` Debug-only runtime 层（Swizzler / UIAlertAction+Trigger / UIAlertController+TriggerAction）。

### 1.2 基调调整的时间点（关键）

「项目是 Debug-only 开发工具、允许使用私有 API / runtime 技巧」这条基调，是在**最新一个实质提交 `35ddc0e`（alert dryRun=false）才正式写入 `AGENTS.md` 的**（`git log -S "Debug-only 开发工具" -- AGENTS.md` 仅命中这一个提交）。

也就是说：基调调整是「刚刚发生」的，而且**目前只应用到了 `ui.alert.respond` 一个命令**。这正是本报告第 5 节要重点回答的问题——其余命令里，哪些是「基调变了但仍停在公开 API 时代、能力因此受限」的迁移候选。

### 1.3 架构约束（评估基线，未变）

- `iOSExploreServer`（core）只依赖 `Foundation` + `Network`，不依赖 UIKit。
- `iOSExploreUIKit` 整体 `#if canImport(UIKit)`；typed factory 规则：入参先 Foundation-only typed query 解析校验，UIKit 类型不穿 public 命令边界。
- executor throw 化：成功返回 `JSON`，失败 `throw UIKitCommandError`，由命令 handler 顶层 catch 转 envelope。
- Swift 6.2 严格并发：跨边界模型 `Sendable`，UIKit executor 全部 `@MainActor enum`。

---

## 2. 真实闭环验证结果（SPMExample + iPhone 17 模拟器）

验证方式：`build_run_sim` 构建 `SPMExample`，用启动参数 `--ios-explore-autostart` 让 App 自动 `server.start()`（`ViewController.swift:186-190` 已实现该开关），Mac 侧 `curl localhost:38321` 直连（模拟器与 Mac 共享网络栈，不需要 `iproxy`）。

| # | 能力 | 命令 | 实测结果 | 备注 |
|---|---|---|---|---|
| 1 | 健康检查 | `ping` | ✅ `{"pong":true}` | server autostart 生效 |
| 2 | 命令发现 | `help` | ✅ 列出 20 个命令（14 ui.* + 6 core/example） | 命令注册齐全 |
| 3 | 结构化观察 | `ui.viewTargets` | ✅ 返回 targets + `viewSnapshotID` + `navigationBar` 摘要 | 主页 3 target / ControlTest 8 target / AlertTest 6 target，分类与 `UIKitDefaultActivationResolver` 三路路由精确一致 |
| 4 | 导航栏按钮 | `ui.navigation.tapBarButton` | ✅ `topAfter` 正确切换到目标 VC | 字段名是 `accessibilityIdentifier`（非 `identifier`） |
| 5 | 默认激活-开关 | `ui.tap` UISwitch | ✅ `switchToggle`，`previousValue:false→currentValue:true` | 走 `setOn(!on)+valueChanged` |
| 6 | 默认激活-短板 | `ui.tap` UISlider | ⚠️ 返回 `invalid_data: "tap dispatch is only supported for UIControl in this version"` | slider **就是** UIControl，文案与实现矛盾，且错误码用 `invalid_data`（应为独立 unsupported 错误）——见 §3.1.4 |
| 7 | 文本注入 | `ui.input` | ✅ `finalText:"hello-agent-验证"` | 走 `insertText`，触发委托/formatter |
| 8 | 滚动 | `ui.scroll` | ✅ `offsetBefore.y:0 → offsetAfter.y:120` | 走 `setContentOffset(animated:false)` |
| 9 | 返回 | `ui.navigation.back` | ✅ `topAfter` 回退正确 | 走 `dismiss` / `popViewController` |
| 10 | alert 查询 | `ui.alert.respond` dryRun=true | ✅ 返回 title/message/buttons/textFields | buttons 含 role（cancel/default） |
| 11 | **alert 真实触发（私有 API）** | `ui.alert.respond` dryRun=false | ✅ `performed:true, dismissed:true`，再查已 `alert_unavailable` | 走系统私有 `_dismissWithAction:`，与真人点按钮一致 |
| 12 | 多结果等待 | `ui.waitAny` | ✅ `matchedID:"a", attempts:1, elapsedMs:0` | 共享 `ConditionProbe` 五模式判断 |

**真实验证的关键结论**：
- (a) **alert 私有 API 闭环完全可用**：`observe→tap(弹窗)→dryRun(query)→dryRun=false(真实触发)→re-query(已关闭)` 全流程在模拟器跑通，证明基调调整后第一个迁移（alert）设计与实现都干净。
- (b) **`ui.tap` 公开 API 短板真实存在**：tap 一个带手势的普通 view 或非默认路由控件（slider/segmented/stepper/手势 view）一律不可点，这正是「基调变了但 tap 还停在公开 API」最直接的体感。
- (c) **stale_locator 防护生效**：observe 与 act 之间间隔过长会触发陈旧保护（TTL 30s / 容量 8），紧凑闭环（observe→立刻 act）正常——这是设计预期，agent 必须遵守「滚动/间隔后重新 observe」协议。

> 未在模拟器覆盖的两项（代码已确认）：① alert `dryRun=false` 在 **Release 构建**下回退 `alertButtonRequired`（§3.1.3 的错误码 bug 就在这里）；② `ui.input` 对 `isSecureTextEntry` 密码字段的脱敏响应。

---

## 3. 代码质量评估

模块整体 49 个文件、约 8455 行。核心架构（typed factory 边界、typed query、Sendable 隔离、错误工厂集中、Debug 隔离）是稳的。agent 多轮迭代主要留下两类债：**(A) 旧路径死代码**（hit-test tap 残留、整树指纹签发）；**(B) 同一规则在多个 executor 各写一遍**（陈旧校验、settle、describe、UITextView 排除）。

### 3.1 严重问题（影响可维护性或正确性，必须改）

#### 3.1.1 正确性 bug：`UIAlertRespondExecutor` 非 Debug 分支抛了语义完全错误的错误码
**位置**：`Sources/iOSExploreUIKit/Support/Action/UIAlertRespondExecutor.swift:27-33`

```swift
if !input.dryRun {
    #if DEBUG
    return try perform(input: input, alert: alert)
    #else
    throw UIKitCommandError.alertButtonRequired(action: action)   // ← 错误码语义错
    #endif
}
```

Release 构建下 `dryRun=false` 抛 `alert_button_required`，其 message 是 `"alert has multiple buttons; specify buttonTitle, buttonIndex, or role"`（`UIKitCommandError.swift:277`），但真实失败原因是「非 Debug 不支持触发」。调用方收到这个错误码会被误导去补 button 选择参数，永远修不好。

**修复**：新增 `UIKitCommandError.alertRespondDisabledInRelease(action:)`（code 用 `unsupportedAction` 或新增 `alert_release_unsupported`），message 明确「非 Debug 构建不支持触发，仅 dryRun=true 可用」。

#### 3.1.2 死代码：旧 hit-test tap 路径残留的错误工厂
**位置**：`Sources/iOSExploreUIKit/UIKitCommandError.swift:97-122`

`hitTestFailed(action:targetDescription:x:y:)` 和 `hitMismatch(action:targetDescription:hitType:)` 是旧「ui.tap 走 hit-test + 坐标注入」路径的残留。当前 `ui.tap` 已重构为默认激活路由，明确不做 hit-test、不接受坐标。grep 全仓：两个工厂生产代码 0 调用方，只在自己测试里出现。

**修复**：删除这两个工厂 + 对应测试 `UIKitCommandErrorTests.swift:51-56`。它们还会误导读者以为 tap 仍走 hit-test。

#### 3.1.3 死代码：`UIKitFingerprintCollector.fingerprints(in:includeHidden:digest:)` + `collect` 整套（约 100 行）
**位置**：`Sources/iOSExploreUIKit/Support/Snapshot/UIKitFingerprintCollector.swift:356-453`

无筛选版的整树指纹收集（遍历每个节点都签发），已被 query 筛选版 `collectFingerprints(rootView:query:digest:)`（line 290-306）+ `collectMatching`（313-354）取代。生产路径里 `ui.viewTargets` 用 collector 自己的 `collected` 累积再逐个 `fingerprint(for:)`，`ui.wait(snapshotChanged)` 用 `collectFingerprints(rootView:query:)`——`fingerprints` 整树版 0 外部调用方。

**修复**：删除 `fingerprints(in:includeHidden:digest:)` 和私有 `collect(view:rootView:path:includeHidden:digest:result:)`。无筛选版会签发非 canonical 节点，与新口径不一致，留着是语义噪音。

#### 3.1.4 错误文案/错误码过期：`unsupportedTarget`（**真机实测暴露 + subagent 独立发现，三重交叉验证**）
**位置**：`Sources/iOSExploreUIKit/UIKitCommandError.swift:124-135`

```swift
static func unsupportedTarget(action:targetDescription:type:) -> UIKitCommandError {
    UIKitCommandError(code: .invalidData,                                    // ← code 用 invalid_data
                      message: "tap dispatch is only supported for UIControl in this version",  // ← 文案过期
                      logMessage: "...")
}
```

三个问题叠加：
1. **文案错**：slider/segmented/stepper **就是** UIControl，但 tap 它们命中此错误，message 却说「只支持 UIControl」——真机实测 tap UISlider 正是这个误导文案（§2 第 6 行）。
2. **code 不准**：用 `.invalid_data`，没有独立的「target 不支持默认激活」错误码，与「参数校验失败」混在一起，调用方难以区分。
3. **注释过期**：注释还写「第一版无法派发非 UIControl 的真实 tap」，是 spike 时代措辞。

> 这条是「agent 反复改 tap 语义」留下的最典型痕迹：实现已经改成默认激活三路由，但错误出口的文案和注释没跟上。测试 `UIKitCommandErrorTests.swift:68` 还把这个错误码+文案锁死了，等于把过期一起固化。

**修复**：message 改为 `"target has no default activation route (UIButton / UISwitch / text input only)"`；注释去掉「第一版」「UIControl」措辞；考虑新增独立 code `unsupported_target`（与 §5 的 tap 合成触摸迁移配合，未来 realTouch 失败也走这个 code）；同步更新锁定的测试。

### 3.2 中等问题（值得清理，机械重构，不涉及架构）

| # | 问题 | 位置 | 建议 |
|---|---|---|---|
| M1 | **双重抽象**：`UIKitLocator` 与 `UIKitViewLookupTarget` 是完全同构的 enum（case 相同、`logSummary` 逐字相同、`parse` 恒等映射），`UIKitLocator` 生产代码 0 真实使用 | `Support/Locator/UIKitLocator.swift:15-52` ↔ `UIKitViewLookupModels.swift:8-93` | `UIKitLocator` 改 `typealias = UIKitViewLookupTarget`，删约 50 行重复 |
| M2 | **8 处 command adapter 重复样板**：`MainActor.run` + `do-catch` 模板逐字重复 | `Commands/{Input,Scroll,Alert,Keyboard,Navigation/*,ScrollToElement,Screenshot}/*Command.swift` 的 `handle(_:)` | 提取 `runUIKitCommand(action:body:)` helper，8 个 handle 各剩一行 |
| M3 | **3 处陈旧校验各写一遍**：重采 path 指纹→`isStale`→抛 `staleLocator`，写法略不同 | `UIKitActionExecutor.swift:93-108` / `UIScrollResolver.swift:54-73` / `UITextInputExecutor.swift:45-62` | 下沉到 `UIKitSnapshotStore` 或新增 `UIKitFreshnessGuard.guardFreshness(...)`，`viewSnapshotID` 为 nil 时内部跳过 |
| M4 | **`settle` 重复 3 处、`describe(type:)` 重复 2 处** + 散写 `String(describing:type(of:))` 8+ 处 | `UINavigationBackExecutor:111` / `UINavigationBarButtonExecutor:104` / `UIKeyboardDismissExecutor:75` | 提到 `UIKitAdapters.swift`；`UITextInputExecutor:83` 硬编码 `RunLoop.run(until:+0.05)` 改用 `settle(milliseconds:50)` |
| M5 | **UITextView 排除规则散落 4 处**：`as? UIScrollView, !(X is UITextView)` | `UIScrollResolver:93,107,151` + `UIKitActionCapabilityResolver:63` | 新增 `asScrollContainer(_:)` 单点判定 |
| M6 | **path 字符串拼接重复**：与统一入口 `UIKitViewLookupTarget.pathString(from:)` 逻辑相同却重写 | `UIKitVisibleTextCollector.swift:66` | 改调统一入口，path 序列化只有一处真相 |
| M7 | **`UIKitActionKind.ordered` 硬编码 declarationOrder 数组**，未用 `CaseIterable` | `UIKitActionCapabilityResolver.swift:113-129` | enum conform `CaseIterable`，用 `allCases.filter` |
| M8 | **迁移兼容残留**：`UIKitSnapshotContext.init(digest:)` + `digest` 属性，0 调用方 | `UIKitSnapshotStore.swift:138-159` | 删除 |
| M9 | **悬空注释**：`perform` 尾端挂着「手动 dismiss 已被取代」注释，下方无方法体（删方法没删注释） | `UIAlertRespondExecutor.swift:117-119` | 并入 `perform` doc comment |
| M10 | **注释与实际相反**：`UIScrollStepResult` 注释说「ui.scroll / ui.scrollToElement 共享」，但 scrollToElement 已改用 `scrollRectToVisible`，不用 step | `UIScrollGeometry.swift:67` ↔ `UIScrollToElementExecutor.swift:9-14` | 改为「仅 ui.scroll 使用」；删 §3.6「为未来循环 scroll 复用」YAGNI 措辞 |
| M11 | **`UIKitCommandError.targetNotFound` 两个重载** api 表面不齐 | `UIKitCommandError.swift:63` vs `78` | 统一为一个重载 |

### 3.3 做得好的地方（避免为了批评而批评，这些是 agent 迭代收敛出的正确设计）

1. **`UIKitDefaultActivationResolver` 单点定义 tap 路由**（`UIKitDefaultActivationResolver.swift:35-47`）：collector（`UIKitActionCapabilityResolver.resolve:54`）和 executor（`UIKitActionExecutor.executeTap:134`）共用同一份规则，保证「声明可 tap」与「实际激活路径」不分叉——这是 ui.tap 反复改语义后收敛出的正确解。
2. **`ConditionProbe` 被 `ui.wait` 和 `ui.waitAny` 真复用**（`UIWaitExecutor.swift:191-250`，`UIWaitAnyExecutor.swift:85`）：五模式判断只写一遍，克制不过度抽象。
3. **错误工厂集中在 `UIKitCommandError`**（27 个工厂各有实际调用）：失败码/message/logMessage 单一来源，handler 顶层只记一次失败日志。
4. **`UIKitLocatorResolver.locate(locator:notFound:ambiguous:)` 错误工厂交调用方注入**：定位器不耦合业务错误码，tap 与 control 命令对「未找到」用不同 message。
5. **`Support/Runtime/` Debug 双重隔离**（`#if DEBUG #if canImport(UIKit)`）：私有 API / runtime hook 完全不进 Release，符合 AGENTS.md「Debug-only 工具」约束。
6. **`UIKitSnapshotStore` 容量/TTL 常量明确**（8 条 × 512 指纹 / 30s TTL）：注释引用 spec 说明 30s 匹配 LLM 推理节奏。
7. **`UIKitContextProvider.topViewController` 覆盖四种容器**（presented/Navigation/Tab/Split）：递归到真实顶部，所有 executor 共享。
8. **typed factory 边界守住**：所有 executor 是 `@MainActor enum`，UIKit 类型不穿 public 边界，跨边界只传 `JSON` / `UIKitTargetFingerprint`（Sendable 值类型）。

### 3.4 代码质量量化

| 维度 | 数量 |
|---|---|
| 确凿死代码（无生产调用方） | **5 处**（hit-test 错误工厂×2、`fingerprints`+`collect` ~100 行、`UIKitLocator` 与 `UIKitViewLookupTarget` 同构、`UIKitSnapshotContext.init(digest:)`） |
| 正确性 bug | **1 处**（alert 非 Debug 错误码） |
| 注释/文案过期 | **5 处** |
| 跨文件重复样板 | **15+ 处**（adapter 8 / settle 3 / describe 2 / 陈旧校验 3 / UITextView 排除 4 / path 拼接 2） |
| 过度抽象（YAGNI） | **0 处确认**（`UIScrollGeometry.step` 当前仍被使用） |
| 做得好的设计 | **8 处** |

**整体判断**：架构不需要重写。问题是机械清理级别——删旧路径死代码 + 提取重复样板，预计 1-2 天可消化。

---

## 4. 基调迁移评估（公开 API → 私有 API）

> 评估口径：不是「能用私有 API 就用」，而是「当前公开 API 是否有**能力短板**，私有 API 能否带来**质变**」。alert 是已验证的标杆——公开 API 无法触发 UIAlertAction handler，私有 `_dismissWithAction:` 让能力从「只能查询」变成「能真实响应」，这是质变。

### 4.1 逐命令评估表

| 命令 | 当前实现（公开 API） | 限制 | 私有 API 方案 | 优先级 |
|---|---|---|---|---|
| **ui.tap** | `sendActions(.touchUpInside)` / `setOn+valueChanged` / `becomeFirstResponder`（`UIKitActionExecutor.swift:140-189`） | **手势识别器 / 坐标点击 / hit-test 遮挡 / 非默认路由控件全不可点** | 合成 `UITouch`+`UIEvent` 注入 `UIWindow.sendEvent` | **高（质变）** |
| ui.scroll | `setContentOffset(animated:)`（`UIScrollGeometry.swift:53-64`） | 下拉刷新不走真实手势路径 | **公开 `UIRefreshControl.beginRefreshing()` 即可**（不需私有） | 中（用公开 API 解决） |
| ui.topViewHierarchy / ui.viewTargets | `subviews` 递归 | 看不到私有 helper view（`_UIButtonBarButton` 等） | 私有 `recursiveDescription` | 低（增强非必需） |
| ui.input | `UITextInput.insertText`（`UITextInputExecutor.swift:79-99`） | 不走真实键盘事件流，但已触发委托/formatter，是公开最佳 | `UIKeyboardImpl` 私有协议 | 低（收益小） |
| ui.keyboard.dismiss | `resignFirstResponder` / `endEditing`（`UIKeyboardDismissExecutor.swift:35-45`） | 无——这就是 Apple 推荐的收键盘方式 | 无 | 不迁移 |
| ui.navigation.back | `dismiss` / `popViewController`（`UINavigationBackExecutor.swift:91-103`） | 不走边缘滑动返回手势——但命令语义就该是「回上一页」 | 无 | 不迁移 |
| ui.navigation.tapBarButton | `method_getNumberOfArguments` 适配签名派发（`UINavigationBarButtonExecutor.swift:58-96`） | 已用 runtime，足够 | 无 | 不迁移（已是范本） |
| ui.control.sendAction | `UIControl.sendActions(for:)`（`UIKitActionExecutor.swift:206-243`） | 无——这是 UIControl 程序化触发标准 API | 无 | 不迁移 |
| ui.screenshot | `drawHierarchy` + `layer.render` 三级回退（`UIScreenshotCollector.swift:129-148`） | 无——已覆盖无 render server 场景 | `_uipreviewImageBuilder` | 不迁移 |
| ui.scrollToElement | `scrollRectToVisible` | 无——UIKit 官方推荐 API | 无 | 不迁移 |
| ui.wait / ui.waitAny | 轮询 + 指纹比对 | 纯查询，无触发动作 | 无 | 不迁移 |

### 4.2 高优先级候选：`ui.tap` 合成触摸事件（价值最高，风险也最高）

**当前痛点**（真机实测 + 代码确认）：
- 任何依赖 `UITapGestureRecognizer`/`UILongPressGestureRecognizer`/`UIPanGestureRecognizer` 的自定义 view：`sendActions` 对它们无效，tap 直接 `unsupported`。
- UIControl 真实跟踪路径（`beginTracking/continueTracking/endTracking`）不触发，highlighted 状态、连续手势反馈丢失。
- hit-test 遮挡场景：按钮被透明 view 覆盖时真人点不到，但 `sendActions` 仍「成功」——掩盖布局 bug。
- 坐标相关高亮/ripple 动画跳过。

**技术方案（按可行性）**：
- **方案 A（推荐）：合成 `UITouch`+`UIEvent` 注入 `UIWindow.sendEvent`**。用 ObjC runtime 创建 UITouch，KVC 设 `_locationInWindow`/`_phase`/`_timestamp`/`_view`/`_window`/`_tapCount` 等私有 ivar，构造 UIEvent 后 `sendEvent`。**风险：高**——iOS 9+ 后 UITouch 无公开初始化器，ivar 名随 iOS 版本漂移（13/14/16/17/26 都调过），需逐版本 `class_copyIvarList` 枚举确认。复用现有 `Swizzler` + `UIAlertAction+Trigger` 的 KVC 反射模式，可直接复用。
- 方案 B（反射触发 UIGestureRecognizer）：风险极高，每个手势类型都要单独逆向，不推荐。
- 方案 C（XCTest `_XCEventGenerator`）：唯一能「完全像真人」（发真实 IOHIDEvent），但链接 XCTest 会让 App 含测试框架、**真机不可用**——本项目要真机闭环，否决。

**落地建议**：
1. **先 spike**（参照 `Tests/.../UIAlertActionHandlerSpikeTests.swift` 模式）：在 iOS 17/18/26 真机验证合成 UITouch 能否触发一个已知 `UITapGestureRecognizer`。
2. spike 通过后，新增 `Support/Runtime/UITouch+Synthetic.swift` + `Support/Action/UIRealTouchExecutor.swift`。
3. 命令层参照 alert 的 `dryRun` 双模式，给 `ui.tap` 加 `dispatchMode: "default" | "realTouch"`，保持向后兼容。
4. 配套新增独立错误码 `unsupported_target`（同时解决 §3.1.4 的 code 问题）。

**能覆盖的真实场景**：自定义 view 的 tap gesture、长按手势、hit-test 遮挡验证、坐标高亮反馈。

### 4.3 中优先级：`ui.scroll` 下拉刷新（用公开 API 解决，不需私有）

当前 `setContentOffset` 不走 `UIPanGestureRecognizer` 真实手势路径，`UIRefreshControl` 不会真实触发。

**建议**：不改 `ui.scroll` 合成手势（风险高收益低），而是新增公开 API 命令 `ui.scroll.refresh` 或在 `ui.scroll` 加 `triggerRefresh:true`，用 `UIRefreshControl.beginRefreshing()` + 触发 `valueChanged` 让宿主 refresh handler 真实执行。**这是公开 API，完全不需要 runtime 设施。**

### 4.4 不建议迁移的命令（公开 API 已是标准/最佳方案）

`ui.input`（`insertText` 是 iOS 公开「模拟键盘输入」标准 API，触发委托/支持 secure）、`ui.keyboard.dismiss`（resignFirstResponder 就是 Apple 推荐）、`ui.navigation.back`（pop/dismiss 是标准）、`ui.navigation.tapBarButton`（已在用 runtime）、`ui.control.sendAction`（UIControl 程序化触发标准）、`ui.screenshot`（三级回退已覆盖）、`ui.scrollToElement`（`scrollRectToVisible` 官方推荐）、`ui.wait`/`ui.waitAny`（纯查询）。

### 4.5 基调调整未落实的总结

按「基调变了但仍停在公开 API 时代、能力因此受限」的程度排序：
1. **`ui.tap`（最严重）**：走 `sendActions` 不是真实触摸，手势/坐标/遮挡验证全失效。alert.respond 已证明私有 API 迁移能带来质变，tap 是下一个同等量级候选。
2. **`ui.scroll` 下拉刷新路径**（中等）：但建议用公开 API（`beginRefreshing`）解决，不需私有。
3. **`ui.topViewHierarchy`/`ui.viewTargets`**（轻度增强）：加 `recursiveDescription` 能看到私有 view，是「看得不全」非「能力缺失」。
4. **其余 9 个命令**：公开 API 已是标准/最佳，基调调整对它们无实质影响，**不算未落实**。

---

## 5. 综合优先级建议（roadmap）

按「风险×收益×依赖」排序，分三波：

### 第一波：纯清理（低风险，1-2 天）
1. **修 alert 非 Debug 错误码 bug**（§3.1.1）——正确性问题，优先级最高。
2. **删死代码**（§3.1.2 hit-test 错误工厂、§3.1.3 `fingerprints`+`collect`、§3.2 M8 `init(digest:)`）。
3. **修 tap 错误文案/错误码**（§3.1.4）——含同步更新被锁定的测试 `UIKitCommandErrorTests.swift:68`。
4. **修注释过期**（§3.2 M9 悬空注释、M10 反向注释）。

### 第二波：机械重构（中风险，2-3 天）
5. **合并 `UIKitLocator` ↔ `UIKitViewLookupTarget`**（§3.2 M1）。
6. **提取重复样板**（§3.2 M2 adapter helper、M3 陈旧校验、M4 settle/describe、M5 UITextView 排除、M6 path 拼接）。
7. **`UIKitActionKind` CaseIterable**（§3.2 M7）。

### 第三波：基调迁移（高价值高风险，按 spike 结果决策）
8. **`ui.tap` 合成触摸 spike**（§4.2）：iOS 17/18/26 真机验证 UITouch ivar 名稳定性。
9. spike 通过 → `dispatchMode:"realTouch"` + 新增 `unsupported_target` 错误码。
10. **`ui.scroll` 下拉刷新**（§4.3）：公开 API `beginRefreshing`，独立命令或参数。

### 持续约束
- 所有第三波私有 API 代码必须 `#if DEBUG` 隔离，参照 `Support/Runtime/` 既有模式。
- 私有 selector / ivar 名漂移是正常维护成本（`_dismissWithAction:` 已接受这类成本），按 iOS 版本适配，不作为拒绝理由。
- 每波完成后跑 `swift test`（SPM）+ framework `xcodebuild test` + SPMExample 真实闭环三层验证。

---

## 6. 附录：真实闭环验证命令清单（可复现）

```bash
# 1. 构建 + 启动 SPMExample（autostart 自动起 server）
#    XcodeBuildMCP: build_run_sim(launchArgs=["--ios-explore-autostart"])

# 2. Mac 侧 curl 直连模拟器（无需 iproxy）
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'

# 3. 观察主页
curl -X POST http://localhost:38321/ -d '{"action":"ui.viewTargets","data":{}}'

# 4. 进 ControlTest
curl -X POST http://localhost:38321/ -d '{"action":"ui.navigation.tapBarButton","data":{"placement":"right","index":0,"accessibilityIdentifier":"example.controlTest"}}'

# 5. tap 开关（紧凑闭环：observe→立刻 tap）
SNAP=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.viewTargets","data":{}}' | python3 -c "import json,sys;print(json.load(sys.stdin)['data']['viewSnapshotID'])")
curl -X POST http://localhost:38321/ -d "{\"action\":\"ui.tap\",\"data\":{\"accessibilityIdentifier\":\"test.switch\",\"viewSnapshotID\":\"$SNAP\"}}"

# 6. input / scroll
curl -X POST http://localhost:38321/ -d '{"action":"ui.input","data":{"accessibilityIdentifier":"test.textfield","text":"hello","mode":"replace","submit":true}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.scroll","data":{"accessibilityIdentifier":"test.textfield","direction":"down","amount":120}}'

# 7. alert 私有 API 闭环（进 AlertTest → 弹窗 → 真实触发）
curl -X POST http://localhost:38321/ -d '{"action":"ui.navigation.tapBarButton","data":{"placement":"left","index":0}}'
SNAP=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.viewTargets","data":{}}' | python3 -c "import json,sys;print(json.load(sys.stdin)['data']['viewSnapshotID'])")
curl -X POST http://localhost:38321/ -d "{\"action\":\"ui.tap\",\"data\":{\"accessibilityIdentifier\":\"alert.trigger.simple\",\"viewSnapshotID\":\"$SNAP\"}}"
curl -X POST http://localhost:38321/ -d '{"action":"ui.alert.respond","data":{"dryRun":true}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.alert.respond","data":{"dryRun":false,"buttonTitle":"确认"}}'

# 8. waitAny
curl -X POST http://localhost:38321/ -d '{"action":"ui.waitAny","data":{"conditions":[{"id":"a","mode":"textExists","text":"弹出标准 alert"}],"timeoutMs":3000}}'
```

---

## 评估方法说明

- **主会话**：用 `codegraph_explore` 精读 `UIKitActionExecutor` / `UIKitDefaultActivationResolver` / `UIKitActionCapabilityResolver` / `UIAlertRespondExecutor` / `UITextInputExecutor` / `UIScrollExecutor` / `UIKeyboardDismissExecutor` / `UIKitCommandError` / Runtime 三件套，并读完整 `UIKitCommandError.swift` 确认错误体系。
- **代码质量 subagent**：通读 `Sources/iOSExploreUIKit/` 全部 49 文件，用 grep + codegraph_callers 验证每个「死代码 / 重复」断言的调用方。
- **基调迁移 subagent**：逐个命令读实现，区分「公开 API 完全够用」vs「有明显短板」，对短板给具体私有 API 方案与 iOS 版本风险。
- **真实闭环**：主会话在 iPhone 17 模拟器（iOS 26.x）跑 §6 全部命令，记录 envelope 真实返回。
- 三方发现交叉验证（tap slider 错误文案、alert 私有 API 闭环等）后才写入本报告。
