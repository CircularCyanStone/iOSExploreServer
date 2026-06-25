# UIKit Query Decode Builder 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用 `QueryDecoder` builder + tracing 把 `iOSExploreUIKit` 的 typed query parse 里重复的取值/校验样板声明式化，并补齐 `parameters` 漏声明（maxTargets、snapshotID ×2）。

**Architecture:** 新增 internal `QueryDecoder`（方法链封装取值/默认/范围/枚举校验，记 `accessedKeys`）；4 个 parse 拆双层（`parse(from:)` public 委托 `parse(decoding:)` internal）；互斥/成对/path 文法等**领域逻辑**保留手写（经 `d.data` 访问，不进 `accessedKeys`）；一致性测试（iOS）断言 `accessedKeys ⊆ parameters` 防漏声明。

**Tech Stack:** Swift 5.0 语言模式（SPM 6.2 + framework 5.0 双编译同一份 `Sources/`）、Swift Testing（`import Testing`）、Foundation + Network（core）。

## Global Constraints

- `SWIFT_VERSION=5.0`，无 Swift-6-only 语法，无 Macros。
- UIKit 类型绝不穿 public 边界；`QueryDecoder` 必须 Foundation-only + `Sendable`，不包 `#if canImport(UIKit)`。
- 错误统一 `QueryParseError`（不引 `DecodingError` 双轨制）。
- core `JSON`/`JSONValue` 非 Codable，本方案不给 core 加 Codable。
- **行为等价**：迁移后错误文案逐字保留，现有 parse 测试全绿。
- SPM 与 framework 共享同一份 `Sources/iOSExploreUIKit/`。
- 集成测试串行（端口 38399）。
- `QueryDecoder` 不记日志（错误归 command handler 单一出口）。
- 实现期检查：`parse(decoding:)` 勿误加 `public`（仅 `parse(from:)` public）。

## File Structure

- **Create** `Sources/iOSExploreUIKit/Utils/QueryDecoder.swift` — internal builder + `accessedKeys`（Foundation-only，不包 `#if`）。
- **Create** `Tests/iOSExploreServerTests/QueryDecoderTests.swift` — message 级单测（macOS，Foundation-only）。
- **Create** `Tests/iOSExploreServerTests/UIKitQueryKeyConsistencyTests.swift` — tracing 一致性测试（整体 `#if canImport(UIKit)`，iOS）。
- **Modify** `Sources/iOSExploreUIKit/ViewTargets/UIViewTargetsModels.swift` — parse 双层 + builder。
- **Modify** `Sources/iOSExploreUIKit/ViewTargets/ViewTargetsCommand.swift` — +maxTargets parameter。
- **Modify** `Sources/iOSExploreUIKit/ViewHierarchy/UIViewHierarchyModels.swift` — parse 双层 + builder + `UIViewHierarchyDetailLevel` CaseIterable。
- **Modify** `Sources/iOSExploreUIKit/ControlAction/UIControlSendActionModels.swift` — parse 双层 + builder + `UIControlSendActionEvent` CaseIterable。
- **Modify** `Sources/iOSExploreUIKit/ControlAction/UIControlSendActionCommand.swift` — +snapshotID parameter。
- **Modify** `Sources/iOSExploreUIKit/Tap/UITapModels.swift` — parse 双层 + snapshotID builder。
- **Modify** `Sources/iOSExploreUIKit/Tap/UITapCommand.swift` — +snapshotID parameter。

---

## Task 1: QueryDecoder 实现 + message 单测 + 骨架双编译

**Files:**
- Create: `Sources/iOSExploreUIKit/Utils/QueryDecoder.swift`
- Test: `Tests/iOSExploreServerTests/QueryDecoderTests.swift`

**Interfaces:**
- Produces: `struct QueryDecoder: Sendable`（internal），方法 `bool`/`string`/`optionalNonNegativeInt`/`rangedInt`/`enumValue`/`requiredEnum`（全 `mutating`），属性 `data: JSON`（internal let）+ `accessedKeys: Set<String>`（private(set) var）。被 Task 2-5 的 `parse(decoding:)` 消费。

