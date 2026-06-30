# 操作三件套命令（ui.screenshot / ui.input / ui.scroll）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 `ui.screenshot` / `ui.input` / `ui.scroll` 三个 UIKit 命令 + core 配套改动（错误码枚举、响应 body 软上限、Command 自声明 timeout），补齐 agent 闭环驱动 iPhone UI 的最后三块拼图。

**Architecture:** 三命令遵循 typed factory（`Command`+`CommandInput`，Foundation-only 解析校验 → `@MainActor` 执行核心 `throw UIKitCommandError` → adapter 顶层 `catch` 转 envelope）。查询命令（screenshot）签发 snapshot，动作命令（input/scroll）消费 snapshot。独立 executor（不进 `UIKitActionPlan`）。

**Tech Stack:** Swift 6.2 / SPM / Network(NWListener) / UIKit(iOS only, `#if canImport(UIKit)`) / Swift Testing。

**上游 spec:** `docs/superpowers/specs/2026-06-30-action-commands-design.md`（v4）。

> **v2 修订（经 codex 审查）：** 修正 8 BLOCKER（JSONValue 无 `.number`/locator 与 context 真实字段名/MainActor 边界/timeout 类型/send 签名/体积配置注入/Input 模型应 Foundation-only）+ 5 HIGH（collectFingerprints 收筛选/maxDimension 用 pixel/append expected/reachedExtent 用 ScrollExtent/TTL 进 Task 6 正文）。

## Global Constraints

- 库 `iOSExploreServer` 只依赖 Foundation + Network，**不依赖 UIKit**；UIKit 执行代码在 `iOSExploreUIKit`，整体 `#if canImport(UIKit)`。
- **typed Input 模型必须 Foundation-only（不包 `#if canImport(UIKit)`）**，让 macOS `swift test` 能直接编译 schema/parse 测试（对齐现有 `UIControlSendActionInput`）。只有 collector/executor/command adapter 包 `#if canImport(UIKit)`。
- Swift 6.2 严格并发：跨边界模型 `Sendable`；`@MainActor` 的 UIKit context 必须在 `MainActor.run { }` 内取用，**不穿过 public 非 MainActor 边界**；`UIImage` 非 Sendable，不跨 actor。
- 源码兼容 SPM(Swift 6.2) + framework(`SWIFT_VERSION=5.0`)：避免 6-only 语法。
- 统一 envelope：`{"code":"ok","data"?}` 或 `{"code":"..","message":".."}`。业务失败 HTTP 200 + body code；code 用 snake_case rawValue。
- **JSON 构造**：`JSONValue` 只有 `.string/.double/.bool/.object(JSON)/.array/.null`（**无 `.number`**）；`JSON` 支持字典字面量；嵌套对象用 `.object(JSON([...]))`；数值统一 `.double`。
- 所有新错误先扩 `ExploreError`(core) / `UIKitCommandError`(UIKit) 工厂。
- 改完先 `swift test`（macOS，Foundation-only）再 `xcodebuild ... test`（iOS）；覆盖率 ≥80%；集成端口 38399 串行。
- public 类型/属性/方法 `///` 注释；日志走 `UIKitCommandLogging`（category `command`），不泄露截图/payload/密码原文。

---

## Phase 1：core 基础设施

### Task 1: 扩展 ExploreError 枚举（新业务 code 的协议落点）

**Why:** spec §8.3——所有新 code 必须先在 core `ExploreError` 枚举有 case + rawValue，否则 UIKit 引用编译不过。

**Files:**
- Modify: `Sources/iOSExploreServer/Models.swift`（`ExploreError` 枚举）
- Modify: `Sources/iOSExploreServer/ExploreServerError.swift`（code→httpStatus 映射）
- Test: `Tests/iOSExploreServerTests/ExploreServerErrorContractTests.swift`

**Interfaces:**
- Produces: `ExploreError` 新 case，rawValue（snake_case）：`.timeout`/`.responseTooLarge`/`.staleLocator`/`.inputRejected`/`.transitionInProgress`/`.unsupportedTextInputType`/`.becomeFirstResponderFailed`/`.renderingFailed`/`.scrollContainerUnavailable`。

- [ ] **Step 1: 读现状**

Run: `codegraph node Sources/iOSExploreServer/Models.swift` + `codegraph node Sources/iOSExploreServer/ExploreServerError.swift`
Expected: 确认 `ExploreError: String, Sendable`；确认 code→httpStatus 映射机制。

- [ ] **Step 2: 写失败测试**

```swift
@Test("新增 ExploreError code 的 rawValue 契约")
func newErrorCodesRawValues() {
    #expect(ExploreError.timeout.rawValue == "timeout")
    #expect(ExploreError.responseTooLarge.rawValue == "response_too_large")
    #expect(ExploreError.staleLocator.rawValue == "stale_locator")
    #expect(ExploreError.inputRejected.rawValue == "input_rejected")
    #expect(ExploreError.transitionInProgress.rawValue == "transition_in_progress")
    #expect(ExploreError.unsupportedTextInputType.rawValue == "unsupported_text_input_type")
    #expect(ExploreError.becomeFirstResponderFailed.rawValue == "become_first_responder_failed")
    #expect(ExploreError.renderingFailed.rawValue == "rendering_failed")
    #expect(ExploreError.scrollContainerUnavailable.rawValue == "scroll_container_unavailable")
}
```

- [ ] **Step 3: 运行确认失败**

Run: `swift test --filter ExploreServerErrorContractTests`
Expected: FAIL。

- [ ] **Step 4: 加 case**

在 `ExploreError` 枚举追加（snake_case rawValue）：

```swift
case timeout = "timeout"
case responseTooLarge = "response_too_large"
case staleLocator = "stale_locator"
case inputRejected = "input_rejected"
case transitionInProgress = "transition_in_progress"
case unsupportedTextInputType = "unsupported_text_input_type"
case becomeFirstResponderFailed = "become_first_responder_failed"
case renderingFailed = "rendering_failed"
case scrollContainerUnavailable = "scroll_container_unavailable"
```

若 `ExploreServerError` 有 code→httpStatus 集中 switch，新 case 全部分 HTTP 200。**同步把 spec §9 MCP 表里的 `inputRejected` 等写法对齐为 rawValue snake_case**（spec 是文档，改 `input_rejected`）。

- [ ] **Step 5: 运行确认通过 + 全量回归**

Run: `swift test`
Expected: PASS（105+ 用例不回归）。

- [ ] **Step 6: 提交**

```bash
git add Sources/iOSExploreServer/Models.swift Sources/iOSExploreServer/ExploreServerError.swift docs/superpowers/specs/2026-06-30-action-commands-design.md Tests/iOSExploreServerTests/ExploreServerErrorContractTests.swift
git commit -m "feat(core): 扩展 ExploreError 新业务 code 枚举落点"
```

---

### Task 2: Command 自声明 timeout（两步查表，UInt64）

**Why:** spec §8.2——`withTimeout` 在 `ClientSession.process`（`ClientSession.swift:278`）包裹 `router.route`，timeout 须 route 之前确定；需 `Router.commandTimeout(for:)` 提前查表。**类型必须用 `UInt64`**（对齐 `commandTimeoutNanoseconds: UInt64` / `withTimeout(nanoseconds: UInt64)`）。

**Files:**
- Modify: `Sources/iOSExploreServer/Command.swift`（`Command.timeout`、`AnyCommand` 透传）
- Modify: `Sources/iOSExploreServer/Router.swift`（`commandTimeout(for:)`）
- Modify: `Sources/iOSExploreServer/ClientSession.swift`（process 两步查表；超时 `.timeout`）
- Modify: `Sources/iOSExploreServer/ExploreServerError.swift`（`commandTimeout` code 改 `.timeout`）
- Test: `Tests/iOSExploreServerTests/RouterTests.swift`、`ExploreServerErrorContractTests.swift`

**Interfaces:**
- Produces: `Command.timeoutNanoseconds: UInt64?`（默认 nil=全局）、`AnyCommand.timeoutNanoseconds`、`Router.commandTimeout(for:) -> UInt64?`。

