# UIKit 命令扩展架构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 拆分可选 `iOSExploreUIKit` 模块，并在不破坏既有四个 UIKit action 的前提下，建立可扩展的查询、定位、执行和 snapshot 架构。

**Architecture:** core 只保留 HTTP、Router、统一结果、最小扩展日志和错误支撑；UIKit target 显式注册命令。真实 UIKit 对象只在 `@MainActor` 的 Context、Resolver、Executor 中存在，HTTP 边界只传 Sendable 值模型。

**Tech Stack:** Swift 6.2 SPM、Swift Testing、Foundation、Network、UIKit、Xcode framework target。

---

## 约束与文件结构

- 在独立 worktree 执行；不得改入用户现有未提交内容。
- 每项功能先写失败测试，再写最小实现；每次提交前执行 `git diff --check`。
- core 不得 import UIKit 或含 `canImport(UIKit)`；不得改变 `POST /`、envelope、既有 action 名和必填参数。
- 陈旧 locator 统一返回 `invalid_data` 和 `locator is stale; re-query`，不新增 `ExploreError` case。

```text
Sources/iOSExploreServer/ExploreCommandSupport.swift
Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift
Sources/iOSExploreUIKit/UIKitCommandError.swift
Sources/iOSExploreUIKit/Context/UIKitContextProvider.swift
Sources/iOSExploreUIKit/Locator/UIKitLocator.swift
Sources/iOSExploreUIKit/Action/UIKitActionCapabilityResolver.swift
Sources/iOSExploreUIKit/Action/UIKitActionExecutor.swift
Sources/iOSExploreUIKit/Snapshot/UIKitSnapshotStore.swift
```

### Task 1: core 的扩展错误与日志支撑

**Files:**
- Create: `Sources/iOSExploreServer/ExploreCommandSupport.swift`
- Modify: `Sources/iOSExploreServer/ExploreLogging.swift`
- Create: `Tests/iOSExploreServerTests/ExploreCommandSupportTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
@Test("扩展 command failure 保留 envelope 与日志语义")
func commandFailureMapsToResult() {
    let failure = ExploreCommandFailure(code: .invalidData,
                                        message: "target not found",
                                        logMessage: "uikit locator missing kind=path")
    #expect(failure.result == .failure(code: .invalidData, message: "target not found"))
}

@Test("扩展日志进入既有 sink")
func extensionLogUsesCoreSink() {
    let records = Mutex<[ExploreLogRecord]>([])
    ExploreLogging.setEnabled(true)
    ExploreLogging.setSinkForTesting { record in records.withLock { $0.append(record) } }
    ExploreLogging.emitExtension(level: .info, category: "uikit.action", message: "tap completed")
    #expect(records.withLock { $0.map(\.category) } == ["uikit.action"])
    ExploreLogging.resetForTesting()
}
```

- [ ] **Step 2: 确认测试失败**

Run: `swift test --filter ExploreCommandSupportTests`

Expected: FAIL，缺少 `ExploreCommandFailure` 与 `emitExtension`。

- [ ] **Step 3: 实现最小公开缝**

```swift
public struct ExploreCommandFailure: Sendable, Equatable {
    public let code: ExploreError
    public let message: String
    public let logMessage: String
    public init(code: ExploreError, message: String, logMessage: String) {
        self.code = code; self.message = message; self.logMessage = logMessage
    }
    public var result: ExploreResult { .failure(code: code, message: message) }
}

public extension ExploreLogging {
    static func emitExtension(level: ExploreLogLevel, category: String, message: String) {
        emit(ExploreLogRecord(level: level, category: category, message: message))
    }
}
```

不要公开 `ExploreLogger`、`ExploreLogCategory`、日志 sink 或 `ExploreServerError`。

- [ ] **Step 4: 验证并提交**

Run: `swift test --filter ExploreCommandSupportTests && swift test --filter ExploreLoggingTests`

Expected: PASS。

```bash
git add Sources/iOSExploreServer/ExploreCommandSupport.swift Sources/iOSExploreServer/ExploreLogging.swift Tests/iOSExploreServerTests/ExploreCommandSupportTests.swift
git commit -m "feat: expose command extension support"
```

