# UITableViewCell / UICollectionViewCell 选择触发设计

> 2026-07-05 · spec
> 范围：让 `ui.tap` 能可靠触发 UITableView/UICollectionView cell 的 selection 回调（`didSelectRowAtIndexPath:` / `collectionView(_:didSelectItemAt:)`）。

## 1. 背景与问题

iOSExploreServer 的 `ui.tap` 已收敛为「只作用于 `ui.viewTargets` 签发的 canonical target，按默认激活路由派发」。`UIKitDefaultActivationResolver` 为 `UIButton`/`UISwitch`/文本输入三类目标提供确定公开路由；其它可控 target（挂手势的自定义 view）由 `UIGestureTargetExecutor` 用 runtime 读 `_targets` 派发手势 target-action。

但 `UITableView`/`UICollectionView` 的 cell selection 没有覆盖：

- `UITableViewCell` 不在 `ui.viewTargets` 输出中（`UIViewTargetsModels.shouldInclude` 的 canonical-only 口径未识别 cell 为可执行 target）。
- viewTargets 返回的是 cell 的子 view（如 `UIListContentView`，path 例 `root/5/0/1`），其 `availableActions` 为空 `[]`，但 `hasGestureRecognizers=true`。
- 实测在 iPhone 17 / iOS 26.3 模拟器上 `ui.tap path=root/5/0/1`(`UIListContentView`) 走现有 gesture adapter，触发的是 cell 透传下来的 `_longPressGestureRecognized:`（与 `prepareForReuse` 等相关，**不是** `didSelectRow`），返回 `route=gesture.targetAction` 但页面未 push。
- 实测在 iPhone 17 / iOS 26.3 模拟器上 `ui.tap path=root/5/0`(`UITableViewCell`) 因 viewTargets 未给 cell 签 fingerprint，命中 `stale_locator`。
- lldb 实测 `tableView.gestureRecognizers` 中存在一项 `UITapGestureRecognizer, action=selectGestureHandler:, target=<_UISelectionInteraction>, enabled=NO`——**真实选中入口挂在外层 tableView 上，不在 cell 上**，且该手势 enabled=NO（实际选中靠 UIKit touches 流程，不是这个手势识别器自身触发）。

结论：要支持 cell selection，必须新开 adapter，既不能依赖 cell 自身的 gesture，也不能简单 invoke 那个 enabled=NO 的 selectGestureHandler。

## 2. 目标与非目标

**目标：**

- `ui.tap` 命中 cell 子树内任意 view（cell 本身、cell.contentView、`UIListContentView`、cell 内的子 view）时，能可靠触发对应 `UITableView`/`UICollectionView` 的 `didSelectRow`/`didSelectItem` 回调。
- 同步覆盖 UITableView 与 UICollectionView。
- 私有 API 优先（探索工具的本职），公有 API 兜底；Release 下仅公有可用。
- 不引入新的 viewTargets 命名空间、不破坏 canonical-only 口径。

**非目标：**

- 不让 `UITableViewCell`/`UICollectionViewCell` 进入 viewTargets 输出。修改 `shouldInclude` 会牵动 canonical-only 不变式与签发集合 == 返回集合的约束，超出本轮范围；agent 已经能通过 cell 子 view（`UIListContentView`）走到 cellSelection 路径。
- 不在 `UIKitDefaultActivationRoute` 加入 `cellSelection` route。route 枚举是 collector 与 executor 共享的「默认激活路由」表，cellSelection 的入口不在那里——它从 `executeTap` 的 route=nil 分支进入。
- 不改 `ui.tap` schema、不改 HTTP 协议。

## 3. 关键约束

