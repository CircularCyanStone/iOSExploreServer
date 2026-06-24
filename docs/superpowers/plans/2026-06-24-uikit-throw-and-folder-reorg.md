# UIKit throw 化 + 文件夹重组 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 UIKit 模块的自定义 Result 枚举（`ContextResult` / `LocateResult` / `UIKitSnapshotValidation`）全部改成 `throws`，执行核心全程 throw `UIKitCommandError`、边界转换集中在 handler 顶层；并把命令与辅助类型按 `Commands/` + `Support/` 重组，让「命令 vs 辅助」一眼可分。

**Architecture:** 让 `UIKitCommandError` 增加 `Error` 协议，成为 UIKit 内部唯一可抛出的业务错误（零新增 error 类型——locate 的 notFound/ambiguous 由调用方传入工厂闭包构造对应 `UIKitCommandError`）。执行核心（executor / collector）签名从 `-> ExploreResult` 改为 `throws -> JSON`，失败 throw，成功返回纯 JSON；handler 顶层 `do/catch` 把 `UIKitCommandError` 与 `QueryParseError` 转成 `ExploreResult.failure`（业务码不丢，日志在顶层一处记）。文件夹用 `git mv` 重组，framework 工程的 `PBXFileSystemSynchronizedRootGroup` 自动同步。

**Tech Stack:** Swift 6.2（SPM）/ Swift 5.0（framework 工程，**禁用 typed throws 等 Swift-6-only 语法**，只用普通 `throws`）；Swift Testing（`import Testing`，`@Test` / `#expect` / `#expect(throws:)`）；`#if canImport(UIKit)` 包裹所有碰 UIKit 的文件。

## Global Constraints

- 库 core 不依赖 UIKit；UIKit 仅在 `Sources/iOSExploreUIKit/` 内使用，UIKit 类型不穿 public 边界（typed factory：query 先解析校验）。
- 命令 handler 协议 `func handle(_ request: ExploreRequest) async throws -> ExploreResult` **不改**；Router 把 thrown error 转成 `internal_error`，故业务码必须以 `ExploreResult.failure` 从 handler 返回——UIKit 内部 throw，handler 顶层 catch 转 `error.result`。
- 错误码语义不变：定位/命中类 `.invalidData`，UIKit 上下文不可用 `.internalError`；envelope message / logMessage 文案逐字保持。
- 所有失败出口经 `UIKitCommandError` 工厂构造（不在调用点散写 code/message）；失败日志记 `error.failure.logMessage`（含 action/target/reason），不写完整 payload。
- 新增/改动 public 类型与方法须有 `///` 简体中文文档注释（用途 + `- Parameters:`/`- Returns:`/`- Throws:`）。
- 改完每个 task 跑 `swift test`（SPM，macOS）；Task 2、3 结束追加 framework `xcodebuild ... test`（iOS）。

## File Structure

**改动（throw 化，Task 1–2）：**
- `Sources/iOSExploreUIKit/UIKitCommandError.swift` — 加 `Error` 协议。
- `Sources/iOSExploreUIKit/Context/UIKitContextProvider.swift` — `currentContext(action:) throws`，删 `ContextResult`。
- `Sources/iOSExploreUIKit/Locator/UIKitLocatorResolver.swift` — `locate(...) throws`（工厂闭包映射），删 `LocateResult`。
- `Sources/iOSExploreUIKit/Snapshot/UIKitSnapshotStore.swift` — `validation(...) -> UIKitSnapshotValidation` 改 `isStale(...) -> Bool`，删 `UIKitSnapshotValidation`。
- `Sources/iOSExploreUIKit/Action/UIKitActionExecutor.swift` — `execute`/`executeTap`/`executeControlEvent`/`validateFreshness` 改 `throws -> JSON`，线性 `try`。
- `Sources/iOSExploreUIKit/ViewHierarchy/UIViewHierarchyCollector.swift` — 无 context 入口 `throws -> JSON`；注入入口 `-> JSON`。
- `Sources/iOSExploreUIKit/ViewTargets/UIViewTargetsCollector.swift` — 同上。
- 4 个 handler（`UITapCommand` / `UIControlSendActionCommand` / `TopViewHierarchyCommand` / `ViewTargetsCommand`）— 顶层 `do/catch`。
- 测试：`UIKitActionExecutorTests` / `UIKitSnapshotTests` / `UIKitCollectorTests`。

**移动（Task 3，纯 `git mv`）：** 见 Task 3 完整命令列表。

**文档（Task 4）：** `docs/uikit/uikit-file-reference.md`、`docs/uikit/reading-guide.md` 路径同步。

---

## Task 1: `UIKitCommandError` conform `Error`

**Files:**
- Modify: `Sources/iOSExploreUIKit/UIKitCommandError.swift:13`
- Test: `Tests/iOSExploreServerTests/UIKitCommandErrorTests.swift`

**Interfaces:**
- Produces: `UIKitCommandError` 同时是 `Error`（后续 task 才能 `throw` 它）。

- [ ] **Step 1: 写失败测试**

在 `UIKitCommandErrorTests.swift` 的 `UIKitCommandErrorTests` struct 内追加（文件末尾 `}` 前）：