### Task 2: 建立第二个 SPM target 和显式 UIKit 注册

**Files:**
- Modify: `Package.swift`, `Sources/iOSExploreServer/ExploreServer.swift`
- Move: `Sources/iOSExploreServer/Handlers/UIKit/**` → `Sources/iOSExploreUIKit/**`
- Create: `Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift`
- Modify: `Tests/iOSExploreServerTests/UIKit*Tests.swift`
- Create: `Tests/iOSExploreServerTests/UIKitCommandRegistrationTests.swift`（Task 7 后在 iOS target 执行）

- [ ] **Step 1: 写失败注册测试**

```swift
@Test("core 初始化不会自动注册 UIKit action")
func coreDoesNotAutoRegisterUIKitCommands() async {
    let server = ExploreServer()
    #expect((await server.routerSnapshotRoute(ExploreRequest(action: "help"))).commandActions.contains("ui.tap") == false)
}
```

测试文件增加以下 `ExploreResult.commandActions` helper：

```swift
private extension ExploreResult {
    var commandActions: [String] {
        guard case .success(let data) = self,
              case .array(let commands)? = data["commands"] else { return [] }
        return commands.compactMap {
            guard case .object(let command) = $0 else { return nil }
            return command["action"]?.stringValue
        }
    }
}
```

- [ ] **Step 2: 确认失败**

Run: `swift test --filter UIKitCommandRegistrationTests`

Expected: FAIL，现有 core 会自动注册 `ui.tap`，断言不成立。

- [ ] **Step 3: 拆分 target 并实现注册入口**

```swift
.library(name: "iOSExploreServer", targets: ["iOSExploreServer"]),
.library(name: "iOSExploreUIKit", targets: ["iOSExploreUIKit"]),
.target(name: "iOSExploreUIKit", dependencies: ["iOSExploreServer"]),
.testTarget(name: "iOSExploreServerTests", dependencies: ["iOSExploreServer", "iOSExploreUIKit"]),
```

用 `git mv` 迁移 UIKit 文件；删除 `ExploreServer` 两个 initializer 中的自动 UIKit 注册。创建：

```swift
#if canImport(UIKit)
import iOSExploreServer

public extension ExploreServer {
    func registerUIKitCommands() {
        UIKitCommandLogging.info("uikit.registrar", "registration started")
        register(TopViewHierarchyCommand())
        register(ViewTargetsCommand())
        register(UIControlSendActionCommand())
        register(UITapCommand())
        UIKitCommandLogging.info("uikit.registrar", "registration completed count=4")
    }
}
#endif
```

- [ ] **Step 4: 验证并提交**

Run: `swift build && swift test --filter coreDoesNotAutoRegisterUIKitCommands && swift test --filter UIKit`

Expected: PASS；macOS 下 Foundation-only UIKit 模型测试仍可运行。正向注册断言在 Task 7 的 framework 链接完成后执行。

```bash
git add Package.swift Sources/iOSExploreServer Sources/iOSExploreUIKit Tests/iOSExploreServerTests
git commit -m "refactor: split UIKit command module"
```

### Task 3: 收敛 UIKit 的 Context、Locator、错误与日志

**Files:**
- Create: `Sources/iOSExploreUIKit/UIKitCommandError.swift`
- Create: `Sources/iOSExploreUIKit/UIKitCommandLogging.swift`
- Create: `Sources/iOSExploreUIKit/Context/UIKitContextProvider.swift`
- Create: `Sources/iOSExploreUIKit/Locator/UIKitLocator.swift`
- Create: `Sources/iOSExploreUIKit/Locator/UIKitLocatorResolver.swift`
- Modify: 迁移后的 tap、control action、collector、lookup 文件和 `Sources/iOSExploreServer/ExploreServerError.swift`

- [ ] **Step 1: 写失败 locator/error 测试**