- **私有 API 隔离**：读 `gestureRecognizers` 与 `perform(:with:)` 是公开 API；但用 runtime 读私有 ivar 的入口（`UIGestureRecognizer+Trigger.swift` 里的 `explore_targetActionPairs()`）整体 `#if DEBUG` 隔离。本 adapter 不需要新读私有 ivar（selectGestureHandler 是公开 `gestureRecognizers` 列出的手势，可被公开枚举），但**调用 `perform(:with:)` 触发 `_UISelectionInteraction` 私有 target 仍属私有 API 路径**——必须 `#if DEBUG` 隔离，Release 空跳。
- `#if canImport(UIKit)` 整体保持（macOS 编译空壳）。
- Swift 6.2 严格并发：adapter 是 `@MainActor`；跨边界只传 `Sendable` 摘要。
- 失败出口统一走 `UIKitCommandError` 工厂；不在调用点散写 code/message。
- 不破坏现有 gesture adapter 行为：非 cell 子树的 view（普通挂手势自定义 view）仍走 `UIGestureTargetExecutor.execute(on:)`。

## 4. 关键事实与未决验证

### 4.1 已实测确证

| 事实 | 来源 |
|---|---|
| `UITableViewCell` 不进 viewTargets | `UIViewTargetsModels.shouldInclude` 逻辑 + 模拟器实测 |
| `UIListContentView` 进 viewTargets，`availableActions=[]`，`hasGestureRecognizers=true` | 模拟器实测 |
| `ui.tap path=root/5/0/1`(`UIListContentView`) 现状触发 `_longPressGestureRecognized:`（误触） | 模拟器实测 `route=gesture.targetAction`，未 push |
| `selectGestureHandler:` 手势挂在 tableView 上、target 是 `_UISelectionInteraction`、enabled=NO | lldb 实测 |

### 4.2 ⚠️ 未决验证（实施第一动作）

`_UISelectionInteraction.selectGestureHandler:` 手势 enabled=NO。直接 `target.perform(action, with: gesture)` 走的是 ObjC `perform` 路径，不经过手势识别器状态机——`enabled` 属性本身不会阻止 `perform:` 调用目标方法。

**但 `_UISelectionInteraction.selectGestureHandler:` 方法内部是否真的会调到 `_selectRowAtIndexPath:` 触发 `didSelectRow` 还不确定**：

- 场景 A（乐观）：方法内部由手势的 `view`（tableView）+ 假设的触点位置推出 indexPath，最终走到 `_selectRowAtIndexPath:`。
- 场景 B（悲观）：方法内部依赖真实触摸事件流中的光标位置；裸 `perform` 没有 event、没有 location，可能 silent return 或返回 NO 但不抛异常。

**实施第一步必须是 SPMExample 模拟器 spike**：临时在 `executeCellSelection` 私有路径里加日志/断点，invoke `selectGestureHandler:` 后看目标页面是否真 push、`tableView(_:didSelectRowAt:)` 是否真被调。

**根据 spike 结果决定私有路径是否激活**：

- 场景 A 命中：私有路径作为主路径，公有路径做兜底。
- 场景 B 命中：私有路径不 invoke（仅在 DEBUG 日志中记录"found selectGestureHandler: gesture but bypassed"作为发现痕迹），公有 API 路径升为主路径，不再叫"兜底"。

无论 spike 结论如何，公有 API 路径**必须实现**——它是 Release 下唯一可用路径，也是私有路径失败时的回退。

## 5. 方案对比

### 方案 A：让 cell 进 viewTargets，route 枚举加 `cellSelection`

- 改 `shouldInclude` 让 `UITableViewCell`/`UICollectionViewCell` 进 canonical target，签发 fingerprint。
- 改 `UIKitDefaultActivationResolver.route` 对 cell 类型返回 `.cellSelection`。
- `executeTap` switch 增加 `.cellSelection` case。

否决理由：

