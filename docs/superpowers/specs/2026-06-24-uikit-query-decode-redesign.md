# UIKit Query 解析重构设计

> 日期：2026-06-24
> 状态：路线 A 已落地（已提交）；路线 B2 已确认采用 QueryDecoder builder（待实现）
> 关联：`Sources/iOSExploreUIKit/**` 的 typed query 解析层

## 背景与现状

`iOSExploreUIKit` 的 4 个 `ui.*` 命令 + 2 个通用定位类型，各自手写了一套 `parse`，并各自定义了一个几乎逐字相同的 `XXXParseResult` 枚举。重复集中在 4 类东西：

| 重复类型 | 当前样子 | 出现位置 |
|---|---|---|
| 每命令一个 ParseResult enum（`success(T)/failure(String)`） | `UIViewTargetsQueryParseResult` / `UITapQueryParseResult` / `UIControlSendActionQueryParseResult` / `UIViewHierarchyQueryParseResult` / `UIKitLocatorParseResult` / `UIKitViewLookupTargetParseResult` | 6 处 |
| 类型转换 + 默认值样板 | `data["includeHidden"]?.boolValue ?? false`、`data["x"]?.stringValue` | 每个 parse |
| 整数范围校验样板 | `UIKitQueryNumber.integer(raw, in: 1...200)` + 手写错误文案 | textLimit / maxTargets / maxDepth |
| 裸 key 字符串散落 | `"maxDepth"`、`"textLimit"`、`"accessibilityIdentifier"`… | parse 里一份，`CommandParameter(name:)` 里又写一份 |

此外每个 command handler 的 `switch parse { case .success…/case .failure→invalidData→log→return }` 这段 ~8 行样板也逐字重复（4 处）。

### 现有边界类型（不在本次重构范围）

- `ExploreResult`（`Sources/iOSExploreServer/Models.swift`）— envelope 核心语义，`success(JSON)/failure(code:message:)`，failure 带 code + message 两段，是协议表达，不是"鸡肋的 success/failure(String)"。
- `HTTPParseResult`（`HTTPParser.swift`）— 三态机（complete/incomplete/invalid），不是二态 result。
- `UIKitContextProvider.currentContext()` 的结果（被 `UIKitActionExecutor`/各 Collector 匹配 `.success/.failure`）— 表达 window/controller/rootView 不可用，不是 parse result。

这三种保留，本文只针对"parse 参数的 `success(T)/failure(String)`"模式。

### core 的设计哲学

`Sources/iOSExploreServer/JSONCoder.swift:5` 明确写"库协议只需要动态 JSON 对象，不需要为每个命令定义 Codable 模型"。`JSON`/`JSONValue` 是自定义动态类型（非 Codable），`JSONCoder` 用 `JSONSerialization` 做 `JSON ↔ Data` 桥接。这是**有意为之**——动态 JSON 作为单一边界。任何 UIKit 侧的 Codable 改造都要考虑是否引入"core 动态 / UIKit Codable"双轨制。

---

## 前置决策：Swift 版本

### 澄清一个常见误解（保留为知识）

`SWIFT_VERSION = 5.0` **不等于**"只能用 Swift 5.0（2016 年）的特性"。在现代工具链（Xcode 16 / Swift 6.x 编译器）下，`SWIFT_VERSION = 5.0` 表示 **Swift 5 语言模式**，它启用 Swift 5.0 ~ 5.9 之间所有非 source-breaking 的语言特性（Property Wrappers 5.1、async/await 5.5、if/else 表达式 5.9 等）。它真正**只挡住**两样：typed throws、Swift 6 默认 strict concurrency。

iOS 版本与语言模式是两个独立维度：语言模式（`SWIFT_VERSION`）= 编译期，决定能用什么语法；Deployment Target（iOS 13）= 运行期，决定能调什么 API/runtime。iOS 13 内置 Swift 5.1 runtime，typed throws 这类编译期特性不依赖新 runtime。

