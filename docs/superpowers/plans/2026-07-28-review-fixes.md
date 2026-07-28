# Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the verified high-value review findings across Core HTTP, UIKit input execution, Diagnostics redaction, and iOSDriver workflows.

**Architecture:** Keep protocol facts in `contracts/` and generated metadata. Prefer behavior-preserving API additions where source-breaking changes are unnecessary. Every runtime behavior change starts with a focused regression test that fails against the current implementation.

**Tech Stack:** Swift 6.2 SwiftPM targets, Foundation/Network/UIKit, TypeScript Node 20, Vitest.

**Execution status:** Tasks 1 through 6 are implemented. Task 3 now includes the public snapshot target contract change: each signed path stores its fingerprint and the exact `availableActions` emitted by the same `ui.inspect`. `ui.tap`, snapshot-bound `ui.input` / directed `ui.scroll`, and `ui.control.sendAction` reject actions absent from that signed set. This intentionally changes public `UIKitSnapshotStore.insert` from `[String: UIKitTargetFingerprint]` to `[String: UIKitSnapshotTarget]`; no legacy overload remains because fingerprint-only callers cannot safely infer which actions the inspect response authorized. Picker/datePicker/webView/swipe/longPress remain separate typed-executor contracts whose optional snapshot is a freshness guard; they are explicitly not deferred action-aware work. Diagnostics registration replacement reporting, `app.logs.read` flush intent reporting, reserved host auth-token forwarding, and CLI extension-action policy lookup were also implemented from confirmed review findings.

**Authentication decision:** Token validation is intentionally disabled for the Debug service. `ExploreServer(authToken:)`, host configuration, header forwarding, and the `ClientSession` validation branch remain reserved implementation, but `ExploreServer` passes no token to the listener while the product switch is `false`. Missing, incorrect, or matching `X-Auth-Token` headers must all be accepted. This is a product decision, not an unfinished wiring bug, and it provides no access-control guarantee. Because the listener binds all interfaces, the service must only run in a controlled development network or through USB forwarding.

**Verification status:** Contract drift and all 165 iOSDriver tests pass. Eleven action-aware UIKit regressions pass on an iPhone 17 Pro simulator through the SwiftPM Xcode workspace, including disabled input, unsigned tap/input/scroll actions, exact control events, valid button/control/gesture/scroll execution, and gesture target release. `swift test` executes 325 tests: 323 pass and two pre-existing macOS `OSLogStore` capture tests fail; the focused `os_log` failure reproduces on an untouched `HEAD` worktree. Running the suite while skipping those two baseline cases passes 323/323.

---

### Task 1: Core HTTP Reserved Authentication and Response Events

**Files:**
- Modify: `Sources/iOSExploreServer/Server/ExploreServer.swift`
- Modify: `Sources/iOSExploreServer/HTTP/HTTPListener.swift`
- Modify: `Sources/iOSExploreServer/HTTP/ClientSession.swift`
- Test: `Tests/iOSExploreServerTests/IntegrationTests.swift`

- [x] **Step 1: Write authentication-decision tests**

Add tests that start `ExploreServer(authToken: "secret")`, send `POST /` without `X-Auth-Token`, with a wrong token, and with the correct token. Expected: all requests return `ping` success because validation is intentionally disabled.

- [x] **Step 2: Write failing response event tests**

Add a test with `onEvent` capture for an invalid parse request such as bad `Content-Length`, and assert a `.responded(status: 400, ok: false)` event is emitted when a response is sent.

- [x] **Step 3: Run failing tests**

Run: `swift test --filter IntegrationTests`

- [x] **Step 4: Implement minimal behavior**

Keep the `HTTPListener` and `ClientSession` token validation implementation reserved, but gate forwarding in `ExploreServer` with the fixed-off product switch. Emit `.responded` from every path that writes an HTTP response.

- [x] **Step 5: Verify**

Run: `swift test --filter IntegrationTests`