```swift
@Test("UIKitCommandError 可作为 Error 抛出与捕获")
func errorIsThrowableAndCatchable() {
    #expect(throws: UIKitCommandError.self) {
        throw UIKitCommandError.targetNotFound(action: "ui.tap", targetDescription: "root/0")
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter UIKitCommandErrorTests`
Expected: 编译失败——`UIKitCommandError` 不是 `Error`，`throw` 不成立（`"Concrete conversion of value of type 'UIKitCommandError' to 'any Error' requires the type conform to 'Error'"`）。

- [ ] **Step 3: 让 `UIKitCommandError` conform `Error`**

修改 `UIKitCommandError.swift:13`：

```swift
// before
struct UIKitCommandError: Sendable, Equatable {
// after
struct UIKitCommandError: Error, Sendable, Equatable {
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --filter UIKitCommandErrorTests`
Expected: PASS（含新增 `errorIsThrowableAndCatchable` 与既有 11 个 case 映射测试，`error.result` 断言不受影响）。

- [ ] **Step 5: Commit**

```bash
git add Sources/iOSExploreUIKit/UIKitCommandError.swift Tests/iOSExploreServerTests/UIKitCommandErrorTests.swift
git commit -m "refactor(uikit): UIKitCommandError conform Error，为 throw 化铺路"
```

---

## Task 2: 执行核心 throw 化（删 3 个 Result 枚举）

签名贯穿重构：`currentContext` / `locate` / `isStale` / executor / collector / 4 handler 是一条链，中间步骤会临时编译失败，**Step 9 整体恢复编译并测试绿**。按文件顺序改，每步聚焦。

**Files:**
- Modify: `Sources/iOSExploreUIKit/Locator/UIKitLocatorResolver.swift`
- Modify: `Sources/iOSExploreUIKit/Snapshot/UIKitSnapshotStore.swift`
- Modify: `Sources/iOSExploreUIKit/Context/UIKitContextProvider.swift`
- Modify: `Sources/iOSExploreUIKit/Action/UIKitActionExecutor.swift`
- Modify: `Sources/iOSExploreUIKit/ViewHierarchy/UIViewHierarchyCollector.swift`
- Modify: `Sources/iOSExploreUIKit/ViewTargets/UIViewTargetsCollector.swift`
- Modify: `Sources/iOSExploreUIKit/Tap/UITapCommand.swift`
- Modify: `Sources/iOSExploreUIKit/ControlAction/UIControlSendActionCommand.swift`
- Modify: `Sources/iOSExploreUIKit/ViewHierarchy/TopViewHierarchyCommand.swift`
- Modify: `Sources/iOSExploreUIKit/ViewTargets/ViewTargetsCommand.swift`
- Test: `Tests/iOSExploreServerTests/UIKitActionExecutorTests.swift`
- Test: `Tests/iOSExploreServerTests/UIKitSnapshotTests.swift`
- Test: `Tests/iOSExploreServerTests/UIKitCollectorTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `UIKitCommandError: Error`。
- Produces: `UIKitLocatorResolver.locate(locator:in:notFound:ambiguous:) throws -> LocatedView`；`UIKitContextProvider.currentContext(action:) throws -> Context`；`UIKitSnapshotStore.isStale(...) -> Bool`；`UIKitActionExecutor.execute(_:) / execute(_:context:) throws -> JSON`；`UIViewHierarchyCollector.collectTopViewHierarchy(query:) throws -> JSON` / `(query:context:) -> JSON`；`UIViewTargetsCollector.collect(query:) throws -> JSON` / `(query:context:) -> JSON`。

### Step 1: `UIKitLocatorResolver.locate` 改 throws（删 `LocateResult`）

`UIKitLocatorResolver.swift`：

删掉 `enum LocateResult`（line 29-37），把 `locate(locator:in:)`（line 39-60）改为：

```swift
/// 按通用目标定位 view，失败时抛出由调用方提供的业务错误。
///
/// 仅解析 `accessibilityIdentifier` 与 `path` 变体；`windowPoint` 不应传入本方法（传入会抛
/// `notFound()`，作为防御）。`notFound` / `ambiguous` 两个工厂由调用方提供——因为 tap 与
/// control 命令对「未找到 / 歧义」映射到不同业务错误码（`targetNotFound` vs
/// `controlTargetNotFound`），定位器本身不持有调用语境，交由调用方决定。
///
/// - Parameters:
///   - locator: 统一定位器。
///   - rootView: 顶部控制器根 view。
///   - notFound: 未命中时构造的业务错误工厂。
///   - ambiguous: 命中多个时构造的业务错误工厂，入参为命中数量。
/// - Returns: 唯一命中的 `LocatedView`。
/// - Throws: 调用方提供的 `UIKitCommandError`（未找到 / 歧义）。
static func locate(locator: UIKitLocator,
                   in rootView: UIView,
                   notFound: () -> UIKitCommandError,
                   ambiguous: (Int) -> UIKitCommandError) throws -> LocatedView {
    switch locator {
    case .accessibilityIdentifier(let identifier):
        let matches = findViews(withAccessibilityIdentifier: identifier, in: rootView, path: [])
        if matches.isEmpty { throw notFound() }
        if matches.count > 1 { throw ambiguous(matches.count) }
        return matches[0]
    case .path(let indexes):
        guard let located = findView(at: indexes, in: rootView) else { throw notFound() }
        return located
    case .windowPoint:
        throw notFound()
    }
}
```

### Step 2: `UIKitSnapshotStore.validation` 改 `isStale`（删 `UIKitSnapshotValidation`）

`UIKitSnapshotStore.swift`：

把两个 `validation(...)` 方法（line 258-286 带 context、line 291-295 不带 context）改为 `isStale(...) -> Bool`，删掉文件末尾的 `public enum UIKitSnapshotValidation`（line 319-328）：

```swift
/// 校验 snapshot 是否陈旧（snapshot 不存在、TTL 过期、context 变化、path 缺失或指纹不匹配）。
///
/// executor 对携带 snapshotID 的交互在陈旧时 throw `staleLocator`；所有无法验证的情况均
/// 返回 `true`，防止 LRU 淘汰后的旧 path 静默退化为无防护执行。
///
/// - Parameters:
///   - snapshotID: 调用方携带的快照标识。
///   - path: 要交互的目标 path。
///   - context: 当前查询上下文身份。
///   - current: 当前重新采集的该 path 指纹。
/// - Returns: `true` 表示陈旧（需重新查询）；`false` 表示有效。
public func isStale(snapshotID: String,
                    path: String,
                    context: UIKitSnapshotContext,
                    current: UIKitTargetFingerprint) -> Bool {
    guard var entry = entries[snapshotID] else {
        UIKitCommandLogging.info("command", "ui snapshot unknown id=\(snapshotID) path=\(path)")
        return true
    }
    if isExpired(entry: entry) {
        entries.removeValue(forKey: snapshotID)
        UIKitCommandLogging.info("command", "ui snapshot expired id=\(snapshotID) path=\(path)")
        return true
    }
    entry.lastAccessedAt = now()
    entries[snapshotID] = entry
    guard entry.context == context else {
        UIKitCommandLogging.info("command", "ui snapshot context mismatch id=\(snapshotID) path=\(path)")
        return true
    }
    guard let stored = entry.fingerprints[path] else {
        UIKitCommandLogging.info("command", "ui snapshot path missing id=\(snapshotID) path=\(path)")
        return true
    }
    if stored == current { return false }
    UIKitCommandLogging.info("command", "ui snapshot fingerprint mismatch id=\(snapshotID) path=\(path)")
    return true
}