- [ ] **Step 1: 写失败测试**

Create `Tests/iOSExploreServerTests/QueryDecoderTests.swift`:

```swift
import Testing
@testable import iOSExploreServer
@testable import iOSExploreUIKit

@Test("QueryDecoder bool 缺失或非布尔取默认值，并记录 key")
func queryDecoderBoolDefaults() {
    var missing = QueryDecoder([:])
    #expect(missing.bool("flag", default: true) == true)
    var nonBool = QueryDecoder(["flag": "yes"])
    #expect(nonBool.bool("flag", default: false) == false)
    var present = QueryDecoder(["flag": true])
    #expect(present.bool("flag", default: false) == true)
    #expect(present.accessedKeys == ["flag"])
}

@Test("QueryDecoder string 缺失返回 nil")
func queryDecoderStringOptional() {
    var missing = QueryDecoder([:])
    #expect(missing.string("name") == nil)
    var present = QueryDecoder(["name": "abc"])
    #expect(present.string("name") == "abc")
}

@Test("QueryDecoder optionalNonNegativeInt 文案与边界")
func queryDecoderOptionalNonNegativeInt() throws {
    var missing = QueryDecoder([:])
    #expect(try missing.optionalNonNegativeInt("depth") == nil)
    var valid = QueryDecoder(["depth": 5])
    #expect(try valid.optionalNonNegativeInt("depth") == 5)
    #expect(throws: QueryParseError("depth must be a non-negative integer")) {
        var d = QueryDecoder(["depth": -1])
        try d.optionalNonNegativeInt("depth")
    }
}

@Test("QueryDecoder rangedInt 文案与边界")
func queryDecoderRangedInt() throws {
    var missing = QueryDecoder([:])
    #expect(try missing.rangedInt("n", in: 1...200, default: 80) == 80)
    var valid = QueryDecoder(["n": 50])
    #expect(try valid.rangedInt("n", in: 1...200, default: 80) == 50)
    #expect(throws: QueryParseError("n must be an integer between 1 and 200")) {
        var d = QueryDecoder(["n": 201])
        try d.rangedInt("n", in: 1...200, default: 80)
    }
}

@Test("QueryDecoder enumValue 文案与默认")
func queryDecoderEnumValue() throws {
    enum Level: String, CaseIterable { case basic, appearance, full }
    var missing = QueryDecoder([:])
    #expect(try missing.enumValue("level", default: Level.appearance) == .appearance)
    var valid = QueryDecoder(["level": "basic"])
    #expect(try valid.enumValue("level", default: Level.appearance) == .basic)
    #expect(throws: QueryParseError("level must be one of basic, appearance, full")) {
        var d = QueryDecoder(["level": "nope"])
        try d.enumValue("level", default: Level.appearance)
    }
}

@Test("QueryDecoder requiredEnum 缺失与非法文案")
func queryDecoderRequiredEnum() throws {
    enum Event: String, CaseIterable { case touchDown, touchUpInside }
    #expect(throws: QueryParseError("missing required parameter 'event'")) {
        var d = QueryDecoder([:])
        _ = try d.requiredEnum("event") as Event
    }
    #expect(throws: QueryParseError("event must be one of touchDown, touchUpInside")) {
        var d = QueryDecoder(["event": "nope"])
        _ = try d.requiredEnum("event") as Event
    }
    var valid = QueryDecoder(["event": "touchUpInside"])
    let e: Event = try valid.requiredEnum("event")
    #expect(e == .touchUpInside)
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift test --filter QueryDecoderTests`
Expected: FAIL（编译错误：`QueryDecoder` 未定义）

- [ ] **Step 3: 实现 QueryDecoder**

Create `Sources/iOSExploreUIKit/Utils/QueryDecoder.swift`:

```swift
import Foundation
import iOSExploreServer

/// UIKit 命令参数的声明式取值器。
///
/// 把"从 `JSON` 按 key 取值 + 类型转换 + 默认值 + 范围/枚举校验 + 错误文案"封装成方法链，
/// 取代各 parse 里重复的 if-let/guard/?? 样板。内部失败统一抛 `QueryParseError`，
/// 文案可直接进入 `invalid_data` envelope。
///
/// 另负责 key 一致性追踪：每个读取方法记录 key 到 `accessedKeys`，供一致性测试断言
/// "走 builder 的 key ⊆ Command.parameters 声明的 key"（仅覆盖走 builder 的字段；
/// 部分迁 query 的手写领域 key 不覆盖，靠人 + review）。
///
/// `internal`：模块内 + `@testable` 测试使用，不进 public 表面。Foundation-only、`Sendable`，
/// 不携带 UIKit 类型；message 单测可在 macOS `swift test` 覆盖，一致性测试因读
/// `Command.parameters` 归 iOS framework test target。
struct QueryDecoder: Sendable {
    /// 待解码的命令 data（internal，供 `parse(decoding:)` 的手写领域字段直接访问，不进 `accessedKeys`）。
    let data: JSON
    /// 累积已读取的 key，供一致性测试断言 ⊆ `Command.parameters`。
    private(set) var accessedKeys: Set<String> = []

    /// 创建取值器。
    ///
    /// - Parameter data: `ExploreRequest.data`。
    init(_ data: JSON) { self.data = data }

    /// 布尔字段：缺失或非布尔都取默认值（保持现状语义，不抛错）。
    mutating func bool(_ key: String, default value: Bool) -> Bool {
        accessedKeys.insert(key)
        return data[key]?.boolValue ?? value
    }

    /// 可选字符串字段：缺失返回 nil。
    mutating func string(_ key: String) -> String? {
        accessedKeys.insert(key)
        return data[key]?.stringValue
    }

    /// 可选非负整数：缺失返回 nil；存在但非有限/非整数/为负抛错。
    mutating func optionalNonNegativeInt(_ key: String) throws -> Int? {
        accessedKeys.insert(key)
        guard let raw = data[key]?.doubleValue else { return nil }
        guard let value = UIKitQueryNumber.nonNegativeInteger(raw) else {
            throw QueryParseError("\(key) must be a non-negative integer")
        }
        return value
    }

    /// 限定范围整数：缺失取默认；存在但越界/非整数抛错。
    mutating func rangedInt(_ key: String, in range: ClosedRange<Int>, default value: Int) throws -> Int {
        accessedKeys.insert(key)
        guard let raw = data[key]?.doubleValue else { return value }
        guard let parsed = UIKitQueryNumber.integer(raw, in: range) else {
            throw QueryParseError("\(key) must be an integer between \(range.lowerBound) and \(range.upperBound)")
        }
        return parsed
    }

    /// String 原始值枚举（带默认）：缺失取默认；存在但非合法抛错。
    mutating func enumValue<E: RawRepresentable & CaseIterable>(_ key: String, default value: E) throws -> E
        where E.RawValue == String {
        accessedKeys.insert(key)
        guard let raw = data[key]?.stringValue else { return value }
        guard let parsed = E(rawValue: raw) else {
            throw QueryParseError("\(key) must be one of \(E.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        return parsed
    }

    /// 必填 String 原始值枚举：缺失抛 "missing required parameter"；非合法抛 must be one of。
    mutating func requiredEnum<E: RawRepresentable & CaseIterable>(_ key: String) throws -> E
        where E.RawValue == String {
        accessedKeys.insert(key)
        guard let raw = data[key]?.stringValue else {
            throw QueryParseError("missing required parameter '\(key)'")
        }
        guard let parsed = E(rawValue: raw) else {
            throw QueryParseError("\(key) must be one of \(E.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        return parsed
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift test --filter QueryDecoderTests`
Expected: PASS（6 个测试全绿）

- [ ] **Step 5: 骨架双编译验证**

Run: `xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator build`
Expected: BUILD SUCCEEDED（验证 `mutating struct` + `private(set) var` + `inout`/泛型 `where` 方法在 framework 5.0 编译通过；`UIKitActionKind.swift` 已用 `\.rawValue` keypath 佐证，但带 `where` 的泛型方法仍先实测）