```swift
@Test("UIKitLocator 统一 identifier path 和坐标")
func uikitLocatorParsesAllForms() {
    #expect(UIKitLocator.parse(identifier: "home.submit", path: nil, x: nil, y: nil) == .success(.accessibilityIdentifier("home.submit")))
    #expect(UIKitLocator.parse(identifier: nil, path: "root/0/2", x: nil, y: nil) == .success(.path([0, 2])))
    #expect(UIKitLocator.parse(identifier: nil, path: nil, x: 24, y: 48) == .success(.windowPoint(x: 24, y: 48)))
}

@Test("陈旧 locator 使用既有 invalid_data")
func staleLocatorUsesExistingErrorCode() {
    #expect(UIKitCommandError.staleLocator(action: "ui.tap", snapshotID: "s").result == .failure(code: .invalidData, message: "locator is stale; re-query"))
}
```

- [ ] **Step 2: 确认失败并实现**

Run: `swift test --filter uikitLocatorParsesAllForms && swift test --filter staleLocatorUsesExistingErrorCode`

Expected: FAIL，类型尚不存在。

```swift
public enum UIKitLocator: Sendable, Equatable {
    case accessibilityIdentifier(String)
    case path([Int])
    case windowPoint(x: Double, y: Double)
}

public enum UIKitLocatorParseResult: Sendable, Equatable {
    case success(UIKitLocator)
    case failure(String)
}

public extension UIKitLocator {
    static func parse(identifier: String?, path: String?, x: Double?, y: Double?) -> UIKitLocatorParseResult {
        let hasViewLocator = identifier != nil || path != nil
        let hasPointLocator = x != nil || y != nil
        guard !(hasViewLocator && hasPointLocator) else { return .failure("view locator and window point are mutually exclusive") }
        if hasPointLocator {
            guard let x, let y else { return .failure("x and y must be provided together") }
            return .success(.windowPoint(x: x, y: y))
        }
        switch UIKitViewLookupTarget.parse(identifier: identifier, rawPath: path) {
        case .success(let target):
            switch target {
            case .accessibilityIdentifier(let value): return .success(.accessibilityIdentifier(value))
            case .path(let value): return .success(.path(value))
            }
        case .failure(let message): return .failure(message)
        }
    }
}

struct UIKitCommandError: Sendable, Equatable {
    let failure: ExploreCommandFailure
    var result: ExploreResult { failure.result }
    static func staleLocator(action: String, snapshotID: String) -> UIKitCommandError {
        UIKitCommandError(failure: ExploreCommandFailure(code: .invalidData,
                                                          message: "locator is stale; re-query",
                                                          logMessage: "uikit locator stale action=\(action) snapshot=\(snapshotID)"))
    }
}

enum UIKitCommandLogging {
    static func info(_ category: String, _ message: String) {
        ExploreLogging.emitExtension(level: .info, category: category, message: message)
    }
    static func error(_ category: String, _ message: String) {
        ExploreLogging.emitExtension(level: .error, category: category, message: message)
    }
}
```

保留只含 identifier/path 的 `UIKitViewLookupTarget` compatibility wrapper，避免现有模型调用方破坏；其 `parse` 继续提供 path 文法，再由 `UIKitLocator.parse` 映射为新 enum。`UIKitContextProvider` 和 `UIKitLocatorResolver` 必须为 `@MainActor`；迁移前台 window、顶部控制器、resolve、祖先和 nearest-control 逻辑。adapter 只能 `await` 这些入口，不能把 UIView 返回到非隔离域。删除 core `ExploreServerError` 的全部 `ui*` 工厂。

- [ ] **Step 3: 验证并提交**

Run: `swift test --filter UIKitTapTests && swift test --filter UIKitControlActionTests && swift test --filter ExploreServerErrorTests`

Expected: PASS。

```bash
git add Sources/iOSExploreUIKit Sources/iOSExploreServer/ExploreServerError.swift Tests/iOSExploreServerTests
git commit -m "refactor: centralize UIKit context and locator"
```

### Task 4: 引入单一动作能力解析器并修复 identifier 截断