### 结论：保持 `SWIFT_VERSION = 5.0`，不升级

已确认当前 `Sources/` **零处** Swift 6 独有语法（typed throws / `nonisolated(nonsending)` / `consuming`/`borrowing` 全无）。当前 SPM(6.2) 与 framework(5.0) 双模式编译同一份源码均通过，正是源码本身 5.x-safe 的证明。

既然没有用到任何 Swift 6 特性，**就没有理由为 typed throws 升级**——升级只徒增 strict concurrency 验证成本与维护面。本设计采用**普通 `throws`**（untyped），不升级 `SWIFT_VERSION`，不碰 `project.pbxproj`。

> 普通 throws 足以消除 result enum 样板、足以让嵌套 parse 自动传播。我们唯一的解析错误 `QueryParseError` 自己收敛成统一类型即可，不需要编译期类型绑定。

---

## 路线 A：普通 throws 统一（优先落地）

用 Swift 原生普通 `throws` 替代自定义 `success(T)/failure(String)` enum。保持 `SWIFT_VERSION=5.0`。

### 为什么 throws 优于自定义 result enum

自定义 `enum { success(T)/failure(String) }` 相比原生 throws 的劣势：

1. 每个类型都要重复定义一个 result enum（当前 6 份）。
2. 调用方要写 `switch` + 手动转发 failure（嵌套 parse 时尤其啰嗦）。
3. `snapshotID` 这种"从 result 里挖字段"的计算属性是补丁。
4. 无法用 `try` / `do-catch` / `try?` / `try!` 标准控制流。
5. 与 Swift 生态（Codable throws、标准库 throws）不一致。

throws 反过来：零样板定义、错误自动向上传播、标准控制流、生态一致。

### A1. 统一错误类型

新建 `Sources/iOSExploreUIKit/Utils/QueryParseError.swift`：

```swift
import Foundation

/// UIKit 命令参数解析失败的统一错误。
///
/// 所有 typed query 的 `parse` 用普通 throws 抛出本类型，错误在 command handler
/// 统一转成 `UIKitCommandError.invalidData`。保持 Foundation-only、Sendable，
/// 不携带 UIKit 类型，可在 macOS `swift test` 覆盖。
public struct QueryParseError: Error, Sendable, Equatable {
    /// 可直接放入 `invalid_data` envelope 的对外文案。
    public let message: String

    /// 创建一条参数解析错误。
    ///
    /// - Parameter message: 失败说明，进入 `invalid_data` envelope。
    public init(_ message: String) { self.message = message }
}
```

### A2. 6 个 parse 改普通 throws

| 类型 | 之前签名 | 之后签名 |
|---|---|---|
| `UIViewTargetsQuery` | `parse(from:) -> UIViewTargetsQueryParseResult` | `parse(from:) throws -> UIViewTargetsQuery` |
| `UIViewHierarchyQuery` | `parse(from:) -> UIViewHierarchyQueryParseResult` | `parse(from:) throws -> UIViewHierarchyQuery` |
| `UITapQuery` | `parse(from:) -> UITapQueryParseResult` | `parse(from:) throws -> UITapQuery` |
| `UIControlSendActionQuery` | `parse(from:) -> UIControlSendActionQueryParseResult` | `parse(from:) throws -> UIControlSendActionQuery` |
| `UIKitLocator` | `parse(identifier:path:x:y:) -> UIKitLocatorParseResult` | `parse(identifier:path:x:y:) throws -> UIKitLocator` |
| `UIKitViewLookupTarget` | `parse(identifier:rawPath:) -> UIKitViewLookupTargetParseResult` | `parse(identifier:rawPath:) throws -> UIKitViewLookupTarget` |

失败处由 `return .failure("...")` 改为 `throw QueryParseError("...")`。6 个 `XXXParseResult` enum **全部删除**。

### A3. 嵌套 parse 的自动传播（throws 的核心收益，普通 throws 即可）