- [ ] **Step 6: Commit**

```bash
git add Sources/iOSExploreUIKit/Utils/QueryDecoder.swift Tests/iOSExploreServerTests/QueryDecoderTests.swift
git commit -m "feat(uikit): 新增 QueryDecoder builder 统一参数取值/校验"
```

---

## Task 2: UIViewTargetsQuery 迁移 + maxTargets parameter + 一致性测试

**Files:**
- Modify: `Sources/iOSExploreUIKit/ViewTargets/UIViewTargetsModels.swift`（替换 `parse(from:)`，约 89-131 行）
- Modify: `Sources/iOSExploreUIKit/ViewTargets/ViewTargetsCommand.swift`（parameters 数组加 maxTargets）
- Create: `Tests/iOSExploreServerTests/UIKitQueryKeyConsistencyTests.swift`

**Interfaces:**
- Consumes: `QueryDecoder`（Task 1）
- Produces: `UIViewTargetsQuery.parse(decoding:)`（internal，供 Task 2 一致性测试）

- [ ] **Step 1: 写失败测试（一致性测试）**

Create `Tests/iOSExploreServerTests/UIKitQueryKeyConsistencyTests.swift`:

```swift
#if canImport(UIKit)
import Testing
@testable import iOSExploreServer
@testable import iOSExploreUIKit

@Test("ui.viewTargets parse 读取的 builder key 全部声明在 parameters")
func viewTargetsKeysCoveredByParameters() throws {
    var d = QueryDecoder([:])
    _ = try UIViewTargetsQuery.parse(decoding: &d)
    let params = Set(ViewTargetsCommand().parameters.map(\.name))
    #expect(d.accessedKeys.isSubset(of: params))
}
#endif
```

- [ ] **Step 2: 迁移 parse + 补 parameter**

在 `UIViewTargetsModels.swift`，用以下替换整个 `parse(from:)` 方法（89-131 行）：

```swift
    /// 从命令 data 解析查询参数。
    ///
    /// - Parameter data: `ExploreRequest.data`。
    /// - Returns: 解析出的查询对象。
    /// - Throws: `QueryParseError`，文案可直接放入 `invalid_data`。
    public static func parse(from data: JSON) throws -> UIViewTargetsQuery {
        var d = QueryDecoder(data)
        return try parse(decoding: &d)
    }

    /// 按 `QueryDecoder` 读取字段（供一致性测试拿 `accessedKeys`）。
    static func parse(decoding d: inout QueryDecoder) throws -> UIViewTargetsQuery {
        UIViewTargetsQuery(
            includeHidden: d.bool("includeHidden", default: false),
            includeDisabled: d.bool("includeDisabled", default: true),
            includeStaticText: d.bool("includeStaticText", default: false),
            includeContainers: d.bool("includeContainers", default: false),
            maxDepth: try d.optionalNonNegativeInt("maxDepth"),
            accessibilityIdentifier: d.string("accessibilityIdentifier"),
            accessibilityIdentifierPrefix: d.string("accessibilityIdentifierPrefix"),
            textLimit: try d.rangedInt("textLimit", in: 1...200, default: 80),
            maxTargets: try d.rangedInt("maxTargets", in: 1...UIKitSnapshotLimits.maxFingerprints, default: 200)
        )
    }
```

在 `ViewTargetsCommand.swift` 的 `parameters` 数组末尾（`textLimit` 的 `CommandParameter(...)` 之后、`]` 之前）追加：

```swift
        CommandParameter(name: "maxTargets",
                         kind: .number,
                         required: false,
                         description: "单次响应最多返回的目标数, 默认 200, 上限 512"),
```

- [ ] **Step 3: 跑行为等价测试（macOS）**

