# navigationBar Reachability Implementation Plan

> **状态：历史执行包（已实施完成，勿按 checkbox 继续执行）。** 本计划对应的 navigationBar 可达性已落地（`UINavigationBarInspector` + `UINavigationBarButtonExecutor` + `ui.navigation.tapBarButton`，`ui.viewTargets`/`ui.topViewHierarchy` 响应追加 `navigationBar` 区块）。checkbox 仅保留为历史执行轨迹；当前事实以 [../agent-mcp-exploration/README.md](../agent-mcp-exploration/README.md) 为准。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Agent 能在观察结果里看到 navigationBar / UIBarButtonItem，并通过 `ui.navigation.tapBarButton` 安全触发导航栏按钮。

**Architecture:** 不把导航栏按钮伪装成普通 `UIView` path，也不放宽坐标点击。新增一个导航栏检查器，把 `UIBarButtonItem` 转成普通 JSON 摘要；观察命令返回 `navigationBar` 区块；动作命令按 `placement + index` 找当前按钮，并用可选 `title` / `accessibilityIdentifier` 防止页面变化后误触发。

**Tech Stack:** Swift, Swift Testing, UIKit, iOSExploreServer typed `CommandInput`, `ExploreResult`, `UIKitCommandError`, Example App.

---

## File Structure

- Create `Sources/iOSExploreUIKit/Support/Navigation/UINavigationBarInspector.swift`
  - 只负责读取当前导航栏状态，把 `UINavigationItem` / `UIBarButtonItem` 转成摘要 JSON。
  - 只在 `#if canImport(UIKit)` 下编译，UIKit 访问限制在 `@MainActor`。

- Create `Sources/iOSExploreUIKit/Commands/Navigation/UINavigationBarButtonModels.swift`
  - 定义 `NavigationBarPlacement` 和 `UINavigationBarButtonInput`。
  - 字段：`placement`、`index`、`title`、`accessibilityIdentifier`、`waitAfterMs`。

- Create `Sources/iOSExploreUIKit/Commands/Navigation/UINavigationBarButtonCommand.swift`
  - 注册 action `ui.navigation.tapBarButton`。
  - 负责日志、切主线程、调用 executor、catch `UIKitCommandError`。

- Create `Sources/iOSExploreUIKit/Support/Action/UINavigationBarButtonExecutor.swift`
  - 执行按钮查找、匹配、触发、等待和响应构造。

- Modify `Sources/iOSExploreServer/Models.swift`
  - 给 `ExploreError` 增加导航栏按钮专用错误码。

- Modify `Sources/iOSExploreUIKit/UIKitCommandError.swift`
  - 增加导航栏按钮错误工厂。

- Modify `Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsCollector.swift`
  - 在成功响应中追加 `navigationBar` 字段。

- Modify `Sources/iOSExploreUIKit/Commands/TopViewHierarchy/UIViewHierarchyCollector.swift`
  - 在成功响应中追加 `navigationBar` 字段。

- Modify `Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift`
  - 注册 `NavigationBarButtonCommand()`。
  - 注册数量从 12 改为 13。

- Modify `Examples/SPMExample/SPMExample/ViewController.swift`
  - 给“控件测试”按钮补稳定 `accessibilityIdentifier`。

- Modify tests under `Tests/iOSExploreServerTests/`
  - 补 input schema、registrar/help、inspector、executor、观察命令响应测试。

- Modify docs
  - `README.md`
  - `AGENTS.md`
  - `docs/runbooks/build-and-test.md`
  - `docs/superpowers/agent-mcp-exploration/README.md`
  - `docs/superpowers/agent-mcp-exploration/agent-usage-protocol.md`

---

### Task 1: Add Models And Error Codes

**Files:**
- Modify: `Sources/iOSExploreServer/Models.swift`
- Modify: `Sources/iOSExploreUIKit/UIKitCommandError.swift`
- Create: `Sources/iOSExploreUIKit/Commands/Navigation/UINavigationBarButtonModels.swift`
- Test: `Tests/iOSExploreServerTests/UIKitCommandInputSchemaTests.swift`

- [ ] **Step 1: Add failing schema tests**

