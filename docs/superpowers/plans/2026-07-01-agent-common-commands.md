# Agent 常用 UIKit 命令 v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现第一批 5 个 agent 常用 UIKit 命令：`ui.keyboard.dismiss`、`ui.navigation.back`、`ui.wait`、`ui.scrollToElement`、`ui.alert.respond`，并修复当前 UIKit 命令文档漂移。

**Architecture:** 新命令继续走 typed factory：Foundation-only `CommandInput` 解析 schema，`@MainActor` executor 访问 UIKit，失败统一经 `UIKitCommandError` 转 envelope。实现顺序按风险从低到高；`ui.alert.respond` 先做 spike，未验证直接点击前只实现查询和 path 建议。

**Tech Stack:** Swift 6.2 / SPM / UIKit optional module (`#if canImport(UIKit)`) / Swift Testing / Xcode framework build。

**上游 spec:** `docs/superpowers/specs/2026-07-01-agent-common-commands-design.md`（v2）。

---

## Global Constraints

- `Sources/iOSExploreServer/` 仍只依赖 Foundation + Network，不引入 UIKit。
- `Sources/iOSExploreUIKit/Commands/**Models.swift` 必须 Foundation-only，保证 macOS `swift test` 能编译 schema/parse 测试。
- UIKit executor/collector/command adapter 整体包 `#if canImport(UIKit)`。
- 所有新增错误先扩 `ExploreError` 或明确复用旧 code，再加 `UIKitCommandError` 工厂。
- 日志只记录 action、字段摘要、长度、类型、耗时、error code，不记录完整输入文本、截图或大块 payload。
- 每个 public 类型、属性、方法补中文 `///` 注释；关键 internal executor/helper 也写职责与日志点。
- 每个任务先写失败测试，再实现，再跑局部测试。

## File Map

- Modify: `Sources/iOSExploreServer/Models.swift`  
  新增可恢复业务错误 code。
- Modify: `Sources/iOSExploreUIKit/UIKitCommandError.swift`  
  新增错误工厂，并修正 `staleLocator` 使用 `.staleLocator`。
- Modify: `Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift`  
  注册新增命令，最终 count 从 7 改为 12。
- Create: `Sources/iOSExploreUIKit/Commands/Keyboard/UIKeyboardDismissModels.swift`
- Create: `Sources/iOSExploreUIKit/Commands/Keyboard/UIKeyboardDismissCommand.swift`
- Create: `Sources/iOSExploreUIKit/Support/Action/UIKeyboardDismissExecutor.swift`
- Create: `Sources/iOSExploreUIKit/Commands/Navigation/UINavigationBackModels.swift`
- Create: `Sources/iOSExploreUIKit/Commands/Navigation/UINavigationBackCommand.swift`
- Create: `Sources/iOSExploreUIKit/Support/Action/UINavigationBackExecutor.swift`
- Create: `Sources/iOSExploreUIKit/Commands/Wait/UIWaitModels.swift`
- Create: `Sources/iOSExploreUIKit/Commands/Wait/UIWaitCommand.swift`
- Create: `Sources/iOSExploreUIKit/Support/Wait/UIWaitExecutor.swift`
- Create: `Sources/iOSExploreUIKit/Support/Wait/UIKitVisibleTextCollector.swift`
- Create: `Sources/iOSExploreUIKit/Support/Action/UIScrollResolver.swift`
- Create: `Sources/iOSExploreUIKit/Support/Action/UIScrollGeometry.swift`
- Modify: `Sources/iOSExploreUIKit/Support/Action/UIScrollExecutor.swift`
- Create: `Sources/iOSExploreUIKit/Commands/ScrollToElement/UIScrollToElementModels.swift`
- Create: `Sources/iOSExploreUIKit/Commands/ScrollToElement/UIScrollToElementCommand.swift`
- Create: `Sources/iOSExploreUIKit/Support/Action/UIScrollToElementExecutor.swift`
- Create: `Sources/iOSExploreUIKit/Commands/Alert/UIAlertRespondModels.swift`
- Create: `Sources/iOSExploreUIKit/Commands/Alert/UIAlertRespondCommand.swift`
- Create: `Sources/iOSExploreUIKit/Support/Action/UIAlertInspector.swift`
- Create: `Tests/iOSExploreServerTests/UIKeyboardDismissInputTests.swift`
- Create: `Tests/iOSExploreServerTests/UIKeyboardDismissTests.swift`
- Create: `Tests/iOSExploreServerTests/UINavigationBackInputTests.swift`
- Create: `Tests/iOSExploreServerTests/UINavigationBackTests.swift`
- Create: `Tests/iOSExploreServerTests/UIWaitInputTests.swift`
- Create: `Tests/iOSExploreServerTests/UIWaitTests.swift`
- Create: `Tests/iOSExploreServerTests/UIScrollToElementInputTests.swift`
- Create: `Tests/iOSExploreServerTests/UIScrollToElementTests.swift`
- Create: `Tests/iOSExploreServerTests/UIAlertRespondInputTests.swift`
- Create: `Tests/iOSExploreServerTests/UIAlertRespondSpikeTests.swift`
- Modify: `Tests/iOSExploreServerTests/UIKitCommandErrorTests.swift`
- Modify: `Tests/iOSExploreServerTests/UIKitCommandRegistrationTests.swift`
- Modify: `Tests/iOSExploreServerTests/UIKitCommandInputSchemaTests.swift`
- Modify docs: `README.md`, `AGENTS.md`, `docs/agent_instructions.md`, `docs/uikit/README.md`, `docs/uikit/reading-guide.md`, `docs/uikit/uikit-file-reference.md`