/// 兼容未传实例上下文的既有调用方（Foundation 测试）。
public func isStale(snapshotID: String,
                    path: String,
                    current: UIKitTargetFingerprint) -> Bool {
    isStale(snapshotID: snapshotID, path: path, context: .test, current: current)
}
```

### Step 3: `UIKitContextProvider.currentContext` 改 throws（删 `ContextResult`）

`UIKitContextProvider.swift`：

删掉 `enum ContextResult`（line 32-38），把 `currentContext()`（line 40-58）改为：

```swift
/// 获取当前顶部控制器 view 查询上下文，失败时抛出 `hierarchyUnavailable`。
///
/// - Parameter action: 触发查询的 action 名，用于错误工厂的日志关联。
/// - Returns: 当前查询上下文。
/// - Throws: `UIKitCommandError.hierarchyUnavailable`——active window / root / top view 任一不可用时。
static func currentContext(action: String) throws -> Context {
    guard let window = activeWindow() else {
        throw UIKitCommandError.hierarchyUnavailable(action: action, reason: "active window not found")
    }
    guard let rootViewController = window.rootViewController else {
        throw UIKitCommandError.hierarchyUnavailable(action: action, reason: "root view controller not found")
    }
    let topViewController = topViewController(from: rootViewController)
    guard let rootView = topViewController.view else {
        throw UIKitCommandError.hierarchyUnavailable(action: action, reason: "top view controller view not found")
    }
    return Context(window: window,
                   rootViewController: rootViewController,
                   topViewController: topViewController,
                   rootView: rootView)
}
```

同步更新类型文档注释里「只能 `await` 其 `currentContext()`」措辞为「只能 `await` 其 `currentContext(action:)`，`throws` 失败」。

### Step 4: `UIKitActionExecutor` 改 throws（线性 try）

`UIKitActionExecutor.swift`：

**(a)** `execute(_:)`（line 44-55）：

```swift
static func execute(_ plan: UIKitActionPlan) throws -> JSON {
    let context = try UIKitContextProvider.currentContext(action: actionName(for: plan))
    return try execute(plan, context: context)
}
```

**(b)** `execute(_:context:)`（line 67-74）签名 `-> ExploreResult` 改 `throws -> JSON`（内部 `executeTap`/`executeControlEvent` 已改 throws，加 `try`）：

```swift
static func execute(_ plan: UIKitActionPlan, context: UIKitContextProvider.Context) throws -> JSON {
    switch plan {
    case .tap(let locator, let snapshotID):
        return try executeTap(locator: locator, snapshotID: snapshotID, context: context)
    case .controlEvent(let locator, let event, let snapshotID):
        return try executeControlEvent(locator: locator, event: event, snapshotID: snapshotID, context: context)
    }
}
```

**(c)** `validateFreshness`（line 97-118）从「返回 `ExploreResult?`」改 `throws`：

```swift
private static func validateFreshness(located: UIKitLocatorResolver.LocatedView,
                                      snapshotID: String?,
                                      context: UIKitContextProvider.Context,
                                      action: String) throws {
    guard let snapshotID else { return }
    let path = located.pathString
    let current = UIKitFingerprintCollector.fingerprint(for: located.view,
                                                         path: path,
                                                         rootView: context.rootView,
                                                         digest: UIKitFingerprintCollector.digest(topViewController: context.topViewController))
    if UIKitSnapshotStore.shared.isStale(snapshotID: snapshotID,
                                         path: path,
                                         context: UIKitFingerprintCollector.context(window: context.window, topViewController: context.topViewController),
                                         current: current) {
        throw UIKitCommandError.staleLocator(action: action, snapshotID: snapshotID)
    }
}
```

**(d)** `executeTap`（line 132-169）改为线性 try，删除所有 `switch … case .notFound/.ambiguous` + `return error.result`：

```swift
private static func executeTap(locator: UIKitLocator,
                               snapshotID: String?,
                               context: UIKitContextProvider.Context) throws -> JSON {
    switch locator {
    case .accessibilityIdentifier, .path:
        let target = locatorSummary(locator)
        let located = try UIKitLocatorResolver.locate(
            locator: locator,
            in: context.rootView,
            notFound: { UIKitCommandError.targetNotFound(action: tapAction, targetDescription: target) },
            ambiguous: { UIKitCommandError.targetAmbiguous(action: tapAction, targetDescription: target, count: $0) })
        if case .path = locator, let snapshotID {
            try validateFreshness(located: located, snapshotID: snapshotID, context: context, action: tapAction)
        }
        return try executeTapViewTarget(located, context: context)
    case .windowPoint(let x, let y):
        return try executeTapWindowPoint(CGPoint(x: x, y: y),
                                         targetDescription: locatorSummary(locator),
                                         context: context)
    }
}
```

**(e)** `executeTapViewTarget`（line 176-205）改 `throws -> JSON`：保留 hitTest / hitMismatch 判断，把每个 `let error = …; UIKitCommandLogging.error(…); return error.result` 三行精简为 `throw …` 一行。例：

```swift
guard let hitView = context.window.hitTest(point, with: nil) else {
    throw UIKitCommandError.hitTestFailed(action: tapAction,
                                          targetDescription: located.pathString,
                                          x: Double(point.x),
                                          y: Double(point.y))
}
guard UIKitLocatorResolver.view(hitView, isDescendantOfOrSameAs: located.view) ||
      UIKitLocatorResolver.view(located.view, isDescendantOfOrSameAs: hitView) else {
    throw UIKitCommandError.hitMismatch(action: tapAction,
                                        targetDescription: located.pathString,
                                        hitType: String(describing: Swift.type(of: hitView)))
}
let control = (located.view as? UIControl) ??
    UIKitLocatorResolver.nearestControl(from: hitView, stoppingAt: located.view.superview)