Add tests that expect `UINavigationBarButtonInput.inputSchema` to contain:

```swift
#expect(schema.required.contains("placement"))
#expect(schema.required.contains("index"))
#expect(schema.properties.keys.contains("title"))
#expect(schema.properties.keys.contains("accessibilityIdentifier"))
#expect(schema.properties.keys.contains("waitAfterMs"))
```

Also add parsing tests:

```swift
let input = try UINavigationBarButtonInput.parse(decoding: &decoder)
#expect(input.placement == .right)
#expect(input.index == 0)
#expect(input.title == "控件测试")
#expect(input.accessibilityIdentifier == "example.controlTest")
#expect(input.waitAfterMs == 300)
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter UIKitCommandInputSchemaTests
```

Expected: fails because `UINavigationBarButtonInput` does not exist.

- [ ] **Step 3: Add `ExploreError` cases**

In `Sources/iOSExploreServer/Models.swift`, append these enum cases near existing navigation and alert errors:

```swift
/// 当前页面没有可操作的导航栏。
case navigationBarUnavailable = "navigation_bar_unavailable"

/// 指定的导航栏按钮不存在。
case navigationBarItemNotFound = "navigation_bar_item_not_found"

/// 导航栏按钮与调用方观察到的标题或 identifier 不一致。
case navigationBarItemMismatch = "navigation_bar_item_mismatch"

/// 导航栏按钮存在但当前不可用。
case navigationBarItemDisabled = "navigation_bar_item_disabled"

/// 导航栏按钮存在但没有可安全触发的 target-action 或 customView 控件动作。
case navigationBarItemUnsupported = "navigation_bar_item_unsupported"
```

- [ ] **Step 4: Add `UIKitCommandError` factories**

In `Sources/iOSExploreUIKit/UIKitCommandError.swift`, add factories:

```swift
static func navigationBarUnavailable(action: String, top: String) -> UIKitCommandError {
    UIKitCommandError(code: .navigationBarUnavailable,
                      message: "navigation bar unavailable",
                      logMessage: "ui navigation bar unavailable action=\(action) top=\(top)")
}

static func navigationBarItemNotFound(action: String, selector: String) -> UIKitCommandError {
    UIKitCommandError(code: .navigationBarItemNotFound,
                      message: "navigation bar item not found",
                      logMessage: "ui navigation bar item not found action=\(action) selector=\(selector)")
}

static func navigationBarItemMismatch(action: String, selector: String) -> UIKitCommandError {
    UIKitCommandError(code: .navigationBarItemMismatch,
                      message: "navigation bar item changed since observation",
                      logMessage: "ui navigation bar item mismatch action=\(action) selector=\(selector)")
}

static func navigationBarItemDisabled(action: String, selector: String) -> UIKitCommandError {
    UIKitCommandError(code: .navigationBarItemDisabled,
                      message: "navigation bar item disabled",
                      logMessage: "ui navigation bar item disabled action=\(action) selector=\(selector)")
}

static func navigationBarItemUnsupported(action: String, selector: String) -> UIKitCommandError {
    UIKitCommandError(code: .navigationBarItemUnsupported,
                      message: "navigation bar item has no supported action",
                      logMessage: "ui navigation bar item unsupported action=\(action) selector=\(selector)")
}
```

- [ ] **Step 5: Create input model**

Create `Sources/iOSExploreUIKit/Commands/Navigation/UINavigationBarButtonModels.swift`:

```swift
import Foundation
import iOSExploreServer

/// 导航栏按钮所在位置。
public enum NavigationBarPlacement: String, Sendable, Equatable, CaseIterable {
    /// 左侧按钮列表。
    case left
    /// 右侧按钮列表。
    case right
}

/// `ui.navigation.tapBarButton` 的命令参数。
public struct UINavigationBarButtonInput: CommandInput, Sendable, Equatable {
    private enum Fields {
        static let placement = CommandFields.enumValue(
            "placement",
            type: NavigationBarPlacement.self,
            description: "导航栏按钮位置: left / right"
        )
        static let index = CommandFields.int(
            "index",
            range: 0...20,
            description: "按钮在当前侧的下标, 从 0 开始"
        )
        static let title = CommandFields.optionalString(
            "title",
            description: "观察时看到的按钮标题; 传入时执行前必须一致"
        )
        static let accessibilityIdentifier = CommandFields.optionalString(
            "accessibilityIdentifier",
            description: "观察时看到的按钮 accessibilityIdentifier; 传入时执行前必须一致"
        )
        static let waitAfterMs = CommandFields.int(
            "waitAfterMs",
            range: 0...3000,
            default: 300,
            description: "执行后等待毫秒数, 范围 0...3000, 默认 300"
        )
        static let all: [AnyCommandField] = [
            placement.erased,
            index.erased,
            title.erased,
            accessibilityIdentifier.erased,
            waitAfterMs.erased,
        ]
    }

    /// `ui.navigation.tapBarButton` 暴露给 help 和工具客户端的输入 schema。
    public static let inputSchema = CommandInputSchema(fields: Fields.all)

    /// 按钮位置。
    public let placement: NavigationBarPlacement
    /// 当前侧按钮下标。
    public let index: Int
    /// 可选标题校验。
    public let title: String?
    /// 可选 identifier 校验。
    public let accessibilityIdentifier: String?
    /// 执行后等待毫秒数。
    public let waitAfterMs: Int

    /// 创建导航栏按钮输入。
    public init(placement: NavigationBarPlacement,
                index: Int,
                title: String? = nil,
                accessibilityIdentifier: String? = nil,
                waitAfterMs: Int = 300) {
        self.placement = placement
        self.index = index
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
        self.waitAfterMs = waitAfterMs
    }

    /// 按 typed schema 解析输入。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UINavigationBarButtonInput {
        UINavigationBarButtonInput(
            placement: try decoder.read(Fields.placement),
            index: try decoder.read(Fields.index),
            title: try decoder.read(Fields.title),
            accessibilityIdentifier: try decoder.read(Fields.accessibilityIdentifier),
            waitAfterMs: try decoder.read(Fields.waitAfterMs)
        )
    }

    /// 日志用选择器摘要，不包含大块 payload。
    var selectorSummary: String {
        "placement=\(placement.rawValue) index=\(index) titleHash=\(title.map(UIKitTargetFingerprint.stableHash).map(String.init) ?? "nil") identifierHash=\(accessibilityIdentifier.map(UIKitTargetFingerprint.stableHash).map(String.init) ?? "nil")"
    }
}
```

If `UIKitTargetFingerprint` is not accessible from this file on macOS, replace `selectorSummary` with length-only summaries.

- [ ] **Step 6: Run schema tests**

Run:

```bash
swift test --filter UIKitCommandInputSchemaTests
```

Expected: schema/model tests pass.

---

### Task 2: Add Navigation Bar Inspector

**Files:**
- Create: `Sources/iOSExploreUIKit/Support/Navigation/UINavigationBarInspector.swift`
- Test: add iOS-only tests under `Tests/iOSExploreServerTests/`

- [ ] **Step 1: Write failing inspector tests**

Create tests that build a `UINavigationController` with a root controller:

```swift
let vc = UIViewController()
vc.title = "首页"
let item = UIBarButtonItem(title: "控件测试", style: .plain, target: nil, action: nil)
item.accessibilityIdentifier = "example.controlTest"
vc.navigationItem.rightBarButtonItem = item
let nav = UINavigationController(rootViewController: vc)
```

Assert summary:

```swift
let summary = UINavigationBarInspector.summarize(topViewController: vc)
#expect(summary.available == true)
#expect(summary.title == "首页")
#expect(summary.rightItems.count == 1)
#expect(summary.rightItems[0].placement == .right)
#expect(summary.rightItems[0].index == 0)
#expect(summary.rightItems[0].title == "控件测试")
#expect(summary.rightItems[0].accessibilityIdentifier == "example.controlTest")
```

- [ ] **Step 2: Run test to verify it fails**

Run iOS framework tests for the new test file, or full framework test if filtering is awkward:

```bash
xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Expected: fails because `UINavigationBarInspector` does not exist.

- [ ] **Step 3: Implement inspector**

Create `Sources/iOSExploreUIKit/Support/Navigation/UINavigationBarInspector.swift`:

```swift
#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// 当前页面导航栏摘要读取器。
@MainActor
enum UINavigationBarInspector {
    struct ItemSummary: Sendable, Equatable {
        let placement: NavigationBarPlacement
        let index: Int
        let title: String?
        let accessibilityIdentifier: String?
        let isEnabled: Bool

        func toJSON() -> JSON {
            [
                "placement": .string(placement.rawValue),
                "index": .double(Double(index)),
                "title": title.map(JSONValue.string) ?? .null,
                "accessibilityIdentifier": accessibilityIdentifier.map(JSONValue.string) ?? .null,
                "isEnabled": .bool(isEnabled),
                "availableActions": .array([.string(NavigationBarButtonCommand.actionName)]),
            ]
        }
    }

    struct Summary: Sendable, Equatable {
        let available: Bool
        let title: String?
        let topViewController: String
        let leftItems: [ItemSummary]
        let rightItems: [ItemSummary]
        let backAvailable: Bool

        func toJSON() -> JSON {
            [
                "available": .bool(available),
                "title": title.map(JSONValue.string) ?? .null,
                "topViewController": .string(topViewController),
                "leftItems": .array(leftItems.map { .object($0.toJSON()) }),
                "rightItems": .array(rightItems.map { .object($0.toJSON()) }),
                "backAvailable": .bool(backAvailable),
            ]
        }
    }

    static func summarize(topViewController: UIViewController) -> Summary {
        let topName = String(describing: type(of: topViewController))
        guard let navigation = topViewController.navigationController else {
            return Summary(available: false,
                           title: topViewController.title,
                           topViewController: topName,
                           leftItems: [],
                           rightItems: [],
                           backAvailable: false)
        }

        let item = topViewController.navigationItem
        let left = items(from: item.leftBarButtonItems ?? single(item.leftBarButtonItem),
                         placement: .left)
        let right = items(from: item.rightBarButtonItems ?? single(item.rightBarButtonItem),
                          placement: .right)
        return Summary(available: true,
                       title: item.title ?? topViewController.title ?? navigation.navigationBar.topItem?.title,
                       topViewController: topName,
                       leftItems: left,
                       rightItems: right,
                       backAvailable: navigation.viewControllers.count > 1 || item.hidesBackButton == false)
    }

    static func item(for input: UINavigationBarButtonInput,
                     topViewController: UIViewController) throws -> UIBarButtonItem {
        guard topViewController.navigationController != nil else {
            throw UIKitCommandError.navigationBarUnavailable(
                action: NavigationBarButtonCommand.actionName,
                top: String(describing: type(of: topViewController))
            )
        }

        let items = barButtonItems(placement: input.placement, from: topViewController.navigationItem)
        guard input.index < items.count else {
            throw UIKitCommandError.navigationBarItemNotFound(
                action: NavigationBarButtonCommand.actionName,
                selector: input.selectorSummary
            )
        }
        let item = items[input.index]
        if let expected = input.title, item.title != expected {
            throw UIKitCommandError.navigationBarItemMismatch(
                action: NavigationBarButtonCommand.actionName,
                selector: input.selectorSummary
            )
        }
        if let expected = input.accessibilityIdentifier, item.accessibilityIdentifier != expected {
            throw UIKitCommandError.navigationBarItemMismatch(
                action: NavigationBarButtonCommand.actionName,
                selector: input.selectorSummary
            )
        }
        return item
    }

    private static func items(from items: [UIBarButtonItem],
                              placement: NavigationBarPlacement) -> [ItemSummary] {
        items.enumerated().map { index, item in
            ItemSummary(placement: placement,
                        index: index,
                        title: item.title,
                        accessibilityIdentifier: item.accessibilityIdentifier,
                        isEnabled: item.isEnabled)
        }
    }

    private static func barButtonItems(placement: NavigationBarPlacement,
                                       from navigationItem: UINavigationItem) -> [UIBarButtonItem] {
        switch placement {
        case .left:
            return navigationItem.leftBarButtonItems ?? single(navigationItem.leftBarButtonItem)
        case .right:
            return navigationItem.rightBarButtonItems ?? single(navigationItem.rightBarButtonItem)
        }
    }