- 改 canonical-only 口径会牵动「签发集合 == 返回集合 == tap 可执行集合」不变式，影响面大（要复核 collector、fingerprint、stale 校验、`ui.wait` 重采表多套对应），超出本轮目标。
- 不必要：实测已经知道 cell 的子 view（`UIListContentView`）能进 viewTargets，agent 能拿到它的 path，cellSelection 入口完全可以从 cell 子 view 走。
- `UIKitDefaultActivationRoute` 当前 enum 是 collector 与 executor 共享的「默认激活路由」表；cellSelection 不是 collector 那一侧该声明的语义（cell 本身不进 targets），把它放进 enum 会让两边再次出现"声明可执行但不输出"的语义分叉。

### 方案 B（采用）：cell 不进 viewTargets，cell 入口走 cell 子树探测 adapter

- 不改 `shouldInclude`、不改 route 枚举。
- 在 `UIGestureTargetExecutor` 新增 `executeCellSelection(on:)`：从入参 view 向上找 cell → tableView，私有手势触发 → 公有 API 兜底。
- 在 `UIKitActionExecutor.executeTap` 的 `route == nil` 分支内，**先于**现有 gesture adapter 调 `executeCellSelection`：

  - 返回 `non-nil` 且 `activated=true` → 返回 cellSelection 响应 JSON。
  - 返回 `non-nil` 且 `activated=false` → cell 子树内两条路径都失败，fallthrough 到 `unsupported_target`。
  - 返回 `nil` → 不在 cell 子树，继续走现有 gesture adapter。

- 关键顺序：**cellSelection 优先于现有 gesture adapter**。因为 cell 内子 view（`UIListContentView`）上挂的 `_longPressGestureRecognized:` 是误触（实测会激活但不是 selection 语义），不能让 agent 先命中那个再被错误响应。

### 方案 C：方案 A + 方案 B 混合

cell 进 viewTargets 收 dosage 可控、cell 子 view 也走 adapter 的双入口。否决理由：方案 A 的代价照付，且 agent 会有两个等价入口（cell 自身 + cell 内 view）造成响应字段不一致。

## 6. 实施设计

### 6.1 新增类型：`CellSelectionAttempt`

`UIGestureTargetExecutor.swift` 内或同目录新建小文件，值类型 `Sendable`，跨 MainActor 边界回传到 handler。

```swift
/// cell selection adapter 的尝试结果摘要。
///
/// 跨 MainActor 边界回传到命令 handler；字段只含路径摘要与类型名，不含
/// target 对象引用，避免泄露业务对象。`activated=true` 表示至少一条路径
/// 真实触发了 selection 回调；`activated=false` 表示 cell 子树内但两条
/// 路径都失败，调用方应 fallthrough 到 `unsupported_target`。
struct UICellSelectionAttempt: Sendable, Equatable {
    /// 是否成功触发 selection。
    let activated: Bool
    /// 实际触发的路由摘要：
    /// - `cell.select.private`：私有手势路径触发；
    /// - `cell.select.public`：公有 API（indexPath(for:) + delegate.didSelectRow）触发；
    /// - `cell.select.failed`：在 cell 子树内但两条路径都失败（不含 `nil`：不在 cell 子树）。
    let activationRoute: String
    /// 入参 view 的运行时类型名（关联日志用，不含引用）。
    let viewType: String
    /// 外层 tableView/CollectionView 的运行时类型名；找不到时为 nil（不应出现，仅防御）。
    let containerViewType: String?
    /// 命中的 cell 类型名（UITableViewCell/UICollectionViewCell 或子类）。
    let cellType: String?
    /// 公有 API 路径解析到的 indexPath；私有路径无此信息，为 nil。
    let indexPathSummary: IndexPathSummary?
}

/// 公有 API 路径解析到的 section/row 摘要，跨边界前从 IndexPath 抽出避免 Sendable 边界问题。
struct IndexPathSummary: Sendable, Equatable {
    let section: Int
    let item: Int  // UITableView 用 row、UICollectionView 用 item；统一字段名简化边界
}
```

### 6.2 `UIGestureTargetExecutor.executeCellSelection(on:)`