---

### Task 1: Core Error Codes And Stale Locator Contract

**Files:**
- Modify: `Sources/iOSExploreServer/Models.swift`
- Modify: `Sources/iOSExploreUIKit/UIKitCommandError.swift`
- Test: `Tests/iOSExploreServerTests/UIKitCommandErrorTests.swift`

- [ ] **Step 1: Write failing error contract tests**

Add assertions to `UIKitCommandErrorTests.swift`:

```swift
@Test("staleLocator 使用 stale_locator code")
func staleLocatorUsesDedicatedCode() {
    let error = UIKitCommandError.staleLocator(action: "ui.tap", snapshotID: "snap-1")
    #expect(error.failure.code == .staleLocator)
    #expect(error.failure.message.contains("ui.screenshot"))
}

@Test("agent common command error code raw values")
func agentCommonCommandErrorCodes() {
    #expect(ExploreError.waitTimeout.rawValue == "wait_timeout")
    #expect(ExploreError.navigationBackUnavailable.rawValue == "navigation_back_unavailable")
    #expect(ExploreError.alertUnavailable.rawValue == "alert_unavailable")
    #expect(ExploreError.alertButtonNotFound.rawValue == "alert_button_not_found")
    #expect(ExploreError.alertButtonRequired.rawValue == "alert_button_required")
    #expect(ExploreError.keyboardDismissFailed.rawValue == "keyboard_dismiss_failed")
    #expect(ExploreError.targetNotFound.rawValue == "target_not_found")
}
```

- [ ] **Step 2: Run focused test and confirm failure**

Run: `swift test --filter UIKitCommandErrorTests`  
Expected: FAIL because new `ExploreError` cases do not exist and `staleLocator` currently returns `.invalidData`.

- [ ] **Step 3: Add core error cases**

Append to `ExploreError` in `Sources/iOSExploreServer/Models.swift`:

```swift
/// 等待条件在业务 deadline 内未满足。
case waitTimeout = "wait_timeout"

/// 当前页面没有可返回的导航路径。
case navigationBackUnavailable = "navigation_back_unavailable"

/// 当前没有可处理的 UIAlertController。
case alertUnavailable = "alert_unavailable"

/// 指定的 alert 按钮不存在。
case alertButtonNotFound = "alert_button_not_found"

/// 当前 alert 不能安全默认选择按钮，需要调用方明确指定。
case alertButtonRequired = "alert_button_required"

/// 键盘或 first responder 收起失败。
case keyboardDismissFailed = "keyboard_dismiss_failed"

/// 目标在当前 UI 树或滚动搜索后仍未找到。
case targetNotFound = "target_not_found"
```

- [ ] **Step 4: Update UIKitCommandError factories**

Change `staleLocator` to use `.staleLocator`. Add factories:

```swift
static func waitTimeout(action: String, mode: String, elapsedMs: Int) -> UIKitCommandError {
    UIKitCommandError(code: .waitTimeout,
                      message: "wait timed out mode=\(mode) elapsedMs=\(elapsedMs)",
                      logMessage: "ui wait timeout action=\(action) mode=\(mode) elapsedMs=\(elapsedMs)")
}

static func navigationBackUnavailable(action: String, top: String) -> UIKitCommandError {
    UIKitCommandError(code: .navigationBackUnavailable,
                      message: "navigation back unavailable",
                      logMessage: "ui navigation back unavailable action=\(action) top=\(top)")
}

static func alertUnavailable(action: String) -> UIKitCommandError {
    UIKitCommandError(code: .alertUnavailable,
                      message: "alert unavailable",
                      logMessage: "ui alert unavailable action=\(action)")
}

static func alertButtonNotFound(action: String, selector: String) -> UIKitCommandError {
    UIKitCommandError(code: .alertButtonNotFound,
                      message: "alert button not found",
                      logMessage: "ui alert button not found action=\(action) selector=\(selector)")
}

static func alertButtonRequired(action: String) -> UIKitCommandError {
    UIKitCommandError(code: .alertButtonRequired,
                      message: "alert button is required",
                      logMessage: "ui alert button required action=\(action)")
}

static func keyboardDismissFailed(action: String, strategy: String) -> UIKitCommandError {
    UIKitCommandError(code: .keyboardDismissFailed,
                      message: "keyboard dismiss failed",
                      logMessage: "ui keyboard dismiss failed action=\(action) strategy=\(strategy)")
}

static func targetNotFound(action: String, message: String, logMessage: String) -> UIKitCommandError {
    UIKitCommandError(code: .targetNotFound, message: message, logMessage: logMessage)
}
```

