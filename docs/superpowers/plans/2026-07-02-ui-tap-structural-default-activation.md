# UI Tap Structural Default Activation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `ui.tap` 从坐标 / hit-test / ancestor fallback 的伪点击，重构为只作用于 `ui.viewTargets` 签发 canonical target 的结构化默认激活能力。

**Architecture:** 先收敛公共协议和 snapshot 语义，再收敛 `ui.viewTargets` 的 canonical target 集合，最后替换 capability 与 executor。`viewSnapshotID` 只由 `ui.viewTargets` 签发，`ui.tap` 与 `ui.control.sendAction` 统一使用同一 freshness 校验；`ui.screenshot` 保留为视觉证据，不再签发结构快照。

**Tech Stack:** Swift Package Manager, Swift 6.2 core tests, UIKit framework target with Swift 5.0 build settings, XCTest/Swift Testing, CodeGraph.

---

## Source Of Truth

Implementation must follow these documents in this order:

1. `AGENTS.md`
2. `docs/superpowers/specs/iOSExploreServer-ui-tap-design-rationale.md`
3. `docs/superpowers/specs/iOSExploreServer-ui-tap-final-refactor-plan.md`
4. This plan: `docs/superpowers/plans/2026-07-02-ui-tap-structural-default-activation.md`

If this plan conflicts with the final refactor plan, follow `iOSExploreServer-ui-tap-final-refactor-plan.md`.

Do not commit. The final refactor plan explicitly says this task should not submit a git commit.

---

## File Map

### Input Models And Commands

- Modify: `Sources/iOSExploreUIKit/Commands/Tap/UITapModels.swift`
  - Remove `x`, `y`, `coordinateSpace`, `UITapCoordinateSpace`, and window-point target parsing.
  - Rename request field `snapshotID` to `viewSnapshotID`.
  - Require `viewSnapshotID` for both `path` and `accessibilityIdentifier`.

- Modify: `Sources/iOSExploreUIKit/Commands/Tap/UITapCommand.swift`
  - Update command description and logging to describe default activation.

- Modify: `Sources/iOSExploreUIKit/Commands/ControlAction/UIControlSendActionModels.swift`
  - Rename `snapshotID` to `viewSnapshotID`.
  - Require `viewSnapshotID` for both `path` and `accessibilityIdentifier`.

- Modify: `Sources/iOSExploreUIKit/Commands/ControlAction/UIControlSendActionCommand.swift`
  - Pass `viewSnapshotID` into the action plan.

- Modify: `Sources/iOSExploreUIKit/Commands/Wait/UIWaitModels.swift`
  - Rename `snapshotID` to `viewSnapshotID` for `snapshotChanged`.

- Modify: `Sources/iOSExploreUIKit/Commands/Wait/UIWaitCommand.swift`
  - Update help/description if it mentions `snapshotID`.

### Locator, Action Plan, Capability, Executor

- Modify: `Sources/iOSExploreUIKit/Support/Locator/UIKitLocator.swift`
  - Remove `.windowPoint`.
  - Remove coordinate parsing.

- Modify: `Sources/iOSExploreUIKit/Support/Action/UIKitActionPlan.swift`
  - Rename `snapshotID` to `viewSnapshotID`.
  - Remove window-point tap support.

- Create: `Sources/iOSExploreUIKit/Support/Action/UIKitDefaultActivationResolver.swift`
  - Single source of truth for default activation route.
  - V1 routes: `UIButton`, `UISwitch`, `UITextField` / `UISearchTextField` / `UITextView`.
  - Unknown custom `UIControl` does not get `tap`.

- Modify: `Sources/iOSExploreUIKit/Support/Action/UIKitActionCapabilityResolver.swift`
  - Use `UIKitDefaultActivationResolver` for `.tap`.
  - Keep exact `control.*`, `input`, and `scroll` capabilities honest.
  - Remove `tap` from `UISlider` and `UISegmentedControl`.

- Modify: `Sources/iOSExploreUIKit/Support/Action/UIKitActionExecutor.swift`
  - Remove coordinate tap.
  - Remove hit-test tap and nearest ancestor control fallback.
  - Add unified `validateViewSnapshot`.
  - Execute default activation routes.
  - Use the same freshness path for tap and control sendAction.

### Snapshot, Fingerprint, Target Collection

- Modify: `Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsModels.swift`
  - Add or normalize `semanticText`, `semanticTextSource` if not already present.
  - Keep `availableActions` aligned with executor routes.

- Modify: `Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsCollector.swift`
  - Return only canonical interaction targets.
  - Build fingerprints from final returned targets after filtering and `maxTargets`.

- Create: `Sources/iOSExploreUIKit/Support/Snapshot/UIKitTargetSemanticDigest.swift`
  - Stable semantic hash for target fingerprints.

- Modify: `Sources/iOSExploreUIKit/Support/Snapshot/UIKitFingerprintCollector.swift`
  - Include `semanticDigest`.
  - Stop producing fingerprints for non-returned targets.

- Modify: `Sources/iOSExploreUIKit/Support/Snapshot/UIKitSnapshotStore.swift`
  - Rename public semantics to `viewSnapshotID`.
  - Expose target membership check or return stored target by path.

- Modify: `Sources/iOSExploreUIKit/Support/Snapshot/UIKitSnapshotResponse.swift`
  - Rename response helper fields for `ui.viewTargets` only.

