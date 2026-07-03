# iOSExploreUIKit 文件档案

> 这是 `Sources/iOSExploreUIKit/` 全部 61 个文件的查阅手册。
> 想知道"从哪开始读"看 [reading-guide.md](./reading-guide.md)；这里按目录逐个登记每个文件的职责、关键点与依赖关系，用于定位与改动。
> 约定：✅ = Foundation-only（macOS `swift test` 可覆盖）；🍎 = `#if canImport(UIKit)`，仅 iOS 编译。
> 目录分两层：`Commands/` 是 12 个对外命令及其紧密配套（adapter + models + collector），`Support/` 是横切辅助（执行引擎 / 定位 / 上下文 / 快照 / 解析 / 等待 / 文本采集），根目录 3 个是模块级横切（注册 / 日志 / 错误）。
> **覆盖范围说明**：keyboard / navigation / wait / scrollToElement / alert 五个新命令、scroll 原语与 wait/alert 辅助类型的逐文件档案见文末「新增命令档案（Task 2-7）」节；navigationBar 可达性（`ui.navigation.tapBarButton` + inspector/executor）见「NavigationBar 可达性档案」节；`ui.tap` 重构新增的 `UIKitDefaultActivationResolver` / `UIKitTargetSemanticDigest` 见各自节。`ui.screenshot` / `ui.input` / `ui.scroll` 三个较早命令的逐文件档案仍待补（总览已列），参见各自源码头 `///` 注释；其中 `ui.screenshot` 已不再签发 `viewSnapshotID`（只作可选视觉证据）。

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
| `Commands/Navigation/` | 4 | `ui.navigation.back` + `ui.navigation.tapBarButton` 命令（各 adapter + models） |
| `Commands/Wait/` | 4 | `ui.wait` + `ui.waitAny` 命令（各 adapter + models） |
| `Commands/ScrollToElement/` | 2 | `ui.scrollToElement` 命令（adapter + models） |
| `Commands/Alert/` | 2 | `ui.alert.respond` 命令（adapter + models） |
| `Support/Context/` | 1 | 前台 window / 顶部控制器 |
| `Support/Locator/` | 3 | 定位语义 + 真实 view 解析 + view lookup 模型 |
| `Support/Action/` | 15 | 动作执行引擎 + 默认激活路由 + scroll 原语 + 各命令 executor |
| `Support/Snapshot/` | 4 | 陈旧检测（指纹快照 + 语义摘要） |
| `Support/Navigation/` | 1 | navigationBar 检查器（读 navigationItem 摘要） |
| `Support/Parsing/` | 3 | UIKit command 共享字段、locator input helper、安全数字、底层 parse 错误类型 |
| `Support/Wait/` | 2 | wait 执行核心 + 可见文本采集 |

---

## 根目录

### `UIKitCommandRegistrar.swift` ✅（整体 `#if canImport(UIKit)`）
- **职责**：`public extension ExploreServer` 的注册入口 `registerUIKitCommands()`，把 14 个命令挂到 router。
- **关键点**：core 不自动注册 UIKit 命令，宿主必须显式调用；幂等安全；注册前后打 `uikit.registrar` 日志（started/completed count）。
- **依赖**：14 个 `*Command` 类型。

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
- **职责**：统一目标定位器（identifier / path 两种语义收敛到一个枚举）。
- **关键点**：Foundation-only 值类型，可在 macOS 测试覆盖。`parse` 处理 identifier 与 path 的互斥关系（坐标定位/windowPoint 已移除）。
- **依赖**：`UIKitViewLookupTarget`（path 文法复用）。

### `UIKitLocatorResolver.swift` 🍎
- **职责**：`@MainActor`，把 `UIKitLocator` 解析为真实 `UIView`。
- **关键点**：`locate(locator:in:notFound:ambiguous:) throws -> LocatedView`——命中失败时抛出**由调用方提供的** `UIKitCommandError`（两个工厂闭包）。因为 tap 与 control 对「未找到 / 歧义」映射到不同错误码（`targetNotFound` vs `controlTargetNotFound`），定位器不持有调用语境，交由调用方决定。identifier 匹配多个时用 `ambiguous(count)` 工厂。仅做 identifier/path 精确解析，**不再提供 `nearestControl` 祖先 fallback**（executor 不再做 hit-test / 祖先兜底）。
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
- **关键点**：Foundation-only，只描述"做什么 + 作用在哪个 locator"，不持 UIKit 对象；**tap / controlEvent 均携带必填 `viewSnapshotID`**（由 `ui.viewTargets` 签发，executor 执行前做陈旧校验）。
- **依赖**：`UIKitLocator`、`UIControlSendActionEvent`。