Run: `swift test --filter UIKitViewTargetsTests`
Expected: PASS（现有测试逐字绿：`viewTargetsQueryParsesDefaultsAndFilters` / `viewTargetsQueryRejectsInvalidNumbers` / `viewTargetsQueryParsesMaxTargets` / `viewTargetsQueryRejectsOutOfRangeNumbers` 文案不变）

- [ ] **Step 4: Commit**

```bash
git add Sources/iOSExploreUIKit/ViewTargets/UIViewTargetsModels.swift Sources/iOSExploreUIKit/ViewTargets/ViewTargetsCommand.swift Tests/iOSExploreServerTests/UIKitQueryKeyConsistencyTests.swift
git commit -m "refactor(uikit): UIViewTargetsQuery 改用 QueryDecoder，补 maxTargets parameter"
```

> 注：一致性测试（`#if canImport(UIKit)`）在 macOS `swift test` 下被跳过，红绿在 Task 6 framework `xcodebuild test` 统一验证。

---

## Task 3: UIViewHierarchyQuery 迁移 + detailLevel CaseIterable + 一致性测试

**Files:**
- Modify: `Sources/iOSExploreUIKit/ViewHierarchy/UIViewHierarchyModels.swift`（`UIViewHierarchyDetailLevel` 加 CaseIterable + 注释；替换 `parse(from:)`，约 393-421 行）
- Modify: `Tests/iOSExploreServerTests/UIKitQueryKeyConsistencyTests.swift`（加 hierarchy 一致性测试）

**Interfaces:**
- Consumes: `QueryDecoder`（Task 1）

- [ ] **Step 1: 加一致性测试**

在 `UIKitQueryKeyConsistencyTests.swift` 的 `#if canImport(UIKit)` 块内追加：

```swift
@Test("ui.topViewHierarchy parse 读取的 builder key 全部声明在 parameters")
func topViewHierarchyKeysCoveredByParameters() throws {
    var d = QueryDecoder([:])
    _ = try UIViewHierarchyQuery.parse(decoding: &d)
    let params = Set(TopViewHierarchyCommand().parameters.map(\.name))
    #expect(d.accessedKeys.isSubset(of: params))
}
```

- [ ] **Step 2: detailLevel 加 CaseIterable + 勿重排注释**

在 `UIViewHierarchyModels.swift`，找到 `public enum UIViewHierarchyDetailLevel: String, Sendable {`（约 336 行），改为：

```swift
/// UI 层级采集的详情级别。
///
/// `basic` 只保留结构、布局和状态；`appearance` 增加文本、颜色、控件等常见验收字段；
/// `full` 预留给后续更高成本字段。第一版中 `appearance` 与 `full` 字段集合相同。
///
/// - Note: case 声明顺序即 `CaseIterable.allCases` 顺序，被 `QueryDecoder.enumValue`
///   的 "must be one of ..." 错误文案依赖，勿随意重排。
public enum UIViewHierarchyDetailLevel: String, Sendable, CaseIterable {
```

（保留原有 `basic`/`appearance`/`full` case 与各 case 注释不变）

- [ ] **Step 3: 迁移 parse**

在 `UIViewHierarchyModels.swift`，用以下替换整个 `parse(from:)` 方法（约 393-421 行）：

```swift
    /// 从命令 `data` 解析查询参数。
    ///
    /// - Parameter data: `ExploreRequest.data`。
    /// - Returns: 解析出的查询对象。
    /// - Throws: `QueryParseError`，文案可直接放入 `invalid_data`。
    public static func parse(from data: JSON) throws -> UIViewHierarchyQuery {
        var d = QueryDecoder(data)
        return try parse(decoding: &d)
    }

    /// 按 `QueryDecoder` 读取字段（供一致性测试拿 `accessedKeys`）。
    static func parse(decoding d: inout QueryDecoder) throws -> UIViewHierarchyQuery {
        UIViewHierarchyQuery(
            detailLevel: try d.enumValue("detailLevel", default: .appearance),
            maxDepth: try d.optionalNonNegativeInt("maxDepth"),
            includeHidden: d.bool("includeHidden", default: false),
            accessibilityIdentifier: d.string("accessibilityIdentifier"),
            accessibilityIdentifierPrefix: d.string("accessibilityIdentifierPrefix")
        )
    }
```