### Screenshot, Wait, Errors, Docs

- Modify: `Sources/iOSExploreUIKit/Commands/Screenshot/UIScreenshotCollector.swift`
  - Stop calling `UIKitSnapshotStore.shared.insert`.
  - Remove `snapshotID` and `snapshotUnavailableReason` from screenshot response.

- Modify: `Sources/iOSExploreUIKit/Support/Wait/UIWaitExecutor.swift`
  - Use `input.viewSnapshotID`.
  - Continue using `UIKitSnapshotStore.signingQuery(for:)` for snapshots signed by `ui.viewTargets`.

- Modify: `Sources/iOSExploreUIKit/UIKitCommandError.swift`
  - Update `staleLocator` message from `ui.screenshot` to `ui.viewTargets`.
  - Add `activationFailed` only if no existing error factory cleanly fits `becomeFirstResponder()` failure.

- Modify docs:
  - `README.md`
  - `docs/architecture/index.md`
  - `docs/uikit/README.md`
  - `docs/uikit/reading-guide.md`
  - `docs/uikit/uikit-file-reference.md`
  - `docs/superpowers/agent-mcp-exploration/README.md`
  - `docs/superpowers/agent-mcp-exploration/agent-usage-protocol.md`

### Tests

- Modify or add tests in:
  - `Tests/iOSExploreServerTests/UIKitCommandInputSchemaTests.swift`
  - `Tests/iOSExploreServerTests/UIKitTapTests.swift`
  - `Tests/iOSExploreServerTests/UIKitControlActionTests.swift`
  - `Tests/iOSExploreServerTests/UIKitActionCapabilityTests.swift`
  - `Tests/iOSExploreServerTests/UIKitActionExecutorTests.swift`
  - `Tests/iOSExploreServerTests/UIKitSnapshotTests.swift`
  - `Tests/iOSExploreServerTests/UIKitViewTargetsTests.swift`
  - `Tests/iOSExploreServerTests/UIScreenshotTests.swift`
  - `Tests/iOSExploreServerTests/UIWaitInputTests.swift`
  - `Tests/iOSExploreServerTests/UIWaitTests.swift`

---

## Task 0: Confirm Current Code And Write A Short Local Audit Note

**Files:**
- Read: `docs/superpowers/specs/iOSExploreServer-ui-tap-final-refactor-plan.md`
- Read via CodeGraph: symbols listed below
- Do not create a permanent audit file unless useful for yourself.

- [ ] **Step 0.1: Use CodeGraph before grep**

Run:

```bash
codegraph explore "UITapInput UIControlSendActionInput UIWaitInput UIKitActionExecutor UIKitActionCapabilityResolver UIViewTargetsCollector UIKitFingerprintCollector UIScreenshotCollector UIKitSnapshotStore UIKitCommandError"
```

Expected:

```text
Output includes current source for the input models, executor, capability resolver, view target collector, fingerprint collector, screenshot collector, snapshot store, and command errors.
```

- [ ] **Step 0.2: Confirm the six known protocol gaps**

Confirm these exact current-state facts before editing:

```text
1. ui.tap still accepts x/y/coordinateSpace.
2. ui.tap uses hit-test / windowPoint / nearest UIControl fallback.
3. UISwitch/UISlider/UISegmentedControl currently declare tap.
4. ui.viewTargets currently includes non-canonical views such as gesture or identifier-only views.
5. Fingerprints can be signed for more paths than maxTargets returns.
6. ui.screenshot currently signs and returns snapshotID.
```

Expected:

```text
All six facts are confirmed from current source. If any fact is already fixed, skip only the corresponding implementation step and keep the tests.
```

---

## Task 1: Lock New Public Input Contracts With Failing Tests

**Files:**
- Modify: `Tests/iOSExploreServerTests/UIKitCommandInputSchemaTests.swift`
- Modify: `Tests/iOSExploreServerTests/UIKitTapTests.swift`
- Modify: `Tests/iOSExploreServerTests/UIKitControlActionTests.swift`
- Modify: `Tests/iOSExploreServerTests/UIWaitInputTests.swift`

- [ ] **Step 1.1: Add failing tests for `ui.tap` input**

Add tests that assert:

```swift
// Expected behavior after implementation:
// - path + viewSnapshotID parses
// - accessibilityIdentifier + viewSnapshotID parses
// - missing viewSnapshotID fails
// - x/y/coordinateSpace fail as unknown or invalid fields
// - path + accessibilityIdentifier together fail
```

Use the existing test helper style in `UIKitCommandInputSchemaTests.swift` and `UIKitTapTests.swift`. Name tests with these exact intents:

```swift
tapInputRequiresViewSnapshotIDForPath
tapInputRequiresViewSnapshotIDForIdentifier
tapInputRejectsCoordinates
tapInputRejectsCoordinateSpace
tapInputRejectsMixedPathAndIdentifier
```

- [ ] **Step 1.2: Add failing tests for `ui.control.sendAction` input**

Add tests that assert:

```swift
sendActionInputParsesPathWithViewSnapshotIDAndEvent
sendActionInputParsesIdentifierWithViewSnapshotIDAndEvent
sendActionInputRejectsMissingViewSnapshotID
sendActionInputRejectsOldSnapshotID
```