### `UIKitActionCapabilityResolver.swift` 🍎
- **职责**：`@MainActor`，解析"某个 UIControl 当前能执行哪些 control event 动作"。
- **关键点**：被 `UIViewTargetsCollector` 用来声明 `availableActions`。disabled 控件一律返回空集合。规则：`UITextField` → 编辑三件套；值型控件 → `valueChanged`；其余 → touchDown/UpInside。**tap 的默认激活路由判定已拆到 `UIKitDefaultActivationResolver`**（本类型不再判 tap）；UISlider/UISegmentedControl 无默认激活路由，tap 会返回 `unsupported_target`。executor 不再调用本类型做祖先 fallback 校验。
- **依赖**：UIKit、`UIKitActionAvailability`、`UIControlSendActionEvent`。
- **被调用**：`UIViewTargetsCollector.availableActions`。

### `UIKitActionExecutor.swift` 🍎
- **职责**：`@MainActor`，tap 与 control.sendAction 的实际 UIKit 执行入口。
- **关键点**：**全模块执行核心**。`execute(_:) throws -> JSON` / `execute(_:context:) throws -> JSON`——成功返回纯 `JSON`，失败 `throw UIKitCommandError`。固定流程：取 Context → resolve locator（线性 `try`）→ **`viewSnapshotID` 陈旧校验（必填，`validateViewSnapshot`）** → tap 走默认激活路由（`UIKitDefaultActivationResolver`，不做 hit-test / 坐标 / 祖先 fallback）/ control 走 `sendActions(for:)`。复用调用方已 locate 的 `LocatedView` 避免二次遍历。失败日志不在执行器内记——统一由 handler 顶层 `catch` 后记 `error.failure.logMessage`。有 `execute(_:context:)` 注入入口供测试。
- **依赖**：UIKit、`UIKitContextProvider`、`UIKitLocatorResolver`、`UIKitDefaultActivationResolver`、`UIKitSnapshotStore`、`UIKitFingerprintCollector`、`UIKitCommandError`、`UIKitCommandLogging`。
- **被调用**：`UITapCommand`、`UIControlSendActionCommand`。

### `UIKitDefaultActivationResolver.swift` 🍎
- **职责**：`@MainActor`，`ui.tap` 的"默认激活动作"路由判定（按 target 类型派发，非触摸注入）。
- **关键点**：V1 路由表：`UIButton` → `sendActions(.touchUpInside)`（`activationRoute = control.touchUpInside`）；`UISwitch` → `setOn(!isOn)` + `sendActions(.valueChanged)`（`switch.toggle`，响应含 `previousValue`/`currentValue`）；`UITextField`/`UITextView` → `becomeFirstResponder`（`input.focus`，响应含 `isFirstResponder`，失败复用 `becomeFirstResponderFailed` 错误码）。`UISlider`/`UISegmentedControl`/普通 `UIView` 无默认激活路由 → executor 返回 `unsupported_target`。navigationBar 走 `ui.navigation.tapBarButton`、alert 走专用命令，均不并入本路由。
- **依赖**：UIKit、`UIKitCommandError`、`UIKitCommandLogging`。
- **被调用**：`UIKitActionExecutor`（tap 分支）。

---

## `Support/Snapshot/`（陈旧检测）

### `UIKitSnapshotStore.swift` ✅（类标 `@MainActor`，但内部纯计算可 macOS 测）
- **职责**：UIKit 视图树指纹快照存储，解决"path 陈旧"问题。
- **关键点**：**仅 `ui.viewTargets` 签发 `viewSnapshotID` 返回给调用方**（`ui.screenshot` / `ui.topViewHierarchy` 不再签发）；交互命令携带它时，executor 执行前用 `isStale(viewSnapshotID:path:context:current:) -> Bool` 比对指纹（含 `semanticDigest`），true 时 `throw UIKitCommandError.staleLocator`（`invalid_data`，固定消息 "locator is stale; call ui.viewTargets first"）。容量 **8 条快照 × 每条最多 512 指纹**，TTL **30 秒**，淘汰策略"先过期后 LRU"。时间可注入（`setNow`），测试推进时间即可触发过期。
- **依赖**：`UIKitCommandLogging`。
- **被调用**：`UIViewTargetsCollector`（insert）、executor（isStale）。

