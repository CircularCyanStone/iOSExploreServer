# iOSExploreUIKit 文件档案

> 这是 `Sources/iOSExploreUIKit/` 全部 55 个文件的查阅手册。
> 想知道"从哪开始读"看 [reading-guide.md](./reading-guide.md)；这里按目录逐个登记每个文件的职责、关键点与依赖关系，用于定位与改动。
> 约定：✅ = Foundation-only（macOS `swift test` 可覆盖）；🍎 = `#if canImport(UIKit)`，仅 iOS 编译。
> 目录分两层：`Commands/` 是 12 个对外命令及其紧密配套（adapter + models + collector），`Support/` 是横切辅助（执行引擎 / 定位 / 上下文 / 快照 / 解析 / 等待 / 文本采集），根目录 3 个是模块级横切（注册 / 日志 / 错误）。
> **覆盖范围说明**：keyboard / navigation / wait / scrollToElement / alert 五个新命令、scroll 原语与 wait/alert 辅助类型的逐文件档案见文末「新增命令档案（Task 2-7）」节。`ui.screenshot` / `ui.input` / `ui.scroll` 三个较早命令的逐文件档案仍待补（总览已列），参见各自源码头 `///` 注释。

## 总览

| 目录 | 文件数 | 职责域 |
|---|---|---|
| 根目录 | 3 | 注册入口、日志、错误工厂（被所有层依赖） |
| `Commands/TopViewHierarchy/` | 3 | `ui.topViewHierarchy` 命令（adapter + models + collector） |
| `Commands/ViewTargets/` | 3 | `ui.viewTargets` 命令（adapter + models + collector） |
| `Commands/Screenshot/` | 3 | `ui.screenshot` 命令（adapter + models + collector） |
| `Commands/Tap/` | 2 | `ui.tap` 命令（adapter + models） |
| `Commands/ControlAction/` | 2 | `ui.control.sendAction` 命令（adapter + models） |
| `Commands/Input/` | 2 | `ui.input` 命令（adapter + models） |
| `Commands/Scroll/` | 2 | `ui.scroll` 命令（adapter + models） |
| `Commands/Keyboard/` | 2 | `ui.keyboard.dismiss` 命令（adapter + models） |
| `Commands/Navigation/` | 2 | `ui.navigation.back` 命令（adapter + models） |
| `Commands/Wait/` | 2 | `ui.wait` 命令（adapter + models） |
| `Commands/ScrollToElement/` | 2 | `ui.scrollToElement` 命令（adapter + models） |
| `Commands/Alert/` | 2 | `ui.alert.respond` 命令（adapter + models） |
| `Support/Context/` | 1 | 前台 window / 顶部控制器 |
| `Support/Locator/` | 3 | 定位语义 + 真实 view 解析 + view lookup 模型 |
| `Support/Action/` | 13 | 动作执行引擎 + scroll 原语 + 各命令 executor |
| `Support/Snapshot/` | 3 | 陈旧检测（指纹快照） |
| `Support/Parsing/` | 3 | UIKit command 共享字段、locator input helper、安全数字、底层 parse 错误类型 |
| `Support/Wait/` | 2 | wait 执行核心 + 可见文本采集 |

---

## 根目录

### `UIKitCommandRegistrar.swift` ✅（整体 `#if canImport(UIKit)`）
- **职责**：`public extension ExploreServer` 的注册入口 `registerUIKitCommands()`，把 4 个命令挂到 router。
- **关键点**：core 不自动注册 UIKit 命令，宿主必须显式调用；幂等安全；注册前后打 `uikit.registrar` 日志（started/completed count）。
- **依赖**：4 个 `*Command` 类型。

### `UIKitCommandLogging.swift` ✅
- **职责**：UIKit 模块统一的日志入口（`info`/`error`）。
- **关键点**：core 的 `ExploreLogger` 是 internal，UIKit 模块通过 core 的 public 缝 `ExploreLogging.emitExtension` 复用日志；category 统一 `"command"`。不暴露 core 内部 logger。
- **依赖**：core `ExploreLogging`。