return try dispatchTap(to: control, hitView: hitView, point: point, targetDescription: located.pathString, context: context)
```

**(f)** `executeTapWindowPoint`（line 208-225）、`dispatchTap`（line 232-273）同样：签名加 `throws -> JSON`，hitTestFailed / unsupportedTarget / unsupportedAction 三行错误块各精简为单行 `throw`；`return .success([...])` 改 `return [...]`（返回类型 `JSON`，字面量自动转 `.object`）；`dispatchTap` 末尾的 info 日志保留。

**(g)** `executeControlEvent`（line 285-347）：与 executeTap 同型。locate 用 `controlTargetNotFound` / `controlTargetAmbiguous` 工厂：

```swift
let located = try UIKitLocatorResolver.locate(
    locator: locator,
    in: context.rootView,
    notFound: { UIKitCommandError.controlTargetNotFound(action: controlAction, targetDescription: target) },
    ambiguous: { UIKitCommandError.controlTargetAmbiguous(action: controlAction, targetDescription: target, count: $0) })
if case .path = locator, let snapshotID {
    try validateFreshness(located: located, snapshotID: snapshotID, context: context, action: controlAction)
}
guard let control = located.view as? UIControl else {
    throw UIKitCommandError.controlTargetNotControl(action: controlAction,
                                                     targetDescription: located.pathString,
                                                     type: String(describing: Swift.type(of: located.view)))
}
let requestedAction = UIKitActionCapabilityResolver.actionKind(for: event)
let availability = UIKitActionCapabilityResolver.resolve(view: control, rootView: context.rootView, nearestControl: control)
guard availability.actions.contains(requestedAction) else {
    throw UIKitCommandError.unsupportedAction(action: controlAction,
                                              targetDescription: located.pathString,
                                              requestedAction: requestedAction.rawValue)
}
UIKitCommandLogging.info("command", "ui control send action mainactor target=\(located.pathString) type=\(String(describing: Swift.type(of: control))) event=\(event.rawValue) enabled=\(control.isEnabled)")
control.sendActions(for: event.uiControlEvent)
return [
    "sent": .bool(true),
    "event": .string(event.rawValue),
    "path": .string(located.pathString),
    "type": .string(String(describing: Swift.type(of: control))),
    "accessibilityIdentifier": control.accessibilityIdentifier.map(JSONValue.string) ?? .null,
    "isEnabled": .bool(control.isEnabled),
    "isSelected": .bool(control.isSelected),
    "isHighlighted": .bool(control.isHighlighted),
]
```

`executeControlEvent`、`executeTapViewTarget`、`executeTapWindowPoint`、`dispatchTap` 全部声明 `throws -> JSON`。

**关键：** 删除每个方法体里 `UIKitCommandLogging.error("command", error.failure.logMessage)` 这些手记日志——失败日志统一收拢到 handler 顶层（Step 7）。各方法的 `UIKitCommandLogging.info(...)`（start / dispatch 摘要）保留。

### Step 5: `UIViewHierarchyCollector` 改 throws

`UIViewHierarchyCollector.swift`：

`collectTopViewHierarchy(query:)`（line 16-27）改为：

```swift
static func collectTopViewHierarchy(query: UIViewHierarchyQuery) throws -> JSON {
    UIKitCommandLogging.info("command", "ui hierarchy collect mainactor start detailLevel=\(query.detailLevel.rawValue) maxDepth=\(query.maxDepth.map(String.init) ?? "none") includeHidden=\(query.includeHidden) hasFilter=\(query.hasIdentifierFilter)")
    let context = try UIKitContextProvider.currentContext(action: TopViewHierarchyCommand.actionName)
    return collectTopViewHierarchy(query: query, context: context)
}
```

`collectTopViewHierarchy(query:context:)`（line 38）：签名 `-> ExploreResult` 改 `-> JSON`（注入入口不 throws——它无失败分支），末尾 `return .success(data)` 改 `return data`，`var data: JSON` 改 `let data: JSON`。

### Step 6: `UIViewTargetsCollector` 改 throws

`UIViewTargetsCollector.swift`：与 Step 5 同型。`collect(query:)`（line 16-28）：

```swift
static func collect(query: UIViewTargetsQuery) throws -> JSON {
    UIKitCommandLogging.info("command", "ui view targets collect mainactor start includeHidden=\(query.includeHidden) includeDisabled=\(query.includeDisabled) includeStaticText=\(query.includeStaticText) includeContainers=\(query.includeContainers) maxDepth=\(query.maxDepth.map(String.init) ?? "none") hasFilter=\(query.hasIdentifierFilter) textLimit=\(query.textLimit)")
    let context = try UIKitContextProvider.currentContext(action: ViewTargetsCommand.actionName)
    return collect(query: query, context: context)
}
```

`collect(query:context:)`（line 39）：`-> ExploreResult` 改 `-> JSON`，`let data: JSON` 保留，`return .success(data)` 改 `return data`。

### Step 7: 4 个 handler 顶层 do/catch

每个 handler 把「parse do/catch + await execute/collect + switch result 记日志」收敛为单一顶层 `do/catch`。**失败日志在此一处记**（`error.failure.logMessage`）。

`UITapCommand.handle`（`UITapCommand.swift` line 56-75）：

```swift
func handle(_ request: ExploreRequest) async throws -> ExploreResult {
    UIKitCommandLogging.info("command", "command \(action) start payloadKeys=\(request.data.storage.count)")
    do {
        let query = try UITapQuery.parse(from: request.data)
        let plan = UIKitActionPlan.tap(locator: query.target.locator, snapshotID: query.snapshotID)
        let data = try await UIKitActionExecutor.execute(plan)
        UIKitCommandLogging.info("command", "command \(action) completed target=\(query.target.description) dispatchMode=\(data["dispatchMode"]?.stringValue ?? "unknown")")
        return .success(data)
    } catch let error as UIKitCommandError {
        UIKitCommandLogging.error("command", error.failure.logMessage)
        return error.result
    } catch let parseError as QueryParseError {
        let error = UIKitCommandError.invalidData(action: action, message: parseError.message)
        UIKitCommandLogging.error("command", error.failure.logMessage)
        return error.result
    }
}
```

`UIControlSendActionCommand.handle`（同结构，do 块内 plan 用 `UIKitActionPlan.controlEvent(locator:event:snapshotID:)`，completed 日志含 `event=\(query.event.rawValue) type=\(data["type"]?.stringValue ?? "unknown")`）：

```swift
func handle(_ request: ExploreRequest) async throws -> ExploreResult {
    UIKitCommandLogging.info("command", "command \(action) start payloadKeys=\(request.data.storage.count)")
    do {
        let query = try UIControlSendActionQuery.parse(from: request.data)
        let plan = UIKitActionPlan.controlEvent(locator: query.target.locator,
                                                event: query.event,
                                                snapshotID: query.snapshotID)
        let data = try await UIKitActionExecutor.execute(plan)
        UIKitCommandLogging.info("command", "command \(action) completed target=\(query.target.description) event=\(query.event.rawValue) type=\(data["type"]?.stringValue ?? "unknown")")
        return .success(data)
    } catch let error as UIKitCommandError {
        UIKitCommandLogging.error("command", error.failure.logMessage)
        return error.result
    } catch let parseError as QueryParseError {
        let error = UIKitCommandError.invalidData(action: action, message: parseError.message)
        UIKitCommandLogging.error("command", error.failure.logMessage)
        return error.result
    }
}
```

`TopViewHierarchyCommand.handle`（do 块内 `let data = try await UIViewHierarchyCollector.collectTopViewHierarchy(query: query)`，completed 日志 `nodeCount=\(data["nodeCount"]?.doubleValue ?? 0) matchCount=\(data["matchCount"]?.doubleValue).map { String($0) } ?? "none")`）：

```swift
func handle(_ request: ExploreRequest) async throws -> ExploreResult {
    UIKitCommandLogging.info("command", "command \(action) start payloadKeys=\(request.data.storage.count)")
    do {
        let query = try UIViewHierarchyQuery.parse(from: request.data)
        let data = try await UIViewHierarchyCollector.collectTopViewHierarchy(query: query)
        let nodeCount = data["nodeCount"]?.doubleValue ?? 0
        let matchCount = data["matchCount"]?.doubleValue
        UIKitCommandLogging.info("command", "command \(action) completed nodeCount=\(nodeCount) matchCount=\(matchCount.map { String($0) } ?? "none")")
        return .success(data)
    } catch let error as UIKitCommandError {
        UIKitCommandLogging.error("command", error.failure.logMessage)
        return error.result
    } catch let parseError as QueryParseError {
        let error = UIKitCommandError.invalidData(action: action, message: parseError.message)
        UIKitCommandLogging.error("command", error.failure.logMessage)
        return error.result
    }
}
```

`ViewTargetsCommand.handle`（do 块内 `let data = try await UIViewTargetsCollector.collect(query: query)`，completed 日志 `targetCount=\(data["targetCount"]?.doubleValue ?? 0) visitedNodeCount=\(data["visitedNodeCount"]?.doubleValue ?? 0)`），catch 结构同上。

### Step 8: 改测试断言方式

**(a) `UIKitActionExecutorTests.swift`** —— 注入入口 `execute(_:context:)` 现返回 `JSON`（成功）或 throw `UIKitCommandError`（失败）。每个 `@Test` 函数标 `throws`。

成功路径模式（例：`executorTapsUIControlByPath`）：

```swift
@Test("executor 按 path tap 可交互 UIControl 走 controlActionFallback") @MainActor
func executorTapsUIControlByPath() throws {
    let context = UIKitTestHost.context { root in
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 100, y: 100, width: 120, height: 60)
        root.addSubview(button)
    }
    let data = try UIKitActionExecutor.execute(.tap(locator: .path([0]), snapshotID: nil), context: context)
    #expect(data["tapped"]?.boolValue == true)
    #expect(data["dispatchMode"]?.stringValue == "controlActionFallback")
    #expect(data["event"]?.stringValue == "touchUpInside")
    #expect(data["controlType"]?.stringValue == "UIButton")
    #expect(data["controlPath"]?.stringValue == "root/0")
}
```

其余成功测试（`executorTapsUIControlByIdentifier` / `executorTapWindowPointHitsControl` / `executorControlSendActionOnUIControl`）同样：去掉 `guard case .success(let data)`，改 `let data = try …`，保留 `#expect(data[…])`。

