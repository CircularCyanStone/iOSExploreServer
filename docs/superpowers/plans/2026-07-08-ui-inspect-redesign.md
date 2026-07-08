# ui.inspect 重设计 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `ui.viewTargets` 重设计为 `ui.inspect`——全节点输出 + full/minimal 两档，让 agent 能按文字定位 cell、看到完整层级，同时保持"签发 fingerprint 的节点才可操作"。

**Architecture:** collector 递归遍历全节点，按"有没有识别信息/可不可操作"分 full/minimal 两档（minimal 只 path+type、强制 actions=[]、不签 fingerprint）；fingerprint 只签 full；executor 对未签发的 path 经新增 `isPathSigned` 判定后返回 `not_actionable`。

**Tech Stack:** Swift 6.2（iOSExploreServer core + iOSExploreUIKit）、Swift Testing（`@Test`）、TypeScript（MCPServer stdio）、XcodeBuildMCP（端到端验证）。

**Spec:** `docs/superpowers/specs/2026-07-08-ui-inspect-redesign-design.md`（v3，两轮评审定稿）

## Global Constraints

- **Debug-only 工具**：私有 API / runtime 技巧用 `#if DEBUG` 隔离，绝不进 Release。
- **core 不依赖 UIKit**：`Sources/iOSExploreServer/` 只 Foundation + Network；新错误码 `not_actionable` 是通用业务码放 core。
- **typed factory**：入参先经 Foundation-only typed query 解析，UIKit 类型不穿 public 边界。
- **Swift 5.0 兼容**：framework 工程 `SWIFT_VERSION=5.0`，避免 Swift-6-only 语法。
- **日志要求**：改命令/关键属性/状态转移要同步打日志（category `command`，复用 `UIKitCommandLogging`）。
- **注释**：public 类型/方法 `///` 注释，简体中文写"为什么"。
- **测试命令**：macOS SPM `swift test`；iOS framework `xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' test`。

---

## File Structure

| 文件 | 职责 | 改动类型 |
|---|---|---|
| `Sources/iOSExploreServer/Models.swift` | core 错误码枚举 | 加 `not_actionable` case |
| `Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsModels.swift` | 候选判定 + summary 模型 + input | shouldInclude→isFull、删死字段、summary 加 isMinimal、toJSON 分档 |
| `Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsCollector.swift` | 采集器 | 全节点+分档+签发只 full+截断只数 full+maxVisitedNodes+日志+matchesIdentifier |
| `Sources/iOSExploreUIKit/Commands/ViewTargets/ViewTargetsCommand.swift` | 命令注册 | actionName `ui.viewTargets`→`ui.inspect` |
| `Sources/iOSExploreUIKit/UIKitCommandError.swift` | UIKit 错误工厂 | 加 notActionable 工厂、staleLocator message 改名 |
| `Sources/iOSExploreUIKit/Support/Snapshot/UIKitSnapshotStore.swift` | 指纹存储 | 加 isPathSigned 方法 |
| `Sources/iOSExploreUIKit/Support/Action/UIKitActionExecutor.swift` | 动作执行 | validateViewSnapshot 前置 isPathSigned |
| `Sources/iOSExploreUIKit/Support/Snapshot/UIKitFingerprintCollector.swift` | 指纹采集 | shouldInclude→isFull 改名连带 |
| `Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift` | 命令注册入口 | 注释/log 同步 |
| `Sources/iOSExploreUIKit/Support/Parsing/UIKitCommandFields.swift` | 通用字段 description | path/viewSnapshotID description 改名（L58/L69） |
| `Sources/iOSExploreUIKit/Commands/Wait/UIWaitModels.swift` | wait 模型 | viewSnapshotID description 改名（L60） |
| `Sources/iOSExploreUIKit/Commands/Tap/UITapModels.swift` | tap 模型 | extensionMessage 改名（L32） |
| `Sources/iOSExploreUIKit/Commands/ControlAction/UIControlSendActionModels.swift` | control 模型 | extensionMessage 改名（L63） |
| `MCPServer/src/staticTools.ts` | MCP 静态工具 | 废弃 observe、wait_and_observe→wait_and_inspect、viewTargetsOptions→inspectOptions |
| 测试 | 各模块 | 全量 viewTargets→inspect + 新增回归 |

---

## 评审修订（v2，2026-07-08，执行依据）

> 实现计划经 subagent 可执行性评审。**正文实现代码、文件路径、行号经确认全部准确**；以下修正针对**测试侧**（正文部分测试 API/命令/路径与真实代码不符），执行时**以此节为准**。

### 全局
- **测试目录**：正文 `Tests/iOSExploreUIKitTests/` 实际为 `Tests/iOSExploreServerTests/`（UIKit 与 core 测试同在 SPM 测试 target）。git add / test filter 路径以此为准。
- **UIKit 测试命令**：Task 2/6/7/8 测 UIKit 代码（`#if canImport(UIKit)` 后），用 `xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' test`，**不用 `swift test`**（macOS 下 UIKit 代码编译为空，会假通过）。Task 1/4/5 与 Task 3 的 isFull 判定是 Foundation-only，仍用 `swift test`。

### Task 1
`not_actionable` 是**业务码**（HTTP 200 + body code），不经传输层 `ExploreServerError`。测试只用 `#expect(ExploreError.notActionable.rawValue == "not_actionable")`；envelope 断言走 `ExploreResult.failure(code: .notActionable, message:)` + 现有序列化（参 `ExploreServerErrorContractTests.swift`）。**不要用** `ExploreServerError(error:message:)` / `.bodyJSON`（均不存在，且概念层级错）。

### Task 2
- 测试访问 `error.failure.code` / `error.failure.message`（**不是** `failure.code` / `httpResponse()`），照搬现有 `UIKitCommandErrorTests.swift:11-12` 的 staleLocator 写法
- **补 step**：改 staleLocator message 后，既有 `UIKitCommandErrorTests.swift:12` 的 `.contains("ui.viewTargets")` 断言会 FAIL，同步改为 `.contains("ui.inspect")`