    private static func single(_ item: UIBarButtonItem?) -> [UIBarButtonItem] {
        item.map { [$0] } ?? []
    }
}
#endif
```

If `backAvailable` semantics are noisy in tests, keep it conservative: only `navigation.viewControllers.count > 1`.

- [ ] **Step 4: Run inspector tests**

Run the iOS framework test command again.

Expected: inspector tests pass.

---

### Task 3: Add `ui.navigation.tapBarButton` Executor And Command

**Files:**
- Create: `Sources/iOSExploreUIKit/Support/Action/UINavigationBarButtonExecutor.swift`
- Create: `Sources/iOSExploreUIKit/Commands/Navigation/UINavigationBarButtonCommand.swift`
- Test: add iOS-only executor tests

- [ ] **Step 1: Write failing executor tests**

Add tests for:

```swift
final class Receiver: NSObject {
    var called = false
    @objc func fire() { called = true }
}
```

Create a `UIBarButtonItem(title:target:action:)`, execute input, assert:

```swift
#expect(receiver.called == true)
```

Also test:

- disabled item returns `navigation_bar_item_disabled`;
- title mismatch returns `navigation_bar_item_mismatch`;
- customView `UIButton` receives `.touchUpInside`;
- item without `target/action` and without `UIControl` customView returns `navigation_bar_item_unsupported`.

- [ ] **Step 2: Run tests to verify failure**

Run iOS framework tests.

Expected: fail because executor/command do not exist.

- [ ] **Step 3: Implement executor**

Create `Sources/iOSExploreUIKit/Support/Action/UINavigationBarButtonExecutor.swift`:

```swift
#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.navigation.tapBarButton` 的执行核心。
@MainActor
enum UINavigationBarButtonExecutor {
    static func execute(input: UINavigationBarButtonInput,
                        context: UIKitContextProvider.Context) throws -> JSON {
        let topBefore = describe(context.topViewController)
        let item = try UINavigationBarInspector.item(for: input, topViewController: context.topViewController)
        guard item.isEnabled else {
            throw UIKitCommandError.navigationBarItemDisabled(
                action: NavigationBarButtonCommand.actionName,
                selector: input.selectorSummary
            )
        }

        let performed = try trigger(item: item, selector: input.selectorSummary)
        guard performed else {
            throw UIKitCommandError.navigationBarItemUnsupported(
                action: NavigationBarButtonCommand.actionName,
                selector: input.selectorSummary
            )
        }

        settle(milliseconds: input.waitAfterMs)
        let topAfter = describe(context.topViewController.navigationController?.topViewController ?? context.topViewController)
        UIKitCommandLogging.info("command", "ui navigation bar button complete performed=true placement=\(input.placement.rawValue) index=\(input.index)")
        return [
            "performed": .bool(true),
            "placement": .string(input.placement.rawValue),
            "index": .double(Double(input.index)),
            "title": item.title.map(JSONValue.string) ?? .null,
            "accessibilityIdentifier": item.accessibilityIdentifier.map(JSONValue.string) ?? .null,
            "topBefore": .string(topBefore),
            "topAfter": .string(topAfter),
        ]
    }

    private static func trigger(item: UIBarButtonItem, selector: String) throws -> Bool {
        if let control = item.customView as? UIControl {
            control.sendActions(for: .touchUpInside)
            return true
        }
        guard let action = item.action else { return false }
        return UIApplication.shared.sendAction(action, to: item.target, from: item, for: nil)
    }

    private static func describe(_ controller: UIViewController) -> String {
        String(describing: type(of: controller))
    }

    private static func settle(milliseconds: Int) {
        guard milliseconds > 0 else { return }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: Double(milliseconds) / 1000.0))
    }
}
#endif
```

If test shows `sendAction` with `target == nil` needs responder-chain handling, keep it supported through `UIApplication.shared.sendAction`; do not add coordinate fallback.

- [ ] **Step 4: Implement command adapter**

Create `Sources/iOSExploreUIKit/Commands/Navigation/UINavigationBarButtonCommand.swift`:

```swift
#if canImport(UIKit)
import Foundation
import iOSExploreServer