### `UIKitCommandError.swift` ✅
- **职责**：UIKit 命令失败的统一错误工厂（包装 core `ExploreCommandFailure`），**conform `Error`**，是 UIKit 内部唯一可抛出的业务错误。
- **关键点**：所有失败出口走这里，不在调用点散写 code/message/logMessage。throw 化后执行核心 `throw UIKitCommandError`（如 `targetNotFound`/`staleLocator`），由 handler 顶层 `catch` 取 `error.result`（保留业务码），失败日志在顶层一处记 `error.failure.logMessage`。错误码语义：定位/命中类失败 → `.invalidData`；UIKit 上下文不可用 → `.internalError`。
- **依赖**：core `ExploreCommandFailure` / `ExploreError`。

---

## `Support/Parsing/`

### `UIKitQueryNumber.swift` ✅
- **职责**：JSON `Double` → `Int` 的安全转换工具。
- **关键点**：命令协议把 JSON 数字统一表示为 `Double`，直接 `Int()` 会在溢出时触发运行时断言；这里先做有限性/整数性/范围校验。`nonNegativeInteger` 与 `integer(in:)` 两个入口。
- **依赖**：无。

### `UIKitLocatorParseError.swift` ✅
- **职责**：底层 locator/path 文法解析失败的错误类型。
- **关键点**：命令输入主路径已经迁移到 core `CommandInputParseError`；本类型只保留给 `UIKitViewLookupTarget`、`UIKitLocator` 这类 Foundation-only helper。命令 input 层必须把它转换为 `CommandInputParseError`，再由 `AnyCommand` 转成 `invalid_data` envelope。
- **依赖**：core `Foundation`。

### `UIKitCommandFields.swift` ✅
- **职责**：UIKit 命令复用的 `CommandField` 定义与 locator input helper。
- **关键点**：`UIKitFilterFields` 只服务查询筛选字段，`UIKitLocatorFields` 只服务交互定位字段，避免同名 key 的 description 被硬套。`UIKitLocatorInput.parse` 通过 core `CommandInputDecoder.read` 读取字段，再复用底层 `UIKitViewLookupTarget.parse`，并把 `UIKitLocatorParseError` 转成 `CommandInputParseError`。
- **依赖**：core `CommandFields`/`CommandInputDecoder`/`CommandInputParseError`、`UIKitViewLookupTarget`。
- **被调用**：`UIViewTargetsInput`、`UIViewHierarchyInput`、`UITapInput`、`UIControlSendActionInput`。

---

## `Support/Context/`

### `UIKitContextProvider.swift` 🍎
- **职责**：`@MainActor` 上下文提供者，取当前前台 window / 根控制器 / 顶部控制器 / 根 view。
- **关键点**：是 UIKit 命令进入 MainActor 隔离域的第一个入口。`Context` 持有 UIKit 对象**不可跨 MainActor 边界传递**。`currentContext(action:) throws`——window/rootVC/view 不可用时直接 `throw UIKitCommandError.hierarchyUnavailable(action:reason:)`（调用方传入自己的 action 做日志关联）。`topViewController` 递归穿透 presentedVC / nav / tab / split。
- **依赖**：UIKit、`UIKitCommandError`。
- **被调用**：所有 collector、executor 都先取它。

---

## `Support/Locator/`

### `UIKitLocator.swift` ✅
- **职责**：统一目标定位器（identifier / path / windowPoint 三种语义收敛到一个枚举）。
- **关键点**：Foundation-only 值类型，可在 macOS 测试覆盖。`parse` 处理 view 定位与坐标定位的互斥关系。
- **依赖**：`UIKitViewLookupTarget`（path 文法复用）。