### Task 3
- `UIViewTargetsInput.parseFromJSON` 不存在；用 `UIViewTargetsInput.parse(from: JSON)` 或直接 `UIViewTargetsInput(...)` init（参 `UIKitViewTargetsTests.swift`）
- **补 step**：既有 `Tests/iOSExploreServerTests/UIKitViewTargetsTests.swift:5-22` 断言了三个将删字段（`includeDisabled`/`includeStaticText`/`includeContainers`），删字段后**编译失败**，Task 3 必须同步清理这段既有断言

### Task 5
`UIKitSnapshotStore.testStore()` 不存在；用 `UIKitSnapshotStore()` 或 `UIKitSnapshotStore(now: { fixedDate })`（参 `UIKitSnapshotTests.swift`）。`.test`（fingerprint/context fixture）、`UIViewTargetsInput` 默认值真实存在。

### Task 6（核心 task，重点 review）
- **`makeCandidate(for:)` 所有权归本 task**：Step 3 加「把 `shouldInclude(view:query:)` L147-158 内联的 candidate 构造提取为 `static func makeCandidate(for view: UIView) -> UIViewTargetCandidate`，`isFull` 与 collect 共用」。Task 8 改为"复用 Task 6 的 makeCandidate"，不重复提取（否则按 6→8 顺序 Task 6 编译失败）。
- **minimalSummary 补完整 init**（`UIViewTargetSummary` 必传 frame/state，即便 toJSON 不输出也要构造）：
```swift
private static func minimalSummary(for view: UIView, path: [Int], window: UIWindow) -> UIViewTargetSummary {
    UIViewTargetSummary(
        path: UIKitViewLookupTarget.pathString(from: path),
        type: String(describing: Swift.type(of: view)),
        role: role(for: view),
        accessibilityIdentifier: nil, accessibilityLabel: nil, title: nil, text: nil,
        placeholder: nil, value: nil, semanticText: nil, semanticTextSource: nil,
        frame: UIViewHierarchyRect(rect: view.convert(view.bounds, to: window)),
        state: UIViewTargetState(isHidden: view.isHidden, alpha: Double(view.alpha),
                                 isUserInteractionEnabled: view.isUserInteractionEnabled,
                                 isEnabled: nil, isSelected: nil, isHighlighted: nil,
                                 hasGestureRecognizers: view.gestureRecognizers?.isEmpty == false),
        availableActions: UIKitActionAvailability(actions: []),
        indexPath: cellIndexPath(for: view),
        isMinimal: true)
}
```
（toJSON 因 `isMinimal=true` 只输出 path+type，frame/state 计算了但不输出；minimal cell 容器带 indexPath 有价值，保留）
- **测试命令改 xcodebuild test**

### Task 7
- **测试命令改 xcodebuild test**（UIKit）

### Task 8
- 复用 Task 6 的 `makeCandidate`（不重复提取）
- **补 step**：`collectMatching` 上方加注释「已知限制：`matchesWholeTable` 全表相等比较，`collectMatching` 重采不遵循 maxTargets 截断；full 超 maxTargets 时可能误报 changed（默认 full≈24 不触发）」
- **测试命令改 xcodebuild test**（UIKit）

### Task 10
- **补 step**：`staticTools.ts` 顶部 `viewTargetsOptionKeys`（L7-17）删 `includeDisabled`/`includeStaticText`/`includeContainers` 三项（Task 3 已删对应 Swift 字段，不同步会让 `pickAllowedFields` 透传 App 已不认识的键）

---

### Task 1: core 新增 `not_actionable` 错误码

**Files:**
- Modify: `Sources/iOSExploreServer/Models.swift`（`ExploreError` 枚举，约 L145）
- Test: `Tests/iOSExploreServerTests/ExploreErrorTests.swift`（若不存在则建）

**Interfaces:**
- Produces: `ExploreError.notActionable`（rawValue `"not_actionable"`），HTTP 200 + body code（与现有业务码同模式）

- [ ] **Step 1: 写失败测试**

```swift
import Testing
@testable import iOSExploreServer

@Test("not_actionable 错误码 rawValue 与 envelope")
func notActionableErrorCode() throws {
    #expect(ExploreError.notActionable.rawValue == "not_actionable")
    let response = ExploreServerError(error: .notActionable, message: "x")
    #expect(response.httpStatus == 200) // 业务码 HTTP 200
    let body = try #require(response.bodyJSON)
    #expect(try body.field("code") == .string("not_actionable"))
}
```

> 注：`ExploreServerError(error:message:)` 与 `bodyJSON` 沿用现有 core 测试模式；若签名不同，对齐 `Tests/iOSExploreServerTests/` 下已有错误码测试的写法。

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter ExploreErrorTests`
Expected: FAIL（`notActionable` 不存在）

- [ ] **Step 3: 实现——枚举加 case**

在 `ExploreError` 枚举（`Models.swift`，现有 case 如 `staleLocator = "stale_locator"` 附近）加：

```swift
/// 目标不可操作：该 path 未签发 fingerprint（minimal 结构节点），
/// ui.tap/ui.control.sendAction 无法对其派发动作。引导调用方在 ui.inspect 结果里
/// 找 availableActions 非空的目标。
case notActionable = "not_actionable"
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --filter ExploreErrorTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/iOSExploreServer/Models.swift Tests/iOSExploreServerTests/ExploreErrorTests.swift
git commit -m "feat(core): 新增 not_actionable 业务错误码，供 ui.inspect minimal 节点 tap 使用"
```

---

### Task 2: `UIKitCommandError` 加 notActionable 工厂 + staleLocator message 改名

**Files:**
- Modify: `Sources/iOSExploreUIKit/UIKitCommandError.swift`（staleLocator 工厂约 L39-43、message 约 L41）
- Test: `Tests/iOSExploreUIKitTests/UIKitCommandErrorTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `ExploreError.notActionable`
- Produces: `UIKitCommandError.notActionable(action:path:)` 工厂；staleLocator message 中 `ui.viewTargets` → `ui.inspect`