普通 throws 让嵌套 parse 的错误**自动向上传播**，不再手写 `switch { case .failure(let msg) return .failure(msg) }` 转发。`UIKitViewLookupTarget.parse` 抛 `QueryParseError`，调用方 `try` 直接传播。

`UITapQuery.parse` 内部（`Sources/iOSExploreUIKit/Tap/UITapModels.swift`）：

```swift
// 之前
switch UIKitViewLookupTarget.parse(identifier: data["accessibilityIdentifier"]?.stringValue,
                                   rawPath: data["path"]?.stringValue) {
case .success(let target):
    return .success(UITapQuery(target: .view(target), snapshotID: snapshotID))
case .failure(let message):
    return .failure(message)
}

// 之后（错误自动传播）
let target = try UIKitViewLookupTarget.parse(identifier: data["accessibilityIdentifier"]?.stringValue,
                                             rawPath: data["path"]?.stringValue)
return UITapQuery(target: .view(target), snapshotID: snapshotID)
```

`UIKitLocator.parse`（内部调 `UIKitViewLookupTarget.parse`）、`UIControlSendActionQuery.parse` 同理简化。

### A4. snapshotID 计算属性删除

`UITapQueryParseResult.snapshotID` 和 `UIControlSendActionQueryParseResult.snapshotID` 这两个"从 result 挖字段"的计算属性删除。调用方 parse 成功后直接 `query.snapshotID`（`UITapQuery`/`UIControlSendActionQuery` 本身已有该属性）。

### A5. command handler 调用点统一（4 处）

每个 handler 的 `switch parse` 样板改成 `do/catch`，parse 错误与业务 result 分离：

```swift
// 之前（每个 handler ~8 行重复）
switch UIViewTargetsQuery.parse(from: request.data) {
case .success(let query):
    let result = await UIViewTargetsCollector.collect(query: query)
    switch result { case .success(let data): … log …; case .failure(let code, let message): … log … }
    return result
case .failure(let message):
    let error = UIKitCommandError.invalidData(action: action, message: message)
    UIKitCommandLogging.error("command", error.failure.logMessage)
    return error.result
}

// 之后：parse 单独 do/catch，业务逻辑放外面
UIKitCommandLogging.info("command", "command \(action) start payloadKeys=\(request.data.storage.count)")
let query: UIViewTargetsQuery
do {
    query = try UIViewTargetsQuery.parse(from: request.data)
} catch let parseError as QueryParseError {
    let error = UIKitCommandError.invalidData(action: action, message: parseError.message)
    UIKitCommandLogging.error("command", error.failure.logMessage)
    return error.result
}
let result = await UIViewTargetsCollector.collect(query: query)
switch result {
case .success(let data):
    let targetCount = data["targetCount"]?.doubleValue ?? 0
    UIKitCommandLogging.info("command", "command \(action) completed targetCount=\(targetCount)")
case .failure(let code, let message):
    UIKitCommandLogging.error("command", "command \(action) failed code=\(code.rawValue) message=\(message)")
}
return result
```

> 可选优化：把 `do { try parse } catch as QueryParseError { → invalidData → log → return }` 收敛成一个 helper（注意普通 throws 下错误类型是 `Error`，helper 内需 downcast）。先 do/catch，helper 作为后续。

### A6. 测试改动（机械替换）

成功断言：
```swift
// 之前
switch UIViewTargetsQuery.parse(from: [:]) {
case .success(let q): query = q
case .failure(let message): Issue.record(message); return
}
// 之后
let query = try UIViewTargetsQuery.parse(from: [:])
```

失败断言：
```swift
// 之前
guard case .failure = UIViewTargetsQuery.parse(from: ["maxDepth": -1]) else { Issue.record(…); return }
// 之后
#expect(throws: QueryParseError.self) { try UIViewTargetsQuery.parse(from: ["maxDepth": -1]) }
```