### `UIKitLocatorResolver.swift` 🍎
- **职责**：`@MainActor`，把 `UIKitLocator` 解析为真实 `UIView`。
- **关键点**：`locate(locator:in:notFound:ambiguous:) throws -> LocatedView`——命中失败时抛出**由调用方提供的** `UIKitCommandError`（两个工厂闭包）。因为 tap 与 control 对「未找到 / 歧义」映射到不同错误码（`targetNotFound` vs `controlTargetNotFound`），定位器不持有调用语境，交由调用方决定。identifier 匹配多个时用 `ambiguous(count)` 工厂。还提供 `nearestControl`（向上找最近 UIControl）与祖先关系判断。`windowPoint` 不在此解析（交给 executor hit-test）。
- **依赖**：UIKit、`UIKitLocator`、`UIKitViewLookupTarget.pathString`、`UIKitCommandError`。
- **被调用**：executor。

### `UIKitViewLookupModels.swift` ✅
- **职责**：UIKit view 的通用定位目标 `UIKitViewLookupTarget`（identifier / path 二选一）。
- **关键点**：path 文法解析（`root/0/2`）；`identifier` 与 `path` 互斥校验；交互执行前桥接为统一 `UIKitLocator`。**`accessibilityIdentifier` 完整匹配、不截断**。
- **依赖**：`UIKitLocator`、`UIKitTargetFingerprint.stableHash`（仅日志脱敏用）。

---

## `Support/Action/`（执行引擎核心）

### `UIKitActionKind.swift` ✅
- **职责**：UIKit 可执行动作的语义类型 + 可用性摘要 `UIKitActionAvailability`。
- **关键点**：`tap` + 6 个 `control.*` case；rawValue 与 executor 实际支持行为一一对应；`availableActions` 由它序列化，是 agent 判断目标可执行性的唯一动作依据。
- **依赖**：无。

### `UIKitActionPlan.swift` ✅
- **职责**：动作执行意图（tap / controlEvent 两种 case 的枚举）。
- **关键点**：Foundation-only，只描述"做什么 + 作用在哪个 locator"，不持 UIKit 对象；携带可选 snapshotID。
- **依赖**：`UIKitLocator`、`UIControlSendActionEvent`。

### `UIKitActionCapabilityResolver.swift` 🍎
- **职责**：`@MainActor`，解析"某个 view 当前能执行哪些动作"。
- **关键点**：**collector 与 executor 共用本类型**，保证"声明可执行"与"实际可派发"走同一份规则。disabled 控件一律返回空集合。规则：`UITextField` → 编辑三件套；值型控件 → `valueChanged`；其余 → touchDown/UpInside。
- **依赖**：UIKit、`UIKitActionAvailability`、`UIControlSendActionEvent`。
- **被调用**：`UIViewTargetsCollector.availableActions`、`UIKitActionExecutor`。

### `UIKitActionExecutor.swift` 🍎
- **职责**：`@MainActor`，tap 与 control.sendAction 的实际 UIKit 执行入口。
- **关键点**：**全模块执行核心**。`execute(_:) throws -> JSON` / `execute(_:context:) throws -> JSON`——成功返回纯 `JSON`，失败 `throw UIKitCommandError`。固定流程：取 Context → resolve locator（线性 `try`）→ 陈旧校验（仅 `.path + snapshotID`）→ 能力校验 → hit-test（tap）/ `sendActions(for:)`（control）。复用调用方已 locate 的 `LocatedView` 避免二次遍历。失败日志不在执行器内记——统一由 handler 顶层 `catch` 后记 `error.failure.logMessage`。有 `execute(_:context:)` 注入入口供测试。
- **依赖**：UIKit、`UIKitContextProvider`、`UIKitLocatorResolver`、`UIKitActionCapabilityResolver`、`UIKitSnapshotStore`、`UIKitFingerprintCollector`、`UIKitCommandError`、`UIKitCommandLogging`。
- **被调用**：`UITapCommand`、`UIControlSendActionCommand`。

---

## `Support/Snapshot/`（陈旧检测）