**Files:**
- Create: `Sources/iOSExploreUIKit/Action/UIKitActionCapabilityResolver.swift`
- Modify: `Sources/iOSExploreUIKit/Query/ViewTargets/UIViewTargetsModels.swift`
- Modify: `Sources/iOSExploreUIKit/Query/ViewTargets/UIViewTargetsCollector.swift`
- Create: `Tests/iOSExploreServerTests/UIKitActionCapabilityTests.swift`
- Modify: `Tests/iOSExploreServerTests/UIKitViewTargetsTests.swift`

- [ ] **Step 1: 写失败能力测试**

```swift
@Test("静态节点不被声明为可 tap")
func staticNodeHasNoAvailableActions() {
    #expect(UIKitActionAvailability(actions: []).rawValues == [])
}

@Test("按钮声明 tap 与 touchUpInside")
func enabledButtonHasExecutableActions() {
    let result = UIKitActionAvailability(actions: [.tap, .controlTouchUpInside])
    #expect(result.rawValues == ["tap", "control.touchUpInside"])
}
```

- [ ] **Step 2: 确认失败并实现唯一能力来源**

Run: `swift test --filter UIKitActionCapabilityTests`

Expected: FAIL。

```swift
public enum UIKitActionKind: String, Sendable, Equatable {
    case tap
    case controlTouchUpInside = "control.touchUpInside"
    case controlValueChanged = "control.valueChanged"
}

public struct UIKitActionAvailability: Sendable, Equatable {
    public let actions: [UIKitActionKind]
    public var rawValues: [String] { actions.map(\.rawValue) }
}
```

`@MainActor UIKitActionCapabilityResolver` 必须按真实 view、nearest control、enabled 状态和 executor 支持范围生成该值；collector 与 executor 都调用同一 resolver。`UIViewTargetSummary.toJSON()` 保留既有 `suggestedActions`，并追加 `availableActions`，后者不得按 role 直接推断。

把 collector 中的 `UIViewTargetText.limited(view.accessibilityIdentifier, limit: query.textLimit)` 改为完整 `view.accessibilityIdentifier`；只裁剪 title、label、text、placeholder、value。

- [ ] **Step 3: 验证并提交**

Run: `swift test --filter UIKitViewTargetsTests && swift test --filter UIKitActionCapabilityTests`

Expected: PASS；长 identifier 原样返回，非 UIControl 不会获得虚假的 `availableActions`。

```bash
git add Sources/iOSExploreUIKit/Action Sources/iOSExploreUIKit/Query/ViewTargets Tests/iOSExploreServerTests/UIKitViewTargetsTests.swift Tests/iOSExploreServerTests/UIKitActionCapabilityTests.swift
git commit -m "fix: derive UIKit actions from executor capability"
```

### Task 5: 将 tap/control action 迁入 ActionExecutor

**Files:**
- Create: `Sources/iOSExploreUIKit/Action/UIKitActionExecutor.swift`
- Modify: `Sources/iOSExploreUIKit/Commands/Tap/UITapCommand.swift`, `UITapModels.swift`
- Modify: `Sources/iOSExploreUIKit/Commands/ControlAction/UIControlSendActionCommand.swift`, `UIControlSendActionModels.swift`

- [ ] **Step 1: 写失败 action plan 测试**

```swift
@Test("ActionPlan 保留 tap 的坐标定位")
func tapActionPlanPreservesWindowPoint() {
    let plan = UIKitActionPlan.tap(locator: .windowPoint(x: 20, y: 30))
    guard case .tap(let locator) = plan else { Issue.record("expected tap plan"); return }
    #expect(locator == .windowPoint(x: 20, y: 30))
}

@Test("ActionPlan 保留 control event")
func controlActionPlanPreservesEvent() {
    let plan = UIKitActionPlan.controlEvent(locator: .path([0]), event: .touchUpInside)
    guard case .controlEvent(_, let event) = plan else { Issue.record("expected control plan"); return }
    #expect(event == .touchUpInside)
}
```

- [ ] **Step 2: 确认失败并实现 executor**

Run: `swift test --filter tapActionPlanPreservesWindowPoint && swift test --filter controlActionPlanPreservesEvent`

Expected: FAIL。