- [ ] **Step 5: Verify**

Run: `swift test --filter UIKitCommandErrorTests`  
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/iOSExploreServer/Models.swift Sources/iOSExploreUIKit/UIKitCommandError.swift Tests/iOSExploreServerTests/UIKitCommandErrorTests.swift
git commit -m "feat(uikit): add agent command error contracts"
```

---

### Task 2: `ui.keyboard.dismiss`

**Files:**
- Create: `Sources/iOSExploreUIKit/Commands/Keyboard/UIKeyboardDismissModels.swift`
- Create: `Sources/iOSExploreUIKit/Commands/Keyboard/UIKeyboardDismissCommand.swift`
- Create: `Sources/iOSExploreUIKit/Support/Action/UIKeyboardDismissExecutor.swift`
- Test: `Tests/iOSExploreServerTests/UIKeyboardDismissInputTests.swift`
- Test: `Tests/iOSExploreServerTests/UIKeyboardDismissTests.swift`
- Modify: `Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift`

- [ ] **Step 1: Write failing input tests**

Create `UIKeyboardDismissInputTests.swift`:

```swift
import Testing
@testable import iOSExploreUIKit

@Test("keyboard dismiss 默认 auto 和 waitAfterMs")
func keyboardDismissDefaults() throws {
    let input = try UIKeyboardDismissInput.parse(from: [:])
    #expect(input.strategy == .auto)
    #expect(input.waitAfterMs == 200)
}

@Test("keyboard dismiss 拒绝非法 strategy")
func keyboardDismissRejectsInvalidStrategy() {
    #expect(throws: Error.self) {
        try UIKeyboardDismissInput.parse(from: ["strategy": "force"])
    }
}

@Test("keyboard dismiss 限制 waitAfterMs 范围")
func keyboardDismissRejectsInvalidWait() {
    #expect(throws: Error.self) {
        try UIKeyboardDismissInput.parse(from: ["waitAfterMs": 3001])
    }
}
```

- [ ] **Step 2: Implement model**

Use `CommandFields.enumValue` and an Int field helper if available. If no bounded Int helper exists, use `optionalFiniteNumber` and check integer/range in `parse`.

```swift
public enum KeyboardDismissStrategy: String, Sendable, Equatable, CaseIterable {
    case auto
    case resignFirstResponder
    case endEditing
}

public struct UIKeyboardDismissInput: CommandInput, Sendable, Equatable {
    public static let inputSchema = CommandInputSchema(fields: Fields.all)
    public let strategy: KeyboardDismissStrategy
    public let waitAfterMs: Int
}
```

- [ ] **Step 3: Write failing executor tests**

Create `UIKeyboardDismissTests.swift` guarded by `#if canImport(UIKit)`. Include:

```swift
@Test("没有 first responder 时返回 dismissed false")
@MainActor
func dismissWithoutFirstResponderIsSuccessNoop() throws {
    let context = UIKitTestHost.context { _ in }
    let data = try UIKeyboardDismissExecutor.execute(input: UIKeyboardDismissInput(), context: context)
    #expect(data["dismissed"]?.boolValue == false)
}
```

If a reliable logic-test first responder setup is available, add a `UITextField` case. If not, keep no-op plus command registration/schema tests and leave full responder case for framework runtime.

- [ ] **Step 4: Implement executor and command**

Executor rules:

- find first responder by walking `context.window`;
- `auto`: try `resignFirstResponder`, then `context.window.endEditing(true)`;
- if none exists, success with `dismissed=false`;
- if responder remains after attempted strategy, throw `keyboardDismissFailed`.

Command shape:

```swift
struct KeyboardDismissCommand: Command {
    typealias Input = UIKeyboardDismissInput
    static let actionName = "ui.keyboard.dismiss"
    let action = KeyboardDismissCommand.actionName
    let description = "收起当前 first responder / 键盘"
}
```

- [ ] **Step 5: Register command**