### `UIKitSnapshotResponse.swift` ✅
- **职责**：snapshot 签发结果 → 响应字段的统一映射。
- **关键点**：`ui.viewTargets` 用它回写 `viewSnapshotID` / `snapshotUnavailableReason`，避免响应 schema 漂移。超限未签发时显式给 `snapshotUnavailableReason = "fingerprintLimit"`，不静默降级。
- **依赖**：core `JSONValue`。

### `UIKitFingerprintCollector.swift` 🍎
- **职责**：`@MainActor`，从真实 `UIView` 构造 `UIKitTargetFingerprint`。
- **关键点**：**identifier 只存稳定哈希（FNV-1a），不存原文**，避免泄露用户输入。context identity 用 `ObjectIdentifier`（进程内实例身份，检测 window/控制器是否换了新实例）。指纹含 `UIKitTargetSemanticDigest`（按钮标题 / a11y label / a11y value / switch isOn / segment index / 默认激活路由 的稳定哈希），参与陈旧检测。
- **依赖**：UIKit、`UIKitTargetFingerprint`、`UIKitTargetSemanticDigest`、`UIKitSnapshotContext`、`UIKitViewLookupTarget.pathString`。
- **被调用**：`UIViewTargetsCollector`、executor（重采比对）。

### `UIKitTargetSemanticDigest.swift` 🍎
- **职责**：`@MainActor`，从 `UIView` 抽取语义摘要的稳定哈希（`semanticDigest`）。
- **关键点**：摘要维度：按钮标题 / accessibilityLabel / accessibilityValue / `UISwitch.isOn` / `UISegmentedControl.selectedSegmentIndex` / 默认激活路由。哈希后写入 `UIKitTargetFingerprint`，与 path/类名/context identity 一起参与 `isStale` 陈旧判定——目标"还是同一个且语义未变"才算未陈旧。只存哈希不存原文，避免泄露用户文本。
- **依赖**：UIKit、`UIKitTargetFingerprint.stableHash`。
- **被调用**：`UIKitFingerprintCollector`。

---

## `Commands/Tap/`（`ui.tap`）

### `UITapModels.swift` ✅
- **职责**：`UITapInput`（`ui.tap` 的 typed input）。
- **关键点**：conform core `CommandInput`；字段定义同时驱动解析和 `help.inputSchema`。**只接受 `accessibilityIdentifier` 或 `path`（二选一）+ 必填 `viewSnapshotID`**；已删除 `x`/`y`/`coordinateSpace`/`window` 坐标输入与 `UITapTarget`（目标直接复用 `UIKitViewLookupTarget`）。`ui.tap` 现是"默认激活动作"（非触摸注入），按 target 类型路由；成功响应字段为 `activated`/`activationRoute`（control.touchUpInside | switch.toggle | input.focus）/`path`/`type`/`event`（switch 另有 previousValue/currentValue，input 另有 isFirstResponder）。旧字段 `tapped`/`dispatchMode=controlActionFallback`/`x`/`y`/`hitPath`/`hitType`/`controlPath` 已删除。
- **依赖**：core `CommandInput`/`CommandFields`、`UIKitCommandFields`、`UIKitViewLookupTarget`。

### `UITapCommand.swift` 🍎
- **职责**：`ui.tap` 命令 adapter。
- **关键点**：薄 adapter——typed input 已由 `AnyCommand` 解析完成；handler 构造 `UIKitActionPlan.tap` → `try await executor.execute(plan)`；只 catch `UIKitCommandError` 取 `error.result`（记 `logMessage`）。执行逻辑全在 executor。
- **依赖**：`UITapInput`、`UIKitActionPlan`、`UIKitActionExecutor`、`UIKitCommandError`、`UIKitCommandLogging`。

---

## `Commands/ControlAction/`（`ui.control.sendAction`）

