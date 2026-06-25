# iOSExploreUIKit 文件档案

> 这是 `Sources/iOSExploreUIKit/` 全部 28 个文件的查阅手册。
> 想知道"从哪开始读"看 [reading-guide.md](./reading-guide.md)；这里按目录逐个登记每个文件的职责、关键点与依赖关系，用于定位与改动。
> 约定：✅ = Foundation-only（macOS `swift test` 可覆盖）；🍎 = `#if canImport(UIKit)`，仅 iOS 编译。
> 目录分两层：`Commands/` 是 4 个对外命令及其紧密配套（adapter + models + collector），`Support/` 是横切辅助（执行引擎 / 定位 / 上下文 / 快照 / 解析），根目录 3 个是模块级横切（注册 / 日志 / 错误）。

## 总览

| 目录 | 文件数 | 职责域 |
|---|---|---|
| 根目录 | 3 | 注册入口、日志、错误工厂（被所有层依赖） |
| `Commands/TopViewHierarchy/` | 3 | `ui.topViewHierarchy` 命令（adapter + models + collector） |
| `Commands/ViewTargets/` | 3 | `ui.viewTargets` 命令（adapter + models + collector） |
| `Commands/Tap/` | 2 | `ui.tap` 命令（adapter + models） |
| `Commands/ControlAction/` | 2 | `ui.control.sendAction` 命令（adapter + models） |
| `Support/Context/` | 1 | 前台 window / 顶部控制器 |
| `Support/Locator/` | 3 | 定位语义 + 真实 view 解析 + view lookup 模型 |
| `Support/Action/` | 4 | 动作执行引擎（tap / control，tap+control 共用） |
| `Support/Snapshot/` | 3 | 陈旧检测（指纹快照） |
| `Support/Parsing/` | 4 | typed query 解析约定、声明式取值器、安全数字、parse 错误类型 |

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

### `QueryParseError.swift` ✅
- **职责**：UIKit 命令参数解析失败的统一错误类型。
- **关键点**：所有 typed query 的 `parse` 用普通 `throws` 抛出本类型；命令 handler 顶层 `catch` 它并转成 `UIKitCommandError.invalidData`，文案直接进 `invalid_data` envelope（与执行阶段的 `UIKitCommandError` 分开 catch）。Foundation-only、`Sendable`，可在 macOS `swift test` 覆盖解析失败断言。
- **依赖**：core `Foundation`。

### `QueryDecoder.swift` ✅
- **职责**：UIKit 命令参数的声明式取值器（builder）。
- **关键点**：把 typed query parse 里重复的"按 key 取值 + 类型转换 + 默认值 + 范围/枚举校验 + 错误文案"封装成方法链（`bool`/`string`/`optionalNonNegativeInt`/`rangedInt`/`enumValue`/`requiredEnum`），失败统一抛 `QueryParseError`。取值 API 为 `public`（库内 `ui.*` query 与业务方自定义命令的 typed query 复用，见 `UIKitQueryParsing`）；`data`/`accessedKeys` 保持 internal——每个读取方法记 key 到 `accessedKeys`，供一致性测试断言"走 builder 的 key ⊆ Command.parameters"防漏声明；`data` 为 internal let，供库内手写领域字段（互斥/成对/path 文法）直接 `d.data[...]` 访问（不进 accessedKeys，业务方用取值方法）。不记日志（错误归 command handler 单一出口）。
- **依赖**：core `JSON`/`JSONValue`、`UIKitQueryNumber`、`QueryParseError`。
- **被调用**：4 个 typed query 的 `parse(decoding:)`（`UIViewTargetsQuery`/`UIViewHierarchyQuery`/`UITapQuery`/`UIControlSendActionQuery`）。