```swift
@MainActor
extension UIGestureTargetExecutor {
    /// 在 cell 子树内尝试触发 cell selection。
    ///
    /// 流程：
    /// 1. 从入参 view 向上找 `UITableViewCell`/`UICollectionViewCell`；找不到返回 nil
    ///    （不在 cell 子树，调用方走其它分支）。
    /// 2. 继续向上找 `UITableView`/`UICollectionView`；找不到同样返回 nil（异常状态）。
    /// 3. DEBUG：在 containerView.gestureRecognizers 中找 action == "selectGestureHandler:"
    ///    （UITableView）的 `UITapGestureRecognizer`，invoke 其 target-action。
    ///    spike 决定是否真的 invoke：spike 失败时仅记日志不 invoke。
    /// 4. 公有 API 兜底：indexPath(for: cell) + delegate.didSelectRow/didSelectItem。
    /// 5. 都失败：返回 activated=false, route="cell.select.failed"。
    ///
    /// - Parameter view: `executeTap` 传入的已定位 canonical target（可能是 cell 本身，
    ///                   也可能是 cell 内任意子 view，如 `UIListContentView`）。
    /// - Returns: 尝试摘要。`nil` 表示 view 不在 cell 子树内（调用方走其它分支）；
    ///            `non-nil` 表示在 cell 子树内（已尝试触发，`activated` 标记是否成功）。
    static func executeCellSelection(on view: UIView) -> UICellSelectionAttempt?
}
```

辅助方法（同文件 private）：

- `findCellAncestor(of:) -> UIView?` — 向上找 `UITableViewCell`/`UICollectionViewCell`。
- `findContainerViewAncestor(of cell:) -> UIView?` — 向上找 `UITableView`/`UICollectionView`。
- `trySelectViaPrivateGesture(tableView:) -> Bool` — DEBUG 隔离，遍历 `gestureRecognizers` 找 `selectGestureHandler:`；找到后再调内部 `invoke(target:action:sender:)`（已有，复用 `UIGestureTargetExecutor.invoke`）；spike 失败时只记日志返回 false。

`invoke(target:action:sender:)` 当前是枚举内 `private static`，复用即可，无需提升可见性。`selectGestureHandler:` 是 1 参签名（接受 `UIGestureRecognizer`），与现有 `UIGestureTriggeredPair` 的派发路径完全一致。

### 6.3 `UIKitActionExecutor.executeTap` 改动

在现有 `guard let route = UIKitDefaultActivationResolver.route(for: located.view) else { ... }` 分支内、现有 gesture adapter 调用之前插入：

```swift
guard let route = UIKitDefaultActivationResolver.route(for: located.view) else {
    // [新增] cellSelection 优先于 gesture adapter：cell 内子 view（如 UIListContentView）
    // 上挂的 _longPressGestureRecognized: 是 prepareForReuse 相关手势，不是 selection 语义，
    // 必须先尝试 cellSelection，否则 agent 会先命中那个再被错误响应。
    if let attempt = UIGestureTargetExecutor.executeCellSelection(on: located.view) {
        if attempt.activated {
            UIKitCommandLogging.info("command",
                "ui tap default activation route=\(attempt.activationRoute) path=\(located.pathString) type=\(attempt.viewType) containerType=\(attempt.containerViewType ?? "nil") indexPath=\(attempt.indexPathSummary.map { "\($0.section)-\($0.item)" } ?? "nil")")
            return [
                "activated": .bool(true),
                "activationRoute": .string(attempt.activationRoute),
                "path": .string(located.pathString),
                "type": .string(attempt.viewType),
                "containerType": attempt.containerViewType.map(JSONValue.string) ?? .null,
                "indexPath": attempt.indexPathSummary.map { indexPathJSON($0) } ?? .null,
            ]
        }
        // cell 子树内但两条路径都失败 → 直接 unsupported_target，
        // 不再走 gesture adapter（cell 子 view 的 _longPressGestureRecognized: 是误触）。
        throw UIKitCommandError.unsupportedTarget(action: tapAction,
                                                  targetDescription: located.pathString,
                                                  type: String(describing: Swift.type(of: located.view)))
    }

    // 不在 cell 子树 → 走原 gesture adapter（非 cell 子树的挂手势自定义 view）
    if !(located.view is UIControl),
       let triggered = UIGestureTargetExecutor.execute(on: located.view), !triggered.isEmpty {
        // …现有
    }
    throw UIKitCommandError.unsupportedTarget(...)
}
```