### `UIControlSendActionModels.swift` ✅
- **职责**：`UIControlSendActionInput` + `UIControlSendActionEvent`。
- **关键点**：conform core `CommandInput`；`event` 必填且来自枚举；`accessibilityIdentifier` 与 `path` 必须二选一；**`viewSnapshotID` 必填**；目标类型直接使用 `UIKitViewLookupTarget`，executor 解析后要求 target 自身必须是 `UIControl`（不做 hit-test / 祖先 fallback）。
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
- **关键点**：`collectTopViewHierarchy(query:) throws -> JSON`（无 context 入口，取真实 context 失败 throw `hierarchyUnavailable`）；`collectTopViewHierarchy(query:context:) -> JSON`（注入入口，测试用）。`UIKitViewElement` 是 `UIViewHierarchyElement` 的 UIKit 实现；读 UIKit 后交给 Foundation-only 的 `UIViewHierarchyBuilder`。**不再签发 viewSnapshotID**（纯观察职责；动作所需的 `viewSnapshotID` 由 `ui.viewTargets` 签发）。
- **依赖**：UIKit、`UIKitContextProvider`、`UIViewHierarchyBuilder`/`UIViewHierarchyModels`、`UIKitCommandError`/`UIKitCommandLogging`。

### `TopViewHierarchyCommand.swift` 🍎
- **职责**：`ui.topViewHierarchy` 命令 adapter。
- **关键点**：薄 adapter——typed input 已由 `AnyCommand` 解析完成；handler `try await collector`；有 identifier 筛选时返回 `matches` 列表，否则返回完整 `root` 树。
- **依赖**：`UIViewHierarchyInput`、`UIViewHierarchyCollector`、`UIKitCommandError`、`UIKitCommandLogging`。

---

## `Commands/ViewTargets/`（`ui.viewTargets`）

### `UIViewTargetsModels.swift` ✅
- **职责**：轻量目标的全部模型——`UIViewTargetsInput` + `UIViewTargetCandidate` + `UIViewTargetSummary` + 角色/状态/文本裁剪。
- **关键点**：`UIViewTargetsInput` conform core `CommandInput`，字段定义同时驱动解析和 schema；**`UIViewTargetsInput.shouldInclude` 是 canonical 目标发现决策核心**，纯 Foundation-only 逻辑。**包含策略改为 canonical-only**：只含 UIControl 系（UIButton/UISwitch/UISlider/UISegmentedControl/UITextField/自定义 UIControl）+ UIScrollView 系（UIScrollView/UITableView/UICollectionView/UITextView）；普通 UILabel / container / gesture-only view / 仅 identifier 或 label 的普通 view 不再进 targets（观察职责在 `ui.topViewHierarchy`）。按钮内部 label/image 不作为独立 target，文本汇总到父 target 的 `semanticText`。disabled control 仍 include（`availableActions` 为空）。`maxTargets` 默认 200（上限 512），`textLimit` 默认 80（上限 200）。**identifier 完整不裁剪**，只裁剪展示型文本。
- **依赖**：core `CommandInput`/`CommandFields`、`UIKitCommandFields`、`UIKitSnapshotLimits`、`UIKitActionAvailability`、`UIViewHierarchyRect`。

### `UIViewTargetsCollector.swift` 🍎
- **职责**：`@MainActor`，递归遍历 view 树采集 canonical 轻量目标摘要并签发 `viewSnapshotID`。
- **关键点**：`collect(query:) throws -> JSON`（无 context 入口）；`collect(query:context:) -> JSON`（注入入口）。刻意不复用完整层级快照（不读颜色/字体/图片）。identifier 筛选不提前剪枝子树。**`availableActions` 只认目标自身的 control 身份**（不向上借祖先 control）。**不变式**：returned target paths == `viewSnapshotID` 签发的 fingerprint paths == tap/sendAction 可执行 paths（`maxTargets` 截断后只为最终 returned targets 签发指纹）。响应字段是 `viewSnapshotID`（不是 `snapshotID`）。
- **依赖**：UIKit、`UIKitContextProvider`、`UIKitFingerprintCollector`、`UIKitSnapshotStore`、`UIKitSnapshotResponse`、`UIKitActionCapabilityResolver`、`UIViewTargetsModels`、`UIKitCommandError`/`UIKitCommandLogging`。