The expected valid JSON shape is:

```json
{
  "path": "root/0",
  "viewSnapshotID": "view_snapshot_test",
  "event": "touchUpInside"
}
```

and:

```json
{
  "accessibilityIdentifier": "checkout.submit",
  "viewSnapshotID": "view_snapshot_test",
  "event": "touchDown"
}
```

- [ ] **Step 1.3: Add failing tests for `ui.wait snapshotChanged` input**

Add tests in `UIWaitInputTests.swift`:

```swift
waitSnapshotChangedParsesViewSnapshotID
waitSnapshotChangedRejectsOldSnapshotID
```

Expected valid JSON shape:

```json
{
  "mode": "snapshotChanged",
  "viewSnapshotID": "view_snapshot_test"
}
```

- [ ] **Step 1.4: Run the targeted tests and verify they fail**

Run:

```bash
swift test --filter UIKitCommandInputSchemaTests
swift test --filter UIKitTapTests
swift test --filter UIKitControlActionTests
swift test --filter UIWaitInputTests
```

Expected:

```text
The new tests fail because source still exposes snapshotID and coordinate tap.
Existing unrelated tests may still pass.
```

Do not move on until the new tests fail for the expected reasons.

---

## Task 2: Rename Public Snapshot Field To `viewSnapshotID`

**Files:**
- Modify: `Sources/iOSExploreUIKit/Support/Parsing/UIKitCommandFields.swift`
- Modify: `Sources/iOSExploreUIKit/Commands/Tap/UITapModels.swift`
- Modify: `Sources/iOSExploreUIKit/Commands/ControlAction/UIControlSendActionModels.swift`
- Modify: `Sources/iOSExploreUIKit/Commands/Wait/UIWaitModels.swift`
- Modify: `Sources/iOSExploreUIKit/Support/Action/UIKitActionPlan.swift`
- Modify tests from Task 1 as needed.

- [ ] **Step 2.1: Add a `viewSnapshotID` command field**

In `UIKitCommandFields.swift`, replace or add the locator snapshot field with this public field name:

```swift
static let viewSnapshotID = CommandFields.optionalString(
    "viewSnapshotID",
    description: "ui.viewTargets 签发的结构化 target 指纹快照标识"
)
```

Keep any internal variable names clear. Avoid leaving a public `snapshotID` alias unless a test explicitly proves old input is rejected.

- [ ] **Step 2.2: Update `UITapInput`**

Change `UITapInput` so it has:

```swift
public let target: UITapTarget
public let viewSnapshotID: String
```

The parser must enforce:

```text
exactly one of accessibilityIdentifier/path
viewSnapshotID required
x/y/coordinateSpace not declared in schema
old snapshotID not accepted
```

Delete:

```text
UITapCoordinateSpace
UITapTarget.windowPoint
coordinate fields
```

- [ ] **Step 2.3: Update `UIControlSendActionInput`**

Change the model to:

```swift
public let target: UIKitViewLookupTarget
public let event: UIControlSendActionEvent
public let viewSnapshotID: String
```

Parser rules:

```text
exactly one of accessibilityIdentifier/path
event required
viewSnapshotID required
old snapshotID rejected
```

- [ ] **Step 2.4: Update `UIWaitInput`**

For `snapshotChanged`, rename the public field to:

```swift
viewSnapshotID
```

The model should expose:

```swift
public let viewSnapshotID: String?
```

or a mode-specific equivalent matching the existing style. Remove public `snapshotID`.

- [ ] **Step 2.5: Update `UIKitActionPlan`**

Use:

```swift
case tap(locator: UIKitLocator, viewSnapshotID: String)
case controlEvent(locator: UIKitLocator, event: UIControlSendActionEvent, viewSnapshotID: String)
```

No tap plan may contain coordinates.

- [ ] **Step 2.6: Run input tests**

Run:

```bash
swift test --filter UIKitCommandInputSchemaTests
swift test --filter UIKitTapTests
swift test --filter UIKitControlActionTests
swift test --filter UIWaitInputTests
```

Expected:

```text
New input tests pass.
Executor and snapshot tests may still fail until later tasks.
```

---

## Task 3: Stop `ui.screenshot` From Signing Structure Snapshots

**Files:**
- Modify: `Sources/iOSExploreUIKit/Commands/Screenshot/UIScreenshotCollector.swift`
- Modify: `Sources/iOSExploreUIKit/Commands/Screenshot/UIScreenshotModels.swift`
- Modify: `Tests/iOSExploreServerTests/UIScreenshotTests.swift`
- Modify: `Tests/iOSExploreServerTests/UIScreenshotInputTests.swift` only if help/schema expectations mention snapshot.

- [ ] **Step 3.1: Add failing screenshot tests**

In `UIScreenshotTests.swift`, add assertions:

```swift
XCTAssertNil(result["snapshotID"])
XCTAssertNil(result["viewSnapshotID"])
XCTAssertNil(result["snapshotUnavailableReason"])
```

If the project uses custom JSON access helpers, use the existing helper style.

- [ ] **Step 3.2: Remove snapshot signing from screenshot collector**

Delete this behavior from `UIScreenshotCollector.collect(...)`:

```swift
let query = UIViewTargetsInput()
let digest = UIKitFingerprintCollector.digest(topViewController: context.topViewController)
let fingerprints = UIKitFingerprintCollector.collectFingerprints(...)
let snapshotID = UIKitSnapshotStore.shared.insert(...)
let (idField, reasonField) = UIKitSnapshotResponse.fields(for: snapshotID)
```

Return only:

```swift
[
    "image": .string(base64),
    "format": .string("png"),
    "width": .double(Double(scaledPxW)),
    "height": .double(Double(scaledPxH)),
    "scale": .double(Double(screenScale)),
    "pixelScale": .double(pixelScale),
]
```

Update the log line so it does not mention `snapshot`.

- [ ] **Step 3.3: Update screenshot comments**

The collector doc comment must say screenshot is visual evidence only and does not sign `viewSnapshotID`.

- [ ] **Step 3.4: Run screenshot tests**

Run:

```bash
swift test --filter UIScreenshotTests
swift test --filter UIScreenshotInputTests
```

Expected:

```text
Screenshot tests pass and no screenshot response contains snapshotID/viewSnapshotID.
```

---

## Task 4: Make `ui.viewTargets` The Only `viewSnapshotID` Signer

**Files:**
- Modify: `Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsCollector.swift`
- Modify: `Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsModels.swift`
- Modify: `Sources/iOSExploreUIKit/Support/Snapshot/UIKitSnapshotResponse.swift`
- Modify: `Sources/iOSExploreUIKit/Support/Snapshot/UIKitSnapshotStore.swift`
- Modify: `Tests/iOSExploreServerTests/UIKitViewTargetsTests.swift`
- Modify: `Tests/iOSExploreServerTests/UIKitSnapshotTests.swift`

- [ ] **Step 4.1: Add failing tests for response field rename**

In `UIKitViewTargetsTests.swift`, assert:

```swift
XCTAssertNotNil(result["viewSnapshotID"])
XCTAssertNil(result["snapshotID"])
```

Also assert `snapshotUnavailableReason` is renamed only if the final protocol needs it. Prefer:

```text
viewSnapshotUnavailableReason
```

if the existing helper returns a reason field.

- [ ] **Step 4.2: Rename snapshot response helper**

Update `UIKitSnapshotResponse` so `ui.viewTargets` returns:

```text
viewSnapshotID
viewSnapshotUnavailableReason
```

Do not use this helper from `ui.screenshot`.

- [ ] **Step 4.3: Sign fingerprints only for returned targets**

Refactor `UIViewTargetsCollector.collect(query:context:)` so the path is:

```text
collect returned UIViewTargetSummary values
collect the matching UIView references or enough source data while traversing
after maxTargets truncation, build fingerprints only for returned target paths
insert those fingerprints into UIKitSnapshotStore
return viewSnapshotID
```

Do not call a full-tree `collectFingerprints(query:)` that ignores `maxTargets`.

Acceptable implementation shape:

```swift
private struct CollectedTarget {
    let summary: UIViewTargetSummary
    let view: UIView
}
```

Then produce:

```swift
let fingerprints = Dictionary(
    uniqueKeysWithValues: collectedTargets.map { target in
        (
            target.summary.path,
            UIKitFingerprintCollector.fingerprint(
                for: target.view,
                path: target.summary.path,
                rootView: context.rootView,
                digest: digest
            )
        )
    }
)
```

Keep UIKit objects on `MainActor`; do not store `UIView` in Sendable models.

- [ ] **Step 4.4: Add membership support in snapshot store**

Add or expose one internal method:

```swift
func targetFingerprint(snapshotID: String, path: String, context: UIKitSnapshotContext) -> UIKitTargetFingerprint?
```

or:

```swift
func containsTarget(snapshotID: String, path: String, context: UIKitSnapshotContext) -> Bool
```

The executor needs to distinguish:

```text
snapshot unknown/expired
path not signed by snapshot
fingerprint mismatch
```

All should ultimately fail closed as `stale_locator`.

- [ ] **Step 4.5: Test maxTargets signing**

In `UIKitViewTargetsTests.swift` or `UIKitSnapshotTests.swift`, build a host with two buttons and call `ui.viewTargets` with `maxTargets = 1`.

Assert:

```text
returned targets count == 1
snapshot store only accepts the returned path
the second button path is treated as stale / not signed
```

- [ ] **Step 4.6: Run target/snapshot tests**

Run:

```bash
swift test --filter UIKitViewTargetsTests
swift test --filter UIKitSnapshotTests
```

Expected:

```text
viewTargets returns viewSnapshotID, not snapshotID.
The signed fingerprint path set equals returned target paths.
```

---

## Task 5: Add `semanticDigest`

**Files:**
- Create: `Sources/iOSExploreUIKit/Support/Action/UIKitDefaultActivationResolver.swift`
- Create: `Sources/iOSExploreUIKit/Support/Snapshot/UIKitTargetSemanticDigest.swift`
- Modify: `Sources/iOSExploreUIKit/Support/Snapshot/UIKitFingerprintCollector.swift`
- Modify: fingerprint model file if `UIKitTargetFingerprint` lives in `UIKitSnapshotStore.swift`
- Modify: `Tests/iOSExploreServerTests/UIKitSnapshotTests.swift`

- [ ] **Step 5.1: Add failing semantic digest tests**

In `UIKitSnapshotTests.swift`, add tests:

```swift
semanticDigestChangesWhenButtonTitleChanges
semanticDigestChangesWhenAccessibilityLabelChanges
semanticDigestChangesWhenSwitchValueChanges
semanticDigestChangesWhenSegmentedSelectionChanges
semanticDigestIsStableForSameSemantics
```

- [ ] **Step 5.2: Create semantic digest helper**

First create the minimal default activation resolver, because semantic digest includes the route name:

```swift
#if canImport(UIKit)
import UIKit

@MainActor
enum UIKitDefaultActivationRoute: String {
    case controlTouchUpInside = "control.touchUpInside"
    case switchToggle = "switch.toggle"
    case inputFocus = "input.focus"
}

@MainActor
enum UIKitDefaultActivationResolver {
    static func route(for view: UIView) -> UIKitDefaultActivationRoute? {
        if view is UIButton { return .controlTouchUpInside }
        if view is UISwitch { return .switchToggle }
        if view is UITextField || view is UISearchTextField || view is UITextView {
            return .inputFocus
        }
        return nil
    }
}
#endif
```

Create `UIKitTargetSemanticDigest.swift`:

```swift
#if canImport(UIKit)
import UIKit

@MainActor
enum UIKitTargetSemanticDigest {
    static func digest(for view: UIView) -> String {
        let parts = semanticParts(for: view)
        return UIKitTargetFingerprint.stableHash(parts.joined(separator: "\u{1F}"))
    }

    private static func semanticParts(for view: UIView) -> [String] {
        var parts: [String] = []
        parts.append("type=\(String(describing: Swift.type(of: view)))")
        parts.append("role=\(UIViewTargetsCollector.role(for: view).rawValue)")
        parts.append("identifier=\(UIKitTargetFingerprint.stableHash(view.accessibilityIdentifier ?? ""))")
        parts.append("label=\(UIKitTargetFingerprint.stableHash(view.accessibilityLabel ?? ""))")
        parts.append("value=\(UIKitTargetFingerprint.stableHash(view.accessibilityValue ?? ""))")

        if let button = view as? UIButton {
            let title = button.title(for: .normal) ?? button.currentTitle ?? ""
            parts.append("buttonTitle=\(UIKitTargetFingerprint.stableHash(title))")
        }
        if let textField = view as? UITextField {
            parts.append("placeholder=\(UIKitTargetFingerprint.stableHash(textField.placeholder ?? ""))")
        }
        if let textView = view as? UITextView {
            parts.append("textViewEditable=\(textView.isEditable)")
        }
        if let switchView = view as? UISwitch {
            parts.append("switchOn=\(switchView.isOn)")
        }
        if let slider = view as? UISlider {
            let rounded = (Double(slider.value) * 1000.0).rounded() / 1000.0
            parts.append("sliderValue=\(rounded)")
        }
        if let segmented = view as? UISegmentedControl {
            parts.append("segmentIndex=\(segmented.selectedSegmentIndex)")
        }

        if let route = UIKitDefaultActivationResolver.route(for: view) {
            parts.append("activationRoute=\(route.rawValue)")
        } else {
            parts.append("activationRoute=none")
        }
        return parts
    }
}
#endif
```

- [ ] **Step 5.3: Add `semanticDigest` to fingerprints**

Add a field to `UIKitTargetFingerprint`:

```swift
let semanticDigest: String
```

Include it in equality / stale comparison.

Set it in `UIKitFingerprintCollector.fingerprint(...)`:

```swift
semanticDigest: UIKitTargetSemanticDigest.digest(for: view)
```

- [ ] **Step 5.4: Run snapshot tests**

Run:

```bash
swift test --filter UIKitSnapshotTests
```

Expected:

```text
Semantic digest tests pass. Existing stale tests still pass.
```

---

## Task 6: Implement Default Activation Resolver And Capability Contract

**Files:**
- Modify: `Sources/iOSExploreUIKit/Support/Action/UIKitDefaultActivationResolver.swift`
- Modify: `Sources/iOSExploreUIKit/Support/Action/UIKitActionCapabilityResolver.swift`
- Modify: `Sources/iOSExploreUIKit/Support/Action/UIKitActionKind.swift` only if route strings need a new enum.
- Modify: `Tests/iOSExploreServerTests/UIKitActionCapabilityTests.swift`

- [ ] **Step 6.1: Add failing capability tests**

In `UIKitActionCapabilityTests.swift`, add:

```swift
buttonDeclaresTapAndTouchEvents
switchDeclaresTapAndValueChanged
sliderDoesNotDeclareTap
segmentedControlDoesNotDeclareTap
textFieldDeclaresTapInputAndEditingEvents
unknownCustomControlDoesNotDeclareTap
```

- [ ] **Step 6.2: Verify resolver route table**

Ensure `UIKitDefaultActivationResolver.swift` still contains exactly this V1 route table:

```swift
#if canImport(UIKit)
import UIKit

@MainActor
enum UIKitDefaultActivationRoute: String {
    case controlTouchUpInside = "control.touchUpInside"
    case switchToggle = "switch.toggle"
    case inputFocus = "input.focus"
}

@MainActor
enum UIKitDefaultActivationResolver {
    static func route(for view: UIView) -> UIKitDefaultActivationRoute? {
        if view is UIButton { return .controlTouchUpInside }
        if view is UISwitch { return .switchToggle }
        if view is UITextField || view is UISearchTextField || view is UITextView {
            return .inputFocus
        }
        return nil
    }
}
#endif
```