- [ ] **Step 4: 跑行为等价测试（macOS）**

Run: `swift test --filter UIKitViewHierarchyTests`
Expected: PASS（现有测试逐字绿：detailLevel 非法值文案仍为 "detailLevel must be one of basic, appearance, full"）

- [ ] **Step 5: Commit**

```bash
git add Sources/iOSExploreUIKit/ViewHierarchy/UIViewHierarchyModels.swift Tests/iOSExploreServerTests/UIKitQueryKeyConsistencyTests.swift
git commit -m "refactor(uikit): UIViewHierarchyQuery 改用 QueryDecoder，detailLevel 加 CaseIterable"
```

---

## Task 4: UIControlSendActionQuery 迁移 + event CaseIterable + snapshotID parameter + 一致性测试

**Files:**
- Modify: `Sources/iOSExploreUIKit/ControlAction/UIControlSendActionModels.swift`（`UIControlSendActionEvent` 加 CaseIterable + 注释；替换 `parse(from:)`，约 51-63 行）
- Modify: `Sources/iOSExploreUIKit/ControlAction/UIControlSendActionCommand.swift`（parameters 加 snapshotID）
- Modify: `Tests/iOSExploreServerTests/UIKitQueryKeyConsistencyTests.swift`（加 control 一致性测试）

**Interfaces:**
- Consumes: `QueryDecoder`（Task 1）

- [ ] **Step 1: 加一致性测试**

在 `UIKitQueryKeyConsistencyTests.swift` 的 `#if canImport(UIKit)` 块内追加：

```swift
@Test("ui.control.sendAction parse 读取的 builder key 全部声明在 parameters")
func controlSendActionKeysCoveredByParameters() throws {
    var d = QueryDecoder(["event": "touchUpInside", "path": "root"])
    _ = try UIControlSendActionQuery.parse(decoding: &d)
    let params = Set(UIControlSendActionCommand().parameters.map(\.name))
    #expect(d.accessedKeys.isSubset(of: params))
}
```

- [ ] **Step 2: event 加 CaseIterable + 勿重排注释**

在 `UIControlSendActionModels.swift`，找到 `public enum UIControlSendActionEvent: String, Sendable, Equatable {`（约 7 行），改为：

```swift
/// `ui.control.sendAction` 支持的 UIControl 事件名。
///
/// 该枚举保持 Foundation-only，UIKit 平台再把它映射为 `UIControl.Event`。
///
/// - Note: case 声明顺序即 `CaseIterable.allCases` 顺序，被 `QueryDecoder.requiredEnum`
///   的 "must be one of ..." 错误文案依赖，勿随意重排。
public enum UIControlSendActionEvent: String, Sendable, Equatable, CaseIterable {
```

（保留原有各 case 不变）

- [ ] **Step 3: 迁移 parse**

在 `UIControlSendActionModels.swift`，用以下替换整个 `parse(from:)` 方法（约 51-63 行）：

```swift
    /// 从命令 `data` 解析查询参数。
    ///
    /// - Parameter data: `ExploreRequest.data`。
    /// - Returns: 解析出的查询对象。
    /// - Throws: `QueryParseError`，文案可直接放入 `invalid_data`。
    public static func parse(from data: JSON) throws -> UIControlSendActionQuery {
        var d = QueryDecoder(data)
        return try parse(decoding: &d)
    }

    /// 按 `QueryDecoder` 读取 snapshotID/event；identifier/path 取值经 builder 但领域校验
    /// （互斥/path 文法）保留在 `UIKitViewLookupTarget.parse`。
    static func parse(decoding d: inout QueryDecoder) throws -> UIControlSendActionQuery {
        let snapshotID = d.string("snapshotID")
        let event: UIControlSendActionEvent = try d.requiredEnum("event")
        let target = try UIKitViewLookupTarget.parse(identifier: d.data["accessibilityIdentifier"]?.stringValue,
                                                     rawPath: d.data["path"]?.stringValue)
        return UIControlSendActionQuery(target: target, event: event, snapshotID: snapshotID)
    }
```