### `ViewTargetsCommand.swift` 🍎
- **职责**：`ui.viewTargets` 命令 adapter。
- **关键点**：薄 adapter——typed input 已由 `AnyCommand` 解析完成；handler `try await collector`。响应含 `targetCount`/`visitedNodeCount`/`truncated`/`viewSnapshotID`。
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

### `Commands/Navigation/`（`ui.navigation.tapBarButton`）

- **`UINavigationBarButtonModels.swift`** ✅ — `UINavigationBarButtonInput`：`placement`（left/right）+ `index` 定位导航栏按钮，可选 `title` / `accessibilityIdentifier` 做二次确认；`dryRun` 默认 false。
- **`UINavigationBarButtonCommand.swift`** 🍎 — 薄 adapter，`MainActor.run` 取 context → 调 `UINavigationBarButtonExecutor`；顶层 catch `UIKitCommandError` 转 envelope（错误码：`navigation_bar_unavailable` / `navigation_bar_item_not_found` / `navigation_bar_item_mismatch` / `navigation_bar_item_disabled` / `navigation_bar_item_unsupported`）。

### `Commands/Wait/`（`ui.wait` + `ui.waitAny`）

- **`UIWaitModels.swift`** ✅ — `WaitMode`（idle/targetExists/targetGone/textExists/snapshotChanged）+ `UIWaitInput`。mode 决定字段需求（targetExists/targetGone 需 locator、textExists 需 text、snapshotChanged 需 `viewSnapshotID`）；timeoutMs 0...30000、intervalMs 50...5000、stableMs 0...10000；target 复用 `UIKitLocatorInput.parseOptional`。
- **`UIWaitCommand.swift`** 🍎 — adapter，`timeoutNanoseconds = 35s`（命令级兜底高于最大业务 timeoutMs）；executor 是 `@MainActor async`，adapter 直接 `await`（不用 `MainActor.run`）。
- **`UIWaitAnyModels.swift`** ✅ — `UIWaitAnyCondition`（id + mode + 该模式字段）+ `UIWaitAnyInput`（conditions 1...16 + 共享 timeoutMs/intervalMs/stableMs/includeHidden）。conditions 是对象数组，无法用标量 `CommandField` 表达，故 schema 只用 `AnyCommandField` 声明 array、解析在 `parse(from:)` 手写（id 唯一、mode 合法、各模式必填字段校验，统一抛 `CommandInputParseError` → `invalid_data`）。
- **`UIWaitAnyCommand.swift`** 🍎 — adapter，`timeoutNanoseconds = 35s`；start 日志含 conditions 数/timeoutMs/intervalMs，complete 含 matchedID/matchedIndex/mode/elapsedMs/attempts。executor 是 `@MainActor async`，adapter 直接 `await`。

### `Commands/ScrollToElement/`（`ui.scrollToElement`）

- **`UIScrollToElementModels.swift`** ✅ — `ScrollToElementMatch`（text/accessibilityIdentifier）+ `UIScrollToElementInput`（value 必填，container 可选）。
- **`UIScrollToElementCommand.swift`** 🍎 — 薄 adapter，`MainActor.run` 取 context → 同步 executor。

### `Commands/Alert/`（`ui.alert.respond`）

- **`UIAlertRespondModels.swift`** ✅ — `AlertButtonRole`（default/cancel/destructive）+ `UIAlertRespondInput`（dryRun 默认 true，buttonTitle/buttonIndex/role 互斥）。
- **`UIAlertRespondCommand.swift`** 🍎 — 薄 adapter，`MainActor.run` 取 context → 同步 executor。

### `Support/Wait/`