`==` 比较（`UIKitLocatorTests`）：
```swift
// 之前
#expect(UIKitLocator.parse(identifier: "home", path: nil, x: nil, y: nil) == .success(.accessibilityIdentifier("home")))
// 之后
let result = try UIKitLocator.parse(identifier: "home", path: nil, x: nil, y: nil)
#expect(result == .accessibilityIdentifier("home"))
```

snapshotID 断言（`UIKitSnapshotTests`）：
```swift
// 之前
#expect(UITapQuery.parse(from: ["path": "root/0", "snapshotID": "s1"]).snapshotID == "s1")
// 之后
#expect(try UITapQuery.parse(from: ["path": "root/0", "snapshotID": "s1"]).snapshotID == "s1")
```

涉及测试文件：`UIKitTapTests` / `UIKitViewTargetsTests` / `UIKitControlActionTests` / `UIKitViewHierarchyTests` / `UIKitLocatorTests` / `UIKitSnapshotTests` / `UIKitCollectorTests`。

### A7. 影响面汇总

| 改动项 | 文件 |
|---|---|
| 新增 `QueryParseError` | `Sources/iOSExploreUIKit/Utils/QueryParseError.swift` |
| 删除 6 个 ParseResult enum | 6 个 Models 文件 |
| 改 6 个 parse 签名为普通 throws | 6 个 Models 文件 |
| 改 4 个 command handler | `UITapCommand` / `UIControlSendActionCommand` / `TopViewHierarchyCommand` / `ViewTargetsCommand` |
| 简化 2 处嵌套 parse | `UITapModels` / `UIKitLocator` |
| 删 2 个 snapshotID 计算属性 | `UITapModels` / `UIControlSendActionModels` |
| 测试机械替换 | 7 个测试文件 |

**不动** `project.pbxproj`、不动 `SWIFT_VERSION`、不动版本约束文档。无 Swift-6-only 兼容问题。改完跑 `swift test`（含集成测试 38399 串行）+ framework `xcodebuild ... test`。

---

## 路线 B：声明式化取值/校验样板

> 状态：B1 否决、B2 已确认采用 QueryDecoder builder（本轮 brainstorming 确认，2026-06-24）。

用户提出：能否用 Codable 配合属性包装器，把手写解析进一步声明式化。下面分两个子路线分析。

### B1. 纯 Codable + property wrapper（不推荐）

思路：给 `JSON`/`JSONValue` 加 `Codable`，或经 `JSONCoder` → `Data` → `JSONDecoder`，让 query 模型直接 `Decodable`，用 `@Default`/`@Range` 等 property wrapper 表达默认值与范围。

可行性障碍：

| 障碍 | 说明 |
|---|---|
| **默认值** | Codable 合成在 key 缺失时 `keyNotFound`，不会调用 wrapper 的默认值。`@Default` 类 wrapper 需 wrapper 自身 `Codable` 且能从容器外感知缺失——Swift 合成 decoder 对每个 wrapper 字段调 `wrapper.init(from:)`，但 key 缺失时容器 decode 已失败，到不了 wrapper。社区 `@Default` 方案普遍要手写 `init(from:)` 或 `decodeIfPresent + ?? default`，又回到手写。 |
| **范围校验** | Codable 无法表达 `textLimit ∈ [1,200]`，decode 后仍需手写校验 + 手写错误文案。 |
| **互斥约束** | tap 的 view vs point、x/y 成对，完全无法用 Codable 表达，decode 后手写。 |
| **自定义错误文案** | `DecodingError` 暴露的是 `"Cannot initialize X from ..."`，不是 `"textLimit must be an integer between 1 and 200"`。要自定义就得手写 `init(from:)` + 重映射，等于两层拼接。 |
| **`JSONValue.double` 统一数字** | query 整数参数（maxDepth/textLimit）要从 `.double` 取整，标准 decoder 把 JSON 数字 decode 成 `Int` 时对 `3.0` 的处理依赖实现，需写桥接，绕一圈。 |