### `UIKitQueryParsing.swift` ✅
- **职责**：UIKit typed query 的解析能力约定（public protocol）。
- **关键点**：requirement 只有 `parse(decoding:) throws -> Self`；protocol extension 提供统一入口 `parse(from:) throws -> Self`（构造 `QueryDecoder` → 转交领域 `parse(decoding:)`），消除四个 `ui.*` query 各自重复的 `parse(from:)` 样板。四个 query adopt 本协议后只保留领域 `parse(decoding:)`（升 public），统一入口 `parse(from:)` 由协议默认实现提供。同时是业务方自定义命令复用 typed query 模式的 public 基建。Foundation-only、`Sendable`。静态分发抽象，无运行时日志点（解析失败日志在 handler 顶层 catch）。
- **依赖**：`QueryDecoder`、core `JSON`。
- **被调用**：四个 typed query 的 conformance；各命令 adapter 调 `parse(from:)`。

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
- **关键点**：path 文法解析（`root/0/2`）；`identifier` 与 `path` 互斥校验；作为 `UIKitLocator` 的 compatibility wrapper（新代码用 `UIKitLocator`）。**`accessibilityIdentifier` 完整匹配、不截断**。
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
- **职责**：`UITapQuery` + `UITapTarget`（view 目标 / windowPoint 目标）；adopt `UIKitQueryParsing`，领域 `parse(decoding:) throws` 失败抛 `QueryParseError`，统一入口 `parse(from:)` 由协议提供。
- **关键点**：view 目标与坐标目标互斥；`coordinateSpace` 第一版仅支持 `window`；解析出可选 snapshotID。
- **依赖**：`UIKitViewLookupTarget`、`UIKitLocator`。

### `UITapCommand.swift` 🍎
- **职责**：`ui.tap` 命令 adapter。
- **关键点**：薄 adapter——顶层 `do/catch`：`parse` query → 构造 `UIKitActionPlan.tap` → `try await executor.execute(plan)`；`catch UIKitCommandError` 取 `error.result`（记 `logMessage`），`catch QueryParseError` 转 `invalidData`。执行逻辑全在 executor。
- **依赖**：`UITapQuery`、`UIKitActionPlan`、`UIKitActionExecutor`、`UIKitCommandError`、`UIKitCommandLogging`。

---

## `Commands/ControlAction/`（`ui.control.sendAction`）

### `UIControlSendActionModels.swift` ✅
- **职责**：`UIControlSendActionQuery` + `UIControlSendActionEvent`；adopt `UIKitQueryParsing`，领域 `parse(decoding:) throws` 失败抛 `QueryParseError`，统一入口 `parse(from:)` 由协议提供。
- **关键点**：事件名 6 种（touchDown/UpInside/valueChanged/editing*）；`UIControlSendActionTarget` 是 `UIKitViewLookupTarget` 的 typealias（兼容旧名）。
- **依赖**：`UIKitViewLookupTarget`。

### `UIControlSendActionCommand.swift` 🍎
- **职责**：`ui.control.sendAction` 命令 adapter。
- **关键点**：薄 adapter——顶层 `do/catch`（同 `UITapCommand`）：`parse` → 构造 `UIKitActionPlan.controlEvent` → `try await executor.execute(plan)`。
- **依赖**：`UIControlSendActionQuery`、`UIKitActionPlan`、`UIKitActionExecutor`、`UIKitCommandError`、`UIKitCommandLogging`。

---

## `Commands/TopViewHierarchy/`（`ui.topViewHierarchy`）

### `UIViewHierarchyModels.swift` ✅（最大文件）
- **职责**：完整层级快照的全部模型——矩形/accessibility/状态/文本/外观/控件/图片/滚动 8 类验收字段 + 查询参数 + `UIViewHierarchyElement` 协议 + `UIViewHierarchyBuilder`。
- **关键点**：`UIViewHierarchyElement` 协议把递归/路径/筛选逻辑与 UIKit 解耦（真实采集器和测试 fake 都复用同一套 builder）；`detailLevel`（basic/appearance/full）控制是否输出文本/颜色等高成本字段；支持 identifier 精确/前缀筛选。
- **依赖**：core `JSON`/`JSONValue`、`UIKitQueryNumber`。

### `UIViewHierarchyCollector.swift` 🍎
- **职责**：`@MainActor`，从真实 `UIView` 递归读取属性生成完整快照。
- **关键点**：`collectTopViewHierarchy(query:) throws -> JSON`（无 context 入口，取真实 context 失败 throw `hierarchyUnavailable`）；`collectTopViewHierarchy(query:context:) -> JSON`（注入入口，测试用）。`UIKitViewElement` 是 `UIViewHierarchyElement` 的 UIKit 实现；读 UIKit 后交给 Foundation-only 的 `UIViewHierarchyBuilder`。还签发 snapshot（含完整树指纹）。
- **依赖**：UIKit、`UIKitContextProvider`、`UIKitFingerprintCollector`、`UIKitSnapshotStore`、`UIKitSnapshotResponse`、`UIViewHierarchyBuilder`/`UIViewHierarchyModels`、`UIKitCommandError`/`UIKitCommandLogging`。