### `UIKitSnapshotStore.swift` ✅（类标 `@MainActor`，但内部纯计算可 macOS 测）
- **职责**：UIKit 视图树指纹快照存储，解决"path 陈旧"问题。
- **关键点**：查询命令签发 snapshotID 返回给调用方；交互命令携带它时，executor 执行前用 `isStale(snapshotID:path:context:current:) -> Bool` 比对指纹，true 时 `throw UIKitCommandError.staleLocator`（`invalid_data`，固定消息 "locator is stale; re-query"）。容量 **8 条快照 × 每条最多 512 指纹**，TTL **10 秒**，淘汰策略"先过期后 LRU"。时间可注入（`setNow`），测试推进时间即可触发过期。
- **依赖**：`UIKitCommandLogging`。
- **被调用**：两个 collector（insert）、executor（isStale）。

### `UIKitSnapshotResponse.swift` ✅
- **职责**：snapshot 签发结果 → 响应字段的统一映射。
- **关键点**：两个查询命令都用它回写 `snapshotID` / `snapshotUnavailableReason`，避免响应 schema 漂移。超限未签发时显式给 `snapshotUnavailableReason = "fingerprintLimit"`，不静默降级。
- **依赖**：core `JSONValue`。

### `UIKitFingerprintCollector.swift` 🍎
- **职责**：`@MainActor`，从真实 `UIView` 构造 `UIKitTargetFingerprint`。
- **关键点**：**identifier 只存稳定哈希（FNV-1a），不存原文**，避免泄露用户输入。context identity 用 `ObjectIdentifier`（进程内实例身份，检测 window/控制器是否换了新实例）。
- **依赖**：UIKit、`UIKitTargetFingerprint`、`UIKitSnapshotContext`、`UIKitViewLookupTarget.pathString`。
- **被调用**：两个 collector、executor（重采比对）。

---

## `Commands/Tap/`（`ui.tap`）

### `UITapModels.swift` ✅
- **职责**：`UITapInput` + `UITapTarget`（view 目标 / windowPoint 目标）。
- **关键点**：conform core `CommandInput`；字段定义同时驱动解析和 `help.inputSchema`。view 目标与坐标目标互斥；`x/y` 必须成对；`coordinateSpace` 第一版仅支持 `window` 且只对坐标目标有效；`snapshotID` 只允许搭配 `path`。
- **依赖**：core `CommandInput`/`CommandFields`、`UIKitCommandFields`、`UIKitViewLookupTarget`、`UIKitLocator`。

### `UITapCommand.swift` 🍎
- **职责**：`ui.tap` 命令 adapter。
- **关键点**：薄 adapter——typed input 已由 `AnyCommand` 解析完成；handler 构造 `UIKitActionPlan.tap` → `try await executor.execute(plan)`；只 catch `UIKitCommandError` 取 `error.result`（记 `logMessage`）。执行逻辑全在 executor。
- **依赖**：`UITapInput`、`UIKitActionPlan`、`UIKitActionExecutor`、`UIKitCommandError`、`UIKitCommandLogging`。

---

## `Commands/ControlAction/`（`ui.control.sendAction`）

### `UIControlSendActionModels.swift` ✅
- **职责**：`UIControlSendActionInput` + `UIControlSendActionEvent`。
- **关键点**：conform core `CommandInput`；`event` 必填且来自枚举；`accessibilityIdentifier` 与 `path` 必须二选一；`snapshotID` 只允许搭配 `path`；目标类型直接使用 `UIKitViewLookupTarget`。
- **依赖**：core `CommandInput`/`CommandFields`、`UIKitCommandFields`、`UIKitViewLookupTarget`。

### `UIControlSendActionCommand.swift` 🍎
- **职责**：`ui.control.sendAction` 命令 adapter。
- **关键点**：薄 adapter——typed input 已由 `AnyCommand` 解析完成；handler 构造 `UIKitActionPlan.controlEvent` → `try await executor.execute(plan)`；只 catch `UIKitCommandError`。
- **依赖**：`UIControlSendActionInput`、`UIKitActionPlan`、`UIKitActionExecutor`、`UIKitCommandError`、`UIKitCommandLogging`。