结论：纯 Codable + property wrapper 只能解决"基础类型转换"约 30%，核心复杂度（默认值/范围/互斥/错误文案）解决不了，硬上变成"Codable decode 一半 + 手写校验一半"两层拼接，错误处理被切成 `DecodingError` 与 `invalid_data` 两套，更碎。**不推荐。**

### B2. QueryDecoder builder（已确认采用）

> 决策日期：2026-06-24（本轮 brainstorming 确认载体）；建立在路线 A 已落地的 throws 统一之上。

#### 决策与三载体取舍

| 载体 | 结论 | 依据 |
|---|---|---|
| γ 纯 Codable | 否决 | 见 B1：core `JSON`/`JSONValue` 有意保持动态单边界、非 Codable；强行 Codable 化破坏 core 设计哲学，且 `JSONValue.double` 取整语义与标准 decoder 不一致。即便让 wrapper 自抛 `QueryParseError`，wrapper 自己就得手写取值+校验，等于自带 decode 驱动——不如直接写驱动，省掉 Codable 合成与 `DecodingError`/`QueryParseError` 双轨制。 |
| β property wrapper | 否决 | `SWIFT_VERSION=5.0`（无 Macros）下做不到"驱动自动遍历 wrapper 字段 decode"，逐字段调用省不掉（Codable 合成只是把逐字段代码藏进编译器，复杂度不消失）。外加每个 wrapper 的 `projectedValue`/`init(wrappedValue:)`/`decode` 样板，且跨字段约束（互斥/成对/path 文法）wrapper 无法表达、decode 后仍要手写。唯一收益（key 绑在属性声明处）在本场景换不回复杂度。 |
| **α QueryDecoder builder** | **采用** | 一个 Foundation-only 取值器，方法链封装"取值+类型转换+默认+范围+错误文案"，失败统一 `throw QueryParseError`。每字段一行，无注入次序问题、无重复默认值、无 projectedValue 杂技、错误文案可控、易单测。 |

> 反直觉要点：B2 的真实收益集中在 **ranged int**（maxDepth/textLimit/maxTargets，每字段 7~8 行 if-let/guard/throw → 1 行，单 `UIViewTargetsQuery.parse` 即净省 ~18 行）和 **enum + 默认**（detailLevel/event）。bool/string 样板本身很短、迁移后行数持平，但**仍全走 builder**——这是 key 防漏策略（tracing）的前提：`QueryDecoder` 靠记录每个读取方法访问的 key 覆盖走 builder 字段的漏声明（互斥/成对/path 文法等手写领域 key 不覆盖，见下"覆盖范围"），bool/string 若不走 builder，其 key 就进不了 `accessedKeys`。

#### 设计：`QueryDecoder`

新增 `Sources/iOSExploreUIKit/Utils/QueryDecoder.swift`，Foundation-only、`Sendable`、不包 `#if canImport(UIKit)`（与 `QueryParseError`/`UIKitQueryNumber` 同目录同边界，macOS `swift test` 可覆盖）。核心是 `UIKitQueryNumber`（已有范围校验）的一层声明式封装：