Add to `registerUIKitCommands()` after `InputCommand()`:

```swift
register(KeyboardDismissCommand(), logCategory: .extensionCommand(category: "command"))
```

Temporarily update count to 8; final docs task will set count to 12 after all commands land.

- [ ] **Step 6: Verify and commit**

Run:

```bash
swift test --filter UIKeyboardDismissInputTests
swift test --filter UIKitCommandRegistrationTests
```

Expected: PASS on macOS where UIKit-gated runtime tests are skipped.

Commit:

```bash
git add Sources/iOSExploreUIKit/Commands/Keyboard Sources/iOSExploreUIKit/Support/Action/UIKeyboardDismissExecutor.swift Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift Tests/iOSExploreServerTests/UIKeyboardDismissInputTests.swift Tests/iOSExploreServerTests/UIKeyboardDismissTests.swift
git commit -m "feat(uikit): add keyboard dismiss command"
```

---

### Task 3: `ui.navigation.back`

**Files:**
- Create: `Sources/iOSExploreUIKit/Commands/Navigation/UINavigationBackModels.swift`
- Create: `Sources/iOSExploreUIKit/Commands/Navigation/UINavigationBackCommand.swift`
- Create: `Sources/iOSExploreUIKit/Support/Action/UINavigationBackExecutor.swift`
- Test: `Tests/iOSExploreServerTests/UINavigationBackInputTests.swift`
- Test: `Tests/iOSExploreServerTests/UINavigationBackTests.swift`
- Modify: `Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift`

- [ ] **Step 1: Write input tests**

Create `UINavigationBackInputTests.swift`:

```swift
import Testing
@testable import iOSExploreUIKit

@Test("navigation back 默认 auto animated false waitAfterMs 300")
func navigationBackDefaults() throws {
    let input = try UINavigationBackInput.parse(from: [:])
    #expect(input.strategy == .auto)
    #expect(input.animated == false)
    #expect(input.waitAfterMs == 300)
}

@Test("navigation back 拒绝非法 waitAfterMs")
func navigationBackRejectsWaitAfterOutOfRange() {
    #expect(throws: Error.self) {
        try UINavigationBackInput.parse(from: ["waitAfterMs": -1])
    }
}
```

- [ ] **Step 2: Implement model**

```swift
public enum NavigationBackStrategy: String, Sendable, Equatable, CaseIterable {
    case auto
    case navigationController
    case barButton
    case dismiss
}

public struct UINavigationBackInput: CommandInput, Sendable, Equatable {
    public static let inputSchema = CommandInputSchema(fields: Fields.all)
    public let strategy: NavigationBackStrategy
    public let animated: Bool
    public let waitAfterMs: Int
}
```

- [ ] **Step 3: Write executor tests**

Add iOS-gated tests:

```swift
@Test("navigationController strategy pop 顶层控制器")
@MainActor
func navigationControllerStrategyPops() throws {
    let root = UIViewController()
    let detail = UIViewController()
    let navigation = UINavigationController(rootViewController: root)
    navigation.pushViewController(detail, animated: false)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    window.rootViewController = navigation
    window.makeKeyAndVisible()
    let context = UIKitContextProvider.Context(window: window,
                                               rootViewController: navigation,
                                               topViewController: detail,
                                               rootView: detail.view)
    let input = UINavigationBackInput(strategy: .navigationController, animated: false, waitAfterMs: 0)
    let data = try UINavigationBackExecutor.execute(input: input, context: context)
    #expect(data["performed"]?.boolValue == true)
    #expect(navigation.viewControllers.count == 1)
}
```

Also test no navigation path throws `navigationBackUnavailable`.

- [ ] **Step 4: Implement executor**

Executor order:

1. `.dismiss`: if `topViewController.presentingViewController != nil`, dismiss.
2. `.navigationController`: if `topViewController.navigationController?.viewControllers.count ?? 0 > 1`, pop.
3. `.barButton`: best-effort only; locate visible navigation bar left-side UIControl and dispatch through existing action primitives if practical.
4. `.auto`: dismiss -> navigationController -> barButton.

Return `performed`, `strategy`, `topBefore`, `topAfter`.

- [ ] **Step 5: Register and verify**

Run:

```bash
swift test --filter UINavigationBackInputTests
swift test --filter UIKitCommandRegistrationTests
```

Commit:

```bash
git add Sources/iOSExploreUIKit/Commands/Navigation Sources/iOSExploreUIKit/Support/Action/UINavigationBackExecutor.swift Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift Tests/iOSExploreServerTests/UINavigationBackInputTests.swift Tests/iOSExploreServerTests/UINavigationBackTests.swift
git commit -m "feat(uikit): add navigation back command"
```

---