新增 helper `indexPathJSON(_:) -> JSONValue` 输出 `{"section":n,"item":n}`。

### 6.4 不改动的文件

- **不改动 phase 1（探索阶段）**：`UIKitDefaultActivationRoute.swift` / `UIKitDefaultActivationResolver.swift`：cellSelection 不入门禁泛 route 枚举（理由见方案 A 否决）。
- **不改动**：`UIViewTargetsModels.swift` / `UIViewTargetsCollector.swift` 的 canonical-only 口径不变，cell 不进 targets。
- **不改动**：`UIViewTargets` schema、`UITapCommand` / `UITapInput` / HTTP 协议不变。
- **改动（capability 显式声明）**：`UIKitActionCapabilityResolver.swift` / `UIKitActionKind.swift` 不需要新增 case（`tap` 已存在）；但 `UIKitActionCapabilityResolver.resolve` 的累加分支需新增一条：cell 子树内的 view（含 cell 本身及其子 view）声明 `.tap`，让 agent 一眼看见这个能力而不仅靠 `hasGestureRecognizers` 推断。此分支由 `executeCellSelection` 路径支撑，与 gesture adapter 的"声明边缘"语义一致。具体见 §6.4.b。

### 6.4.b `UIKitActionCapabilityResolver` 新增 cell 子树声明分支

在 `resolve(view:rootView:)` 内，`isInteractable` 通过、disabled 排除四条累加分支之后追加一条（顺序无所谓，Set 去重）：

```swift
// cell 子树：cellSelection adapter（executeTap 的 cellSelection 分支）能为其派发
// UITapGestureRecognizer → didSelectRow/Item，故声明 tap 让 agent 直接知道此 view 可点。
// 与 hasGestureRecognizers 推断双保险：即使该子 view 未挂私有 gesture（理论上 cell contentView
// 内的 label 之类），只要它在 cell 子树内就声明 tap；executeTap 走 cellSelection 仍可达。
if findCellAncestor(of: view) != nil {
    collected.insert(.tap)
}
```

实现细节：

- `findCellAncestor(of:)` 在 `UIGestureTargetExecutor` 里新增（已是 `@MainActor` 内部静态方法），通过 `var cur = view; while let n = cur.superview { if n is UITableViewCell || n is UICollectionViewCell { return n }; cur = n }` 向上找。
- 该方法对 `UIKitActionCapabilityResolver` 可见——`@MainActor enum` 内部 helper，参照 `availableActions` 模式暴露为 `internal static`（与 `UIViewTargetsCollector.role(for:)` 同级）。
- 边界：`isInteractable` 已先做了用户交互性校验，cell 子树里 disabled 控件在更早分支返回空集合；这里的 cell 子树分支只对可交互的 cell 子树 view 声明 tap。
- 影响：cell 子 view（`UIListContentView`、cell.contentView、cell 内 sub view） 在 `ui.viewTargets` 响应里的 `availableActions` 从 `[]` 变为 `["tap"]`。agent 直接看到可点，不再需要"靠 hasGestureRecognizers 蒙一把"。
- 不影响 collector：`shouldInclude` 的 canonical-only 口径不变；新增声明只是把"已采集到的 cell 子树 view"的 `availableActions` 加上 `tap`。cell 本身仍不进 targets。
- 测试：`UIViewTargetsModelsTests` 里已有的 capability resolve 测试需要补一条 cell 子树 view 的期望 `["tap"]`。