---

## `Commands/TopViewHierarchy/`（`ui.topViewHierarchy`）

### `UIViewHierarchyModels.swift` ✅（最大文件）
- **职责**：完整层级快照的全部模型——矩形/accessibility/状态/文本/外观/控件/图片/滚动 8 类验收字段 + 查询参数 + `UIViewHierarchyElement` 协议 + `UIViewHierarchyBuilder`。
- **关键点**：`UIViewHierarchyInput` conform core `CommandInput`，字段定义同时驱动解析和 schema；`UIViewHierarchyElement` 协议把递归/路径/筛选逻辑与 UIKit 解耦（真实采集器和测试 fake 都复用同一套 builder）；`detailLevel`（basic/appearance/full）控制是否输出文本/颜色等高成本字段；支持 identifier 精确/前缀筛选。
- **依赖**：core `CommandInput`/`CommandFields`/`JSON`/`JSONValue`、`UIKitCommandFields`。

### `UIViewHierarchyCollector.swift` 🍎
- **职责**：`@MainActor`，从真实 `UIView` 递归读取属性生成完整快照。
- **关键点**：`collectTopViewHierarchy(query:) throws -> JSON`（无 context 入口，取真实 context 失败 throw `hierarchyUnavailable`）；`collectTopViewHierarchy(query:context:) -> JSON`（注入入口，测试用）。`UIKitViewElement` 是 `UIViewHierarchyElement` 的 UIKit 实现；读 UIKit 后交给 Foundation-only 的 `UIViewHierarchyBuilder`。还签发 snapshot（含完整树指纹）。
- **依赖**：UIKit、`UIKitContextProvider`、`UIKitFingerprintCollector`、`UIKitSnapshotStore`、`UIKitSnapshotResponse`、`UIViewHierarchyBuilder`/`UIViewHierarchyModels`、`UIKitCommandError`/`UIKitCommandLogging`。

### `TopViewHierarchyCommand.swift` 🍎
- **职责**：`ui.topViewHierarchy` 命令 adapter。
- **关键点**：薄 adapter——typed input 已由 `AnyCommand` 解析完成；handler `try await collector`；有 identifier 筛选时返回 `matches` 列表，否则返回完整 `root` 树。
- **依赖**：`UIViewHierarchyInput`、`UIViewHierarchyCollector`、`UIKitCommandError`、`UIKitCommandLogging`。

---

## `Commands/ViewTargets/`（`ui.viewTargets`）

### `UIViewTargetsModels.swift` ✅
- **职责**：轻量目标的全部模型——`UIViewTargetsInput` + `UIViewTargetCandidate` + `UIViewTargetSummary` + 角色/状态/文本裁剪。
- **关键点**：`UIViewTargetsInput` conform core `CommandInput`，字段定义同时驱动解析和 schema；**`UIViewTargetsInput.shouldInclude` 是目标发现决策核心**，纯 Foundation-only 逻辑。默认包含策略：控件全部包含、有手势/有 identifier/有 label 的可交互节点包含；静态文本与容器默认排除。`maxTargets` 默认 200（上限 512），`textLimit` 默认 80（上限 200）。**identifier 完整不裁剪**，只裁剪展示型文本。
- **依赖**：core `CommandInput`/`CommandFields`、`UIKitCommandFields`、`UIKitSnapshotLimits`、`UIKitActionAvailability`、`UIViewHierarchyRect`。

### `UIViewTargetsCollector.swift` 🍎
- **职责**：`@MainActor`，递归遍历 view 树采集轻量目标摘要。
- **关键点**：`collect(query:) throws -> JSON`（无 context 入口）；`collect(query:context:) -> JSON`（注入入口）。刻意不复用完整层级快照（不读颜色/字体/图片）。identifier 筛选不提前剪枝子树。**`availableActions` 只认目标自身的 control 身份**（不向上借祖先 control），避免与 executor 的 path 派发分叉。
- **依赖**：UIKit、`UIKitContextProvider`、`UIKitFingerprintCollector`、`UIKitSnapshotStore`、`UIKitSnapshotResponse`、`UIKitActionCapabilityResolver`、`UIViewTargetsModels`、`UIKitCommandError`/`UIKitCommandLogging`。