```swift
import Foundation
import iOSExploreServer

/// UIKit 命令参数的声明式取值器。
///
/// 把"从 `JSON` 按 key 取值 + 类型转换 + 默认值 + 范围/枚举校验 + 错误文案"封装成方法链，
/// 取代各 parse 里重复的 if-let/guard/?? 样板。内部失败统一抛 `QueryParseError`，
/// 文案可直接进入 `invalid_data` envelope。
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

> `enumValue`/`requiredEnum` 的文案依赖 `CaseIterable`：`UIViewHierarchyDetailLevel`、`UIControlSendActionEvent` 需补 `CaseIterable`（零成本，case 声明顺序即现有文案顺序，逐字一致）。

#### 日志策略（刻意不加日志）

`QueryDecoder` **不记日志**。理由：所有 parse 错误已在 command handler 的 `do/catch` 转成 `UIKitCommandError.invalidData` 并记 `command` category 日志（见 A5），decoder 再记会双重记录。decoder 只负责抛带对外文案的 `QueryParseError`，日志归 handler 层单一出口。符合 AGENTS.md"刻意不加日志须说明原因"。

#### 迁移边界（哪些迁 / 哪些保留手写）

| parse | 迁移程度 | 说明 |
|---|---|---|
| `UIViewTargetsQuery.parse` | 完全 | 3 ranged int（maxDepth/textLimit/maxTargets）+ 4 bool + 2 string 全迁 |
| `UIViewHierarchyQuery.parse` | 完全 | `enumValue` detailLevel + `optionalNonNegativeInt` maxDepth + bool + 2 string |
| `UIControlSendActionQuery.parse` | 部分 | snapshotID `string`、event `requiredEnum`；嵌套 `UIKitViewLookupTarget.parse` 保留 |
| `UITapQuery.parse` | 部分（仅 snapshotID） | 仅 snapshotID 迁 `string`；coordinateSpace 单值校验（文案 `"must be window"`，非 enum）、view-vs-point 互斥、x/y 成对均保留手写 |
| `UIKitViewLookupTarget.parse` | 不迁 | identifier/path 互斥 + `root/0/2` path 文法，多字段领域逻辑 |
| `UIKitLocator.parse` | 不迁 | 不直接吃 data（入参已拆为 `String?`/`Double?`），view/point 互斥 + x/y 成对，领域逻辑 |

边界原则：builder 只接手**单字段取值+校验**；**跨字段约束**（互斥/成对/path 文法）继续 `throw QueryParseError` 手写。这条边界护住 typed factory 硬规则——领域语义不被通用机制吞掉。

#### 行为等价约束（重构不改行为）

- bool：缺失或非布尔 → 默认（不报错）。（`JSONValue.boolValue` 是 `if case .bool` 精确匹配，非布尔返回 nil → 取默认，与现状逐字等价；同理 `doubleValue`/`stringValue` 类型不符返回 nil。）
- int/enum：缺失 → 默认（或 required 抛 missing）；存在但非法 → throw 文案。
- 文案逐字保留：`rangedInt`/`enumValue` 方法机械生成与现状相同的字符串。**两处隐式契约需显式锁定**：(a) `maxTargets` 现状文案硬编码 "512"，builder 绑定 `UIKitSnapshotLimits.maxFingerprints`（当前 == 512，逐字一致；常量变更时 builder 文案自动跟，比手写更正确）；(b) `event`/`detailLevel` 的 "must be one of ..." 文案依赖 `CaseIterable` allCases 顺序 = case 声明顺序，两个 enum 加注释"case 顺序即对外文案顺序，勿重排"。
- 现有测试大多只断言错误类型（`#expect(throws: QueryParseError.self)`）、不断言文案；**`QueryDecoderTests` 必须对每个方法的文案做 message 级断言**（`between X and Y`/`must be one of`/`missing required parameter 'X'`/`must be a non-negative integer`），弥补 per-query 测试只验类型的缺口。注意 `rangedInt` 文案含动态 `range.upperBound`（maxTargets 绑 `maxFingerprints` 常量），message 断言用 `message.contains("must be an integer between")` + 边界参数化，不锁死字面量上限（常量变更时文案应自动跟）。

#### before/after 样例

`UIViewTargetsQuery.parse` 的字段读取体（~43 行 → ~12 行）：

```swift
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
// parse(from:) 保持 public：var d = QueryDecoder(data); return try parse(decoding: &d)
```

#### key 双写收敛（c1：一致性测试 + 补漏）

读代码时发现**现存遗漏**——review 系统核对全部 4 个 Command 后确认为 3 处同型漏（不止 maxTargets）：