失败路径模式（例：`executorTapNonControlReturnsInvalidData`）——用 do/catch 断言 `error.failure.code`：

```swift
@Test("executor tap 非 control 可交互 view 返回 invalid_data") @MainActor
func executorTapNonControlReturnsInvalidData() {
    let context = UIKitTestHost.context { root in
        let view = UIView()
        view.frame = CGRect(x: 100, y: 100, width: 120, height: 60)
        view.isUserInteractionEnabled = true
        root.addSubview(view)
    }
    do {
        _ = try UIKitActionExecutor.execute(.tap(locator: .path([0]), snapshotID: nil), context: context)
        Issue.record("expected failure, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .invalidData)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}
```

`executorControlSendActionNonControlReturnsInvalidData` / `executorControlSendActionUnsupportedEventReturnsInvalidData` / `executorTapStaleSnapshotReturnsInvalidData` 同此模式。

`executorTapStaleSnapshotReturnsInvalidData`（line 160）额外：开头 `let collectResult = UIViewTargetsCollector.collect(query: .default, context: context)` 现注入入口返回 `JSON`，改为：

```swift
let data = UIViewTargetsCollector.collect(query: .default, context: context)
guard let snapshotID = data["snapshotID"]?.stringValue else {
    Issue.record("collect should produce snapshotID"); return
}
(context.rootView.subviews.first as? UIButton)?.isEnabled = false
// 然后 do/catch 断言 execute 抛 UIKitCommandError 且 code == .invalidData
```