- [ ] **Step 1: 写失败测试**

```swift
import Testing
@testable import iOSExploreUIKit

@Test("notActionable 工厂生成 not_actionable 业务码")
func notActionableFactory() throws {
    let failure = UIKitCommandError.notActionable(action: "ui.tap", path: "root/5/0")
    #expect(failure.code == .notActionable)
    let response = failure.httpResponse()
    #expect(try response.bodyJSON?.field("code") == .string("not_actionable"))
}

@Test("staleLocator message 引导调用 ui.inspect")
func staleLocatorMessageReferencesInspect() throws {
    let failure = UIKitCommandError.staleLocator(action: "ui.tap", path: "root/1")
    let msg = try #require(failure.message)
    #expect(msg.contains("ui.inspect"))
    #expect(!msg.contains("ui.viewTargets"))
}
```

> `code`/`message`/`httpResponse` 字段名对齐现有 `UIKitCommandError` 测试；若为 `ExploreCommandFailure` 包装，按现有 staleLocator 测试的实际访问路径调整。

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter UIKitCommandErrorTests`
Expected: FAIL（`notActionable` 工厂不存在；staleLocator message 仍是旧文案）

- [ ] **Step 3: 实现**

参照现有 `staleLocator` 工厂模式新增：

```swift
/// minimal 结构节点被 tap/control 时的失败：该 path 未签发 fingerprint，
/// 引导调用方在 ui.inspect 结果里找 availableActions 非空的目标。
static func notActionable(action: String, path: String) -> ExploreCommandFailure {
    UIKitCommandError(code: .notActionable,
                      message: "节点 \(path) 不可操作（availableActions 为空）。请在 ui.inspect 结果里找 availableActions 非空的目标再操作。",
                      logMessage: "uikit not_actionable action=\(action) path=\(path)")
}
```

把 staleLocator 的 message 中 `"call ui.viewTargets first"` 改为 `"call ui.inspect first"`（精确替换 `ui.viewTargets` → `ui.inspect`，保留其余文案）。

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter UIKitCommandErrorTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/iOSExploreUIKit/UIKitCommandError.swift Tests/iOSExploreUIKitTests/UIKitCommandErrorTests.swift
git commit -m "feat(uikit/error): 新增 notActionable 工厂，staleLocator message 改引导 ui.inspect"
```

---

### Task 3: `UIViewTargetCandidate` 删死字段 + `shouldInclude` → `isFull`

**Files:**
- Modify: `Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsModels.swift`（`UIViewTargetsInput` Fields/属性/init/parse 约 L10-164、`UIViewTargetCandidate` 约 L171-227、`shouldInclude` 约 L137-145）
- Test: `Tests/iOSExploreUIKitTests/UIViewTargetsInputTests.swift`、`Tests/iOSExploreUIKitTests/UIViewTargetCandidateTests.swift`

**Interfaces:**
- Produces: `UIViewTargetsInput` 不再有 `includeStaticText`/`includeContainers`/`includeDisabled`；`UIViewTargetCandidate` 不再有 `isEnabled`/`hasSubviews`；新增 `UIViewTargetsInput.isFull(candidate:) -> Bool`

- [ ] **Step 1: 写失败测试——isFull 六条规则**

```swift
import Testing
@testable import iOSExploreUIKit

private func candidate(isControl: Bool = false, isScrollView: Bool = false,
                       hasGestureRecognizers: Bool = false, hasStaticText: Bool = false,
                       hasAccessibilityLabel: Bool = false, hasAccessibilityIdentifier: Bool = false) -> UIViewTargetCandidate {
    UIViewTargetCandidate(isHidden: false, isControl: isControl, isEnabled: true,
                          isUserInteractionEnabled: true, hasGestureRecognizers: hasGestureRecognizers,
                          hasAccessibilityIdentifier: hasAccessibilityIdentifier, hasAccessibilityLabel: hasAccessibilityLabel,
                          hasStaticText: hasStaticText, isScrollView: isScrollView)
}

@Test("isFull: 任一识别/可操作条件为 true 即 full")
func isFullRules() throws {
    let input = UIViewTargetsInput()
    #expect(input.isFull(candidate: candidate(isControl: true)))
    #expect(input.isFull(candidate: candidate(isScrollView: true)))
    #expect(input.isFull(candidate: candidate(hasGestureRecognizers: true)))
    #expect(input.isFull(candidate: candidate(hasStaticText: true)))
    #expect(input.isFull(candidate: candidate(hasAccessibilityLabel: true)))
    #expect(input.isFull(candidate: candidate(hasAccessibilityIdentifier: true)))
}

@Test("isFull: 全 false 即 minimal")
func isFullMinimal() throws {
    let input = UIViewTargetsInput()
    #expect(input.isFull(candidate: candidate()) == false)
}

@Test("UIViewTargetsInput 不再声明 includeStaticText/includeContainers/includeDisabled")
func deadFieldsRemoved() throws {
    // 解析空对象应成功，且不识别这三个字段
    let input = try UIViewTargetsInput.parseFromJSON("{}")
    #expect(input.maxTargets == 200) // 默认值仍在
    // 未知字段应被拒绝（additionalProperties: false）
    #expect(throws: (any Error).self) {
        try UIViewTargetsInput.parseFromJSON(#"{"includeStaticText": true}"#)
    }
}
```