### `ViewTargetsCommand.swift` 🍎
- **职责**：`ui.viewTargets` 命令 adapter。
- **关键点**：薄 adapter——typed input 已由 `AnyCommand` 解析完成；handler `try await collector`。响应含 `targetCount`/`visitedNodeCount`/`truncated`/`snapshotID`。
- **依赖**：`UIViewTargetsInput`、`UIViewTargetsCollector`、`UIKitCommandError`、`UIKitCommandLogging`。

---

## 新增命令档案（Task 2-7）

> 以下为 agent 常用命令 v2（`docs/superpowers/plans/2026-07-01-agent-common-commands.md`）新增文件。adapter/models 保持 Foundation-only（✅），executor/inspector/collector 整体 `#if canImport(UIKit)`（🍎）。

### `Commands/Keyboard/`（`ui.keyboard.dismiss`）

- **`UIKeyboardDismissModels.swift`** ✅ — `KeyboardDismissStrategy`（auto/resignFirstResponder/endEditing）+ `UIKeyboardDismissInput`。strategy 用 `CommandFields.enumValue`、waitAfterMs 用 `CommandFields.int(range: 0...3000, default: 200)`；parse 读全 `Fields.all`。
- **`UIKeyboardDismissCommand.swift`** 🍎 — 薄 adapter：`MainActor.run` 取 context → 同步 executor；顶层 catch `UIKitCommandError` 转 envelope。

### `Commands/Navigation/`（`ui.navigation.back`）

- **`UINavigationBackModels.swift`** ✅ — `NavigationBackStrategy`（auto/navigationController/dismiss）+ `UINavigationBackInput`（animated 默认 false，waitAfterMs 默认 300）。
- **`UINavigationBackCommand.swift`** 🍎 — 薄 adapter，模式同 keyboard。

### `Commands/Wait/`（`ui.wait`）

- **`UIWaitModels.swift`** ✅ — `WaitMode`（idle/targetExists/targetGone/textExists/snapshotChanged）+ `UIWaitInput`。mode 决定字段需求（targetExists/targetGone 需 locator、textExists 需 text、snapshotChanged 需 snapshotID）；timeoutMs 0...30000、intervalMs 50...5000、stableMs 0...10000；target 复用 `UIKitLocatorInput.parseOptional`。
- **`UIWaitCommand.swift`** 🍎 — adapter，`timeoutNanoseconds = 35s`（命令级兜底高于最大业务 timeoutMs）；executor 是 `@MainActor async`，adapter 直接 `await`（不用 `MainActor.run`）。

### `Commands/ScrollToElement/`（`ui.scrollToElement`）

- **`UIScrollToElementModels.swift`** ✅ — `ScrollToElementMatch`（text/accessibilityIdentifier）+ `UIScrollToElementInput`（value 必填，container 可选）。
- **`UIScrollToElementCommand.swift`** 🍎 — 薄 adapter，`MainActor.run` 取 context → 同步 executor。

### `Commands/Alert/`（`ui.alert.respond`）

- **`UIAlertRespondModels.swift`** ✅ — `AlertButtonRole`（default/cancel/destructive）+ `UIAlertRespondInput`（dryRun 默认 true，buttonTitle/buttonIndex/role 互斥）。
- **`UIAlertRespondCommand.swift`** 🍎 — 薄 adapter，`MainActor.run` 取 context → 同步 executor。

### `Support/Wait/`