### Task 2: Core Registration and Start Semantics

**Files:**
- Modify: `Sources/iOSExploreServer/Commands/Router.swift`
- Modify: `Sources/iOSExploreServer/Server/ExploreServer.swift`
- Test: `Tests/iOSExploreServerTests/RouterTests.swift`
- Test: `Tests/iOSExploreServerTests/IntegrationTests.swift`

- [x] **Step 1: Write failing registration tests**

Change/add tests so invalid action registration returns `false` and valid registration returns `true`, while existing callers may still ignore the result.

- [x] **Step 2: Write failing repeated-start test**

Add a test that calls `start()` twice on the same server and expects the second call to be idempotent rather than trying to bind the port again.

- [x] **Step 3: Run failing tests**

Run: `swift test --filter RouterTests && swift test --filter IntegrationTests`

- [x] **Step 4: Implement minimal behavior**

Return `Bool` from public registration wrappers with `@discardableResult`. Make `ExploreServer.start()` return immediately when a listener already exists.

- [x] **Step 5: Verify**

Run: `swift test --filter RouterTests && swift test --filter IntegrationTests`

### Task 3: UIKit Input and Action-Aware Snapshot Signing

**Files:**
- Modify: `Sources/iOSExploreUIKit/Support/Action/UITextInputExecutor.swift`
- Modify: `Sources/iOSExploreUIKit/Support/Action/UIScrollResolver.swift`
- Modify: `Sources/iOSExploreUIKit/Support/Action/UIKitActionExecutor.swift`
- Modify: `Sources/iOSExploreUIKit/Support/Action/UIKitActionCapabilityResolver.swift`
- Modify: `Sources/iOSExploreUIKit/Support/Action/UIGestureTargetExecutor.swift`
- Modify: `Sources/iOSExploreUIKit/Support/Snapshot/UIKitSnapshotStore.swift`
- Modify: `Sources/iOSExploreUIKit/Commands/Inspect/UIInspectCollector.swift`
- Modify: `contracts/device-actions/uikit.inspect.json`
- Modify: `contracts/device-actions/uikit.tap.json`
- Modify: `contracts/device-actions/uikit.input.json`
- Modify: `contracts/device-actions/uikit.control-send-action.json`
- Modify: `contracts/device-actions/uikit.scroll.json`
- Test: `Tests/iOSExploreServerTests/UIInputTests.swift`
- Test: `Tests/iOSExploreServerTests/UIKitActionExecutorTests.swift`
- Test: `Tests/iOSExploreServerTests/UIGestureTargetExecutorTests.swift`
- Test: `Tests/iOSExploreServerTests/UIKitSnapshotTests.swift`
- Test: `Tests/iOSExploreServerTests/UIScrollTests.swift`

- [x] **Step 1: Write failing disabled input test**

Add a `UIInputTests` case with a disabled `UITextField` and assert `ui.input` returns a business failure instead of inserting text.

- [x] **Step 2: Write failing signed-action tests**

Add a snapshot store test proving a signed static label path is not considered signed for `.input` or `.tap` unless that action was present in inspect `availableActions`.

- [x] **Step 3: Run the scoped failing tests**

Run the store tests on macOS and the input/tap/control/gesture regressions through the SwiftPM Xcode workspace on an iOS simulator.

- [x] **Step 4: Implement action-aware signing and execution**

Add public `UIKitSnapshotTarget(fingerprint, availableActions)`, store it per path, and make the collector persist the same availability returned in JSON. Require `.tap`, `.input`, `.scroll`, or the specific `control.*` event before freshness validation whenever those commands carry a target snapshot. Keep Debug gesture tap available only when runtime target-action inspection confirms it is executable. Treat the `UIKitSnapshotStore.insert` signature change as intentional public API migration; do not retain a fingerprint-only overload that would silently create unsigned or over-authorized targets.

- [x] **Step 5: Verify action and recovery semantics**

