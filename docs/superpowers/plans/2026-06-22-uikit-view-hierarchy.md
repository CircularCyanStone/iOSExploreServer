# UIKit View Hierarchy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add built-in optional UIKit commands that return a structured top-view-controller view hierarchy for agent page understanding and UI acceptance checks.

**Architecture:** Keep protocol/router/network code UIKit-free. Put reusable Foundation-only hierarchy node models and query logic under `Handlers/UIKit/ViewHierarchy/`, then wrap actual UIKit traversal and the `ui.topViewHierarchy` command in `#if canImport(UIKit)`.

**Tech Stack:** Swift 6.2 SPM, Swift Testing, UIKit under conditional compilation, existing `Command`/`Router`/`JSON` models.

---

### Task 1: Foundation-only model and tests

**Files:**
- Create: `Tests/iOSExploreServerTests/UIKitViewHierarchyTests.swift`
- Create: `Sources/iOSExploreServer/Handlers/UIKit/ViewHierarchy/UIViewHierarchyModels.swift`

- [ ] Write tests for node JSON, recursive path generation, depth limiting, hidden filtering, and identifier matching.
- [ ] Run `swift test --filter UIKitViewHierarchyTests` and verify failures reference missing model types.
- [ ] Implement `UIViewHierarchyRect`, `UIViewHierarchyState`, `UIViewHierarchyText`, `UIViewHierarchyAppearance`, `UIViewHierarchyControl`, `UIViewHierarchyImage`, `UIViewHierarchyScroll`, `UIViewHierarchyNode`, `UIViewHierarchyQuery`, and `UIViewHierarchyBuilder`.
- [ ] Run `swift test --filter UIKitViewHierarchyTests` and verify the tests pass.

### Task 2: UIKit collector and command

**Files:**
- Create: `Sources/iOSExploreServer/Handlers/UIKit/ViewHierarchy/UIViewHierarchyCollector.swift`
- Create: `Sources/iOSExploreServer/Handlers/UIKit/ViewHierarchy/TopViewHierarchyCommand.swift`
- Create: `Sources/iOSExploreServer/Handlers/UIKit/UIKitHandlers.swift`
- Modify: `Sources/iOSExploreServer/ExploreServer.swift`

- [ ] Add UIKit-only traversal that runs on `MainActor` and extracts layout, accessibility, text, appearance, control, image, and scroll fields.
- [ ] Add `TopViewHierarchyCommand` with action `ui.topViewHierarchy` and optional parameters `detailLevel`, `maxDepth`, `includeHidden`, `accessibilityIdentifier`, `accessibilityIdentifierPrefix`.
- [ ] Register UIKit handlers in `ExploreServer.init` under `#if canImport(UIKit)`.
- [ ] Add command logs for start, MainActor collection, filtering, success, and failure exits.

### Task 3: Docs and verification

**Files:**
- Modify: `docs/architecture/index.md`
- Modify: `docs/tools/network-tools.md`
- Modify: `docs/runbooks/build-and-test.md`

- [ ] Document the UIKit optional command package and `ui.topViewHierarchy` request/response.
- [ ] Run `swift test`.
- [ ] Run `xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`.