- [ ] **Step 1: 写失败测试**

```swift
@Test("Router.commandTimeout 返回命令自声明 timeoutNanoseconds，缺省 nil")
func commandTimeoutLookup() async {
    let router = Router()
    router.register(action: "defaultTimeout", input: EmptyCommandInput.self) { _ in .success([:]) }
    #expect(await router.commandTimeout(for: "defaultTimeout") == nil)
    #expect(await router.commandTimeout(for: "unregistered") == nil)
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter RouterTests`
Expected: FAIL。

- [ ] **Step 3: 实现**

`Command.swift` 协议加（**UInt64，非 Duration**）：

```swift
/// 命令自声明的执行超时（纳秒）；nil 表示用全局 commandTimeout。类型对齐 ClientSession.Configuration.commandTimeoutNanoseconds。
var timeoutNanoseconds: UInt64? { get }
```

```swift
public extension Command {
    var timeoutNanoseconds: UInt64? { nil }
}
```

`AnyCommand` 加 `let timeoutNanoseconds: UInt64?`，两个 init 里赋值（协议命令 init 读 `command.timeoutNanoseconds`；闭包命令 init 传 nil）。

`Router.swift`：

```swift
func commandTimeout(for action: String) -> UInt64? {
    handlers.withLock { $0[action]?.timeoutNanoseconds }
}
```

`ClientSession.process`（约 278 行）改：

```swift
let timeoutNanos = router.commandTimeout(for: exploreReq.action)
    ?? configuration.commandTimeoutNanoseconds
result = try await withTimeout(nanoseconds: timeoutNanos,
                               timeoutError: .commandTimeout(action: exploreReq.action)) { [router] in
    await router.route(exploreReq)
}
```

`ExploreServerError.commandTimeout` 的 code 从 `.internalError` 改 `.timeout`；更新契约测试。

- [ ] **Step 4: 运行确认通过**