- **`UIKitVisibleTextCollector.swift`** 🍎 — `@MainActor`，递归采集可见文本（UILabel.text/UIButton.currentTitle/UITextField.placeholder/accessibilityLabel/非编辑态 accessibilityValue）。**有意不收集 UITextField.text/UITextView.text**（用户输入，防泄露），与 `UIViewHierarchyCollector.textInfo` 分工。被 `UIWaitExecutor` 的 textExists/idle 用。
- **`UIWaitExecutor.swift`** 🍎 — `@MainActor async`，按 intervalMs 轮询至满足或 deadline。`DispatchTime.uptimeNanoseconds` 做 deadline；sleep clamp 到剩余 deadline（业务 waitTimeout 先于命令级 35s）；`try? Task.sleep` 吞 cancellation + `Task.isCancelled` 收敛到 waitTimeout。5 模式：idle（活动签名连续 stableMs 不变）/ targetExists·targetGone（resolver.contains）/ textExists（VisibleTextCollector）/ snapshotChanged（store.contextMatches 检测页面身份变化）。注入 contextProvider 便于测试。

### `Support/Action/` 新增

- **`UIScrollResolver.swift`** 🍎 — `@MainActor`，滚动容器解析（ui.scroll/scrollToElement 共享）。`resolveFromTarget`（locator=target → 最近 scrollView 祖先）+ `resolveContainer`（locator=容器自身，scrollToElement）；都排除 UITextView。`Resolved` 持 UIScrollView，**仅 @MainActor 不 Sendable**。
- **`UIScrollGeometry.swift`** 🍎 — `@MainActor`，滚动几何（defaultDistance/delta/reachedExtent/step + `UIScrollStepResult.toJSON`），全基于 `adjustedContentInset` + 1pt 容差。ui.scroll 与 scrollToElement 共享，防行为漂移。
- **`UIKeyboardDismissExecutor.swift`** 🍎 — `@MainActor`，first responder 查找与收起。无 responder 时 success noop（dismissed=false）；auto 先 resign 再 endEditing(true)；失败 throw `keyboardDismissFailed`；settle 用 RunLoop。
- **`UINavigationBackExecutor.swift`** 🍎 — `@MainActor`，dismiss/pop 决策。auto 先 dismiss（presenting!=nil）再 navigationController pop（count>1）；返回**实际生效策略**；不可用 throw `navigationBackUnavailable`。
- **`UIScrollToElementExecutor.swift`** 🍎 — `@MainActor`，容器内 findTarget + `scrollRectToVisible`。用 UIKit 原生（自动最短滚动、保证可见），替代循环小步 scroll 避免污染 snapshot store（评审 M3）；不签 snapshot（agent 应重新 screenshot）。
- **`UIAlertInspector.swift`** 🍎 — `@MainActor`，`findAlert`（cast topViewController）+ `summarize`（actions 的 index/title/role）。不依赖 present 转场（评审 M7），logic test 可靠。
- **`UIAlertRespondExecutor.swift`** 🍎 — `@MainActor`，query-first。dryRun=true 返回 alert 信息；dryRun=false 暂抛 `alertButtonRequired`（UIAlertAction 点击私有路径未 spike，不直接点）。

---

## 相关设计文档

| 主题 | 文档 |
|---|---|
| 模块整体架构（typed factory、隔离边界） | `docs/superpowers/specs/2026-06-23-uikit-command-extension-architecture-design.md` |
| throw 化 + 文件夹重组 | `docs/superpowers/specs/2026-06-24-uikit-throw-and-folder-reorg-design.md` |
| typed command input 与 inputSchema 重构 | `docs/superpowers/specs/2026-06-25-typed-command-input-schema-design.md` |
| `ui.topViewHierarchy` 设计 | `docs/superpowers/specs/2026-06-22-uikit-view-hierarchy-design.md` |
| `ui.viewTargets` 设计 | `docs/superpowers/specs/2026-06-23-uikit-view-targets-design.md` |
| view targets 加固（identifier 不截断、能力一致性） | `docs/superpowers/specs/2026-06-24-uikit-view-targets-hardening-design.md` |
| core 协议总设计 | `docs/superpowers/specs/2026-06-21-ios-explore-server-design.md` |