Verify static labels, disabled controls, unsupported control events, unsigned scroll targets, and deallocated gesture targets return `not_actionable`; valid buttons, control events, inputs, scroll views, and executable gestures continue to work. Unknown/expired snapshot IDs must still return `stale_locator` through the existing three-state lookup.

### Task 4: Diagnostics Redaction

**Files:**
- Modify: `Sources/iOSExploreDiagnostics/DeveloperAPI/ESLogRedactor.swift`
- Test: `Tests/iOSExploreServerTests/DiagnosticsStoreTests.swift`
- Test: `Tests/iOSExploreServerTests/DiagnosticsCommandTests.swift`

- [x] **Step 1: Write failing redaction tests**

Add tests for metadata keys `accessToken`, `refreshToken`, and `api_key`, plus message text containing `api_key=secret`.

- [x] **Step 2: Run failing tests**

Run: `swift test --filter DiagnosticsStoreTests && swift test --filter DiagnosticsCommandTests`

- [x] **Step 3: Implement minimal behavior**

Normalize metadata keys by removing separators and lowercasing. Add `apikey`, `accesstoken`, and `refreshtoken` to sensitive key detection. Extend message regex for `api_key` and camelCase token keys.

- [x] **Step 4: Verify**

Run: `swift test --filter DiagnosticsStoreTests && swift test --filter DiagnosticsCommandTests`

### Task 5: iOSDriver Workflow Error Handling

**Files:**
- Modify: `iOSDriver/src/workflows/tapAndInspect.ts`
- Modify: `iOSDriver/src/workflows/waitAndInspect.ts`
- Create or modify: `iOSDriver/src/workflows/errorPolicy.ts`
- Test: `iOSDriver/tests/workflows/tapAndInspect.test.ts`
- Test: `iOSDriver/tests/workflows/waitAndInspect.test.ts`

- [x] **Step 1: Write failing workflow tests**

Add a `tap_and_inspect` test where wait returns `transport_unavailable` and assert the workflow fails without inspect. Keep the existing `wait_timeout` continuation behavior.

- [x] **Step 2: Run failing tests**

Run: `cd iOSDriver && npx vitest run tests/workflows/tapAndInspect.test.ts tests/workflows/waitAndInspect.test.ts`

- [x] **Step 3: Implement minimal behavior**

Add a workflow helper that treats `wait_timeout` as inspect-continue, and treats transport/protocol/http/request validation errors as terminal. Use generated `CONTRACT_ERROR_INDEX` only for metadata lookup, with explicit allowlist for continuation.

- [x] **Step 4: Verify**

Run: `cd iOSDriver && npx vitest run tests/workflows/tapAndInspect.test.ts tests/workflows/waitAndInspect.test.ts`

### Task 6: Final Verification

**Files:**
- No direct edits.

- [x] **Step 1: Check contract drift**

Run: `cd iOSDriver && npm run contracts:check`

- [x] **Step 2: Run Swift tests**

Run: `swift test`

Result: 323/325 pass. The two `OSLogStore` capture failures (`osLogCaptureWritesEntriesIntoDiagnosticsStore` and `osLogCaptureFiltersAppleSystemSubsystem`) are pre-existing macOS baseline failures; the focused `os_log` failure reproduces on an untouched `HEAD` worktree. Skipping those two cases yields 323/323 pass.

- [x] **Step 3: Run iOSDriver tests**

Run: `cd iOSDriver && npm test`

Result: 23 test files, 165/165 tests pass, including contract drift generation and TypeScript build.

- [x] **Step 4: Run action-aware UIKit regressions on iOS**

Run the snapshot/tap/input/control/gesture cases through the SwiftPM Xcode workspace on an iPhone 17 Pro simulator.

Result: 11/11 pass. The suite covers static-label tap/input/scroll rejection, disabled button/slider rejection, exact control-event signing, valid button/control/scroll execution, gesture execution, and deallocated gesture targets.