### 6.5 错误出口

无新增错误码：

- cell 子树内两条路径都失败 → 复用 `UIKitCommandError.unsupportedTarget(action:targetDescription:type:)`，错误信息保持「目标无默认激活路由」语义，外部 envelope `unsupported_target`。
- 不在 cell 子树、gesture adapter 失败 → 现有 `unsupportedTarget` 路径不变。
- 私有路径 invoke 异常 ObjC runtime 不会有 Swift 可 catch 异常（C API 不抛 NSException），按现有 `UIGestureTargetExecutor` 的安全降级模式处理。
- 公有 API 路径 `delegate?.tableView?(tableView, didSelectRowAt:)` 是公开调用，无异常路径。

## 7. 测试设计

### 7.1 单元/集成测试（macOS SPM `swift test`）

新建 `Tests/iOSExploreServerTests/UITableViewCellSelectionTests.swift`：

| 测试 | 目的 |
|---|---|
| `executeCellSelection 非 cell 子树 view 返回 nil` | 输入普通 UIView/UIButton，确认返回 nil，executeTap 走原有 gesture adapter 分支 |
| `executeCellSelection 在 cell 子树但无 tableView 祖先返回 nil`（合成异常树） | 防御性边界 |
| `executeCellSelection cell 子树 + DEBUG 私有路径命中 → activated=true, route=cell.select.private` | 用 mock `UITableView` 子类注入 `gestureRecognizers` 为带 `selectGestureHandler:` selector 的 `UITapGestureRecognizer`（target 为能响应该 selector 的 stub），验证 invoke 被调用 |
| `executeCellSelection cell 子树 + 公有 API 路径命中 → activated=true, route=cell.select.public, indexPath 填回` | mock `UITableView` + mock `UITableViewDelegate`，验证 `delegate.didSelectRow` 被调用 |
| `executeCellSelection cell 子树 + 两条路径都失败 → activated=false, route=cell.select.failed` | 构造无 delegate 且无 selectGestureHandler 的容器，cell 子树内的 view 命中失败摘要 |
| `executeTap cell 子树 view 命中 cellSelection → 返回 cell.select.* JSON` | 端到端：通过 `UIKitActionExecutor.execute(_:context:)` 注入路径走到 executeTap，验证响应 JSON 字段 |
| `executeTap cell 子树 + cellSelection 失败 → unsupported_target` | 验证 fallthrough 不走原 gesture adapter（cell 子 view 的 `_longPressGestureRecognized:` 是误触） |
| `UICollectionView cell 子树镜像测试` | 用 `UICollectionView`/`UICollectionViewCell` 同样覆盖私有/公有/失败三路径 |
| `Release 路径测试` | `#if !DEBUG` 分支下的 mock 期望：私有路径直接跳过，公有路径可达 |

测试放两处：

- `Tests/iOSExploreServerTests/UITableViewCellSelectionTests.swift` 覆盖纯逻辑（非 cell 子树返回 nil、私有/公有/失败三路径、capability resolver 声明、Release 隔离）。这些测试依赖 `UIKitActionExecutor.execute(_:context:)` 注入的 `UIKitContextProvider.Context`，可在 framework 测试 target 里跑（`xcodebuild ... test` iOS 模拟器），**不在** `swift test` 里跑（macOS 无 UIKit 运行环境）。
- 真实模拟器端到端验证在 SPMExample 里做（§7.2）。端到端不写成自动化 `XCTest`——用手动/脚本化 `curl` 命令验证 HTTP 响应与页面行为。

### 7.2 真实模拟器端到端验证