- **`UIKitVisibleTextCollector.swift`** 🍎 — `@MainActor`，递归采集可见文本（UILabel.text/UIButton.currentTitle/UITextField.placeholder/accessibilityLabel/非编辑态 accessibilityValue）。**有意不收集 UITextField.text/UITextView.text**（用户输入，防泄露），与 `UIViewHierarchyCollector.textInfo` 分工。被 `UIWaitExecutor` 的 textExists/idle 用。
- **`UIWaitExecutor.swift`** 🍎 — `@MainActor async`，按 intervalMs 轮询至满足或 deadline。`DispatchTime.uptimeNanoseconds` 做 deadline；sleep clamp 到剩余 deadline（业务 waitTimeout 先于命令级 35s）；`try? Task.sleep` 吞 cancellation + `Task.isCancelled` 收敛到 waitTimeout。5 模式判断抽成共享 `evaluate(_:state:now:context:snapshotStore:snapshotUnavailableReason:)` + `ConditionProbe`/`PollState`（idle 的稳定窗口状态封装在 PollState），供 `UIWaitAnyExecutor` 复用，避免复制五套判断。注入 contextProvider 便于测试。
- **`UIWaitAnyExecutor.swift`** 🍎 — `@MainActor async`，多条件轮询：每轮按 conditions 顺序调 `UIWaitExecutor.evaluate`，第一个满足立即返回 satisfied/matchedID/matchedIndex/matchedMode/elapsedMs/attempts。共享 timeoutMs/intervalMs；cancel 与 contextProvider 瞬时不可用对齐 `ui.wait`（前者收敛 waitTimeout，后者当本轮未满足继续）。超时复用 `UIKitCommandError.waitTimeout`（mode="any"），不发明新错误码。

### `Support/Action/` 新增

- **`UIScrollResolver.swift`** 🍎 — `@MainActor`，滚动容器解析（ui.scroll/scrollToElement 共享）。`resolveFromTarget`（locator=target → 最近 scrollView 祖先）+ `resolveContainer`（locator=容器自身，scrollToElement）；都排除 UITextView。`Resolved` 持 UIScrollView，**仅 @MainActor 不 Sendable**。
- **`UIScrollGeometry.swift`** 🍎 — `@MainActor`，滚动几何（defaultDistance/delta/reachedExtent/step + `UIScrollStepResult.toJSON`），全基于 `adjustedContentInset` + 1pt 容差。ui.scroll 与 scrollToElement 共享，防行为漂移。
- **`UIKeyboardDismissExecutor.swift`** 🍎 — `@MainActor`，first responder 查找与收起。无 responder 时 success noop（dismissed=false）；auto 先 resign 再 endEditing(true)；失败 throw `keyboardDismissFailed`；settle 用 RunLoop。
- **`UINavigationBackExecutor.swift`** 🍎 — `@MainActor`，dismiss/pop 决策。auto 先 dismiss（presenting!=nil）再 navigationController pop（count>1）；返回**实际生效策略**；不可用 throw `navigationBackUnavailable`。
- **`UINavigationBarButtonExecutor.swift`** 🍎 — `@MainActor`，触发 `UIBarButtonItem`。由 `UINavigationBarInspector` 摘出 leftItems/rightItems，按 `placement + index` 选定按钮，依 selector 签名派发 target-action（避开 `UIApplication.sendAction` 在单测里不派发无参 action 的问题）；按钮不存在/不匹配/disabled/无可触发动作分别对应明确错误码。navigationBar 按钮走此专用命令，**不并入 `ui.tap`**。
- **`UIScrollToElementExecutor.swift`** 🍎 — `@MainActor`，容器内 findTarget + `scrollRectToVisible`。用 UIKit 原生（自动最短滚动、保证可见），替代循环小步 scroll 避免污染 snapshot store（评审 M3）；不签 snapshot（agent 应重新 screenshot）。
- **`UIAlertInspector.swift`** 🍎 — `@MainActor`，`findAlert`（cast topViewController）+ `summarize`（actions 的 index/title/role）。不依赖 present 转场（评审 M7），logic test 可靠。
- **`UIAlertRespondExecutor.swift`** 🍎 — `@MainActor`，query-first。dryRun=true 返回 alert 信息；dryRun=false 统一抛 `alertButtonRequired`（`UIAlertAction` handler 无公共触发路径：闭包仅 `init` 设置、无 public getter/perform，`dismiss` 也不调 handler），不直接点。

### `Support/Navigation/`

- **`UINavigationBarInspector.swift`** 🍎 — `@MainActor`，读顶部控制器 `navigationItem` 的 leftItems/rightItems 摘要（每个按钮含 `placement`、`index`、`title`、`accessibilityIdentifier`、`isEnabled`、`availableActions`）。`ui.viewTargets` / `ui.topViewHierarchy` 响应均追加 `navigationBar` 区块；`UINavigationBarButtonExecutor` 也复用本类型定位按钮。不依赖 UIKit 私有 view。

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