### `TopViewHierarchyCommand.swift` 🍎
- **职责**：`ui.topViewHierarchy` 命令 adapter。
- **关键点**：薄 adapter——顶层 `do/catch`：`parse` `UIViewHierarchyQuery` → `try await collector`；有 identifier 筛选时返回 `matches` 列表，否则返回完整 `root` 树。
- **依赖**：`UIViewHierarchyQuery`、`UIViewHierarchyCollector`、`UIKitCommandError`、`UIKitCommandLogging`。

---

## `Commands/ViewTargets/`（`ui.viewTargets`）

### `UIViewTargetsModels.swift` ✅
- **职责**：轻量目标的全部模型——`UIViewTargetsQuery` + `UIViewTargetCandidate` + `UIViewTargetSummary` + 角色/状态/文本裁剪。
- **关键点**：**`UIViewTargetsQuery.shouldInclude` 是目标发现决策核心**，纯 Foundation-only 逻辑。默认包含策略：控件全部包含、有手势/有 identifier/有 label 的可交互节点包含；静态文本与容器默认排除。`maxTargets` 默认 200（上限 512），`textLimit` 默认 80（上限 200）。**identifier 完整不裁剪**，只裁剪展示型文本。
- **依赖**：`UIKitQueryNumber`、`UIKitSnapshotLimits`、`UIKitActionAvailability`、`UIViewHierarchyRect`。

### `UIViewTargetsCollector.swift` 🍎
- **职责**：`@MainActor`，递归遍历 view 树采集轻量目标摘要。
- **关键点**：`collect(query:) throws -> JSON`（无 context 入口）；`collect(query:context:) -> JSON`（注入入口）。刻意不复用完整层级快照（不读颜色/字体/图片）。identifier 筛选不提前剪枝子树。**`availableActions` 只认目标自身的 control 身份**（不向上借祖先 control），避免与 executor 的 path 派发分叉。
- **依赖**：UIKit、`UIKitContextProvider`、`UIKitFingerprintCollector`、`UIKitSnapshotStore`、`UIKitSnapshotResponse`、`UIKitActionCapabilityResolver`、`UIViewTargetsModels`、`UIKitCommandError`/`UIKitCommandLogging`。

### `ViewTargetsCommand.swift` 🍎
- **职责**：`ui.viewTargets` 命令 adapter。
- **关键点**：薄 adapter——顶层 `do/catch`：`parse` `UIViewTargetsQuery` → `try await collector`。响应含 `targetCount`/`visitedNodeCount`/`truncated`/`snapshotID`。
- **依赖**：`UIViewTargetsQuery`、`UIViewTargetsCollector`、`UIKitCommandError`、`UIKitCommandLogging`。

---

## 相关设计文档

| 主题 | 文档 |
|---|---|
| 模块整体架构（typed factory、隔离边界） | `docs/superpowers/specs/2026-06-23-uikit-command-extension-architecture-design.md` |
| throw 化 + 文件夹重组 | `docs/superpowers/specs/2026-06-24-uikit-throw-and-folder-reorg-design.md` |
| typed Query 解析入口抽象（`UIKitQueryParsing`） | `docs/superpowers/specs/2026-06-25-uikit-query-abstraction-design.md` |
| `ui.topViewHierarchy` 设计 | `docs/superpowers/specs/2026-06-22-uikit-view-hierarchy-design.md` |
| `ui.viewTargets` 设计 | `docs/superpowers/specs/2026-06-23-uikit-view-targets-design.md` |
| view targets 加固（identifier 不截断、能力一致性） | `docs/superpowers/specs/2026-06-24-uikit-view-targets-hardening-design.md` |
| core 协议总设计 | `docs/superpowers/specs/2026-06-21-ios-explore-server-design.md` |