- [ ] **Step 6.3: Update capability resolver**

Rules:

```text
if not interactable through rootView -> no actions
if disabled control -> no actions
if default activation route exists -> include .tap
if target is UIControl -> include exact supported control events
if target is UITextInput -> include .input and editing events as current behavior requires
if target is UIScrollView and not UITextView -> include .scroll
```

Specific control action rules:

```text
UIButton: control.touchDown + control.touchUpInside
UISwitch: control.valueChanged
UISlider: control.valueChanged
UISegmentedControl: control.valueChanged
UITextField: editingChanged + editingDidBegin + editingDidEnd
unknown custom UIControl: control.touchDown + control.touchUpInside only if existing behavior requires exact debug events; no tap
```

Do not reintroduce nearest ancestor action borrowing.

- [ ] **Step 6.4: Run capability tests**

Run:

```bash
swift test --filter UIKitActionCapabilityTests
```

Expected:

```text
Capability tests pass and tap appears only for default activation routes.
```

---

## Task 7: Replace Tap Executor And Unify Freshness

**Files:**
- Modify: `Sources/iOSExploreUIKit/Support/Action/UIKitActionExecutor.swift`
- Modify: `Sources/iOSExploreUIKit/UIKitCommandError.swift`
- Modify: `Tests/iOSExploreServerTests/UIKitTapTests.swift`
- Modify: `Tests/iOSExploreServerTests/UIKitActionExecutorTests.swift`
- Modify: `Tests/iOSExploreServerTests/UIKitControlActionTests.swift`

- [ ] **Step 7.1: Add failing executor tests**

Add tests:

```swift
tapButtonActivatesTouchUpInsideRoute
tapSwitchTogglesAndSendsValueChanged
tapTextFieldFocusesFirstResponder
tapSliderReturnsUnsupportedTarget
tapSegmentedControlReturnsUnsupportedTarget
tapChildLabelPathDoesNotActivateParentButton
tapIdentifierRequiresFreshViewSnapshot
sendActionIdentifierRequiresFreshViewSnapshot
```

- [ ] **Step 7.2: Implement unified freshness validation**

Add a private method in `UIKitActionExecutor`:

```swift
private static func validateViewSnapshot(
    located: UIKitLocatorResolver.LocatedView,
    viewSnapshotID: String,
    context: UIKitContextProvider.Context,
    action: String
) throws {
    let path = located.pathString
    let snapshotContext = UIKitFingerprintCollector.context(
        window: context.window,
        topViewController: context.topViewController
    )
    let current = UIKitFingerprintCollector.fingerprint(
        for: located.view,
        path: path,
        rootView: context.rootView,
        digest: UIKitFingerprintCollector.digest(topViewController: context.topViewController)
    )

    guard !UIKitSnapshotStore.shared.isStale(
        snapshotID: viewSnapshotID,
        path: path,
        context: snapshotContext,
        current: current
    ) else {
        throw UIKitCommandError.staleLocator(action: action, snapshotID: viewSnapshotID)
    }
}
```

If `isStale` cannot distinguish missing path from mismatch, still fail closed as `stale_locator`.

- [ ] **Step 7.3: Delete old tap paths**

Remove:

```text
executeTapWindowPoint
executeTapViewTarget center hit-test
dispatchTap
nearestControl fallback for tap
hitPath/hitType/controlPath/x/y response fields
```

- [ ] **Step 7.4: Implement default activation execution**

Implement tap route:

```swift
private static func executeTap(
    locator: UIKitLocator,
    viewSnapshotID: String,
    context: UIKitContextProvider.Context
) throws -> JSON {
    let target = locatorSummary(locator)
    let located = try UIKitLocatorResolver.locate(
        locator: locator,
        in: context.rootView,
        notFound: { UIKitCommandError.targetNotFound(action: tapAction, targetDescription: target) },
        ambiguous: { UIKitCommandError.targetAmbiguous(action: tapAction, targetDescription: target, count: $0) }
    )

    try validateViewSnapshot(located: located, viewSnapshotID: viewSnapshotID, context: context, action: tapAction)

    guard let route = UIKitDefaultActivationResolver.route(for: located.view) else {
        throw UIKitCommandError.unsupportedTarget(
            action: tapAction,
            targetDescription: located.pathString,
            type: String(describing: Swift.type(of: located.view))
        )
    }

    switch route {
    case .controlTouchUpInside:
        guard let control = located.view as? UIControl else {
            throw UIKitCommandError.unsupportedTarget(action: tapAction, targetDescription: located.pathString, type: String(describing: Swift.type(of: located.view)))
        }
        control.sendActions(for: .touchUpInside)
        return [
            "activated": .bool(true),
            "activationRoute": .string(route.rawValue),
            "path": .string(located.pathString),
            "type": .string(String(describing: Swift.type(of: control))),
            "event": .string("touchUpInside"),
            "accessibilityIdentifier": control.accessibilityIdentifier.map(JSONValue.string) ?? .null,
        ]
    case .switchToggle:
        guard let switchView = located.view as? UISwitch else {
            throw UIKitCommandError.unsupportedTarget(action: tapAction, targetDescription: located.pathString, type: String(describing: Swift.type(of: located.view)))
        }
        let previous = switchView.isOn
        switchView.setOn(!previous, animated: false)
        switchView.sendActions(for: .valueChanged)
        return [
            "activated": .bool(true),
            "activationRoute": .string(route.rawValue),
            "path": .string(located.pathString),
            "type": .string(String(describing: Swift.type(of: switchView))),
            "event": .string("valueChanged"),
            "previousValue": .bool(previous),
            "currentValue": .bool(switchView.isOn),
        ]
    case .inputFocus:
        let focused = located.view.becomeFirstResponder()
        guard focused else {
            throw UIKitCommandError.activationFailed(action: tapAction, targetDescription: located.pathString, reason: "becomeFirstResponder returned false")
        }
        return [
            "activated": .bool(true),
            "activationRoute": .string(route.rawValue),
            "path": .string(located.pathString),
            "type": .string(String(describing: Swift.type(of: located.view))),
            "isFirstResponder": .bool(located.view.isFirstResponder),
        ]
    }
}
```