**(b) `UIKitSnapshotTests.swift`** —— `validation(...) == .stale` 改 `isStale(...)`（3 处）。例（line 23）：

```swift
// before
#expect(store.validation(snapshotID: id, path: "root/0", current: .test) == .stale)
// after
#expect(store.isStale(snapshotID: id, path: "root/0", current: .test))
```

`snapshotRejectsChangedContextOrAncestorDigest`（line 49-64）两处 `validation(...:context:current:) == .stale` 改 `isStale(...:context:current:)`（去 `== .stale`）。`unknownSnapshotIsStale`（line 71）同样。

**(c) `UIKitCollectorTests.swift`** —— 注入入口返回 `JSON`。`viewTargetsCollectsTargetsInContext`（line 29-34）：

```swift
// before
let result = UIViewTargetsCollector.collect(query: .default, context: context)
guard case .success(let data) = result else { Issue.record("expected success, got \(result)"); return }
// after
let data = UIViewTargetsCollector.collect(query: .default, context: context)
```

`topViewHierarchyCollectsTreeInContext`（line 82-87）同样去掉 `guard case .success`，改 `let data = UIViewHierarchyCollector.collectTopViewHierarchy(query: query, context: context)`。

### Step 9: SPM 构建与测试

- [ ] Run: `swift build`
  Expected: BUILD SUCCEEDED（确认全部签名贯穿改动编译通过、3 个 Result 枚举已删）。