- `ViewTargetsCommand.parameters` 漏 `maxTargets`（parse 实际接受，1...512，默认 200）；
- `UITapCommand.parameters` 漏 `snapshotID`（`UITapQuery.parse` 读取，陈旧防护核心参数）；
- `UIControlSendActionCommand.parameters` 漏 `snapshotID`（`UIControlSendActionQuery.parse` 读取）。

`TopViewHierarchyCommand` 的 5 个声明 key 与 parse 读取完全对齐，无漏。三处都是"parse 接受的 key 未在 parameters 声明、help schema 缺该参数"，印证 key 双写会漏且非孤例。

收敛方案（最小且够用）：
1. 把 3 处漏声明补进各自 `parameters`：`maxTargets`→`ViewTargetsCommand`、`snapshotID`→`UITapCommand` + `UIControlSendActionCommand`。
2. **tracing 防漏（取代手维护期望 key 表）**：`QueryDecoder` 记录每个读取方法访问的 key 到 `accessedKeys`；每个 query 的 `parse` 拆为双层——`parse(from:)` 委托给 `parse(decoding: inout QueryDecoder)`（`parse(decoding:)` 为 internal，测试经 `@testable import`；`parse(from:)` 保持 public 供 command handler 调用），一致性测试注入 decoder 跑一次后断言 `d.accessedKeys ⊆ Set(command.parameters.map(\.name))`。走 builder 的字段加进 `accessedKeys`，漏声明立即报红，零手维护。

   **覆盖范围（诚实化）**：tracing 只覆盖**走 builder 的 key**。`UIViewTargetsQuery`/`UIViewHierarchyQuery` 完全迁 → 所有 key 进 `accessedKeys`，tracing 真保护。`UITapQuery`（仅 snapshotID 迁）/`UIControlSendActionQuery`（snapshotID+event 迁）的**手写领域 key**（coordinateSpace/x/y/identifier/path）不进 `accessedKeys`——这些是互斥/成对/path 文法领域逻辑，第一轮已确认在各自 `parameters` 声明无漏，靠人 + review 保证（tracing 不覆盖）。`UIKitViewLookupTarget`/`UIKitLocator` 不直接吃 data、无独立 `parameters`，不纳入。

   **测试 data（关键约束）**：tracing 测试必须让 parse **走到成功路径**，否则抛错时 `accessedKeys` 不完整、子集断言假绿。每个 query 最小成功 data：

   | Query | 最小成功 data | 说明 |
   |---|---|---|
   | `UIViewTargetsQuery` | `[:]` | 全可选/有默认 |
   | `UIViewHierarchyQuery` | `[:]` | detailLevel 默认 `.appearance` |
   | `UIControlSendActionQuery` | `["event":"touchUpInside","path":"root"]` | event 必填；需 identifier 或 path 喂 `UIKitViewLookupTarget.parse` |
   | `UITapQuery` | `["path":"root"]` | 需 view 或 point 定位，否则抛 "either...required" |

   **测试 target 归属**：4 个 Command 全 `#if canImport(UIKit)` 守卫，`Command.parameters` 在 macOS `swift test` 不可见 → 一致性测试归 **iOS framework test target**；macOS SPM test 只跑 `QueryDecoder` message 级单测 + query parse 行为等价测（query 模型 Foundation-only）。

```swift
// parse 双层：from 保持 public（command handler 调用），decoding 为 internal 测试入口
public static func parse(from data: JSON) throws -> UIViewTargetsQuery {
    var d = QueryDecoder(data)
    return try parse(decoding: &d)
}
static func parse(decoding d: inout QueryDecoder) throws -> UIViewTargetsQuery {
    UIViewTargetsQuery(
        includeHidden: d.bool("includeHidden", default: false),
        ...
        textLimit: try d.rangedInt("textLimit", in: 1...200, default: 80),
        maxTargets: try d.rangedInt("maxTargets", in: 1...UIKitSnapshotLimits.maxFingerprints, default: 200)
    )
}

// 一致性测试（iOS framework test target，@testable import iOSExploreUIKit）
@Test func viewTargetsKeysCovered() throws {
    var d = QueryDecoder([:])                 // UIViewTargetsQuery 全可选，[:] 够
    _ = try UIViewTargetsQuery.parse(decoding: &d)
    let params = Set(ViewTargetsCommand().parameters.map(\.name))
    #expect(d.accessedKeys.isSubset(of: params))   // snapshotID/maxTargets 这类漏声明报红
}
```