### Task 4: `ui.wait`

**Files:**
- Create: `Sources/iOSExploreUIKit/Commands/Wait/UIWaitModels.swift`
- Create: `Sources/iOSExploreUIKit/Commands/Wait/UIWaitCommand.swift`
- Create: `Sources/iOSExploreUIKit/Support/Wait/UIWaitExecutor.swift`
- Create: `Sources/iOSExploreUIKit/Support/Wait/UIKitVisibleTextCollector.swift`
- Test: `Tests/iOSExploreServerTests/UIWaitInputTests.swift`
- Test: `Tests/iOSExploreServerTests/UIWaitTests.swift`
- Modify: `Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift`

- [ ] **Step 1: Write input tests**

Create `UIWaitInputTests.swift`:

```swift
import Testing
@testable import iOSExploreUIKit

@Test("wait 默认超时和轮询间隔")
func waitDefaults() throws {
    let input = try UIWaitInput.parse(from: ["mode": "idle"])
    #expect(input.mode == .idle)
    #expect(input.timeoutMs == 3000)
    #expect(input.intervalMs == 100)
    #expect(input.stableMs == 300)
}

@Test("targetExists 必须提供 identifier 或 path")
func targetExistsRequiresLocator() {
    #expect(throws: Error.self) {
        try UIWaitInput.parse(from: ["mode": "targetExists"])
    }
}

@Test("snapshotChanged 必须提供 snapshotID")
func snapshotChangedRequiresSnapshotID() {
    #expect(throws: Error.self) {
        try UIWaitInput.parse(from: ["mode": "snapshotChanged"])
    }
}
```

- [ ] **Step 2: Implement model and command timeout**

```swift
public enum WaitMode: String, Sendable, Equatable, CaseIterable {
    case idle
    case targetExists
    case targetGone
    case textExists
    case snapshotChanged
}

struct WaitCommand: Command {
    typealias Input = UIWaitInput
    static let actionName = "ui.wait"
    let action = WaitCommand.actionName
    let description = "等待 UI 稳定或等待目标/文本/快照变化"
    var timeoutNanoseconds: UInt64? { 31_000_000_000 }
}
```

- [ ] **Step 3: Add visible text collector**

Create `UIKitVisibleTextCollector`:

- recursively walk `UIView`;
- skip hidden views when `includeHidden == false`;
- collect `UILabel.text`, `UIButton.currentTitle`, `UITextField.placeholder`, `accessibilityLabel`, and non-editing `accessibilityValue`;
- do not log collected text;
- return path/type/text fragments for matching and optional response summary.

- [ ] **Step 4: Write executor tests**

Include iOS-gated tests:

```swift
@Test("wait textExists 找到 UILabel 文本")
@MainActor
func waitTextExistsFindsLabel() async throws {
    let context = UIKitTestHost.context { root in
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 20))
        label.text = "订单详情"
        root.addSubview(label)
    }
    let input = UIWaitInput(mode: .textExists, timeoutMs: 300, intervalMs: 50, stableMs: 100, target: nil, text: "订单", snapshotID: nil, includeHidden: false)
    let data = try await UIWaitExecutor.execute(input: input, contextProvider: { context })
    #expect(data["satisfied"]?.boolValue == true)
}
```

Also test timeout with a short deadline returns `UIKitCommandError.waitTimeout`.

- [ ] **Step 5: Implement executor**

Implementation rules:

- compute deadline with monotonic `Date()` or `ContinuousClock` compatible with framework target;
- loop while now < deadline;
- each attempt fetches context via injected provider;
- check mode condition;
- sleep `intervalMs` between attempts with `Task.sleep`;
- return success JSON with `satisfied`, `mode`, `elapsedMs`, `attempts`, `snapshotID`, `snapshotUnavailableReason`;
- on deadline throw `UIKitCommandError.waitTimeout`.

- [ ] **Step 6: Register, verify, commit**

Run:

```bash
swift test --filter UIWaitInputTests
swift test --filter UIWaitTests
swift test --filter UIKitCommandRegistrationTests
```

Commit:

```bash
git add Sources/iOSExploreUIKit/Commands/Wait Sources/iOSExploreUIKit/Support/Wait Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift Tests/iOSExploreServerTests/UIWaitInputTests.swift Tests/iOSExploreServerTests/UIWaitTests.swift
git commit -m "feat(uikit): add wait command"
```

---

### Task 5: Extract Shared Scroll Primitives

**Files:**
- Create: `Sources/iOSExploreUIKit/Support/Action/UIScrollResolver.swift`
- Create: `Sources/iOSExploreUIKit/Support/Action/UIScrollGeometry.swift`
- Modify: `Sources/iOSExploreUIKit/Support/Action/UIScrollExecutor.swift`
- Test: `Tests/iOSExploreServerTests/UIScrollTests.swift`