/// 触发 navigationBar 上的 UIBarButtonItem。
struct NavigationBarButtonCommand: Command {
    typealias Input = UINavigationBarButtonInput

    static let actionName = "ui.navigation.tapBarButton"
    let action = NavigationBarButtonCommand.actionName
    let description = "触发导航栏按钮: 按 left/right + index 定位, 可用 title/identifier 防误点"

    func handle(_ input: UINavigationBarButtonInput) async -> ExploreResult {
        UIKitCommandLogging.info("command", "command \(action) start \(input.selectorSummary) waitAfterMs=\(input.waitAfterMs)")
        do {
            let data = try await MainActor.run {
                let context = try UIKitContextProvider.currentContext(action: NavigationBarButtonCommand.actionName)
                return try UINavigationBarButtonExecutor.execute(input: input, context: context)
            }
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        } catch {
            let wrapped = UIKitCommandError.hierarchyUnavailable(action: NavigationBarButtonCommand.actionName, reason: "\(error)")
            UIKitCommandLogging.error("command", wrapped.failure.logMessage)
            return wrapped.result
        }
    }
}
#endif
```

- [ ] **Step 5: Run executor/command tests**

Run iOS framework tests.

Expected: new executor tests pass.

---

### Task 4: Add Navigation Bar Summary To Observation Commands

**Files:**
- Modify: `Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsCollector.swift`
- Modify: `Sources/iOSExploreUIKit/Commands/TopViewHierarchy/UIViewHierarchyCollector.swift`
- Test: observation tests under `Tests/iOSExploreServerTests/`

- [ ] **Step 1: Write failing observation tests**

For `UIViewTargetsCollector.collect(query:context:)`, assert returned data contains:

```swift
let nav = data["navigationBar"]?.objectValue
#expect(nav?["available"]?.boolValue == true)
#expect(nav?["rightItems"]?.arrayValue?.count == 1)
```

Repeat for `UIViewHierarchyCollector.collectTopViewHierarchy(query:context:)`.

- [ ] **Step 2: Run tests to verify failure**

Run iOS framework tests.

Expected: fail because response does not contain `navigationBar`.

- [ ] **Step 3: Append navigationBar to `ui.viewTargets` response**

In `UIViewTargetsCollector.collect(query:context:)`, change `let data: JSON = [` to `var data: JSON = [` and append:

```swift
data["navigationBar"] = .object(
    UINavigationBarInspector.summarize(topViewController: context.topViewController).toJSON()
)
```

Keep existing `targets`, `snapshotID`, `targetCount` unchanged.

- [ ] **Step 4: Append navigationBar to `ui.topViewHierarchy` response**

In `UIViewHierarchyCollector.collectTopViewHierarchy(query:context:)`, after `var data: JSON = [...]`, add:

```swift
data["navigationBar"] = .object(
    UINavigationBarInspector.summarize(topViewController: context.topViewController).toJSON()
)
```

- [ ] **Step 5: Run observation tests**

Run iOS framework tests.

Expected: observation tests pass.

---

### Task 5: Register Command And Update Example App

**Files:**
- Modify: `Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift`
- Modify: `Examples/SPMExample/SPMExample/ViewController.swift`
- Test: `Tests/iOSExploreServerTests/UIKitCommandRegistrationTests.swift`
- Test: `Tests/iOSExploreServerTests/IntegrationTests.swift`

- [ ] **Step 1: Write failing registration tests**

Update registration tests:

```swift
#expect(result.commandActions.contains("ui.navigation.tapBarButton"))
```

Update any HTTP help count assertion from 12 UIKit actions to 13.

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter UIKitCommandRegistrationTests
```

Expected on macOS may skip UIKit sections; iOS framework test should fail until registration is added.

- [ ] **Step 3: Register new command**

In `UIKitCommandRegistrar.swift`:

```swift
register(NavigationBarButtonCommand(), logCategory: .extensionCommand(category: "command"))
```

Place it next to `NavigationBackCommand()`.

Update comments:

```swift
// ... ui.navigation.back、ui.navigation.tapBarButton、ui.wait ...
```

Update log count:

```swift
UIKitCommandLogging.info("uikit.registrar", "registration completed count=13")
```

- [ ] **Step 4: Add Example App identifier**

In `Examples/SPMExample/SPMExample/ViewController.swift`, replace direct assignment with a local item:

```swift
let controlTestItem = UIBarButtonItem(
    title: "控件测试",
    style: .plain,
    target: self,
    action: #selector(openControlTest)
)
controlTestItem.accessibilityIdentifier = "example.controlTest"
navigationItem.rightBarButtonItem = controlTestItem
```

- [ ] **Step 5: Run registration tests**

Run iOS framework tests or the relevant registration test.

Expected: registration/help tests pass.

---

### Task 6: Update Docs And Agent Protocol

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `docs/runbooks/build-and-test.md`
- Modify: `docs/superpowers/agent-mcp-exploration/README.md`
- Modify: `docs/superpowers/agent-mcp-exploration/agent-usage-protocol.md`

- [ ] **Step 1: Update counts**

Expected counts after implementation:

```text
core 4 + UIKit 13 = 17 built-in action
Example App extra greet/device => help shows 19 action
```

Update old references:

- `16 个内置 action` -> `17 个内置 action`
- `UIKit 12` -> `UIKit 13`
- `help 实测共 18 个 action` -> `help 实测共 19 个 action`
- registrar comment/log text from 12 -> 13.

- [ ] **Step 2: Update protocol wording**

In `agent-usage-protocol.md`, replace the navigationBar current limitation with:

```text
导航栏按钮不走 ui.tap，也不要坐标硬点。
观察结果的 navigationBar 区块会列出 leftItems / rightItems。
触发时使用 ui.navigation.tapBarButton，并带上 placement、index，以及观察到的 title 或 accessibilityIdentifier。
动作成功后仍要 wait 或 observe again。
```

Keep a note:

```text
如果旧版本没有 navigationBar 字段，Agent 应记录为工具能力缺口，不要坐标硬点。
```

- [ ] **Step 3: Update entrance map**

In `docs/superpowers/agent-mcp-exploration/README.md`, mark:

```text
实现 navigationBar 可达性 | 已完成第一轮 | ...
```

Only do this after tests and Example App validation pass. Before validation, keep it as in progress.

---

### Task 7: Verification

**Files:**
- No new implementation files unless tests expose a bug.

- [ ] **Step 1: Run SPM tests**

Run:

```bash
swift test
```

Expected:

```text
Test run ... passed
```

Record the exact test count and tail output.

- [ ] **Step 2: Run iOS framework tests**

Run:

```bash
xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Expected:

```text
** TEST SUCCEEDED **
```

Record exact test count and tail output.

If the simulator name is unavailable, run:

```bash
xcrun simctl list devices available
```

Pick an available iPhone simulator and record the substitution.

- [ ] **Step 3: Run Example App closed loop**

Run the Example App with server started, then verify:

```text
ui.viewTargets
→ navigationBar.rightItems includes title "控件测试" and identifier "example.controlTest"
→ ui.navigation.tapBarButton placement=right index=0 title="控件测试" accessibilityIdentifier="example.controlTest"
→ ui.wait or ui.viewTargets confirms ControlTestViewController
```

Record:

- request payloads;
- response code and important data fields;
- final page evidence.

- [ ] **Step 4: Final status check**

Run:

```bash
git diff --check
git status --short
```

Expected:

- no whitespace errors;
- changed files match the planned scope.

---

## Self-Review Checklist

- Spec coverage:
  - Observation returns navigationBar: Task 4.
  - Dedicated action: Task 3 and Task 5.
  - No private UIKit view dependency: Task 2 and Task 3.
  - Error classification: Task 1 and Task 3.
  - Example App validation: Task 5 and Task 7.

- Scope:
  - Does not modify `Sources/iOSExploreServer/` except `ExploreError` enum.
  - Does not change HTTP protocol.
  - Does not change `ui.tap` behavior.
  - Does not introduce platform/tester features.

- Handoff:
  - Claude Code should execute this plan task-by-task.
  - After execution, current session should review diffs and real command output before marking the entrance map as completed.