```swift
enum UIKitActionPlan: Sendable, Equatable {
    case tap(locator: UIKitLocator)
    case controlEvent(locator: UIKitLocator, event: UIControlSendActionEvent)
}
```

`@MainActor UIKitActionExecutor.execute(_:)` 固定执行：获取 Context、resolve locator、共享 capability 校验、hit-test 或 `sendActions(for:)`、生成既有 JSON。保留 `controlActionFallback`、event 名、target 摘要和既有错误语义；adapter 只构造 plan 并 `await` executor。本任务不解析或校验 snapshotID。

- [ ] **Step 3: 验证并提交**

Run: `swift test --filter UIKitTapTests && swift test --filter UIKitControlActionTests && swift test --filter UIKitCommandRegistrationTests`

Expected: PASS；既有请求的解析与迁移前一致。

```bash
git add Sources/iOSExploreUIKit/Action Sources/iOSExploreUIKit/Commands/Tap Sources/iOSExploreUIKit/Commands/ControlAction Tests/iOSExploreServerTests
git commit -m "refactor: route UIKit actions through executor"
```

### Task 6: 独立实现 snapshot store 与陈旧 path 检测

**Files:**
- Create: `Sources/iOSExploreUIKit/Snapshot/UIKitSnapshotStore.swift`
- Modify: ViewHierarchy、ViewTargets collectors 与 `UIKitActionExecutor.swift`
- Create: `Tests/iOSExploreServerTests/UIKitSnapshotTests.swift`

- [ ] **Step 1: 写失败 snapshot 测试**

```swift
@Test("超过 TTL 的 snapshot 被判定陈旧") @MainActor
func expiredSnapshotIsStale() {
    let store = UIKitSnapshotStore(now: { Date(timeIntervalSince1970: 100) })
    guard let id = store.insert(context: .test, targets: ["root/0": .test]) else {
        Issue.record("small snapshot should be stored"); return
    }
    store.setNow(Date(timeIntervalSince1970: 111))
    #expect(store.validation(snapshotID: id, path: "root/0", current: .test) == .stale)
}

@Test("超过 512 条指纹时不签发 snapshot") @MainActor
func oversizedSnapshotIsNotStored() {
    let store = UIKitSnapshotStore()
    let targets = Dictionary(uniqueKeysWithValues: (0...512).map { ("root/\($0)", UIKitTargetFingerprint.test) })
    #expect(store.insert(context: .test, targets: targets) == nil)
}

@Test("交互命令解析可选 snapshotID")
func actionQueriesParseSnapshotID() {
    #expect(UITapQuery.parse(from: ["path": "root/0", "snapshotID": "s1"]).snapshotID == "s1")
    #expect(UIControlSendActionQuery.parse(from: ["path": "root/0", "event": "touchUpInside", "snapshotID": "s1"]).snapshotID == "s1")
}
```

- [ ] **Step 2: 确认失败并实现 MainActor store**

Run: `swift test --filter UIKitSnapshotTests`

Expected: FAIL。

实现 `@MainActor final class UIKitSnapshotStore`：最多 8 条、每条最多 512 指纹、TTL 10 秒、先清过期后 LRU 淘汰。fingerprint 只保存 context 类型摘要、path、view type、identifier 哈希、role、基础状态；绝不保存 UIView、文本或完整 identifier。超过 512 条时 collector 仍成功返回，但 `snapshotID` 为 JSON null。

本任务同时为 `UITapQuery` 与 `UIControlSendActionQuery` 增加可选 `snapshotID` 参数，并把 `UIKitActionPlan` 扩展为携带该值。两个 collector 都返回 `snapshotID`；仅 ViewTargets target 返回 `availableActions`。executor 只在 `.path + snapshotID` 时校验，失败通过 `UIKitCommandError.staleLocator` 返回 `invalid_data`。

- [ ] **Step 3: 验证并提交**

Run: `swift test --filter UIKitSnapshotTests && swift test --filter UIKitTapTests && swift test --filter UIKitControlActionTests`

Expected: PASS。