- [ ] **Step 4: 补 snapshotID parameter**

在 `UIControlSendActionCommand.swift` 的 `parameters` 数组中，`event` 的 `CommandParameter(...)` 之后追加：

```swift
        CommandParameter(name: "snapshotID",
                         kind: .string,
                         required: false,
                         description: "快照标识, 用于 path 定位的陈旧校验"),
```

- [ ] **Step 5: 跑行为等价测试（macOS）**

Run: `swift test --filter UIKitControlActionTests`
Expected: PASS（event 缺失文案 "missing required parameter 'event'"、非法值文案 "event must be one of touchDown, touchUpInside, valueChanged, editingChanged, editingDidBegin, editingDidEnd" 逐字保留）

- [ ] **Step 6: Commit**

```bash
git add Sources/iOSExploreUIKit/ControlAction/UIControlSendActionModels.swift Sources/iOSExploreUIKit/ControlAction/UIControlSendActionCommand.swift Tests/iOSExploreServerTests/UIKitQueryKeyConsistencyTests.swift
git commit -m "refactor(uikit): UIControlSendActionQuery 改用 QueryDecoder，补 snapshotID parameter"
```

---

## Task 5: UITapQuery 迁移 + snapshotID parameter + 一致性测试

**Files:**
- Modify: `Sources/iOSExploreUIKit/Tap/UITapModels.swift`（替换 `parse(from:)`，约 63-87 行）
- Modify: `Sources/iOSExploreUIKit/Tap/UITapCommand.swift`（parameters 加 snapshotID）
- Modify: `Tests/iOSExploreServerTests/UIKitQueryKeyConsistencyTests.swift`（加 tap 一致性测试）

**Interfaces:**
- Consumes: `QueryDecoder`（Task 1）

- [ ] **Step 1: 加一致性测试**

在 `UIKitQueryKeyConsistencyTests.swift` 的 `#if canImport(UIKit)` 块内追加：

```swift
@Test("ui.tap parse 读取的 builder key 全部声明在 parameters")
func tapKeysCoveredByParameters() throws {
    var d = QueryDecoder(["path": "root"])
    _ = try UITapQuery.parse(decoding: &d)
    let params = Set(UITapCommand().parameters.map(\.name))
    #expect(d.accessedKeys.isSubset(of: params))
}
```

- [ ] **Step 2: 迁移 parse**

在 `UITapModels.swift`，用以下替换整个 `parse(from:)` 方法（约 63-87 行）。snapshotID 走 builder；view-vs-point 互斥、x/y 成对、coordinateSpace 单值校验保留手写（经 `d.data` 访问，不进 `accessedKeys`）：

```swift
    /// 从命令 `data` 解析查询参数。
    ///
    /// - Parameter data: `ExploreRequest.data`。
    /// - Returns: 解析出的查询对象。
    /// - Throws: `QueryParseError`，文案可直接放入 `invalid_data`。
    public static func parse(from data: JSON) throws -> UITapQuery {
        var d = QueryDecoder(data)
        return try parse(decoding: &d)
    }

    /// snapshotID 走 builder；以下为领域逻辑（互斥/成对/coordinateSpace 单值校验），
    /// 保留手写，经 `d.data` 访问原始 data，不进 `accessedKeys`。
    static func parse(decoding d: inout QueryDecoder) throws -> UITapQuery {
        let snapshotID = d.string("snapshotID")
        let accessibilityIdentifier = d.data["accessibilityIdentifier"]?.stringValue
        let rawPath = d.data["path"]?.stringValue
        let x = d.data["x"]?.doubleValue
        let y = d.data["y"]?.doubleValue
        let coordinateSpace = d.data["coordinateSpace"]?.stringValue ?? "window"

        let hasViewTarget = accessibilityIdentifier != nil || rawPath != nil
        let hasPointTarget = x != nil || y != nil

        if hasViewTarget, hasPointTarget {
            throw QueryParseError("view target and coordinate target are mutually exclusive")
        }
        if hasPointTarget {
            guard let x, let y else {
                throw QueryParseError("x and y must be provided together")
            }
            guard coordinateSpace == "window" else {
                throw QueryParseError("coordinateSpace must be window")
            }
            return UITapQuery(target: .windowPoint(x: x, y: y), snapshotID: snapshotID)
        }

        let target = try UIKitViewLookupTarget.parse(identifier: accessibilityIdentifier, rawPath: rawPath)
        return UITapQuery(target: .view(target), snapshotID: snapshotID)
    }
```