- [ ] **Step 1: Add regression tests before refactor**

Extend `UIScrollTests.swift` to assert:

- `UITextView` is still rejected as a scroll container;
- default amount remains visible dimension × 0.5 for `ui.scroll`;
- `reachedExtent` still uses `adjustedContentInset` with 1pt tolerance.

- [ ] **Step 2: Extract resolver**

Create `UIScrollResolver` with:

```swift
@MainActor
enum UIScrollResolver {
    struct Resolved: Sendable {
        let scrollView: UIScrollView
        let targetDescription: String
        let targetPath: String?
    }

    static func resolve(locator: UIKitViewLookupTarget?,
                        snapshotID: String?,
                        context: UIKitContextProvider.Context,
                        action: String) throws -> Resolved
}
```

Rules: preserve current `nearestScrollView`, `foremostScrollView`, stale path validation, and `UITextView` exclusion.

- [ ] **Step 3: Extract geometry**

Create `UIScrollGeometry`:

```swift
@MainActor
enum UIScrollGeometry {
    static func defaultDistance(scrollView: UIScrollView, direction: ScrollDirection, ratio: Double) -> Double
    static func delta(for direction: ScrollDirection, amount: Double) -> CGPoint
    static func reachedExtent(scrollView: UIScrollView) -> ScrollExtent?
    static func step(scrollView: UIScrollView, direction: ScrollDirection, amount: Double, animated: Bool) -> UIScrollStepResult
}
```

`UIScrollStepResult` should expose `offsetBefore`, `offsetAfter`, `reachedExtent`, `adjustedContentInset`, and `toJSON(container:)`.

- [ ] **Step 4: Rewrite UIScrollExecutor to use primitives**

`UIScrollExecutor.execute` becomes:

1. resolve scroll view;
2. amount = input.amount ?? `UIScrollGeometry.defaultDistance(scrollView: resolved.scrollView, direction: input.direction, ratio: 0.5)`;
3. step;
4. return same JSON fields as before.

- [ ] **Step 5: Verify behavior unchanged**

Run:

```bash
swift test --filter UIScrollInputTests
swift test --filter UIScrollTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/iOSExploreUIKit/Support/Action/UIScrollResolver.swift Sources/iOSExploreUIKit/Support/Action/UIScrollGeometry.swift Sources/iOSExploreUIKit/Support/Action/UIScrollExecutor.swift Tests/iOSExploreServerTests/UIScrollTests.swift
git commit -m "refactor(uikit): extract shared scroll primitives"
```

---

### Task 6: `ui.scrollToElement`

**Files:**
- Create: `Sources/iOSExploreUIKit/Commands/ScrollToElement/UIScrollToElementModels.swift`
- Create: `Sources/iOSExploreUIKit/Commands/ScrollToElement/UIScrollToElementCommand.swift`
- Create: `Sources/iOSExploreUIKit/Support/Action/UIScrollToElementExecutor.swift`
- Test: `Tests/iOSExploreServerTests/UIScrollToElementInputTests.swift`
- Test: `Tests/iOSExploreServerTests/UIScrollToElementTests.swift`
- Modify: `Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift`

- [ ] **Step 1: Write input tests**

Create `UIScrollToElementInputTests.swift`:

```swift
import Testing
@testable import iOSExploreUIKit

@Test("scrollToElement 默认 direction down maxScrolls 8")
func scrollToElementDefaults() throws {
    let input = try UIScrollToElementInput.parse(from: ["match": "text", "value": "订单"])
    #expect(input.match == .text)
    #expect(input.value == "订单")
    #expect(input.direction == .down)
    #expect(input.maxScrolls == 8)
}

@Test("scrollToElement 容器 identifier 和 path 互斥")
func scrollToElementRejectsBothContainers() {
    #expect(throws: Error.self) {
        try UIScrollToElementInput.parse(from: [
            "match": "text",
            "value": "订单",
            "containerAccessibilityIdentifier": "list",
            "containerPath": "root/0"
        ])
    }
}
```

- [ ] **Step 2: Implement model**

```swift
public enum ScrollToElementMatch: String, Sendable, Equatable, CaseIterable {
    case accessibilityIdentifier
    case text
}

public struct UIScrollToElementInput: CommandInput, Sendable, Equatable {
    public static let inputSchema = CommandInputSchema(fields: Fields.all,
                                                       constraints: [.extensionMessage("containerAccessibilityIdentifier/containerPath are mutually exclusive")])
}
```

- [ ] **Step 3: Write executor tests**

iOS-gated tests:

- found visible text without scrolling returns `found=true`, `scrolls=0`;
- list requires one or more scroll steps then finds target;
- target missing returns `.targetNotFound`;
- container missing returns `.scrollContainerUnavailable`.

- [ ] **Step 4: Implement executor**

Loop:

1. collect visible targets from current context;
2. match by identifier exact or text contains;
3. if visible intersection with window bounds, return target/container/snapshot JSON;
4. else perform `UIScrollGeometry.step` with default ratio 0.7;
5. break on reached extent matching direction or `maxScrolls`.

Do not support `WKWebView` DOM.

- [ ] **Step 5: Register, verify, commit**

Run:

```bash
swift test --filter UIScrollToElementInputTests
swift test --filter UIScrollToElementTests
swift test --filter UIKitCommandRegistrationTests
```

Commit:

```bash
git add Sources/iOSExploreUIKit/Commands/ScrollToElement Sources/iOSExploreUIKit/Support/Action/UIScrollToElementExecutor.swift Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift Tests/iOSExploreServerTests/UIScrollToElementInputTests.swift Tests/iOSExploreServerTests/UIScrollToElementTests.swift
git commit -m "feat(uikit): add scroll to element command"
```

---

### Task 7: `ui.alert.respond` Spike And Query-First Command

**Files:**
- Create: `Sources/iOSExploreUIKit/Commands/Alert/UIAlertRespondModels.swift`
- Create: `Sources/iOSExploreUIKit/Commands/Alert/UIAlertRespondCommand.swift`
- Create: `Sources/iOSExploreUIKit/Support/Action/UIAlertInspector.swift`
- Test: `Tests/iOSExploreServerTests/UIAlertRespondInputTests.swift`
- Test: `Tests/iOSExploreServerTests/UIAlertRespondSpikeTests.swift`
- Modify: `Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift`

- [ ] **Step 1: Write input tests**

Create `UIAlertRespondInputTests.swift`:

```swift
import Testing
@testable import iOSExploreUIKit

@Test("alert respond 默认 dryRun false")
func alertRespondDefaults() throws {
    let input = try UIAlertRespondInput.parse(from: [:])
    #expect(input.dryRun == false)
    #expect(input.buttonTitle == nil)
    #expect(input.buttonIndex == nil)
    #expect(input.role == nil)
}

@Test("alert respond 选择字段最多一个")
func alertRespondRejectsMultipleSelectors() {
    #expect(throws: Error.self) {
        try UIAlertRespondInput.parse(from: ["buttonTitle": "确定", "buttonIndex": 0])
    }
}
```

- [ ] **Step 2: Implement model**

```swift
public enum AlertButtonRole: String, Sendable, Equatable, CaseIterable {
    case `default`
    case cancel
    case destructive
}

public struct UIAlertRespondInput: CommandInput, Sendable, Equatable {
    public static let inputSchema = CommandInputSchema(fields: Fields.all,
                                                       constraints: [.extensionMessage("buttonTitle/buttonIndex/role 最多提供一个")])
}
```

In `parse(decoding:)`, count non-nil `buttonTitle` / `buttonIndex` / `role`; if count > 1, throw `CommandInputParseError("buttonTitle/buttonIndex/role are mutually exclusive")`.

- [ ] **Step 3: Write spike tests**

Create iOS-gated test:

```swift
@Test("alert inspector lists UIAlertController actions")
@MainActor
func alertInspectorListsActions() throws {
    let alert = UIAlertController(title: "确认", message: "是否继续", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "继续", style: .default))
    let host = UIViewController()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.present(alert, animated: false)
    let summary = try UIAlertInspector.inspect(presented: alert, rootView: alert.view)
    #expect(summary.buttons.map(\.title) == ["取消", "继续"])
}
```

Add a second spike assertion only if button view path can be found by public hierarchy traversal. If it is not stable, assert `buttonPath == nil` and keep command query-only.

- [ ] **Step 4: Implement query-first inspector and command**

Rules:

- find current presented controller;
- if it is not `UIAlertController`, throw `alertUnavailable`;
- return title/message/buttons;
- for each action return index/title/role and optional `path`;
- if `dryRun == true`, do not act;
- if selector is present and path is available, optionally dispatch through existing tap path only after spike passes;
- if selector is present but path is unavailable, return failure with `alertUnavailable` or `invalid_data` per spec, not fake success.

- [ ] **Step 5: Register, verify, commit**

Run:

```bash
swift test --filter UIAlertRespondInputTests
swift test --filter UIAlertRespondSpikeTests
swift test --filter UIKitCommandRegistrationTests
```

Commit:

```bash
git add Sources/iOSExploreUIKit/Commands/Alert Sources/iOSExploreUIKit/Support/Action/UIAlertInspector.swift Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift Tests/iOSExploreServerTests/UIAlertRespondInputTests.swift Tests/iOSExploreServerTests/UIAlertRespondSpikeTests.swift
git commit -m "feat(uikit): add alert respond query command"
```

---

### Task 8: Registration, Schema, Docs, And Final Verification

**Files:**
- Modify: `Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift`
- Modify: `Tests/iOSExploreServerTests/UIKitCommandRegistrationTests.swift`
- Modify: `Tests/iOSExploreServerTests/UIKitCommandInputSchemaTests.swift`
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `docs/agent_instructions.md`
- Modify: `docs/uikit/README.md`
- Modify: `docs/uikit/reading-guide.md`
- Modify: `docs/uikit/uikit-file-reference.md`

- [ ] **Step 1: Update final registrar count**

`registerUIKitCommands()` should register 12 commands:

```swift
register(TopViewHierarchyCommand(), logCategory: .extensionCommand(category: "command"))
register(ViewTargetsCommand(), logCategory: .extensionCommand(category: "command"))
register(UIControlSendActionCommand(), logCategory: .extensionCommand(category: "command"))
register(UITapCommand(), logCategory: .extensionCommand(category: "command"))
register(ScreenshotCommand(maxResponseBodyBytes: maxResponseBodyBytes), logCategory: .extensionCommand(category: "command"))
register(InputCommand(), logCategory: .extensionCommand(category: "command"))
register(KeyboardDismissCommand(), logCategory: .extensionCommand(category: "command"))
register(ScrollCommand(), logCategory: .extensionCommand(category: "command"))
register(NavigationBackCommand(), logCategory: .extensionCommand(category: "command"))
register(WaitCommand(), logCategory: .extensionCommand(category: "command"))
register(ScrollToElementCommand(), logCategory: .extensionCommand(category: "command"))
register(AlertRespondCommand(), logCategory: .extensionCommand(category: "command"))
```

Log line: `registration completed count=12`.

- [ ] **Step 2: Update registration tests**

In `UIKitCommandRegistrationTests`, assert all 12 actions:

```swift
#expect(result.commandActions.contains("ui.keyboard.dismiss"))
#expect(result.commandActions.contains("ui.navigation.back"))
#expect(result.commandActions.contains("ui.wait"))
#expect(result.commandActions.contains("ui.scrollToElement"))
#expect(result.commandActions.contains("ui.alert.respond"))
```

- [ ] **Step 3: Update schema tests**

Add tests in `UIKitCommandInputSchemaTests.swift`:

```swift
@Test("ui.keyboard.dismiss 命令 schema 声明 typed input 字段")
func keyboardDismissCommandSchemaMatchesInputFields() {
    #expect(KeyboardDismissCommand.Input.inputSchema.fields.map(\.name) == UIKeyboardDismissInput.inputSchema.fields.map(\.name))
}
```

Repeat for `NavigationBackCommand`, `WaitCommand`, `ScrollToElementCommand`, `AlertRespondCommand`.

- [ ] **Step 4: Update docs**

Update command count:

- README command list: 16 total if core remains 4 and UIKit becomes 12.
- AGENTS/module boundary: `registerUIKitCommands()` lists 12 commands.
- `docs/uikit/README.md`: replace “4 个命令” with current 12 and table.
- `docs/uikit/reading-guide.md`: add new command family reading order.
- `docs/uikit/uikit-file-reference.md`: add new files and responsibilities.

- [ ] **Step 5: Run full verification**

Run:

```bash
swift test
xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
git diff --check
```

Expected:

- `swift test` PASS.
- framework build PASS.
- `git diff --check` no output.

If framework tests are required, first run:

```bash
xcrun simctl list devices available
```

Then select an available simulator destination explicitly.

- [ ] **Step 6: Commit**

```bash
git add Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift Tests/iOSExploreServerTests/UIKitCommandRegistrationTests.swift Tests/iOSExploreServerTests/UIKitCommandInputSchemaTests.swift README.md AGENTS.md docs/agent_instructions.md docs/uikit/README.md docs/uikit/reading-guide.md docs/uikit/uikit-file-reference.md
git commit -m "docs: update UIKit command catalog"
```

---

## Self-Review

- Spec coverage: covers all 5 commands plus error strategy, stale locator consistency, scroll primitive extraction, alert spike, registration, docs, and verification.
- No unresolved implementation choice remains except the alert spike outcome, which is intentionally represented as a test-gated branch.
- Task order follows agreed risk order: keyboard, navigation, wait, scroll primitives, scrollToElement, alert.
- Core remains UIKit-free; UIKit code stays in `iOSExploreUIKit`.
- Verification uses `generic/platform=iOS Simulator` build and avoids hard-coding a simulator name.