```bash
git add Sources/iOSExploreUIKit/Snapshot Sources/iOSExploreUIKit/Query Sources/iOSExploreUIKit/Action/UIKitActionExecutor.swift Tests/iOSExploreServerTests/UIKitSnapshotTests.swift
git commit -m "feat: detect stale UIKit path locators"
```

### Task 7: 配置 framework、Example、文档并全量验证

**Files:**
- Modify: `iOSExploreServer/iOSExploreServer.xcodeproj/project.pbxproj`
- Modify: `Examples/SPMExample/SPMExample.xcodeproj/project.pbxproj`, `ViewController.swift`
- Modify: `docs/architecture/index.md`, `docs/tools/network-tools.md`, `docs/runbooks/build-and-test.md`, `AGENTS.md`

- [ ] **Step 1: 先让 Example 引用新模块并确认构建失败**

```swift
import iOSExploreUIKit

// UIKit 命令由宿主显式开放。
server.registerUIKitCommands()
```

Run: `xcodebuild -project Examples/SPMExample/SPMExample.xcodeproj -scheme SPMExample -sdk iphonesimulator build`

Expected: FAIL，尚未添加 `iOSExploreUIKit` package product。

- [ ] **Step 2: 配置两个 framework 与 Example package product**

在 framework 工程新增 `iOSExploreUIKit.framework` target，filesystem-synchronized root group 指向 `../Sources/iOSExploreUIKit`；链接并依赖 core framework；Debug/Release 均设置 `SWIFT_VERSION=5.0`、`BUILD_LIBRARY_FOR_DISTRIBUTION=NO` 和相同 deployment target。测试 target 同时链接两个 framework。SPMExample 的本地 package dependency 同时选择 core/UIKit products。

在 `UIKitCommandRegistrationTests.swift` 增加仅 iOS 编译的正向断言：

```swift
#if canImport(UIKit)
@Test("显式注册后 help 包含 UIKit actions")
func explicitRegistrationAddsUIKitCommands() async {
    let server = ExploreServer()
    server.registerUIKitCommands()
    let result = await server.routerSnapshotRoute(ExploreRequest(action: "help"))
    #expect(result.commandActions.contains("ui.topViewHierarchy"))
    #expect(result.commandActions.contains("ui.viewTargets"))
    #expect(result.commandActions.contains("ui.control.sendAction"))
    #expect(result.commandActions.contains("ui.tap"))
}
#endif
```

运行 `xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator test`，预期该断言 PASS。

- [ ] **Step 3: 同步项目文档**

更新模块图与显式注册、query→identifier 优先→可选 path+snapshot、双 framework/Example 构建、core/UIKit 模块边界、typed factory 规则。日志说明必须覆盖 registrar、MainActor hop、query、resolver、executor。

- [ ] **Step 4: 全量验证**

Run `swift test`、framework 的 `xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator build`、Example 的 `xcodebuild -project Examples/SPMExample/SPMExample.xcodeproj -scheme SPMExample -sdk iphonesimulator build`，最后运行 `git diff --check`。

Expected: 四条命令均退出 0。App 验收：未注册时 help 不含 UIKit action；注册后四 action 可用；identifier 不被截断；旧 `path + snapshotID` 页面变动后返回 HTTP 200、`ok:false`、`invalid_data` 和固定陈旧消息。

- [ ] **Step 5: 提交集成变更**

```bash
git add iOSExploreServer/iOSExploreServer.xcodeproj Examples/SPMExample docs AGENTS.md
git commit -m "docs: document UIKit extension integration"
```

## 计划自检

- [ ] Task 1 覆盖 core 的错误/日志扩展缝。
- [ ] Task 2 覆盖 target 拆分与显式注册。
- [ ] Task 3 覆盖 MainActor Context、Locator 和 UIKit typed factory。
- [ ] Task 4 覆盖真实动作能力与 identifier 修复。
- [ ] Task 5 覆盖既有 action 迁入 executor。
- [ ] Task 6 覆盖 snapshot 上限、TTL、兼容行为与 `invalid_data`。
- [ ] Task 7 覆盖 framework、Example、文档和全量验证。