Adjust `JSONValue` enum names to match the current codebase.

- [ ] **Step 7.5: Update `ui.control.sendAction` freshness**

`executeControlEvent` must require `viewSnapshotID` for both path and identifier:

```text
locate current view
validateViewSnapshot
guard located.view is UIControl
guard requested exact action is currently available
send explicit event
```

No hit-test and no ancestor fallback.

- [ ] **Step 7.6: Update errors**

In `UIKitCommandError.staleLocator`, message must mention `ui.viewTargets`:

```text
view snapshot expired or target changed; call ui.viewTargets first, then retry with the new viewSnapshotID
```

Add:

```swift
static func activationFailed(action: String, targetDescription: String, reason: String) -> UIKitCommandError
```

only if no equivalent factory exists.

- [ ] **Step 7.7: Run executor tests**

Run:

```bash
swift test --filter UIKitTapTests
swift test --filter UIKitActionExecutorTests
swift test --filter UIKitControlActionTests
swift test --filter UIKitCommandErrorTests
```

Expected:

```text
Tap no longer returns controlActionFallback or coordinate fields.
Tap routes button/switch/text input correctly.
Child label paths do not activate parent controls.
Identifier and path both require freshness.
```

---

## Task 8: Canonicalize `ui.viewTargets`

**Files:**
- Modify: `Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsModels.swift`
- Modify: `Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsCollector.swift`
- Modify: `Tests/iOSExploreServerTests/UIKitViewTargetsTests.swift`

- [ ] **Step 8.1: Add failing canonical target tests**

Add tests:

```swift
viewTargetsReturnsButtonButNotInternalLabel
viewTargetsDoesNotReturnGestureOnlyView
viewTargetsDoesNotReturnIdentifierOnlyPlainView
viewTargetsDoesNotReturnAccessibilityLabelOnlyPlainView
viewTargetsAggregatesButtonSemanticText
disabledDirectTargetHasEmptyActions
```

- [ ] **Step 8.2: Update inclusion policy**

`UIViewTargetsInput.shouldInclude` should no longer make a view executable solely because:

```text
hasGestureRecognizers
hasAccessibilityIdentifier
hasAccessibilityLabel
hasStaticText
hasSubviews
```

Canonical include rules:

```text
include known direct command targets:
- UIButton / UIButton subclass
- UISwitch
- UISlider
- UISegmentedControl
- UITextField / UISearchTextField / UITextView
- UIScrollView / UITableView / UICollectionView, excluding UITextView for scroll if current semantics require
- unknown UIControl only as exact control-event target, with no tap
- disabled direct targets as observable targets with empty actions
```

Keep `includeStaticText` and `includeContainers` out of executable `targets`. If those options are still needed, document that they belong to `ui.topViewHierarchy` or remove them from `ui.viewTargets` schema in the same task.

- [ ] **Step 8.3: Add semantic text fields**

If `UIViewTargetSummary` lacks these fields, add:

```swift
public let semanticText: String?
public let semanticTextSource: String?
```

Extraction priority:

```text
accessibilityLabel
UIButton.title(for: .normal) / currentTitle
accessibilityValue
accessibilityIdentifier
strict descendant text fallback with length/count limits
```

Do not log semantic text in plaintext.

- [ ] **Step 8.4: Run view target tests**

Run:

```bash
swift test --filter UIKitViewTargetsTests
```

Expected:

```text
viewTargets returns canonical targets only.
Semantic text is carried by the parent canonical target.
```

---

## Task 9: Migrate `ui.wait snapshotChanged`

**Files:**
- Modify: `Sources/iOSExploreUIKit/Commands/Wait/UIWaitModels.swift`
- Modify: `Sources/iOSExploreUIKit/Support/Wait/UIWaitExecutor.swift`
- Modify: `Tests/iOSExploreServerTests/UIWaitInputTests.swift`
- Modify: `Tests/iOSExploreServerTests/UIWaitTests.swift`

- [ ] **Step 9.1: Update wait executor**

Replace:

```swift
input.snapshotID
```

with:

```swift
input.viewSnapshotID
```

For `snapshotChanged`, continue:

```text
load signing query from UIKitSnapshotStore
recollect current fingerprint table using that query
compare whole table
```