- [ ] Run: `swift test`
  Expected: 全绿（SPM macOS，原 105 个用例 + Task 1 新增，断言方式已迁移）。

### Step 10: framework 构建与测试（iOS）

- [ ] Run: `xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' test`
  Expected: TEST SUCCEEDED（含 iOS 正向注册断言、UIKitActionExecutorTests 运行时覆盖）。

### Step 11: Commit

```bash
git add Sources/iOSExploreUIKit Tests/iOSExploreServerTests
git commit -m "refactor(uikit): 执行核心 throw 化，删 ContextResult/LocateResult/UIKitSnapshotValidation"
```

---

## Task 3: 文件夹重组 `Commands/` + `Support/`

纯 `git mv`，不改代码。framework 工程 `PBXFileSystemSynchronizedRootGroup` 自动同步。

**Files:** 仅移动，无内容改动。

- [ ] **Step 1: 创建目录并移动文件**

在仓库根执行（`cd` 到仓库根 `iOSExploreServer/`）：

```bash
cd /Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer

# Commands/（4 命令 + 紧密配套）
mkdir -p Sources/iOSExploreUIKit/Commands/TopViewHierarchy
mkdir -p Sources/iOSExploreUIKit/Commands/ViewTargets
mkdir -p Sources/iOSExploreUIKit/Commands/Tap
mkdir -p Sources/iOSExploreUIKit/Commands/ControlAction

git mv Sources/iOSExploreUIKit/ViewHierarchy/TopViewHierarchyCommand.swift   Sources/iOSExploreUIKit/Commands/TopViewHierarchy/
git mv Sources/iOSExploreUIKit/ViewHierarchy/UIViewHierarchyModels.swift     Sources/iOSExploreUIKit/Commands/TopViewHierarchy/
git mv Sources/iOSExploreUIKit/ViewHierarchy/UIViewHierarchyCollector.swift   Sources/iOSExploreUIKit/Commands/TopViewHierarchy/

git mv Sources/iOSExploreUIKit/ViewTargets/ViewTargetsCommand.swift          Sources/iOSExploreUIKit/Commands/ViewTargets/
git mv Sources/iOSExploreUIKit/ViewTargets/UIViewTargetsModels.swift          Sources/iOSExploreUIKit/Commands/ViewTargets/
git mv Sources/iOSExploreUIKit/ViewTargets/UIViewTargetsCollector.swift       Sources/iOSExploreUIKit/Commands/ViewTargets/

git mv Sources/iOSExploreUIKit/Tap/UITapCommand.swift                        Sources/iOSExploreUIKit/Commands/Tap/
git mv Sources/iOSExploreUIKit/Tap/UITapModels.swift                         Sources/iOSExploreUIKit/Commands/Tap/

git mv Sources/iOSExploreUIKit/ControlAction/UIControlSendActionCommand.swift  Sources/iOSExploreUIKit/Commands/ControlAction/
git mv Sources/iOSExploreUIKit/ControlAction/UIControlSendActionModels.swift   Sources/iOSExploreUIKit/Commands/ControlAction/

# Support/（横切辅助）
mkdir -p Sources/iOSExploreUIKit/Support/Context
mkdir -p Sources/iOSExploreUIKit/Support/Locator
mkdir -p Sources/iOSExploreUIKit/Support/Action
mkdir -p Sources/iOSExploreUIKit/Support/Snapshot
mkdir -p Sources/iOSExploreUIKit/Support/Parsing

git mv Sources/iOSExploreUIKit/Context/UIKitContextProvider.swift             Sources/iOSExploreUIKit/Support/Context/

git mv Sources/iOSExploreUIKit/Locator/UIKitLocator.swift                     Sources/iOSExploreUIKit/Support/Locator/
git mv Sources/iOSExploreUIKit/Locator/UIKitLocatorResolver.swift             Sources/iOSExploreUIKit/Support/Locator/
git mv Sources/iOSExploreUIKit/Utils/UIKitViewLookupModels.swift              Sources/iOSExploreUIKit/Support/Locator/

git mv Sources/iOSExploreUIKit/Action/UIKitActionExecutor.swift               Sources/iOSExploreUIKit/Support/Action/
git mv Sources/iOSExploreUIKit/Action/UIKitActionCapabilityResolver.swift     Sources/iOSExploreUIKit/Support/Action/
git mv Sources/iOSExploreUIKit/Action/UIKitActionKind.swift                   Sources/iOSExploreUIKit/Support/Action/
git mv Sources/iOSExploreUIKit/Action/UIKitActionPlan.swift                   Sources/iOSExploreUIKit/Support/Action/

git mv Sources/iOSExploreUIKit/Snapshot/UIKitFingerprintCollector.swift       Sources/iOSExploreUIKit/Support/Snapshot/
git mv Sources/iOSExploreUIKit/Snapshot/UIKitSnapshotStore.swift              Sources/iOSExploreUIKit/Support/Snapshot/
git mv Sources/iOSExploreUIKit/Snapshot/UIKitSnapshotResponse.swift           Sources/iOSExploreUIKit/Support/Snapshot/

git mv Sources/iOSExploreUIKit/Utils/QueryDecoder.swift                       Sources/iOSExploreUIKit/Support/Parsing/
git mv Sources/iOSExploreUIKit/Utils/QueryParseError.swift                    Sources/iOSExploreUIKit/Support/Parsing/
git mv Sources/iOSExploreUIKit/Utils/UIKitQueryNumber.swift                   Sources/iOSExploreUIKit/Support/Parsing/

# 删除空目录
rmdir Sources/iOSExploreUIKit/ViewHierarchy Sources/iOSExploreUIKit/ViewTargets \
       Sources/iOSExploreUIKit/Tap Sources/iOSExploreUIKit/ControlAction \
       Sources/iOSExploreUIKit/Context Sources/iOSExploreUIKit/Locator \
       Sources/iOSExploreUIKit/Action Sources/iOSExploreUIKit/Snapshot \
       Sources/iOSExploreUIKit/Utils
```