不自动从元数据生成 `parameters`（无 Macros 不可行/脆弱，YAGNI）；暂不引入 per-command `Key` enum（c2，c1 测试已够防漏）。

#### 改动面

| 改动 | 文件 |
|---|---|
| 新增 `QueryDecoder` + 单测 | `Sources/iOSExploreUIKit/Utils/QueryDecoder.swift`、`Tests/iOSExploreServerTests/QueryDecoderTests.swift` |
| 完全迁 2 个 parse | `UIViewTargetsModels.swift`、`UIViewHierarchyModels.swift` |
| 部分迁 2 个 parse | `UITapModels.swift`、`UIControlSendActionModels.swift` |
| 2 个 enum 加 `CaseIterable` + "case 顺序即对外文案顺序，勿重排"注释 | `UIViewHierarchyModels.swift`、`UIControlSendActionModels.swift` |
| 补 3 处漏声明 | `maxTargets`→`ViewTargetsCommand.swift`、`snapshotID`→`UITapCommand.swift` + `UIControlSendActionCommand.swift` |
| `QueryDecoder` message 单测 + parse 行为等价测 | `Tests/iOSExploreServerTests/`（macOS SPM，Foundation-only） |
| key 一致性 tracing 测试 | iOS framework test target（`#if canImport(UIKit)`，读 `Command.parameters`） |
| 现有 parse 测试 | 行为等价，预期全绿（失败断言文案不变） |

验证：**第一步先写 `QueryDecoder` 骨架（泛型 `enumValue`/`requiredEnum` + `E.allCases.map(\.rawValue)`）跑一次 framework `xcodebuild -sdk iphonesimulator build` 确认 5.0 双编译通过**（`UIKitActionKind.swift` 已用同 keypath 语法佐证可行，但带 `where` 子句的泛型方法仍先实测），再铺开迁移；全量 `swift test`（含集成 38399 串行）+ framework `xcodebuild ... test`。不动 `project.pbxproj`、不动 `SWIFT_VERSION`、不碰 core `JSON`/`JSONValue`。

#### 不做（YAGNI）

- property wrapper（β）、纯 Codable（γ）、core 加 Codable。
- 自动生成 `parameters`、per-command `Key` enum。

### 路线 A vs B 关系

- 路线 A（普通 throws 统一）：**消除 result enum 样板 + 嵌套转发样板**，是必做的基础。
- 路线 B（Codable/wrapper）：**消除取值/校验样板**，是 A 之后的可选演进；B1 不推荐，B2 可行但需先解决 wrapper 注入与 key 双写。
- 两条路线**不互斥**：先 A 后 B2。

---

## 决策与下一步

1. **版本**：保持 `SWIFT_VERSION=5.0` 不变（已确认源码无 Swift 6 特性，不升级）。
2. **路线 A**：已落地（普通 throws 统一，已提交）。
3. **路线 B2**：已确认采用 QueryDecoder builder（见上）。新增 `Utils/QueryDecoder.swift` + 迁 4 个 parse + 2 个 enum 补 `CaseIterable` + key 一致性测试 + 补 `maxTargets` 参数声明。
4. **key 双写收敛**：采用 c1（一致性测试 + 补漏），不做自动生成 `parameters` / per-command `Key` enum（YAGNI）。

验证：`swift test`（含集成 38399 串行）+ framework `xcodebuild ... test`。不动 `SWIFT_VERSION`、不动 `project.pbxproj`、不碰 core `JSON`/`JSONValue` 的动态边界。