- [ ] **Step 3: 补 snapshotID parameter**

在 `UITapCommand.swift` 的 `parameters` 数组中，`coordinateSpace` 的 `CommandParameter(...)` 之后追加：

```swift
        CommandParameter(name: "snapshotID",
                         kind: .string,
                         required: false,
                         description: "快照标识, 用于 path 定位的陈旧校验"),
```

- [ ] **Step 4: 跑行为等价测试（macOS）**

Run: `swift test --filter UIKitTapTests`
Expected: PASS（互斥/成对/coordinateSpace 文案逐字保留）

- [ ] **Step 5: Commit**

```bash
git add Sources/iOSExploreUIKit/Tap/UITapModels.swift Sources/iOSExploreUIKit/Tap/UITapCommand.swift Tests/iOSExploreServerTests/UIKitQueryKeyConsistencyTests.swift
git commit -m "refactor(uikit): UITapQuery snapshotID 改用 QueryDecoder，补 snapshotID parameter"
```

---

## Task 6: 全量验证 + 文档同步

**Files:**
- Verify: 全部测试 + framework
- Modify（视现状）: `docs/uikit/uikit-file-reference.md`（若记录 Utils 文件，补 QueryDecoder 条目）

- [ ] **Step 1: framework 全量测试（验证一致性测试 + iOS 正向注册断言）**

Run: `xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS（含 4 个一致性测试 + 原有 109 个 iOS 测试）

- [ ] **Step 2: SPM 全量测试（含集成 38399 串行）**

Run: `swift test`
Expected: PASS（macOS SPM 全绿；一致性测试因 `#if canImport(UIKit)` 在 macOS 跳过，行为等价测试全绿）

- [ ] **Step 3: 覆盖率**

Run: `swift test --enable-code-coverage`
Expected: 行覆盖率不低于现状基线（86.62%）；`QueryDecoder` 覆盖率应接近 100%

- [ ] **Step 4: 文档同步**

检查 `docs/uikit/uikit-file-reference.md`：若该档案记录 `Utils/` 下文件（如 `QueryParseError`/`UIKitQueryNumber`），补一条 `QueryDecoder` 的档案条目（职责、关键属性 `data`/`accessedKeys`、关键方法、不记日志说明）。若档案不逐文件记录 Utils，跳过。

- [ ] **Step 5: Commit**

```bash
git add docs/uikit/uikit-file-reference.md   # 若有改动
git commit -m "docs: UIKit 文件档案补 QueryDecoder"
```

---

## Self-Review 笔记

- **Spec 覆盖**：QueryDecoder（Task 1）、4 parse 迁移（Task 2-5）、2 enum CaseIterable（Task 3/4）、3 处 parameters 补漏（Task 2/4/5）、message 单测（Task 1）、tracing 一致性测试（Task 2-5 写入，Task 6 framework 验证）、骨架双编译（Task 1 Step 5）、全量验证（Task 6）—— spec B2 各项均有任务覆盖。
- **data 可见性**：spec 草案 `private let data` 已在计划编写时改为 internal（供部分迁 query 手写字段访问）；spec 文档已同步。
- **类型一致**：`parse(decoding d: inout QueryDecoder)` 全 4 个 query 签名一致；`accessedKeys` 贯穿；`QueryDecoder` 方法名（bool/string/optionalNonNegativeInt/rangedInt/enumValue/requiredEnum）全任务一致。
