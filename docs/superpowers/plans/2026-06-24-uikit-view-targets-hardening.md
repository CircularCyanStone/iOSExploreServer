# UIKit View Targets Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `ui.viewTargets` 建立有界输出与可验证快照，并修复 UIKit 动作能力、listener 生命周期和日志脱敏缺口。

**Architecture:** 查询在 MainActor 上以 `maxTargets` 短路遍历；每个返回 target 只存一条包含祖先摘要的 fingerprint，保证 512 条快照预算。`ExploreServer` 管理 listener 的停止完成状态，测试用显式屏障消除固定端口竞态。

**Tech Stack:** Swift 6.2 SPM、Swift Testing、UIKit（`#if canImport(UIKit)`）、Network/NWListener、现有 `Mutex`。

---

## 文件职责

- `Sources/iOSExploreUIKit/ViewTargets/UIViewTargetsModels.swift`：`maxTargets` 的 public 查询契约。
- `Sources/iOSExploreUIKit/ViewTargets/UIViewTargetsCollector.swift`：短路采集、响应截断元数据、有限 fingerprint 投影。
- `Sources/iOSExploreUIKit/Snapshot/UIKitSnapshotStore.swift`：context 持久化、祖先摘要 fingerprint 和 validation 契约。
- `Sources/iOSExploreUIKit/Snapshot/UIKitFingerprintCollector.swift`：在 MainActor 生成 target + ancestor digest。
- `Sources/iOSExploreUIKit/Action/UIKitActionCapabilityResolver.swift`：collector/executor 共用的祖先可交互性判定。
- `Sources/iOSExploreServer/ExploreServer.swift`、`HTTPListener.swift`：停止完成状态与无保留环 listener 回调。
- `Tests/iOSExploreServerTests/*`：Foundation、UIKit framework 和真实 TCP 验证。

### Task 1: 查询上限与快照值模型

**Files:**
- Modify: `Sources/iOSExploreUIKit/ViewTargets/UIViewTargetsModels.swift`
- Modify: `Sources/iOSExploreUIKit/Snapshot/UIKitSnapshotStore.swift`
- Modify: `Tests/iOSExploreServerTests/UIKitViewTargetsTests.swift`
- Modify: `Tests/iOSExploreServerTests/UIKitSnapshotTests.swift`

- [ ] **Step 1: 写失败的 Foundation-only 测试**

在 `UIKitViewTargetsTests.swift` 增加：

```swift
@Test("UIViewTargetsQuery 解析 maxTargets 默认值和边界")
func viewTargetsQueryParsesMaxTargets() {
    guard case .success(let defaultQuery) = UIViewTargetsQuery.parse(from: [:]) else {
        Issue.record("default query should parse"); return
    }
    #expect(defaultQuery.maxTargets == 200)
    for invalid: JSON in [["maxTargets": 0], ["maxTargets": 513], ["maxTargets": 1.5]] {
        guard case .failure = UIViewTargetsQuery.parse(from: invalid) else {
            Issue.record("invalid maxTargets accepted: \(invalid)"); return
        }
    }
}
```

在 `UIKitSnapshotTests.swift` 增加两个不同 context、相同 target 的 fixture，断言 validation 为 `.stale`；再构造 `ancestorDigest` 不同的 fingerprint，断言为 `.stale`。

- [ ] **Step 2: 验证测试失败**

Run: `swift test --filter UIKitViewTargetsTests --filter UIKitSnapshotTests`

Expected: FAIL，因为 `UIViewTargetsQuery` 没有 `maxTargets`，snapshot context 还未参与 validation。

- [ ] **Step 3: 最小实现 public 契约与固定预算 snapshot**

在 `UIViewTargetsQuery` 的最后一个 stored property 增加 `public let maxTargets: Int`，并把 initializer 的最后一个参数写为 `maxTargets: Int = 200`。解析使用既有安全整数工具：

```swift
let maxTargets: Int
if let raw = data["maxTargets"]?.doubleValue {
    guard let value = UIKitQueryNumber.integer(raw, in: 1...UIKitSnapshotStore.maxFingerprints) else {
        return .failure("maxTargets must be an integer between 1 and 512")
    }
    maxTargets = value
} else {
    maxTargets = 200
}
```

在 `UIKitTargetFingerprint` 增加 `ancestorDigest: UInt64`；在 `UIKitSnapshotContext` 增加 `windowIdentity`、`topViewControllerIdentity`；`Entry` 保存 `context`。将 validation 改为：

```swift
public func validation(snapshotID: String,
                       path: String,
                       context: UIKitSnapshotContext,
                       current: UIKitTargetFingerprint) -> UIKitSnapshotValidation {
    // unknown/expired/path-missing -> stale
    // entry.context != context -> stale
    // stored != current -> stale
}
```

保持 `maxFingerprints = 512`，每个返回 target 仅存一条 fingerprint，禁止再以“祖先链条数”消耗预算。

- [ ] **Step 4: 验证 Foundation 测试通过**

Run: `swift test --filter UIKitViewTargetsTests --filter UIKitSnapshotTests`

Expected: PASS。

- [ ] **Step 5: 提交值模型**