> `parseFromJSON` 是测试便利方法，沿用现有 input 测试模式（若现有测试用 `CommandInputDecoder` 直接构造，按其模式调整）。

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter UIViewTargetsInputTests`
Expected: FAIL（`isFull` 不存在；旧字段还在）

- [ ] **Step 3: 实现——删字段 + 改判定**

(a) `UIViewTargetsInput`：删除 `Fields.includeStaticText`/`includeDisabled`/`includeContainers` 三组声明（声明 + `all` 数组条目 + 属性 + init 参数 + parse 读取）。保留 `includeHidden`/`maxDepth`/`accessibilityIdentifier`/`accessibilityIdentifierPrefix`/`textLimit`/`maxTargets`。

(b) `UIViewTargetCandidate`：删除 `isEnabled`（L177）和 `hasSubviews`（L189）属性 + init 参数。注意 `UIViewTargetState.isEnabled`（在 summary 模型内）是另一个字段，**不要动**。

(c) `shouldInclude` 改名为 `isFull`，规则扩为六条：

```swift
/// 判定节点是 full（带识别信息或可操作）还是 minimal（仅结构）。
///
/// full = isControl ∪ isScrollView ∪ hasGestureRecognizers ∪ hasStaticText
///        ∪ hasAccessibilityLabel ∪ hasAccessibilityIdentifier
/// full 节点签发 fingerprint、可被 ui.tap/ui.control.sendAction 操作；
/// minimal 节点只输出 path+type 维持层级，强制 actions=[]、不签发。
public func isFull(candidate: UIViewTargetCandidate) -> Bool {
    if !includeHidden, candidate.isHidden { return false }
    return candidate.isControl || candidate.isScrollView || candidate.hasGestureRecognizers
        || candidate.hasStaticText || candidate.hasAccessibilityLabel || candidate.hasAccessibilityIdentifier
}
```

(d) collector L152-156 构造 candidate 的地方同步删 `isEnabled`/`hasSubviews` 两个参数（isHidden/isControl/isUserInteractionEnabled/hasGestureRecognizers/hasAccessibilityIdentifier/hasAccessibilityLabel/hasStaticText/isScrollView 保留）。

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter UIViewTargetsInputTests` 和 `swift test --filter UIViewTargetCandidateTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsModels.swift Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsCollector.swift Tests/iOSExploreUIKitTests/
git commit -m "refactor(uikit/viewTargets): shouldInclude→isFull 六条判定，删 includeStaticText/includeContainers/includeDisabled 与 candidate 死字段"
```

---

### Task 4: `UIViewTargetSummary` 加 isMinimal + toJSON 分档

**Files:**
- Modify: `Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsModels.swift`（`UIViewTargetSummary` 约 L314-441、`toJSON` 约 L410-440）
- Test: `Tests/iOSExploreUIKitTests/UIViewTargetSummaryTests.swift`

**Interfaces:**
- Produces: `UIViewTargetSummary(isMinimal:)` 新增带默认值的 init 参数（`= false`，不破坏现有构造点）；`toJSON` minimal 档只输出 `{path, type}`

- [ ] **Step 1: 写失败测试**

```swift
import Testing
@testable import iOSExploreUIKit

@Test("minimal summary toJSON 只含 path + type")
func minimalToJSON() throws {
    let summary = UIViewTargetSummary(path: "root/5/0", type: "UITableViewCell",
                                      role: .container, /* 其余字段用现有 fixture 填 */ isMinimal: true)
    let json = try #require(summary.toJSON().field("path"))
    let keys = Set(summary.toJSON().objectValue!.keys)
    #expect(keys == ["path", "type"])
}

@Test("full summary toJSON 输出全部字段（与现状一致）")
func fullToJSON() throws {
    let summary = UIViewTargetSummary(path: "root/1", type: "UILabel", /* ... */ isMinimal: false)
    let keys = Set(summary.toJSON().objectValue!.keys)
    #expect(keys.contains("frame"))
    #expect(keys.contains("text"))
    #expect(keys.contains("availableActions"))
}
```