Run: `swift test`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add Sources/iOSExploreServer/Command.swift Sources/iOSExploreServer/Router.swift Sources/iOSExploreServer/ClientSession.swift Sources/iOSExploreServer/ExploreServerError.swift Tests/iOSExploreServerTests/RouterTests.swift Tests/iOSExploreServerTests/ExploreServerErrorContractTests.swift
git commit -m "feat(core): Command 自声明 timeoutNanoseconds（Router 两步查表）+ 超时单独 code"
```

---

### Task 3: 响应 body 软上限（send 加 action + public 暴露）

**Why:** spec §8.1——screenshot 响应可能数 MB，core 响应方向无保护。**`send` 当前无 action 参数，需扩签名**才能记正确 action。

**Files:**
- Modify: `Sources/iOSExploreServer/ExploreServer.swift`（public init 暴露 `maxResponseBodyBytes`）
- Modify: `Sources/iOSExploreServer/ClientSession.swift`（`Configuration` 加字段；`send(_:action:closeReason:)`）
- Modify: `Sources/iOSExploreServer/ExploreServerError.swift`（`responseTooLarge` 工厂）
- Test: `Tests/iOSExploreServerTests/ExploreServerErrorContractTests.swift`

**Interfaces:**
- Produces: `ExploreServer.init(..., maxResponseBodyBytes: Int = 6MB)`；`ClientSession.send(_:action:closeReason:)`；`ExploreServerError.responseTooLarge(action:bytes:limit:)`。

- [ ] **Step 1: 读 send/Configuration 链路**

Run: `codegraph node Sources/iOSExploreServer/ClientSession.swift`（看 `send`、`Configuration`、`process` 怎么调 send）+ `codegraph node Sources/iOSExploreServer/ExploreServer.swift`（public init）。
Expected: 搞清 `maxBodyBytes` 传递路径，照搬 `maxResponseBodyBytes`。

- [ ] **Step 2: 写失败测试**

```swift
@Test("responseTooLarge: HTTP 200 + response_too_large")
func responseTooLargeEnvelope() throws {
    let error = ExploreServerError.responseTooLarge(action: "ui.screenshot", bytes: 7_000_000, limit: 6_000_000)
    #expect(error.code == .responseTooLarge)
    #expect(error.httpStatus == 200)
}
```

- [ ] **Step 3: 运行确认失败**

Run: `swift test --filter ExploreServerErrorContractTests`
Expected: FAIL。

- [ ] **Step 4: 实现**

`ExploreServerError.swift`：

```swift
static func responseTooLarge(action: String, bytes: Int, limit: Int) -> ExploreServerError {
    ExploreServerError(category: .command, httpStatus: 200, httpReason: "OK",
                       code: .responseTooLarge, message: "response body too large",
                       logMessage: "response too large action=\(action) bytes=\(bytes) limit=\(limit)")
}
```

`ClientSession.Configuration` 加 `let maxResponseBodyBytes: Int`（默认 6MB），沿 `maxBodyBytes` 路径下传。

`ClientSession.send` 改签名为 `send(_ response: HTTPResponse, action: String?, closeReason: String)`，在 `connection.send` 前加：

```swift
if response.body.count > configuration.maxResponseBodyBytes {
    let error = ExploreServerError.responseTooLarge(action: action ?? "unknown",
                                                    bytes: response.body.count,
                                                    limit: configuration.maxResponseBodyBytes)
    ExploreLogger.error(.listener, "session response too large id=\(sessionID) action=\(action ?? "?") bytes=\(response.body.count) limit=\(configuration.maxResponseBodyBytes)")
    await send(HTTPParser.errorResponse(for: error), action: action, closeReason: "response_too_large")
    return
}
```

`ClientSession` **所有** `send(...)` 调用补 `action:`：`process` 内传 `exploreReq.action`；`run`（`ClientSession.swift:187`）和 `readRequest`（`:217` bad_request 分支）传 `action: nil`（codex 复审：这两处也调 send，漏改会编译失败）。

`ExploreServer` public init 加 `maxResponseBodyBytes: Int = 6 * 1024 * 1024`。

- [ ] **Step 5: 运行确认通过**

Run: `swift test`
Expected: PASS。

- [ ] **Step 6: 提交**

```bash
git add Sources/iOSExploreServer/ExploreServerError.swift Sources/iOSExploreServer/ExploreServer.swift Sources/iOSExploreServer/ClientSession.swift Tests/iOSExploreServerTests/ExploreServerErrorContractTests.swift
git commit -m "feat(core): 响应 body 软上限（send 加 action + public init 暴露）"
```

---

## Phase 2：UIKit 支撑

### Task 4: UIKitLocatorInput.parseOptional + 最小 schema 测试

**Why:** spec §6/§7——`ui.scroll` 定位字段都缺时走"最前 scrollView"，但现有 `UIKitLocatorInput.parse` 两者都缺会抛错。

**Files:**
- Modify: `Sources/iOSExploreUIKit/Support/Parsing/UIKitCommandFields.swift`
- Test: `Tests/iOSExploreServerTests/UIKitCommandInputSchemaTests.swift`

**Interfaces:**
- Produces: `UIKitLocatorInput.parseOptional(decoder:identifierField:pathField:) throws -> UIKitViewLookupTarget?`。

- [ ] **Step 1: 写失败测试（用真实最小 schema，不用 EmptyCommandInput 占位）**

```swift
@Test("parseOptional: 都缺 nil；互斥抛错")
func parseOptionalLocator() throws {
    let schema = CommandInputSchema(fields: [
        UIKitLocatorFields.accessibilityIdentifier.erased,
        UIKitLocatorFields.path.erased,
    ])
    // 都缺
    var d1 = CommandInputDecoder(JSON([:]), schema: schema)
    #expect(try UIKitLocatorInput.parseOptional(decoder: &d1) == nil)
    // 两者都给 → 互斥抛错
    #expect(throws: CommandInputParseError.self) {
        var d2 = CommandInputDecoder(JSON(["accessibilityIdentifier": "x", "path": "root/0"]), schema: schema)
        _ = try UIKitLocatorInput.parseOptional(decoder: &d2)
    }
    // 单 path
    var d3 = CommandInputDecoder(JSON(["path": "root/0"]), schema: schema)
    let t = try UIKitLocatorInput.parseOptional(decoder: &d3)
    #expect(t != nil)
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter UIKitCommandInputSchemaTests`
Expected: FAIL。

- [ ] **Step 3: 实现**

```swift
public static func parseOptional(decoder: inout CommandInputDecoder,
                                 identifierField: CommandField<String?> = UIKitLocatorFields.accessibilityIdentifier,
                                 pathField: CommandField<String?> = UIKitLocatorFields.path) throws -> UIKitViewLookupTarget? {
    let identifier = try decoder.read(identifierField)
    let rawPath = try decoder.read(pathField)
    guard identifier != nil || rawPath != nil else { return nil }
    do {
        return try UIKitViewLookupTarget.parse(identifier: identifier, rawPath: rawPath)
    } catch let error as UIKitLocatorParseError {
        throw CommandInputParseError(error.message)
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter UIKitCommandInputSchemaTests`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add Sources/iOSExploreUIKit/Support/Parsing/UIKitCommandFields.swift Tests/iOSExploreServerTests/UIKitCommandInputSchemaTests.swift
git commit -m "feat(uikit): UIKitLocatorInput.parseOptional"
```

---

### Task 5: UIKitActionKind + capability resolver 扩展（.input/.scroll + UITextView 排除）

**Why:** spec §3.5——resolver `guard let control` 使 UITextView `.input` 空集；UITextView 是 UIScrollView 子类会误暴露 `.scroll`。

**Files:**
- Modify: `Sources/iOSExploreUIKit/Support/Action/UIKitActionKind.swift`
- Modify: `Sources/iOSExploreUIKit/Support/Action/UIKitActionCapabilityResolver.swift`
- Test: `Tests/iOSExploreServerTests/UIKitActionCapabilityTests.swift`（@MainActor iOS framework）

**Interfaces:**
- Produces: `UIKitActionKind.input`/`.scroll`（rawValue `"input"`/`"scroll"`）；resolver 对 UITextField/UITextView/UISearchTextField 声明 `.input`、UIScrollView 系（非 UITextView）声明 `.scroll`。

- [ ] **Step 1: 读 resolver 真实返回结构**

Run: `codegraph node Sources/iOSExploreUIKit/Support/Action/UIKitActionCapabilityResolver.swift` + `codegraph node UIKitActionKind`
Expected: 确认 `resolve(view:rootView:nearestControl:)` 返回类型的 `actions` 字段名、`UIKitActionAvailability` 结构、`UIKitActionKind` 现有 case。

- [ ] **Step 2: 写失败测试（@MainActor iOS）**

```swift
@Test("capability: input/scroll 声明 + UITextView 排除 scroll")
@MainActor
func capabilityDeclarations() {
    let root = UIView()
    let textField = UITextField(); root.addSubview(textField)
    let scrollView = UIScrollView(); root.addSubview(scrollView)
    let textView = UITextView(); root.addSubview(textView)
    let plain = UIView(); root.addSubview(plain)
    // 断言按真实 actions 结构调整（contains .input/.scroll）
    #expect(UIKitActionCapabilityResolver.resolve(view: textField, rootView: root, nearestControl: textField).actions.contains(.input))
    #expect(UIKitActionCapabilityResolver.resolve(view: scrollView, rootView: root, nearestControl: nil).actions.contains(.scroll))
    #expect(!UIKitActionCapabilityResolver.resolve(view: textView, rootView: root, nearestControl: nil).actions.contains(.scroll))
    #expect(UIKitActionCapabilityResolver.resolve(view: plain, rootView: root, nearestControl: nil).actions.isEmpty)
}
```

> `UIKitActionAvailability.actions` 是 `[UIKitActionKind]`，直接 `.contains(.input)`/`.contains(.scroll)`（codex 复审核对）。

- [ ] **Step 3: 运行确认失败**

Run: `xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:iOSExploreServerTests/UIKitActionCapabilityTests`
Expected: FAIL。

- [ ] **Step 4: 实现**

`UIKitActionKind` 加 `case input`/`case scroll`（rawValue `"input"`/`"scroll"`，对齐现有命名风格）。

`UIKitActionCapabilityResolver`：在 `resolve` 内 isInteractable 通过后，加 UITextInput/UIScrollView 路径（与现有 UIControl 路径并列）：

```swift
// UITextView 不声明 scroll（内部长文滚动留 v2），但 conform UITextInput → 声明 input
if view is UITextInput { avail.insert(.input) }           // UITextField/UITextView/UISearchTextField
if view is UIScrollView, !(view is UITextView) { avail.insert(.scroll) }
```

disabled 控件沿用"返回空集"。具体 insert 语法按现有 actions 构造方式。

- [ ] **Step 5: 运行确认通过**

Run: 同 Step 3
Expected: PASS。

- [ ] **Step 6: 提交**

```bash
git add Sources/iOSExploreUIKit/Support/Action/UIKitActionKind.swift Sources/iOSExploreUIKit/Support/Action/UIKitActionCapabilityResolver.swift Tests/iOSExploreServerTests/UIKitActionCapabilityTests.swift
git commit -m "feat(uikit): capability 扩展 input/scroll + UITextView scroll 排除"
```

---

### Task 6: 指纹采集统一（collectFingerprints 收 UIViewTargetsInput）+ TTL→30s

**Why:** spec §3.2/§3.6——screenshot 签发的指纹集必须与 `ui.viewTargets` 默认采集**逐字同筛选**；snapshot TTL 10s→30s（spec §3.6）。

**Files:**
- Modify: `Sources/iOSExploreUIKit/Support/Snapshot/UIKitFingerprintCollector.swift`
- Modify: `Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsCollector.swift`（改调共享 helper，输出契约不变）
- Modify: `Sources/iOSExploreUIKit/Support/Snapshot/UIKitSnapshotStore.swift`（`ttlSeconds = 30`）
- Test: `Tests/iOSExploreServerTests/UIKitCollectorTests.swift`、`UIKitSnapshotTests.swift`

**Interfaces:**
- Produces: `UIKitFingerprintCollector.collectFingerprints(rootView:query:digest:) -> [String:UIKitTargetFingerprint]`（**收 UIViewTargetsInput 筛选**，viewTargets 与 screenshot 共用）。

- [ ] **Step 1: 读 viewTargets 采集 + TTL 现状**

Run: `codegraph node UIViewTargetsCollector` + `codegraph node UIKitFingerprintCollector` + `codegraph node UIKitSnapshotStore`
Expected: 看清 viewTargets 怎么从 rootView + UIViewTargetsInput 筛选生成 path→fingerprint 表；TTL=10（UIKitSnapshotStore.swift:180）。

- [ ] **Step 2: 写回归测试（viewTargets 输出契约不变 + TTL=30）**

```swift
@Test("viewTargets 指纹采集重构后输出契约不变")
@MainActor
func viewTargetsFingerprintContractUnchanged() throws {
    // 重构前先记录快照：targetCount + 各 path；重构后断言一致
}
@Test("snapshot TTL=30s")
func snapshotTTL30() {
    // 25s 不过期、35s 过期（用 setNow 注入时间）
}
```

- [ ] **Step 3: 实现 collectFingerprints（收 query）**

```swift
/// viewTargets 与 ui.screenshot 共享的"目标指纹表"采集入口。
/// 收 UIViewTargetsInput 保证两命令同筛选，使跨命令 snapshotID 校验成立。
static func collectFingerprints(rootView: UIView,
                                query: UIViewTargetsInput,
                                digest: String) -> [String: UIKitTargetFingerprint] {
    // 把 UIViewTargetsCollector 现有"遍历→按筛选输出 target + 建 fingerprint"的逻辑搬来，
    // 返回 path→fingerprint 表（与 viewTargets 响应里的 targets 同源同筛选）。
    ...
}
```

`UIViewTargetsCollector` 改调 `collectFingerprints`，**筛选参数与重构前完全相同**。

- [ ] **Step 4: 改 TTL**

`UIKitSnapshotStore.swift:180`：`static let ttlSeconds: TimeInterval = 30`。更新 `UIKitSnapshotTests` 里 TTL 过期断言（原 10s 边界改 30s）+ stale message 文案（spec §3.6："请重新调用 ui.screenshot 获取新快照"）。

- [ ] **Step 5: 运行确认不回归**

Run: `xcodebuild ... test -only-testing:iOSExploreServerTests/UIKitCollectorTests` + `UIKitSnapshotTests`
Expected: PASS。

- [ ] **Step 6: 提交**

```bash
git add Sources/iOSExploreUIKit/Support/Snapshot/UIKitFingerprintCollector.swift Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsCollector.swift Sources/iOSExploreUIKit/Support/Snapshot/UIKitSnapshotStore.swift Tests/iOSExploreServerTests/UIKitCollectorTests.swift Tests/iOSExploreServerTests/UIKitSnapshotTests.swift
git commit -m "refactor(uikit): collectFingerprints 收 UIViewTargetsInput 共享 + snapshot TTL 30s"
```

---

## Phase 3：三个命令

> 三命令的 **Input 模型 Foundation-only（不包 `#if canImport(UIKit)`）**，对齐 `UIControlSendActionInput`；只有 collector/executor/command adapter 包 `#if canImport(UIKit)`。
> UIKit 调用统一模式：adapter `handle` 内 `await MainActor.run { try UIKitContextProvider.currentContext(action:...); ... executor.execute(...) }`（context 是 `@MainActor`，必须 MainActor.run 内取用）。

### Task 7: ui.screenshot

**Files:**
- Create: `Sources/iOSExploreUIKit/Commands/Screenshot/UIScreenshotModels.swift`（**Foundation-only**，`UIScreenshotInput`）
- Create: `Sources/iOSExploreUIKit/Commands/Screenshot/UIScreenshotCollector.swift`（`#if canImport(UIKit)`，@MainActor）
- Create: `Sources/iOSExploreUIKit/Commands/Screenshot/UIScreenshotCommand.swift`（`#if canImport(UIKit)`）
- Modify: `Sources/iOSExploreUIKit/UIKitCommandError.swift`（`renderingFailed`/`transitionInProgress`）
- Modify: `Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift`（注册，count→5）

**Interfaces:**
- Consumes: Task 1(`.renderingFailed`/`.transitionInProgress`/`.responseTooLarge`)、Task 2(`timeoutNanoseconds`=30s)、Task 3(`maxResponseBodyBytes` 经注册注入)、Task 6(`collectFingerprints`)、`UIKitContextProvider.currentContext(action:)`、`UIKitFingerprintCollector.digest/context`、`UIKitSnapshotStore.shared.insert`、`UIKitSnapshotResponse.fields`
- Produces: `UIScreenshotInput`（`maxDimension?:Int` 默认 1280，1-4096，**pixel**）、`ScreenshotCommand(maxResponseBodyBytes:)`（actionName `"ui.screenshot"`，timeout 30s）。

- [ ] **Step 1: 写失败测试——Input schema（macOS）**

```swift
@Test("UIScreenshotInput: maxDimension 默认 1280，范围 1-4096")
func screenshotInputDefaults() throws {
    #expect(try UIScreenshotInput.parse(from: JSON([:])).maxDimension == 1280)
    #expect(try UIScreenshotInput.parse(from: JSON(["maxDimension": 2000])).maxDimension == 2000)
    #expect(throws: CommandInputParseError.self) { _ = try UIScreenshotInput.parse(from: JSON(["maxDimension": 0])) }
    #expect(throws: CommandInputParseError.self) { _ = try UIScreenshotInput.parse(from: JSON(["maxDimension": 99999])) }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter Screenshot`
Expected: FAIL。

- [ ] **Step 3: 实现 UIScreenshotModels.swift（Foundation-only，无 #if）**

```swift
import Foundation
import iOSExploreServer

/// ui.screenshot 的命令参数（Foundation-only，macOS SPM 可测 schema/parse）。
public struct UIScreenshotInput: CommandInput, Sendable, Equatable {
    private enum Fields {
        static let maxDimension = CommandFields.optionalNonNegativeInt(
            "maxDimension",
            description: "截图长边像素上限(1-4096), 默认 1280"
        )
        static let all: [AnyCommandField] = [maxDimension.erased]
    }
    public static let inputSchema = CommandInputSchema(fields: Fields.all, constraints: [])
    public let maxDimension: Int
    public init(maxDimension: Int = 1280) { self.maxDimension = maxDimension }
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIScreenshotInput {
        let raw = try decoder.read(Fields.maxDimension)
        let dim = raw ?? 1280
        guard (1...4096).contains(dim) else { throw CommandInputParseError("maxDimension must be in 1...4096") }
        return UIScreenshotInput(maxDimension: dim)
    }
}
```

- [ ] **Step 4: 实现 UIKitCommandError 工厂**

```swift
static func renderingFailed(action: String, reason: String) -> UIKitCommandError {
    UIKitCommandError(code: .renderingFailed, message: "screenshot rendering failed: \(reason)",
        logMessage: "ui screenshot rendering failed action=\(action) reason=\(reason)")
}
static func transitionInProgress(action: String) -> UIKitCommandError {
    UIKitCommandError(code: .transitionInProgress, message: "view controller transition in progress; retry",
        logMessage: "ui screenshot transition in progress action=\(action)")
}
```

- [ ] **Step 5: 实现 UIScreenshotCollector.swift（#if canImport(UIKit)，@MainActor，pixel + drawHierarchy 捕获 Bool + 体积前置检查）**

```swift
#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

@MainActor
enum UIScreenshotCollector {
    static func collect(input: UIScreenshotInput, maxResponseBodyBytes: Int) throws -> JSON {
        let action = ScreenshotCommand.actionName
        UIKitCommandLogging.info("command", "ui screenshot start maxDimension=\(input.maxDimension)")
        let context = try UIKitContextProvider.currentContext(action: action)

        // 1. VC transition 检测（不覆盖键盘动画——已知限制）
        if context.topViewController.transitionCoordinator != nil {
            throw UIKitCommandError.transitionInProgress(action: action)
        }
        let window = context.window   // Context.window 非 Optional（codex 复审核对）

        // 2. MainActor 渲染（截当前帧，闭包外记录 drawHierarchy 返回的 Bool）
        let renderer = UIGraphicsImageRenderer(size: window.bounds.size)
        var renderOK = false
        let image = renderer.image { _ in
            renderOK = window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        guard renderOK else { throw UIKitCommandError.renderingFailed(action: action, reason: "drawHierarchy returned false") }

        // 3. 降采样到 maxDimension **像素**长边
        guard let cg = image.cgImage else {
            throw UIKitCommandError.renderingFailed(action: action, reason: "no cgImage")
        }
        let longestPx = max(cg.width, cg.height)
        let pixelScale: Double = longestPx > input.maxDimension ? Double(input.maxDimension) / Double(longestPx) : 1.0
        let scaledImage: UIImage
        if pixelScale < 1.0 {
            let newSize = CGSize(width: image.size.width * pixelScale, height: image.size.height * pixelScale)
            let r = UIGraphicsImageRenderer(size: newSize)
            scaledImage = r.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        } else {
            scaledImage = image
        }

        // 4. MainActor PNG 编码（UIImage 非 Sendable，不跨 actor）
        guard let pngData = scaledImage.pngData(), !pngData.isEmpty else {
            throw UIKitCommandError.renderingFailed(action: action, reason: "png encode failed")
        }

        // 5. 体积前置检查（base64 ≈ pngData × 4/3）
        let estimated = pngData.count * 4 / 3
        if estimated > maxResponseBodyBytes {
            throw UIKitCommandError(code: .responseTooLarge,
                message: "screenshot too large; reduce maxDimension",
                logMessage: "ui screenshot too large action=\(action) bytes=\(pngData.count) est=\(estimated) limit=\(maxResponseBodyBytes)")
        }
        let base64 = pngData.base64EncodedString()

        // 6. 同帧指纹（与 viewTargets 同筛选）+ 签发 snapshot
        let query = UIViewTargetsInput()   // 默认筛选
        let digest = UIKitFingerprintCollector.digest(topViewController: context.topViewController)
        let fingerprints = UIKitFingerprintCollector.collectFingerprints(rootView: context.rootView, query: query, digest: digest)
        let snapContext = UIKitFingerprintCollector.context(window: context.window, topViewController: context.topViewController)
        let snapshotID = UIKitSnapshotStore.shared.insert(context: snapContext, targets: fingerprints)
        let (idField, reasonField) = UIKitSnapshotResponse.fields(for: snapshotID)

        let screenScale = window.screen.scale   // window.screen 非 Optional
        UIKitCommandLogging.info("command", "ui screenshot completed pngBytes=\(pngData.count) pxW=\(scaledImage.cgImage?.width ?? 0) pxH=\(scaledImage.cgImage?.height ?? 0) pixelScale=\(pixelScale) snapshot=\(snapshotID ?? "nil")")

        return [
            "image": .string(base64),
            "format": .string("png"),
            "width": .double(Double(scaledImage.cgImage?.width ?? 0)),      // pixel
            "height": .double(Double(scaledImage.cgImage?.height ?? 0)),    // pixel
            "scale": .double(Double(screenScale)),
            "pixelScale": .double(pixelScale),
            "snapshotID": idField,
            "snapshotUnavailableReason": reasonField,
        ]
    }
}
#endif
```

> `drawHierarchy` 返回 Bool 但在 `renderer.image` 闭包内不便直接 throw；Step 5 已用 `pngData` 非空校验兜底。若需更严格，渲染前先 `let ok = window.drawHierarchy(...)` 单独调用、false 即 throw renderingFailed（实现者择一）。

- [ ] **Step 6: 实现 UIScreenshotCommand.swift（adapter，maxResponseBodyBytes 注入，MainActor.run 包 context+executor）**

```swift
#if canImport(UIKit)
import Foundation
import iOSExploreServer

struct ScreenshotCommand: Command {
    typealias Input = UIScreenshotInput
    static let actionName = "ui.screenshot"
    let action = actionName
    let description = "截屏 (PNG base64) + 降采样 + 签发 snapshot"
    var timeoutNanoseconds: UInt64? { 30_000_000_000 }   // 30s
    private let maxResponseBodyBytes: Int

    init(maxResponseBodyBytes: Int) { self.maxResponseBodyBytes = maxResponseBodyBytes }

    func handle(_ input: UIScreenshotInput) async -> ExploreResult {
        UIKitCommandLogging.info("command", "command \(action) start maxDimension=\(input.maxDimension)")
        do {
            // UIKitContextProvider @MainActor → 必须在 MainActor.run 内取 context + 调 collector
            let data = try await MainActor.run {
                try UIScreenshotCollector.collect(input: input, maxResponseBodyBytes: maxResponseBodyBytes)
            }
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        } catch {
            let e = UIKitCommandError.renderingFailed(action: action, reason: "\(error)")
            UIKitCommandLogging.error("command", e.failure.logMessage)
            return e.result
        }
    }
}
#endif
```

- [ ] **Step 7: iOS framework 测试——渲染有效（解码回 UIImage + 像素采样）**

```swift
@Test("screenshot: base64 解码回 UIImage 非空 + 像素非全透明")
@MainActor
func screenshotProducesValidImage() throws {
    // 造含对比色背景的 window（复用现有 fixture 或自建）
    let data = try UIScreenshotCollector.collect(input: .init(), maxResponseBodyBytes: 6_000_000)
    let base64 = try #require(data["image"]?.stringValue)
    let png = try #require(Data(base64Encoded: base64))
    let img = try #require(UIImage(data: png))
    let pxW = try #require(data["width"]?.doubleValue)
    #expect(Double(img.cgImage?.width ?? 0) == pxW)
    #expect(Self.hasNonTransparentPixel(img))   // 防空白位图假通过
}
```

- [ ] **Step 8: 运行测试 + 注册（count→5，传 maxResponseBodyBytes）**

`UIKitCommandRegistrar.registerUIKitCommands(maxResponseBodyBytes:)`（或从 ExploreServer 暴露只读配置）：

```swift
register(ScreenshotCommand(maxResponseBodyBytes: maxResponseBodyBytes), logCategory: .extensionCommand(category: "command"))
```

Run: `swift test --filter Screenshot` + `xcodebuild ... test -only-testing:iOSExploreServerTests/Screenshot`
Expected: PASS。

- [ ] **Step 9: 提交**

```bash
git add Sources/iOSExploreUIKit/Commands/Screenshot/ Sources/iOSExploreUIKit/UIKitCommandError.swift Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift Tests/iOSExploreServerTests/
git commit -m "feat(uikit): ui.screenshot（降采样 pixel + MainActor 编码 + 体积前置检查 + 签发 snapshot）"
```

---

### Task 8: ui.input

**Files:**
- Create: `Sources/iOSExploreUIKit/Commands/Input/UIInputModels.swift`（Foundation-only）
- Create: `Sources/iOSExploreUIKit/Support/Action/UITextInputExecutor.swift`（#if UIKit，@MainActor）
- Create: `Sources/iOSExploreUIKit/Commands/Input/UIInputCommand.swift`（#if UIKit）
- Modify: `Sources/iOSExploreUIKit/UIKitCommandError.swift`

**Interfaces:**
- Consumes: Task 1(`.unsupportedTextInputType`/`.becomeFirstResponderFailed`/`.inputRejected`/`.staleLocator`)、`UIKitLocatorInput.parse`、`UIKitLocatorResolver.locate(locator:in:notFound:ambiguous:)`（**真实签名**）、`LocatedView.view`/`.pathString`、`UIKitSnapshotStore.shared.isStale`、`UIKitFingerprintCollector.fingerprint/digest/context`、`UIKitContextProvider.currentContext`。
- Produces: `UIInputInput`、`InputCommand`（actionName `"ui.input"`）。

- [ ] **Step 1: 写失败测试——Input schema（macOS）**

```swift
@Test("UIInputInput: text 必填；mode 默认 replace；submit 默认 true")
func inputInputParse() throws {
    let i = try UIInputInput.parse(from: JSON(["path": "root/0", "text": "hi"]))
    #expect(i.text == "hi"); #expect(i.mode == .replace); #expect(i.submit == true)
    #expect(throws: CommandInputParseError.self) { _ = try UIInputInput.parse(from: JSON(["path": "root/0"])) }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter Input`
Expected: FAIL。

- [ ] **Step 3: 实现 UIInputModels.swift（Foundation-only）**

```swift
import Foundation
import iOSExploreServer

public enum InputMode: String, Sendable, Equatable, CaseIterable { case replace, append }

public struct UIInputInput: CommandInput, Sendable, Equatable {
    private enum Fields {
        static let accessibilityIdentifier = UIKitLocatorFields.accessibilityIdentifier
        static let path = UIKitLocatorFields.path
        static let snapshotID = UIKitLocatorFields.snapshotID
        static let text = CommandFields.requiredString("text", description: "要输入的文本 (任意 Unicode)")
        static let mode = CommandFields.enumValue("mode", type: InputMode.self, default: .replace, description: "replace(默认,先清空) / append")
        static let submit = CommandFields.bool("submit", default: true, description: "输入后是否 resignFirstResponder")
        static let all: [AnyCommandField] = [accessibilityIdentifier.erased, path.erased, snapshotID.erased, text.erased, mode.erased, submit.erased]
    }
    public static let inputSchema = CommandInputSchema(fields: Fields.all, constraints: [
        .exactlyOneOf(["accessibilityIdentifier", "path"]),
        .extensionMessage("snapshotID is valid only with path"),
    ])
    public let target: UIKitViewLookupTarget
    public let text: String
    public let mode: InputMode
    public let submit: Bool
    public let snapshotID: String?
    public init(target: UIKitViewLookupTarget, text: String, mode: InputMode = .replace, submit: Bool = true, snapshotID: String? = nil) {
        self.target = target; self.text = text; self.mode = mode; self.submit = submit; self.snapshotID = snapshotID
    }
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIInputInput {
        let snapshotID = try decoder.read(Fields.snapshotID)
        let mode = try decoder.read(Fields.mode)
        let submit = try decoder.read(Fields.submit)
        let text = try decoder.read(Fields.text)
        let target = try UIKitLocatorInput.parse(decoder: &decoder)
        if snapshotID != nil, case .accessibilityIdentifier = target {
            throw CommandInputParseError("snapshotID is valid only with path")
        }
        return UIInputInput(target: target, text: text, mode: mode, submit: submit, snapshotID: snapshotID)
    }
}
```

- [ ] **Step 4: UIKitCommandError 工厂**

```swift
static func unsupportedTextInputType(action: String, type: String) -> UIKitCommandError {
    UIKitCommandError(code: .unsupportedTextInputType, message: "target is not a supported text input",
        logMessage: "ui input unsupported type action=\(action) type=\(type)")
}
static func becomeFirstResponderFailed(action: String, target: String) -> UIKitCommandError {
    UIKitCommandError(code: .becomeFirstResponderFailed, message: "failed to become first responder",
        logMessage: "ui input becomeFirstResponder failed action=\(action) target=\(target)")
}
static func inputRejected(action: String, expectedLen: Int, finalLen: Int, secure: Bool) -> UIKitCommandError {
    UIKitCommandError(code: .inputRejected, message: "text input was rejected or altered by delegate",
        logMessage: "ui input rejected action=\(action) expectedLen=\(expectedLen) finalLen=\(finalLen) secure=\(secure)")
}
```

- [ ] **Step 5: 实现 UITextInputExecutor.swift（@MainActor，真实 locate 签名 + pathString + append expected）**

```swift
#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

@MainActor
enum UITextInputExecutor {
    /// context 由调用方在 MainActor.run 内取好传入（@MainActor 不穿边界）。
    static func execute(input: UIInputInput, context: UIKitContextProvider.Context) throws -> JSON {
        let action = InputCommand.actionName
        let located = try UIKitLocatorResolver.locate(
            locator: input.target.locator,
            in: context.rootView,
            notFound: { UIKitCommandError.invalidData(action: action, message: "target not found") },
            ambiguous: { n in UIKitCommandError.invalidData(action: action, message: "target ambiguous count=\(n)") }
        )
        // stale 校验（仅 path 定位 + 带 snapshotID）
        if let snapshotID = input.snapshotID, case .path = input.target {
            let cur = UIKitFingerprintCollector.fingerprint(for: located.view, path: located.pathString, rootView: context.rootView, digest: UIKitFingerprintCollector.digest(topViewController: context.topViewController))
            let snapCtx = UIKitFingerprintCollector.context(window: context.window, topViewController: context.topViewController)
            if UIKitSnapshotStore.shared.isStale(snapshotID: snapshotID, path: located.pathString, context: snapCtx, current: cur) {
                throw UIKitCommandError.staleLocator(action: action, snapshotID: snapshotID)
            }
        }
        // 白名单（UITextField/UITextView/UISearchTextField）
        let view = located.view
        guard (view is UITextField) || (view is UITextView) || (view is UISearchTextField) else {
            throw UIKitCommandError.unsupportedTextInputType(action: action, type: String(describing: type(of: view)))
        }
        // UITextInput 协议只有 insertText/deleteBackward/selectedTextRange；
        // becomeFirstResponder/isFirstResponder/resignFirstResponder/selectAll 是 UIResponder 的，按具体类型调（codex 复审）。
        let responder = view as! UIResponder
        let textInput = view as! UITextInput
        // 插入前读原文（append expected 用）
        let oldText = (view as? UITextField)?.text ?? (view as? UITextView)?.text ?? ""
        guard responder.becomeFirstResponder() else {
            throw UIKitCommandError.becomeFirstResponderFailed(action: action, target: input.target.description)
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))   // 等一帧
        guard responder.isFirstResponder, textInput.selectedTextRange != nil else {
            throw UIKitCommandError.becomeFirstResponderFailed(action: action, target: input.target.description)
        }
        if input.mode == .replace {
            // selectAll(_:) 是 UIResponder 方法，按具体控件调用
            if let field = view as? UITextField { field.selectAll(nil) }
            else if let tv = view as? UITextView { tv.selectAll(nil) }
            textInput.deleteBackward()
        }
        textInput.insertText(input.text)
        let finalText = (view as? UITextField)?.text ?? (view as? UITextView)?.text ?? ""
        if input.submit { responder.resignFirstResponder() }
        // 比对：replace expected=input.text；append expected=old+input.text
        let expected = (input.mode == .append) ? oldText + input.text : input.text
        let secure = (view as? UITextField)?.isSecureTextEntry ?? false
        if finalText != expected {
            throw UIKitCommandError.inputRejected(action: action, expectedLen: expected.count, finalLen: finalText.count, secure: secure)
        }
        UIKitCommandLogging.info("command", "ui input completed type=\(String(describing: type(of: view))) finalLen=\(finalText.count) secure=\(secure)")
        if secure {
            return [
                "type": .string(String(describing: type(of: view))),
                "masked": .string(String(repeating: "•", count: finalText.count)),
                "length": .double(Double(finalText.count)),
            ]
        }
        return ["type": .string(String(describing: type(of: view))), "finalText": .string(finalText)]
    }
}
#endif
```

> `UIKitLocatorResolver.locate` 的 `notFound`/`ambiguous` 闭包签名以 `codegraph node UIKitLocatorResolver` 为准（Step 实现时核对）；`input.target.locator`（UIKitViewLookupTarget.locator → UIKitLocator）。

- [ ] **Step 6: 实现 UIInputCommand.swift（adapter，MainActor.run）**

```swift
#if canImport(UIKit)
import Foundation
import iOSExploreServer

struct InputCommand: Command {
    typealias Input = UIInputInput
    static let actionName = "ui.input"
    let action = actionName
    let description = "向 UITextField/UITextView/UISearchTextField 注入文本 (UITextInput.insertText)"
    func handle(_ input: UIInputInput) async -> ExploreResult {
        UIKitCommandLogging.info("command", "command \(action) start mode=\(input.mode.rawValue) textLen=\(input.text.count)")
        do {
            let data = try await MainActor.run {
                let context = try UIKitContextProvider.currentContext(action: actionName)
                return try UITextInputExecutor.execute(input: input, context: context)
            }
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        } catch {
            let e = UIKitCommandError.hierarchyUnavailable(action: actionName, reason: "\(error)")
            return e.result
        }
    }
}
#endif
```

- [ ] **Step 7: iOS framework 测试（replace/append/中文/委托拒绝→inputRejected/UILabel 拒绝/secure 脱敏/stale）**

```swift
@Test("input replace 写入中文") @MainActor func inputReplace() throws { /* "old" + replace("中文🎉") → finalText=="中文🎉" */ }
@Test("input append 拼接") @MainActor func inputAppend() throws { /* "old" + append("X") → finalText=="oldX", 不报 rejected */ }
@Test("input UILabel → unsupportedTextInputType") @MainActor func inputRejectsLabel() { /* throws */ }
@Test("input secure 只回 masked/length") @MainActor func inputSecureMasked() { /* 断言无明文 */ }
@Test("input 委托拒绝 → inputRejected") @MainActor func inputDelegateReject() { /* delegate false → inputRejected */ }
```

- [ ] **Step 8: 运行测试 + 注册（count→6）**

Run: `swift test --filter Input` + `xcodebuild ... test -only-testing:iOSExploreServerTests/Input`
Expected: PASS。

- [ ] **Step 9: 提交**

```bash
git add Sources/iOSExploreUIKit/Commands/Input/ Sources/iOSExploreUIKit/Support/Action/UITextInputExecutor.swift Sources/iOSExploreUIKit/UIKitCommandError.swift Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift Tests/iOSExploreServerTests/
git commit -m "feat(uikit): ui.input（等帧+append expected+委托比对+密码脱敏）"
```

---

### Task 9: ui.scroll

**Files:**
- Create: `Sources/iOSExploreUIKit/Commands/Scroll/UIScrollModels.swift`（Foundation-only，`UIScrollInput` + `ScrollDirection` + `ScrollExtent`）
- Create: `Sources/iOSExploreUIKit/Support/Action/UIScrollExecutor.swift`（#if UIKit）
- Create: `Sources/iOSExploreUIKit/Commands/Scroll/UIScrollCommand.swift`（#if UIKit）
- Modify: `Sources/iOSExploreUIKit/UIKitCommandError.swift`（`scrollContainerUnavailable`）

**Interfaces:**
- Consumes: Task 1(`.scrollContainerUnavailable`/`.staleLocator`)、Task 4(`parseOptional`)、真实 `UIKitLocatorResolver.locate`/`LocatedView.pathString`、`adjustedContentInset`。
- Produces: `UIScrollInput`、`ScrollExtent { top,bottom,left,right }`、`ScrollCommand`（actionName `"ui.scroll"`）。

- [ ] **Step 1: 写失败测试——Input（macOS）**

```swift
@Test("UIScrollInput: direction 必填；amount>0；target 可缺")
func scrollInputParse() throws {
    let i = try UIScrollInput.parse(from: JSON(["direction": "down"]))
    #expect(i.direction == .down); #expect(i.amount == nil); #expect(i.locator == nil); #expect(i.animated == false)
    #expect(throws: CommandInputParseError.self) { _ = try UIScrollInput.parse(from: JSON(["direction": "down", "amount": -1])) }
    #expect(throws: CommandInputParseError.self) { _ = try UIScrollInput.parse(from: JSON([:])) }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter Scroll`
Expected: FAIL。

- [ ] **Step 3: 实现 UIScrollModels.swift（Foundation-only，含 ScrollExtent）**

```swift
import Foundation
import iOSExploreServer

public enum ScrollDirection: String, Sendable, Equatable, CaseIterable { case up, down, left, right }
/// reachedExtent 输出值（对齐 spec §7，不复用 direction）。
public enum ScrollExtent: String, Sendable, Equatable { case top, bottom, left, right }

public struct UIScrollInput: CommandInput, Sendable, Equatable {
    private enum Fields {
        static let direction = CommandFields.requiredEnum("direction", type: ScrollDirection.self, description: "up/down/left/right")
        static let amount = CommandFields.optionalFiniteNumber("amount", description: "滚动距离(pt), 必须>0; 缺省=可见区×0.5")
        static let accessibilityIdentifier = UIKitLocatorFields.accessibilityIdentifier
        static let path = UIKitLocatorFields.path
        static let snapshotID = UIKitLocatorFields.snapshotID
        static let animated = CommandFields.bool("animated", default: false, description: "是否动画(默认 false)")
        static let all: [AnyCommandField] = [direction.erased, amount.erased, accessibilityIdentifier.erased, path.erased, snapshotID.erased, animated.erased]
    }
    public static let inputSchema = CommandInputSchema(fields: Fields.all, constraints: [
        .extensionMessage("accessibilityIdentifier/path 都缺时滚动 keyWindow 最前 scrollView"),
        .extensionMessage("snapshotID is valid only with path"),
    ])
    public let direction: ScrollDirection
    public let amount: Double?
    public let locator: UIKitViewLookupTarget?
    public let snapshotID: String?
    public let animated: Bool
    public init(direction: ScrollDirection, amount: Double? = nil, locator: UIKitViewLookupTarget? = nil, snapshotID: String? = nil, animated: Bool = false) {
        self.direction = direction; self.amount = amount; self.locator = locator; self.snapshotID = snapshotID; self.animated = animated
    }
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIScrollInput {
        let direction = try decoder.read(Fields.direction)
        let amountRaw = try decoder.read(Fields.amount)
        let animated = try decoder.read(Fields.animated)
        let snapshotID = try decoder.read(Fields.snapshotID)
        let locator = try UIKitLocatorInput.parseOptional(decoder: &decoder)
        if let a = amountRaw, a <= 0 { throw CommandInputParseError("amount must be > 0") }
        if snapshotID != nil, let loc = locator, case .accessibilityIdentifier = loc {
            throw CommandInputParseError("snapshotID is valid only with path")
        }
        return UIScrollInput(direction: direction, amount: amountRaw, locator: locator, snapshotID: snapshotID, animated: animated)
    }
}
```

- [ ] **Step 4: UIKitCommandError 加 `scrollContainerUnavailable`**

```swift
static func scrollContainerUnavailable(action: String, target: String) -> UIKitCommandError {
    UIKitCommandError(code: .scrollContainerUnavailable, message: "no UIScrollView ancestor (UITextView excluded)",
        logMessage: "ui scroll container unavailable action=\(action) target=\(target)")
}
```

- [ ] **Step 5: 实现 UIScrollExecutor.swift（@MainActor，真实 locate + ScrollExtent + adjustedContentInset）**

```swift
#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

@MainActor
enum UIScrollExecutor {
    /// execute 改同步（codex 复审：去掉 async Task.yield，避免 MainActor.run 包 async body）。
    /// setContentOffset(animated:false) 同步更新 contentOffset，立即读 after 即目标值。
    static func execute(input: UIScrollInput, context: UIKitContextProvider.Context) throws -> JSON {
        let action = ScrollCommand.actionName
        let scrollView: UIScrollView
        if let locator = input.locator {
            let located = try UIKitLocatorResolver.locate(
                locator: locator.locator, in: context.rootView,
                notFound: { UIKitCommandError.invalidData(action: action, message: "target not found") },
                ambiguous: { _, n in UIKitCommandError.invalidData(action: action, message: "ambiguous count=\(n)") })
            if let snapshotID = input.snapshotID, case .path = locator {
                let cur = UIKitFingerprintCollector.fingerprint(for: located.view, path: located.pathString, rootView: context.rootView, digest: UIKitFingerprintCollector.digest(topViewController: context.topViewController))
                let snapCtx = UIKitFingerprintCollector.context(window: context.window, topViewController: context.topViewController)
                if UIKitSnapshotStore.shared.isStale(snapshotID: snapshotID, path: located.pathString, context: snapCtx, current: cur) {
                    throw UIKitCommandError.staleLocator(action: action, snapshotID: snapshotID)
                }
            }
            guard let sv = nearestScrollView(from: located.view) else {
                throw UIKitCommandError.scrollContainerUnavailable(action: action, target: locator.description)
            }
            scrollView = sv
        } else {
            guard let sv = foremostScrollView(in: context.window) else {
                throw UIKitCommandError.scrollContainerUnavailable(action: action, target: "keyWindow")
            }
            scrollView = sv
        }
        let adjusted = scrollView.adjustedContentInset
        let visibleH = scrollView.bounds.height - adjusted.top - adjusted.bottom
        let visibleW = scrollView.bounds.width - adjusted.left - adjusted.right
        let dist = input.amount ?? (input.direction.isVertical ? visibleH * 0.5 : visibleW * 0.5)
        let before = scrollView.contentOffset
        let delta = delta(for: input.direction, amount: dist)
        scrollView.setContentOffset(CGPoint(x: before.x + delta.x, y: before.y + delta.y), animated: input.animated)
        let after = scrollView.contentOffset
        let extent = reachedExtent(scrollView: scrollView)
        UIKitCommandLogging.info("command", "ui scroll completed container=\(String(describing: type(of: scrollView))) beforeY=\(before.y) afterY=\(after.y) extent=\(extent?.rawValue ?? "nil")")
        return [
            "container": .string(String(describing: type(of: scrollView))),
            "offsetBefore": .object(JSON(["x": .double(before.x), "y": .double(before.y)])),
            "offsetAfter": .object(JSON(["x": .double(after.x), "y": .double(after.y)])),
            "reachedExtent": extent.map { .string($0.rawValue) } ?? .null,
            "adjustedContentInset": .object(JSON(["top": .double(adjusted.top), "bottom": .double(adjusted.bottom)])),
        ]
    }

    private static func nearestScrollView(from view: UIView) -> UIScrollView? {
        var cur: UIView? = view
        while let v = cur {
            if let sv = v as? UIScrollView, !(v is UITextView) { return sv }
            cur = v.superview
        }
        return nil
    }
    private static func foremostScrollView(in window: UIWindow?) -> UIScrollView? {
        guard let window else { return nil }
        var found: UIScrollView?
        func walk(_ v: UIView) {
            if let sv = v as? UIScrollView, !(v is UITextView), found == nil { found = sv; return }
            v.subviews.forEach(walk)
        }
        walk(window)
        return found
    }
    private static func delta(for d: ScrollDirection, amount: Double) -> CGPoint {
        switch d { case .up: return CGPoint(x: 0, y: -amount); case .down: return CGPoint(x: 0, y: amount); case .left: return CGPoint(x: -amount, y: 0); case .right: return CGPoint(x: amount, y: 0) }
    }
    private static func reachedExtent(scrollView: UIScrollView) -> ScrollExtent? {
        let a = scrollView.adjustedContentInset
        if scrollView.contentOffset.y <= -a.top + 1 { return .top }
        let maxY = max(-a.top, scrollView.contentSize.height - scrollView.bounds.height + a.bottom)
        if scrollView.contentOffset.y >= maxY - 1 { return .bottom }
        if scrollView.contentOffset.x <= -a.left + 1 { return .left }
        let maxX = max(-a.left, scrollView.contentSize.width - scrollView.bounds.width + a.right)
        if scrollView.contentOffset.x >= maxX - 1 { return .right }
        return nil
    }
}
extension ScrollDirection { var isVertical: Bool { self == .up || self == .down } }
#endif
```

- [ ] **Step 6: 实现 UIScrollCommand.swift（adapter，MainActor.run）**

```swift
#if canImport(UIKit)
import Foundation
import iOSExploreServer

struct ScrollCommand: Command {
    typealias Input = UIScrollInput
    static let actionName = "ui.scroll"
    let action = actionName
    let description = "在 UIScrollView 系(排除 UITextView)上按方向+距离滚动"
    func handle(_ input: UIScrollInput) async -> ExploreResult {
        UIKitCommandLogging.info("command", "command \(action) start direction=\(input.direction.rawValue) amount=\(input.amount.map(String.init) ?? "half") animated=\(input.animated)")
        do {
            let data = try await MainActor.run {
                let context = try UIKitContextProvider.currentContext(action: actionName)
                return try UIScrollExecutor.execute(input: input, context: context)
            }
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        } catch {
            let e = UIKitCommandError.hierarchyUnavailable(action: actionName, reason: "\(error)")
            return e.result
        }
    }
}
#endif
```

- [ ] **Step 7: iOS framework 测试（UICollectionView 滚动 offset 增大 + reachedExtent + 纯 UIView 拒绝）**

```swift
@Test("scroll: CollectionView down → afterY>beforeY；纯 UIView → scrollContainerUnavailable")
@MainActor func scrollOffset() async throws { /* 超屏 CollectionView scroll(.down) 断言 after.y>before.y；UIView 断言 throws scrollContainerUnavailable */ }
```

- [ ] **Step 8: 运行测试 + 注册（count→7）**

Run: `swift test --filter Scroll` + `xcodebuild ... test -only-testing:iOSExploreServerTests/Scroll`
Expected: PASS。

- [ ] **Step 9: 提交**

```bash
git add Sources/iOSExploreUIKit/Commands/Scroll/ Sources/iOSExploreUIKit/Support/Action/UIScrollExecutor.swift Sources/iOSExploreUIKit/UIKitCommandError.swift Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift Tests/iOSExploreServerTests/
git commit -m "feat(uikit): ui.scroll（adjustedContentInset + ScrollExtent + UITextView 排除 + animated:false）"
```

---

## Phase 4：集成与收尾

### Task 10: 集成测试（iOS only）+ registrar count + help

**Why:** spec §10——三命令端到端 envelope + responseTooLarge 负向契约。**UIKit 集成必须 `#if canImport(UIKit)` 或放 iOS framework test**（`registerUIKitCommands` 是 UIKit-only，macOS swift test 编译不过）。

**Files:**
- Modify: `Tests/iOSExploreServerTests/IntegrationTests.swift`（UIKit 端到端加 `#if canImport(UIKit)`）

**Interfaces:**
- Consumes: Task 7/8/9。

- [ ] **Step 1: 写集成测试（#if canImport(UIKit)，端口 38399 串行）**

```swift
#if canImport(UIKit)
@Suite(.serialized)
struct ActionCommandsIntegrationTests {
    @Test("screenshot 端到端: envelope image 合法 base64 + 维度正")
    func screenshotRoundTrip() async throws {
        let server = ExploreServer(port: 38399, maxResponseBodyBytes: 8 * 1024 * 1024)
        server.registerUIKitCommands(maxResponseBodyBytes: 8 * 1024 * 1024)
        try await server.start(); defer { Task { await server.stop() } }
        // envelope 解包：JSONValue 无下标，按现有 IntegrationTests 的解包模式
        // （case .object(let body) = resp 取 code；data 再 case .object 解包取 image）。
        let resp = try await postJSON(port: 38399, action: "ui.screenshot", data: [:])
        #expect(envelopeCode(resp) == "ok")                       // 测试辅助：case .object 链式解包
        let img = try #require(envelopeImageBase64(resp))         // 同上，提取 data.image 的 base64
        #expect(Data(base64Encoded: img)?.count ?? 0 > 100)
    }
    @Test("默认上限下超大图 → response_too_large（负向契约）")
    func screenshotTooLarge() async throws { /* maxDimension:4096 + maxResponseBodyBytes:1MB → code=="response_too_large" */ }
    // input/scroll 端到端需宿主 App 可交互 view；若集成环境无宿主 UI，标注在 SPMExample 手测
}
#endif
```

- [ ] **Step 2: 运行（iOS framework test，非 macOS swift test）**

Run: `xcodebuild ... test -only-testing:iOSExploreServerTests/ActionCommandsIntegrationTests`
Expected: screenshot 通过。

- [ ] **Step 3: 验证 registrar count + help**

Run: 启 SPMExample → `curl -X POST http://localhost:38321/ -d '{"action":"help"}'`
Expected: 含 `ui.screenshot`/`ui.input`/`ui.scroll`；registrar 日志 `count=7`。

- [ ] **Step 4: 覆盖率**

Run: `swift test --enable-code-coverage`
Expected: ≥80%。

- [ ] **Step 5: 提交**

```bash
git add Tests/iOSExploreServerTests/IntegrationTests.swift
git commit -m "test: 操作三件套集成测试（screenshot 端到端 + responseTooLarge 负向）"
```

---

## Self-Review（v2，codex 审后）

**Spec 覆盖：** §3.1(Task 3+7)、§3.2(Task 6)、§3.3(Task 8)、§3.4(Task 9)、§3.5(Task 5)、§3.6(Task 6 TTL 已进正文)、§3.7(MCP 表，spec §9 文档)、§8.2(Task 2)、§8.3(Task 1)——全覆盖。

**Placeholder 扫描：** 各 Task 代码均给具体实现；少数 UIKit resolver 真实签名（`locate` 的 `notFound`/`ambiguous` 闭包参数）标注"以 codegraph node 为准"作为对齐提示（非占位）。

**类型一致性：** `timeoutNanoseconds: UInt64?` 全链路一致；`ScrollExtent` 独立于 `ScrollDirection`；JSON 构造统一 `.double`/`.object(JSON([...]))`；三 Input 模型 Foundation-only（不包 `#if`），collector/executor/adapter 包 `#if`。

**codex BLOCKER 全部已修：** .number→.double、locator/Context 真实字段、MainActor.run 包裹、UInt64 timeout、send(action:)、体积注入、Input Foundation-only、collectFingerprints 收 query、pixel 维度、append expected、ScrollExtent、TTL 进 Task 6。