```bash
git add Sources/iOSExploreUIKit/ViewTargets/UIViewTargetsModels.swift \
        Sources/iOSExploreUIKit/Snapshot/UIKitSnapshotStore.swift \
        Tests/iOSExploreServerTests/UIKitViewTargetsTests.swift \
        Tests/iOSExploreServerTests/UIKitSnapshotTests.swift
git commit -m "feat: bound UIKit target query snapshots"
```

### Task 2: 有界 MainActor 采集与真实动作能力

**Files:**
- Modify: `Sources/iOSExploreUIKit/Snapshot/UIKitFingerprintCollector.swift`
- Modify: `Sources/iOSExploreUIKit/ViewTargets/UIViewTargetsCollector.swift`
- Modify: `Sources/iOSExploreUIKit/ViewTargets/ViewTargetsCommand.swift`
- Modify: `Sources/iOSExploreUIKit/Action/UIKitActionCapabilityResolver.swift`
- Modify: `Sources/iOSExploreUIKit/Action/UIKitActionExecutor.swift`
- Modify: `Tests/iOSExploreServerTests/UIKitActionCapabilityTests.swift`
- Modify: `Tests/iOSExploreServerTests/UIKitViewTargetsTests.swift`

- [ ] **Step 1: 写失败的 UIKit 能力测试**

在 `UIKitActionCapabilityTests.swift`（`#if canImport(UIKit)`）创建 root → container → button，分别设置 container 的 `isHidden`、`alpha = 0`、`isUserInteractionEnabled = false`，并断言：

```swift
#expect(UIKitActionCapabilityResolver.resolve(view: button,
                                              rootView: root,
                                              nearestControl: button).actions.isEmpty)
```

在 `UIKitViewTargetsTests.swift` 增加纯值断言，确认 `UIViewTargetSummary` 响应可表达 `maxTargets=2`、`truncated=true`、`truncationReason="maxTargets"`。

- [ ] **Step 2: 验证测试失败**

Run: `swift test --filter UIKitActionCapabilityTests --filter UIKitViewTargetsTests`

Expected: FAIL，因为 resolver 没有 `rootView` 参数，目标响应没有截断字段。

- [ ] **Step 3: 实现有限 projection 与短路遍历**

将 fingerprint collector 的入口改为接收 root、target、path 和 context；从 root 到 target 逐级混合稳定字段生成 `ancestorDigest`。context 通过：

```swift
UIKitSnapshotContext(windowIdentity: String(describing: ObjectIdentifier(context.window)),
                     topViewControllerIdentity: String(describing: ObjectIdentifier(context.topViewController)))
```

在 `UIViewTargetsCollector.collect` 维护 `limitReached`。递归函数返回 `Bool`：当 `targets.count == query.maxTargets` 后返回 `true`，父级立即停止枚举 sibling。仅对 append 后的 target 写入 `fingerprints[path]`；响应固定加入：

```swift
"maxTargets": .double(Double(query.maxTargets)),
"truncated": .bool(limitReached),
"truncationReason": limitReached ? .string("maxTargets") : .null,
"snapshotUnavailableReason": snapshotID == nil ? .string("fingerprintLimit") : .null,
```

把 resolver 统一为 `resolve(view:rootView:nearestControl:)`：从 view 向 root 检查 hidden、`alpha <= 0.01`、interaction；若未抵达 root 返回空；再检查实际 control enabled。collector 和 executor 都传入当前 `context.rootView`。

- [ ] **Step 4: 验证通过并检查 Swift 5 编译**

Run: `swift test --filter UIKitActionCapabilityTests --filter UIKitViewTargetsTests`

Expected: PASS。

- [ ] **Step 5: 提交 UIKit 采集修复**

```bash
git add Sources/iOSExploreUIKit/Snapshot/UIKitFingerprintCollector.swift \
        Sources/iOSExploreUIKit/ViewTargets/UIViewTargetsCollector.swift \
        Sources/iOSExploreUIKit/ViewTargets/ViewTargetsCommand.swift \
        Sources/iOSExploreUIKit/Action/UIKitActionCapabilityResolver.swift \
        Sources/iOSExploreUIKit/Action/UIKitActionExecutor.swift \
        Tests/iOSExploreServerTests/UIKitActionCapabilityTests.swift \
        Tests/iOSExploreServerTests/UIKitViewTargetsTests.swift
git commit -m "fix: bound UIKit target collection and capabilities"
```

### Task 3: listener 停止完成与端口复用

**Files:**
- Modify: `Sources/iOSExploreServer/HTTPListener.swift`
- Modify: `Sources/iOSExploreServer/ExploreServer.swift`
- Modify: `Tests/iOSExploreServerTests/IntegrationTests.swift`

- [ ] **Step 1: 写失败的 TCP 生命周期测试**

将集成测试的停止逻辑改为显式 await，并新增：

```swift
@Test("停止完成后新 server 可立即复用端口")
func stopAndWaitReleasesPort() async throws {
    let first = ExploreServer(port: testPort)
    try await first.start()
    await first.stopAndWait()
    let second = ExploreServer(port: testPort)
    try await second.start()
    await second.stopAndWait()
}
```