> summary 其余字段用现有测试 fixture 构造（`UIViewTargetSummary` 现有 init 模式）。若字段太多，建一个测试辅助函数 `makeSummary(...)`。

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter UIViewTargetSummaryTests`
Expected: FAIL（`isMinimal` 参数不存在）

- [ ] **Step 3: 实现**

(a) `UIViewTargetSummary` 加属性与 init 参数（默认值 `false`）：

```swift
/// 是否为 minimal 档（仅 path+type，不签 fingerprint、不可操作）。
/// collector 对无识别信息的结构节点置 true；toJSON 据此分档输出。
public let isMinimal: Bool
// init 末尾加：
public init(/* 现有参数 */, isMinimal: Bool = false) {
    /* 现有赋值 */
    self.isMinimal = isMinimal
}
```

(b) `toJSON` 开头加分档短路：

```swift
public func toJSON() -> JSON {
    if isMinimal {
        return [
            "path": .string(path),
            "type": .string(type),
        ]
    }
    // 现有完整输出逻辑保持不变
    return [ /* ...现有全部字段... */ ]
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter UIViewTargetSummaryTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsModels.swift Tests/iOSExploreUIKitTests/UIViewTargetSummaryTests.swift
git commit -m "feat(uikit/viewTargets): UIViewTargetSummary 加 isMinimal，toJSON 分档（minimal 只 path+type）"
```

---

### Task 5: `UIKitSnapshotStore.isPathSigned`（三态语义）

**Files:**
- Modify: `Sources/iOSExploreUIKit/Support/Snapshot/UIKitSnapshotStore.swift`（新增方法，建议放 `isStale` 附近 L292 后）
- Test: `Tests/iOSExploreUIKitTests/UIKitSnapshotStoreTests.swift`

**Interfaces:**
- Produces: `UIKitSnapshotStore.isPathSigned(viewSnapshotID:path:) -> Bool`

- [ ] **Step 1: 写失败测试（三态）**

```swift
import Testing
@testable import iOSExploreUIKit

@Test("isPathSigned: id 有效且 path 在表 → true")
func signedPath() async {
    let store = await UIKitSnapshotStore.testStore()
    let id = await store.insert(context: .test, targets: ["root/1": .test], query: .default)
    let signed = await store.isPathSigned(viewSnapshotID: try #require(id), path: "root/1")
    #expect(signed == true)
}

@Test("isPathSigned: id 有效但 path 不在表 → false（not_actionable 判据）")
func unsignedPath() async {
    let store = await UIKitSnapshotStore.testStore()
    let id = await store.insert(context: .test, targets: ["root/1": .test], query: .default)
    let signed = await store.isPathSigned(viewSnapshotID: try #require(id), path: "root/9")
    #expect(signed == false)
}

@Test("isPathSigned: unknown id → true（交 isStale 裁决 stale_locator，不误报 not_actionable）")
func unknownId() async {
    let store = await UIKitSnapshotStore.testStore()
    let signed = await store.isPathSigned(viewSnapshotID: "snap-nonexistent", path: "root/1")
    #expect(signed == true)
}
```

> `.testStore()`/`.default` 沿用现有 store 测试 fixture 模式（现有 `UIKitTargetFingerprint.test`/`UIKitSnapshotContext.test` 已有）。store 是 `@MainActor`，测试标 async 或 `@MainActor`。

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter UIKitSnapshotStoreTests`
Expected: FAIL（`isPathSigned` 不存在）

- [ ] **Step 3: 实现**

```swift
/// 查询 path 是否在指定快照的指纹表内（用于区分 not_actionable 与 stale_locator）。
///
/// **三态语义**：
/// - unknown/expired snapshotID（entries 无该 id）→ **true**：视为"可能签发过"，
///   交 `isStale` 裁决 stale_locator，引导 agent 重新 inspect；
/// - snapshotID 有效但 path 不在指纹表 → **false**：该 path 是 minimal 结构节点，
///   executor 据此返回 not_actionable。
///
/// 纯读，不改 LRU/TTL（保活由 isStale 在真正校验时更新）。
///
/// - Parameters:
///   - viewSnapshotID: 快照标识。
///   - path: 要查询的目标 path。
/// - Returns: true=视为已签发（含 unknown id）；false=id 有效但 path 未签发。
func isPathSigned(viewSnapshotID: String, path: String) -> Bool {
    guard let entry = entries[viewSnapshotID], !isExpired(entry: entry) else {
        return true // unknown/expired id → 交 isStale 裁决
    }
    return entry.fingerprints[path] != nil
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter UIKitSnapshotStoreTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/iOSExploreUIKit/Support/Snapshot/UIKitSnapshotStore.swift Tests/iOSExploreUIKitTests/UIKitSnapshotStoreTests.swift
git commit -m "feat(uikit/snapshot): 新增 isPathSigned 三态查询，区分 not_actionable 与 stale_locator"
```

---

### Task 6: `UIViewTargetsCollector` 全节点 + 分档 + 签发只 full + 截断只数 full

**Files:**
- Modify: `Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsCollector.swift`（`collect(query:context:)` L39-90、`collect(view:...)` 递归 L104-139、L24 日志、L52-67 签发）
- Modify: `Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsModels.swift`（`UIViewTargetsInput` 加 `maxVisitedNodes` 字段，默认如 2000）
- Test: `Tests/iOSExploreUIKitTests/UIViewTargetsCollectorTests.swift`

**Interfaces:**
- Consumes: Task 3 `isFull`、Task 4 `UIViewTargetSummary(isMinimal:)`
- Produces: collector 输出全节点（full+minimal），fingerprint 只签 full，截断只数 full

- [ ] **Step 1: 写失败测试**

```swift
import Testing
@testable import iOSExploreUIKit

@Test("minimal 节点进 collected 但不签 fingerprint；full 签发")
func collectEmitsMinimalAndSignsFull() async {
    // 构造：UIView(root) - UILabel(full,text) - UIView(minimal) - UILabel(full,text)
    let root = UIView()
    let label1 = UILabel(); label1.text = "A"; root.addSubview(label1)
    let container = UIView(); root.addSubview(container)
    let label2 = UILabel(); label2.text = "B"; container.addSubview(label2)
    let context = UIKitContextProvider.Context(window: ..., rootViewController: ..., topViewController: ..., rootView: root)
    let data = UIViewTargetsCollector.collect(query: .default, context: context)
    let targets = data.targets
    // 两个 label（full）+ 一个 container（minimal）
    #expect(targets.contains { $0.type == "UILabel" && $0.text == "A" })
    #expect(targets.contains { $0.type == "UILabel" && $0.text == "B" })
    let minimal = targets.filter { $0.isMinimal }
    #expect(minimal.contains { $0.type == "UIView" })
    // minimal 的 availableActions 为空
    #expect(minimal.allSatisfy { $0.availableActions.isEmpty })
}
```

> `UIKitContextProvider.Context` 在测试里构造 window/rootViewController 的方式沿用现有 collector 测试（现有测试已用注入入口 `collect(query:context:)`）。`data.targets`/`$0.isMinimal` 访问路径按实际 summary 结构调整。

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter UIViewTargetsCollectorTests`
Expected: FAIL（minimal 节点未输出）

- [ ] **Step 3: 实现**

(a) `UIViewTargetsInput` 加 `maxVisitedNodes`（防深树失控）：

```swift
static let maxVisitedNodes = CommandFields.int("maxVisitedNodes", range: 100...20000, default: 2000,
    description: "DFS 访问节点上限，防深树失控，默认 2000")
// 属性 + init + parse + all 数组同步加
```

(b) `CollectedTarget` 加 `isFull` 标记：

```swift
private struct CollectedTarget {
    let summary: UIViewTargetSummary
    let view: UIView
    let isFull: Bool
}
```

(c) `collect(view:...)` 递归改为：**全节点收集，分档，截断只数 full**。新增 `fullCount` 计数（独立于 `collected.count`）：

```swift
private static func collect(view: UIView, rootView: UIView, window: UIWindow,
                            path: [Int], depth: Int, query: UIViewTargetsInput,
                            visitedNodeCount: inout Int, fullCount: inout Int,
                            collected: inout [CollectedTarget]) -> Bool {
    visitedNodeCount += 1
    if visitedNodeCount > query.maxVisitedNodes { return true } // 深树保护
    if !query.includeHidden, view.isHidden { return false }

    let isFull = query.isFull(candidate: makeCandidate(for: view))
    let matchesId = matchesIdentifier(view: view, query: query)
    // §3.10: identifier 筛选只影响 full 输出；minimal 结构节点不受筛用于维持层级
    if isFull && matchesId {
        let summary = summary(for: view, rootView: rootView, window: window, path: path, query: query, isMinimal: false)
        collected.append(CollectedTarget(summary: summary, view: view, isFull: true))
        fullCount += 1
        if fullCount >= query.maxTargets { return true } // 截断只数 full
    } else if !isFull {
        // minimal 结构节点：维持层级，不签发、强制 actions=[]
        let summary = minimalSummary(for: view, path: path)
        collected.append(CollectedTarget(summary: summary, view: view, isFull: false))
    }

    if let maxDepth = query.maxDepth, depth >= maxDepth { return false }
    for (index, child) in view.subviews.enumerated() {
        if collect(view: child, rootView: rootView, window: window, path: path + [index],
                   depth: depth + 1, query: query, visitedNodeCount: &visitedNodeCount,
                   fullCount: &fullCount, collected: &collected) { return true }
    }
    return false
}
```

(d) minimal summary 构造（强制 actions=[]）：

```swift
private static func minimalSummary(for view: UIView, path: [Int]) -> UIViewTargetSummary {
    UIViewTargetSummary(path: UIKitViewLookupTarget.pathString(from: path),
                        type: String(describing: Swift.type(of: view)),
                        role: role(for: view), /* 其余字段填默认值 */ isMinimal: true)
}
```

(e) 签发循环（L52-67）只对 full 签发：

```swift
let fingerprints = Dictionary(uniqueKeysWithValues:
    collected.filter { $0.isFull }.map { target in
        (target.summary.path,
         UIKitFingerprintCollector.fingerprint(for: target.view, path: target.summary.path,
                                                rootView: context.rootView, digest: digest))
    })
```

(f) 响应字段（L70-82）：`targetCount` 仍是 `collected.count`（全节点数），新增 `fullCount`/`minimalCount` 字段方便 agent 与日志：

```swift
"targetCount": .double(Double(collected.count)),
"fullCount": .double(Double(collected.filter { $0.isFull }.count)),
"minimalCount": .double(Double(collected.filter { !$0.isFull }.count)),
```

(g) L24 日志改为：

```swift
UIKitCommandLogging.info("command", "ui inspect collect mainactor start includeHidden=\(query.includeHidden) maxDepth=\(query.maxDepth.map(String.init) ?? "none") hasFilter=\(query.hasIdentifierFilter) textLimit=\(query.textLimit) maxVisitedNodes=\(query.maxVisitedNodes)")
```

L88 完成日志改为含 fullCount/minimalCount。

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter UIViewTargetsCollectorTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/iOSExploreUIKit/Commands/ViewTargets/ Tests/iOSExploreUIKitTests/UIViewTargetsCollectorTests.swift
git commit -m "feat(uikit/viewTargets): 全节点输出+full/minimal分档，签发只full，截断只数full，加maxVisitedNodes"
```

---

### Task 7: `UIKitActionExecutor` 前置 `isPathSigned`（not_actionable）

**Files:**
- Modify: `Sources/iOSExploreUIKit/Support/Action/UIKitActionExecutor.swift`（`validateViewSnapshot` 约 L97-112）
- Test: `Tests/iOSExploreUIKitTests/UIKitActionExecutorTests.swift`

**Interfaces:**
- Consumes: Task 5 `isPathSigned`、Task 2 `UIKitCommandError.notActionable`
- Produces: tap 和 control.sendAction 对未签发 path 返回 `not_actionable`

- [ ] **Step 1: 写失败测试**

```swift
@Test("minimal 节点 tap 返回 not_actionable")
func tapMinimalReturnsNotActionable() async throws {
    // 构造 snapshot 只签了 root/1（full），tap root/2（minimal）
    let store = UIKitSnapshotStore.shared
    // ... insert snapshot with only root/1 signed ...
    let failure = await UIKitActionExecutor.executeTap(path: "root/2", viewSnapshotID: signedId, ...)
    #expect(failure?.code == .notActionable)
}
```

> 沿用现有 executor 测试的 snapshot 注入与 executeTap 调用模式。

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter UIKitActionExecutorTests`
Expected: FAIL（minimal tap 现返回 stale_locator）

- [ ] **Step 3: 实现**

在 `validateViewSnapshot`（isStale 调用之前）插入：

```swift
// minimal 节点未签发 fingerprint → not_actionable（区别于 stale_locator 的快照陈旧）
// isPathSigned 对 unknown/expired id 返回 true（交 isStale 裁决），只有"id 有效 + path 未签发"才 false
guard UIKitSnapshotStore.shared.isPathSigned(viewSnapshotID: viewSnapshotID, path: path) else {
    throw UIKitCommandError.notActionable(action: action, path: path)
}
// 之后走现有 isStale freshness 校验
```

`validateViewSnapshot` 是 tap 和 control.sendAction 共用入口（确认两条路径都经此），一处插入即覆盖。

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter UIKitActionExecutorTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/iOSExploreUIKit/Support/Action/UIKitActionExecutor.swift Tests/iOSExploreUIKitTests/UIKitActionExecutorTests.swift
git commit -m "feat(uikit/action): tap/control 前置 isPathSigned，minimal 节点返回 not_actionable"
```

---

### Task 8: `UIKitFingerprintCollector` shouldInclude → isFull 改名连带

**Files:**
- Modify: `Sources/iOSExploreUIKit/Support/Snapshot/UIKitFingerprintCollector.swift`（`collectMatching` 约 L313-354，L328 调 shouldInclude）
- Test: `Tests/iOSExploreUIKitTests/UIKitFingerprintCollectorTests.swift`、`Tests/iOSExploreUIKitTests/UIWaitExecutorTests.swift`

**Interfaces:**
- Consumes: Task 3 `isFull`
- Produces: 重采口径与签发同（full 集合一致）

- [ ] **Step 1: 写测试——wait(snapshotChanged) 重采与签发同口径**

```swift
@Test("snapshotChanged 重采口径与签发一致（isFull 六条）")
func waitSnapshotChangedRecollectSameScope() async {
    // 签发一次 viewTargets → 改一个 full 节点的文字 → wait snapshotChanged 应报 changed
    // 不改任何东西 → 报 unchanged
    // 覆盖：cell 内 UILabel（hasStaticText）变化能被检测（v1 漏掉的场景）
}
```

- [ ] **Step 2: 运行确认状态**

Run: `swift test --filter UIKitFingerprintCollectorTests`
Expected: 编译 FAIL（L328 `shouldInclude` 已改名 isFull）

- [ ] **Step 3: 实现**

`collectMatching` L328 把 `UIViewTargetsCollector.shouldInclude(view:query:)` 改为 `query.isFull(candidate: UIViewTargetsCollector.makeCandidate(for: view))`（candidate 构造逻辑需从 collector 的 `shouldInclude` 内联或提取为 `makeCandidate(for:)` 模块内方法，供两处共用）。语义从"3 条白名单"扩到"6 条 full 判定"，collectMatching 签发范围随之与 viewTargets 签发完全一致。

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter UIKitFingerprintCollectorTests` 和 `swift test --filter UIWaitExecutorTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/iOSExploreUIKit/Support/Snapshot/UIKitFingerprintCollector.swift Tests/
git commit -m "refactor(uikit/fingerprint): collectMatching 改用 isFull，重采口径与签发一致"
```

---

### Task 9: 改名 `ui.viewTargets` → `ui.inspect`（command + registrar + 5 处字符串）

**Files:**
- Modify: `Sources/iOSExploreUIKit/Commands/ViewTargets/ViewTargetsCommand.swift`（actionName）
- Modify: `Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift`（注册注释/log）
- Modify: `Sources/iOSExploreUIKit/Support/Parsing/UIKitCommandFields.swift`（L58 path description、L69 viewSnapshotID description）
- Modify: `Sources/iOSExploreUIKit/Commands/Wait/UIWaitModels.swift`（L60 viewSnapshotID description）
- Modify: `Sources/iOSExploreUIKit/Commands/Tap/UITapModels.swift`（L32 extensionMessage）
- Modify: `Sources/iOSExploreUIKit/Commands/ControlAction/UIControlSendActionModels.swift`（L63 extensionMessage）
- Test: 全仓 grep `ui.viewTargets` 与 `viewTargets` 确认无遗漏

**Interfaces:**
- Produces: action 名 `ui.inspect`；动态工具名 `ui_inspect`

- [ ] **Step 1: grep 确认全部引用点**

Run: `grep -rn "ui\.viewTargets\|viewTargets" Sources/ Tests/ MCPServer/src/ Examples/ docs/ | grep -v "\.git"` 记录所有命中。

- [ ] **Step 2: 改 actionName + 注册**

`ViewTargetsCommand.swift`：`static let actionName = "ui.viewTargets"` → `"ui.inspect"`（同步改 `description` 文案，体现"当前页面探索主入口"）。

`UIKitCommandRegistrar.swift`：注册处注释/log 中 `ui.viewTargets` → `ui.inspect`。

- [ ] **Step 3: 改 5 处运行时字符串**（UIKitCommandError L41 已在 Task 2 改）

| 文件:行 | old 片段 | new 片段 |
|---|---|---|
| `UIKitCommandFields.swift:58` | `按 ui.viewTargets 或 ui.topViewHierarchy 返回的` | `按 ui.inspect 或 ui.topViewHierarchy 返回的` |
| `UIKitCommandFields.swift:69` | `ui.viewTargets 签发的` | `ui.inspect 签发的` |
| `UIWaitModels.swift:60` | `由 ui.viewTargets 签发` | `由 ui.inspect 签发` |
| `UITapModels.swift:32` | `must come from ui.viewTargets` | `must come from ui.inspect` |
| `UIControlSendActionModels.swift:63` | 同上 | 同上 |

- [ ] **Step 4: 改测试与文档引用**

测试里所有 `ui.viewTargets` action 名改 `ui.inspect`（grep 定位）。文档（AGENTS.md 命令清单、docs/uikit/*）留到 Task 11，但**测试此步必须改全**否则编译/断言失败。

- [ ] **Step 5: 运行测试**

Run: `swift test`
Expected: PASS（所有 viewTargets 测试已改 inspect）

- [ ] **Step 6: Commit**

```bash
git add Sources/iOSExploreUIKit/ Tests/
git commit -m "refactor(uikit): ui.viewTargets → ui.inspect 改名（command + 5 处运行时字符串）"
```

---

### Task 10: MCPServer staticTools——废弃 observe、wait_and_inspect、inspectOptions

**Files:**
- Modify: `MCPServer/src/staticTools.ts`（observe L82-92、wait_and_observe L93-112、schema L128-162）
- Modify: `MCPServer/tests/staticTools.test.ts`
- Build: `cd MCPServer && npm run build`

**Interfaces:**
- Produces: 移除 `observe`；`wait_and_observe` → `wait_and_inspect`（调 `ui.inspect`、`viewTargetsOptions`→`inspectOptions`）

- [ ] **Step 1: 写/改测试**

```typescript
// staticTools.test.ts
test("observe 已移除", () => {
  const tools = createStaticTools({ client, registry });
  expect(tools.observe).toBeUndefined();
});

test("wait_and_inspect 调用 ui.inspect", async () => {
  const calls: any[] = [];
  const tools = createStaticTools({ client: { call: async (a: string) => { calls.push(a); return a === "ui.waitAny" ? {} : { targets: [] }; } }, registry });
  await tools.wait_and_inspect.handler({ conditions: [{ id: "x", mode: "idle" }] });
  expect(calls).toContain("ui.inspect");
  expect(calls).not.toContain("ui.viewTargets");
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd MCPServer && npm test -- staticTools`
Expected: FAIL

- [ ] **Step 3: 实现**

(a) 删除 `observe` 工具定义（L82-92）+ `observeSchema()`（若仅 observe 用）。
(b) `wait_and_observe` 重命名为 `wait_and_inspect`，handler 内 `client.call("ui.viewTargets", ...)` → `client.call("ui.inspect", ...)`。
(c) schema 里 `viewTargetsOptions` → `inspectOptions`（字段名 + description）。
(d) `server.ts` 若有 observe 专用逻辑同步删。

- [ ] **Step 4: 运行确认通过**

Run: `cd MCPServer && npm test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add MCPServer/src/staticTools.ts MCPServer/src/server.ts MCPServer/tests/
git commit -m "refactor(mcp): 废弃 observe，wait_and_observe→wait_and_inspect（调 ui.inspect），viewTargetsOptions→inspectOptions"
```

---

### Task 11: 文档更新 + 端到端验证

**Files:**
- Modify: `AGENTS.md`（命令清单、模块边界中 viewTargets 描述）
- Modify: `docs/uikit/README.md`、`docs/uikit/uikit-file-reference.md`（ViewTargets 命令档案）
- Modify: `MCPServer/README.md`、`MCPServer/docs/local-mcp-test.md`（工具名映射表、示例）
- Modify: `docs/investigations/mcp-spim-example-e2e-issues.md`（P9 标记已修复，补 commit）

- [ ] **Step 1: 更新文档**

grep `docs/` 与 `AGENTS.md` 里所有 `ui.viewTargets`/`viewTargets`/`observe` 引用，按新命名与 full/minimal 两档语义更新（命令清单、模块边界、文件档案、工具名映射表）。补 `not_actionable` 错误码、`full/minimal` 字段、`isMinimal` 说明。

- [ ] **Step 2: 构建 + framework 测试**

Run: `xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: 全绿（含 cell 内 UILabel 进 full、minimal tap 返回 not_actionable 的 iOS 正向断言）

- [ ] **Step 3: 端到端——重做点击滚动测试 cell**

用 `MCPServer/scripts/mcp-inspector.mjs`（profile `sim-app`，App 以 `IOS_EXPLORE_AUTOSTART=1` 启动）：

```bash
cd MCPServer
# 1. ui_inspect 能看到 cell 文字
node scripts/mcp-inspector.mjs ui_inspect '{}'   # 期望：root/5/0/1/0 UILabel text="📜  滚动测试"
# 2. 直接 tap 该 UILabel path → push 到 ScrollTestViewController
node scripts/mcp-inspector.mjs ui_tap '{"path":"root/5/0/1/0","viewSnapshotID":"<上步的snap>"}'
# 3. 验证跳转
node scripts/mcp-inspector.mjs ui_inspect '{}'   # 期望 navigationBar.topViewController=ScrollTestViewController
```

验证点：① cell 文字在 `ui_inspect` 直接可见；② 直接 tap label path 成功跳转（无需 topViewHierarchy 二次解析）；③ minimal 节点 tap 返回 `not_actionable`（可选验证：tap 一个 `root/5/0` minimal 节点）。

- [ ] **Step 4: 标记 P9 已修复**

`docs/investigations/mcp-spim-example-e2e-issues.md` P9 节补"已修复：<commit>"，修复概要表更新。

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md docs/ MCPServer/README.md MCPServer/docs/
git commit -m "docs: ui.inspect 重设计文档同步（full/minimal 两档、not_actionable、改名）+ P9 闭环"
```

---

## Self-Review

**Spec coverage**：spec 各节 → task 映射——
- §3.1 改名 → Task 9
- §3.2 全节点+两档+toJSON → Task 4/6
- §3.3 minimal 强制 actions=[] → Task 6（minimalSummary）
- §3.4 cell 内 UILabel 可 tap（cellAncestor 已有）→ Task 11 端到端验证
- §3.5 fingerprint 只签 full → Task 6
- §3.6 不变式 → Task 6（签发 filter full）
- §3.7 not_actionable → Task 1/2/5/7
- §3.8 删死字段 → Task 3
- §3.9 observe 废弃/wait_and_inspect → Task 10
- §3.10 matchesIdentifier 语义 → Task 6（isFull && matchesId 才 full 输出，minimal 不受筛）
- §4.1 影响面 → 全 task 覆盖
- §5 边界（maxVisitedNodes、matchesWholeTable）→ Task 6（maxVisitedNodes）；matchesWholeTable 为已知限制，Task 8 注释记录
- §7 验证计划 → 各 task 测试 + Task 11 端到端

**Type 一致性**：`isFull`（Task 3 定义）→ Task 6/8 调用一致；`isMinimal`（Task 4）→ Task 6 构造一致；`isPathSigned`（Task 5）→ Task 7 调用一致；`notActionable` 工厂（Task 2）→ Task 7 抛出一致；`CollectedTarget.isFull`（Task 6）签名贯穿签发 filter。

**Placeholder 扫描**：无 TBD/TODO；每步有实际代码或精确 old/new；测试代码可跑（fixture 沿用现有模式）。

## 执行顺序依赖

```
Task 1 (core error) ─┬─→ Task 2 (UIKitCommandError)
                     │
Task 3 (isFull) ─────┼─→ Task 6 (collector) ─→ Task 8 (fingerprint)
Task 4 (isMinimal) ──┘                  └─→ Task 7 (executor) ← Task 5 (isPathSigned) + Task 2
Task 9 (改名) 独立于 6/7，可并行或其后
Task 10 (MCP) 独立
Task 11 (文档+端到端) 最后
```

建议顺序：1→2→3→4→5→6→7→8→9→10→11。Task 9 改名会触发全量测试改名，放 collector/executor 稳定后做，减少中间编译断裂。
