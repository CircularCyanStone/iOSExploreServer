# UIKit Query 解析重构设计

> 日期：2026-06-24
> 状态：方案提案（路线 A 待确认落地，路线 B 待后续分析）
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

## 路线 B：Codable + 属性包装器（待后续分析）

> 状态：本轮仅记录思路与可行性分析，不在路线 A 之前落地。

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

### B2. 自定义 decode 协议 + property wrapper（QueryDecoder 的 wrapper 化，可行演进）

思路：不走标准 Codable，而是基于现有 `JSON` 写一个轻量 decode 驱动，用 property wrapper 把"取值 + 类型转换 + 默认值 + 校验 + 错误文案"声明式化。这是路线 A 落地后的**自然演进**——throws 已经统一了错误出口（抛 `QueryParseError`），剩下的样板（取值/校验）再用 wrapper 声明式化。

雏形（待细化）：

```swift
/// 带默认值的布尔字段。
@propertyWrapper
struct DefaultBool {
    let key: String
    let defaultValue: Bool
    var wrappedValue: Bool
}

/// 限定范围的整数字段。
@propertyWrapper
struct RangedInt {
    let key: String
    let range: ClosedRange<Int>
    let defaultValue: Int
    var wrappedValue: Int
}

// 一个统一的 decode 驱动按字段元数据取值、校验，失败抛 QueryParseError
```

待解决的问题（后续分析重点）：
1. property wrapper 的 `wrappedValue` 初始值与 decoder 注入的次序——wrapper 默认 init 与 decode 注入如何协调（Swift 的 wrapper 在 init 完成后才能被外部赋值，decoder 驱动模式需要 wrapper 暴露可写后端存储）。
2. `@MainActor` 与 Foundation-only 边界：wrapper 必须保持 Foundation-only（typed factory 硬规则），不能引入 UIKit 类型。
3. 裸 key 的终极收敛：让 `CommandParameter(name:)` 从 property wrapper 的 `key` 生成，消灭 parse/parameters 的 key 双写——这是更大工程，需评估 property wrapper 的 `key` 能否在运行时/编译期被 `parameters` 反射读取（Swift 元数据有限，可能要手写映射表）。
4. 互斥/成对约束（tap/locator）是领域逻辑，不该塞进通用 wrapper，保留手写。
5. 与路线 A 的关系：**B 建立在 A 之上**（A 用普通 throws 统一错误出口后，B 才能声明式化剩余样板）。不建议在 A 落地前做 B。

### 路线 A vs B 关系

- 路线 A（普通 throws 统一）：**消除 result enum 样板 + 嵌套转发样板**，是必做的基础。
- 路线 B（Codable/wrapper）：**消除取值/校验样板**，是 A 之后的可选演进；B1 不推荐，B2 可行但需先解决 wrapper 注入与 key 双写。
- 两条路线**不互斥**：先 A 后 B2。

---

## 决策与下一步

1. **版本**：保持 `SWIFT_VERSION=5.0` 不变（已确认源码无 Swift 6 特性，不升级）。
2. **路线 A**：按 A1~A7 落地普通 throws 统一。直接消除用户指出的"鸡肋 result enum"模式，无版本风险。
3. **路线 B**：本设计文档已记录，待 A 落地后单独评估 B2（property wrapper 声明式化 + key 双写收敛）。

硬编码 key（`"maxDepth"` 等）：路线 A 不强制收敛（parse 内仍是字符串 key），真正的 key 双写收敛留给路线 B2 评估。若希望 A 阶段就引入每命令一个 `enum Key: String`，可作为 A 的可选项。