保留 retry helper 仅用于报告环境异常，但新测试不得调用它。

- [ ] **Step 2: 验证测试失败**

Run: `swift test --filter IntegrationTests.stopAndWaitReleasesPort`

Expected: FAIL，因为 `ExploreServer.stopAndWait()` 不存在。

- [ ] **Step 3: 实现停止状态机与弱回调**

在 `HTTPListener` 用 `Mutex` 保存 listener 生命周期、终态 continuation 列表与是否已终止；`stateUpdateHandler` 使用 `[weak self]`。`stopAndWait()` 调用 cancel 后 await 已注册的终态 continuation；收到 `.cancelled` 或 `.failed` 时在锁内取出并清空 waiter，锁外 resume，再把 `stateUpdateHandler = nil`。

`ExploreServer` 在 `stop()` 时保留 stopping listener；新增内部 `func stopAndWait() async` 供 `@testable` 测试使用。`start()` 发现 stopping listener 时先 await 它的终态，再新建 `HTTPListener`。所有 continuation 用 `didResume` 守卫，不能在 Mutex 内 await，不能新增 `@unchecked Sendable`。

- [ ] **Step 4: 验证真实 TCP 测试通过**

Run: `swift test --filter IntegrationTests`

Expected: PASS，且 suite 不再以 retry 作为正常端口释放路径。

- [ ] **Step 5: 提交 listener 修复**

```bash
git add Sources/iOSExploreServer/HTTPListener.swift \
        Sources/iOSExploreServer/ExploreServer.swift \
        Tests/iOSExploreServerTests/IntegrationTests.swift
git commit -m "fix: await listener shutdown before restart"
```

### Task 4: 日志脱敏、文档和全量验证

**Files:**
- Modify: `Sources/iOSExploreUIKit/Action/UIKitActionExecutor.swift`
- Modify: `Sources/iOSExploreUIKit/Utils/UIKitViewLookupModels.swift`
- Modify: `Sources/iOSExploreUIKit/UIKitCommandError.swift`
- Modify: `Tests/iOSExploreServerTests/ExploreLoggingTests.swift`
- Modify: `AGENTS.md`
- Modify: `docs/architecture/index.md`
- Modify: `docs/tools/network-tools.md`
- Modify: `docs/runbooks/build-and-test.md`
- Modify: `docs/runbooks/debugging.md`

- [ ] **Step 1: 写失败的日志脱敏测试**

在 `ExploreLoggingTests.swift` 注册 sink，传入随机 identifier `secret.identifier.9F8E7D` 的 locator 摘要，并断言记录包含 hash/长度、不包含原字符串：

```swift
#expect(records.joined(separator: "\n").contains("secret.identifier.9F8E7D") == false)
```

- [ ] **Step 2: 验证测试失败**

Run: `swift test --filter ExploreLoggingTests`

Expected: FAIL，因为现有 `locatorSummary` 会返回完整 identifier。

- [ ] **Step 3: 实现唯一日志摘要入口并同步文档**

在 `UIKitViewLookupModels.swift` 新增 `logSummary`，identifier 分支返回 `accessibilityIdentifierHash=<stableHash> length=<count>`；executor、command adapter 和 `UIKitCommandError` 的日志入参全部改用它。HTTP JSON 响应不改。

在 help/docs 写明 `maxTargets` 默认 200、范围 1...512、`truncated` 的保守语义、snapshot 不可用字段和 `stopAndWait` 仅测试内部使用。将 `AGENTS.md` 测试数更新为本次实际输出；debugging runbook 说明串行 suite 仍必须等待 listener 终态，不能只归因于并行。

- [ ] **Step 4: 全量验证**

Run:

```bash
swift test
xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj \
           -scheme iOSExploreServer -sdk iphonesimulator \
           -destination 'platform=iOS Simulator,name=iPhone 17' test
git diff --check
```

Expected: 所有测试通过、无 whitespace error；报告实际 macOS/iOS 测试数，不预填常量。

- [ ] **Step 5: 提交文档与日志修复**

```bash
git add Sources/iOSExploreUIKit/Action/UIKitActionExecutor.swift \
        Sources/iOSExploreUIKit/Utils/UIKitViewLookupModels.swift \
        Sources/iOSExploreUIKit/UIKitCommandError.swift \
        Tests/iOSExploreServerTests/ExploreLoggingTests.swift \
        AGENTS.md docs/architecture/index.md docs/tools/network-tools.md \
        docs/runbooks/build-and-test.md docs/runbooks/debugging.md
git commit -m "docs: document bounded UIKit target discovery"
```

## Plan self-review

- Spec coverage: Task 1 fixes public bounds and fixed snapshot storage; Task 2 makes collection and capability semantics match it; Task 3 owns listener cancellation; Task 4 prevents identifier logging and updates all user-facing guidance.
- Type consistency: `maxTargets` is always `Int`; context/fingerprint validation always receives both `UIKitSnapshotContext` and `UIKitTargetFingerprint`; `stopAndWait()` remains internal/test-visible.
- Scope: no cursor, no new UIKit action, no new unchecked sendability boundary.