1. `session_use_defaults_profile("sim-app")`
2. `build_run_sim()`
3. `launch_app_sim(env={"IOS_EXPLORE_AUTOSTART":"1"})`（autostart 让 `server.start()` 自动执行）
4. `curl -X POST http://localhost:38321/ -d '{"action":"ui.viewTargets","data":{}}'` → 拿当前 `viewSnapshotID`，确认 `root/5/0/1`(UIListContentView) 等条目存在
5. `curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{"path":"root/5/0/1","viewSnapshotID":"<id>"}}'` —— **观察响应**：
   - `activated=true, activationRoute=cell.select.private` 或 `cell.select.public`
   - SPMExample 主菜单真从该 cell push 进了 `DiagnosticsTestViewController`（"日志诊断测试"页面）
6. 验证不同 cell：再 tap root/5/1/1、root/5/2/1，确认其它菜单项也能进入对应页面
7. 验证 iproxy 真机同样可达

### 7.3 spike 验证（实施第一动作）

在 `executeCellSelection` 私有路径里临时加 print/log，invoke `selectGestureHandler:` 后看：

- `tableView(_:didSelectRowAt:)` 是否被调
- SPMExample 是否真 push 进 `DiagnosticsTestViewController`

如两者均否，确认场景 B：spike 通过的实现里私有路径只记日志不 invoke，公有 API 升为主路径。

## 8. 实施顺序（writing-plans 会基于此细化）

1. **Spike**：在 SPMExample 模拟器，先临时 print 验证 `selectGestureHandler:` 是否真触发 `didSelectRow`。结论决定私有路径的"激活 / 仅观察"分支（§4.2 + §7.3）。
2. 在 `UIGestureTargetExecutor.swift` 新增 `UICellSelectionAttempt`/`IndexPathSummary` 与 `executeCellSelection(on:)` + 辅助查找方法。私有路径用已有 `#if DEBUG` 模式隔离（参照现有 `execute(on:)` 的 Release 隔离边界）；spike 失败时仅记日志不 invoke。
3. 在 `UIKitActionExecutor.executeTap` 的 route==nil 分支插入 cellSelection 优先逻辑 + `indexPathJSON` helper。
4. 写单元/集成测试（§7.1）。
5. `swift test` 跑 macOS SPM；`xcodebuild ... test` 跑 iOS framework 测试。
6. 真实模拟器端到端（§7.2）。
7. 修订 `AGENTS.md`/`CLAUDE.md` 与 `docs/uikit/` 文档：`UIKitActionExecutor.executeTap` 文档注释要补 cellSelection 路径；`docs/uikit/uikit-file-reference.md` 加 `UICellSelectionAttempt` 与 `executeCellSelection` 档案。

## 9. 影响与风险

- **不变的对外行为**：`ui.viewTargets` 输出 schema、HTTP 协议、`availableActions` 字段、所有 default route（UIButton/UISwitch/文本输入），以及非 cell 子树的 gesture-only view 行为。
- **变化**：cell 子树内 view 的 `ui.tap` 行为从"误触 `_longPressGestureRecognized:` 返回 gesture.targetAction"变为"返回 cell.select.private/public"，并真正触发 selection。
- **风险评估**：
  - 私有 API spike 失败（场景 B）→ 降级为公有 API 主路径，工作流不阻塞。
  - iOS 版本漂移导致 `selectGestureHandler:` action 名变化 → adapter 以"找不到该 selector"作为私有路径不命中的依据，自然降级到公有；不需要预先做版本分支。
  - 公有 API `indexPath(for:)` 在 cell 已被 prepareForReuse 复用但 view 还在 cell 子树时可能返回 nil（罕见）→ 此时私有路径若 spike 验证有效可补救；都失败则 `unsupported_target`，agent 重发 viewTargets 后再试即可。
- **响应字段命名**：新增字段（`activated`/`activationRoute`/`path`/`type`/`containerType`/`indexPath`）与现有 gesture adapter 响应（`activated`/`activationRoute`/`path`/`type`/`gestures`/`triggeredCount`）平行；agent 端按 `activationRoute` 字段值分支处理。