The signing source must be `ui.viewTargets`, not `ui.screenshot`.

- [ ] **Step 9.2: Update wait unavailable reason**

If response currently says:

```text
snapshot unknown or expired
```

that may remain acceptable, but field/docs should refer to `viewSnapshotID`.

- [ ] **Step 9.3: Run wait tests**

Run:

```bash
swift test --filter UIWaitInputTests
swift test --filter UIWaitTests
```

Expected:

```text
snapshotChanged accepts viewSnapshotID and rejects old snapshotID.
```

---

## Task 10: Update Docs And Help Text

**Files:**
- Modify: `README.md`
- Modify: `docs/architecture/index.md`
- Modify: `docs/uikit/README.md`
- Modify: `docs/uikit/reading-guide.md`
- Modify: `docs/uikit/uikit-file-reference.md`
- Modify: `docs/superpowers/agent-mcp-exploration/README.md`
- Modify: `docs/superpowers/agent-mcp-exploration/agent-usage-protocol.md`
- Modify command descriptions in Swift command files where help text is generated.

- [ ] **Step 10.1: Find stale public wording**

Run:

```bash
rg -n "snapshotID|viewSnapshotID|ui\\.screenshot|coordinateSpace|window point|x/y|controlActionFallback|ui\\.tap|touchUpInside" README.md docs Sources/iOSExploreUIKit
```

Expected:

```text
You find all stale mentions before editing docs.
```

- [ ] **Step 10.2: Update docs with new protocol**

Docs must say:

```text
ui.viewTargets signs viewSnapshotID.
ui.screenshot does not sign viewSnapshotID.
ui.tap requires path/accessibilityIdentifier + viewSnapshotID.
ui.tap is default activation, not touch injection.
ui.control.sendAction requires path/accessibilityIdentifier + viewSnapshotID + explicit event.
stale_locator means call ui.viewTargets again.
navigationBar remains ui.navigation.tapBarButton.
alert remains its current dedicated command/dry-run boundary.
```

- [ ] **Step 10.3: Update generated help expectations**

If tests assert command help schema, update them so:

```text
ui.tap schema has no x/y/coordinateSpace
ui.tap schema includes viewSnapshotID
ui.control.sendAction schema includes viewSnapshotID
ui.wait snapshotChanged schema includes viewSnapshotID
ui.screenshot schema/response docs do not mention snapshotID
```

- [ ] **Step 10.4: Run docs-related tests and stale grep**

Run:

```bash
swift test --filter UIKitCommandInputSchemaTests
rg -n "snapshotID|coordinateSpace|controlActionFallback|call ui\\.screenshot first" README.md docs Sources/iOSExploreUIKit Tests
```

Expected:

```text
Only historical design documents may still mention old snapshotID/coordinate behavior as previous/current-state context.
Active README, command help, agent protocol, and source comments no longer teach stale behavior.
```

---

## Task 11: Full Verification

**Files:**
- No new source files.
- Run verification only.

- [ ] **Step 11.1: Run package tests**

Run:

```bash
swift test
```

Expected:

```text
All Swift package tests pass.
```

- [ ] **Step 11.2: Run iOS framework tests**

Run:

```bash
xcodebuild \
  -project iOSExploreServer/iOSExploreServer.xcodeproj \
  -scheme iOSExploreServer \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
```

Expected:

```text
Framework tests pass.
```

If `iPhone 17` is unavailable, list available simulators and use the closest available iPhone simulator. Record the exact substituted destination in the final response.

- [ ] **Step 11.3: Run whitespace check**

Run:

```bash
git diff --check
```

Expected:

```text
No whitespace errors.
```

- [ ] **Step 11.4: Inspect final status**

Run:

```bash
git status --short
```

Expected:

```text
Only intentional source, test, and docs changes are present.
No commit is created.
```

---

## Final Acceptance Checklist

Before reporting completion, verify every item:

- [ ] `ui.tap` no longer accepts `x`, `y`, or `coordinateSpace`.
- [ ] `UIKitLocator` no longer exposes `.windowPoint`.
- [ ] `ui.tap` requires `viewSnapshotID` for path and identifier.
- [ ] `ui.control.sendAction` requires `viewSnapshotID` for path and identifier.
- [ ] `ui.wait snapshotChanged` uses `viewSnapshotID`.
- [ ] `ui.screenshot` does not sign or return `snapshotID` / `viewSnapshotID`.
- [ ] `ui.viewTargets` returns `viewSnapshotID`.
- [ ] Returned target paths equal signed fingerprint paths.
- [ ] `semanticDigest` participates in stale detection.
- [ ] `UIButton` tap sends `.touchUpInside`.
- [ ] `UISwitch` tap toggles and sends `.valueChanged`.
- [ ] Text input tap focuses first responder.
- [ ] `UISlider` and `UISegmentedControl` do not declare tap.
- [ ] Child label/image path does not activate parent control.
- [ ] `stale_locator` tells clients to call `ui.viewTargets`, not `ui.screenshot`.
- [ ] Navigation bar behavior remains under `ui.navigation.tapBarButton`.
- [ ] Alert behavior is not folded into `ui.tap`.
- [ ] `swift test` passes.
- [ ] iOS framework `xcodebuild ... test` passes or the exact environment blocker is reported.
- [ ] No git commit was created.