- [ ] **Step 2: SPM 构建测试**

Run: `swift build && swift test`
Expected: 全绿（同模块内移动，无 import 变化）。

- [ ] **Step 3: framework 构建测试（确认 synchronized group 同步）**

Run: `xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: BUILD SUCCEEDED。若失败，确认两个 framework target 的 `PBXFileSystemSynchronizedRootGroup` 仍指向 `Sources/iOSExploreUIKit/`（目录移动不应破坏）。

- [ ] **Step 4: Commit**

```bash
git add -A Sources/iOSExploreUIKit
git commit -m "refactor(uikit): 文件夹重组 Commands/ + Support/，命令与辅助边界清晰"
```

---

## Task 4: 更新 `docs/uikit/` 文档路径

**Files:**
- Modify: `docs/uikit/uikit-file-reference.md`
- Modify: `docs/uikit/reading-guide.md`

- [ ] **Step 1: 更新 `uikit-file-reference.md`**

逐条把文件登记里的旧路径替换为新路径（25 个文件的登记 + 头部「25 个文件」计数不变）。映射表见 Task 3 的 `git mv` 列表。重点：
- 4 个 `*Command` + 各自 Models/Collector → `Commands/<领域>/`
- `UIKitContextProvider` → `Support/Context/`；`UIKitLocator`/`UIKitLocatorResolver`/`UIKitViewLookupModels` → `Support/Locator/`；executor 等 4 个 → `Support/Action/`；3 个 Snapshot → `Support/Snapshot/`；3 个解析工具 → `Support/Parsing/`
- 根目录 3 个（`UIKitCommandRegistrar`/`UIKitCommandError`/`UIKitCommandLogging`）不变。
- 同步描述「目录组织」的小节，改为 `Commands/` + `Support/` 两层。

- [ ] **Step 2: 更新 `reading-guide.md`**

把阅读路线里引用的文件路径同步为新路径；若其中有「throw 化」相关描述（`ContextResult`/`LocateResult` 返回值语义），更新为「失败 throw `UIKitCommandError`、handler 顶层 catch」。

- [ ] **Step 3: 更新 `docs/architecture/index.md`（若含 UIKit 子目录树）**

检索 `docs/architecture/index.md` 是否有 UIKit 文件夹树或 `UIKitContextProvider.ContextResult` 描述，有则同步。

- [ ] **Step 4: Commit**

```bash
git add docs/uikit docs/architecture
git commit -m "docs(uikit): 同步 throw 化与 Commands/Support 重组后的文件路径"
```

---

## Self-Review

**1. Spec coverage:**
- throw 化 B2（executor/collector `throws -> JSON`）：Task 2 Step 4-7。✓
- 删除 `ContextResult`/`LocateResult`/`UIKitSnapshotValidation`：Task 2 Step 1/2/3。✓
- `UIKitCommandError: Error`：Task 1。✓
- locate 的 notFound/ambiguous 工厂闭包（零新增 error 类型）：Task 2 Step 1 + Step 4(d)(g)。✓
- handler 顶层 catch + 失败日志收拢：Task 2 Step 7。✓
- 文件夹 `Commands/` + `Support/`（甲）：Task 3。✓
- collector 归 `Commands/X/`、executor 归 `Support/Action/`、`UIKitViewLookupModels` 归 `Support/Locator/`：Task 3 命令列表。✓
- 测试断言方式迁移：Task 2 Step 8。✓
- 文档路径同步：Task 4。✓

**2. Placeholder scan:** 无 TBD/TODO；每个改动给了 before/after 代码或精确命令；handler 的 `ViewTargetsCommand.handle` 与 `UIControlSendActionCommand.handle` 给了完整结构，`TopViewHierarchyCommand.handle` 给了完整结构，`UITapCommand.handle` 给了完整结构。

**3. Type consistency:** `locate(locator:in:notFound:ambiguous:) throws -> LocatedView` 在 Step 1 定义、Step 4(d)(g) 调用签名一致；`currentContext(action:) throws` 在 Step 3 定义、Step 4(a)/5/6 调用一致；`isStale(snapshotID:path:context:current:) -> Bool` 在 Step 2 定义、Step 4(c) 调用一致；executor/collector 返回类型统一 `JSON`，handler 与测试 `data[…]` 下标用法与现有一致。
