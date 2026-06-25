# 2026-06-25 UIKit typed Query 解析入口抽象设计

## 背景

`iOSExploreUIKit` 四个 `ui.*` 命令各有 typed query：`UIViewHierarchyQuery`、`UIViewTargetsQuery`、`UITapQuery`、`UIControlSendActionQuery`。每个 query 都逐字重复同一个 `parse(from:)` dispatcher 及其文档注释：

```swift
public static func parse(from data: JSON) throws -> Self {
    var d = QueryDecoder(data)
    return try parse(decoding: &d)
}
```

真正各不相同的领域逻辑在 `parse(decoding:)`；`parse(from:)` 纯属样板，复制了四份。

## 目标

1. 消除四个 query 的 `parse(from:)` 样板（方法体 + 文档注释各重复一份）。
2. 把 typed query 的解析入口抽象为 **public** 基建，使业务方（集成方 App）自定义命令时能复用同一模式：声明 query struct → adopt 协议 → 只写领域 `parse(decoding:)` → 自动获得 `parse(from:)`。

## 非目标

- 不抽象 `parse(decoding:)` 内部逻辑（字段、互斥校验是各命令领域逻辑，保留）。
- 不抽 `hasIdentifierFilter` 等仅部分 query 共有的辅助（非四个 query 一致共性）。
- 不补全 `QueryDecoder` 取值方法（如 optional double）。业务方若需 double 等，后续按需扩展；本次保持现有六个取值方法。
- 不改各命令 handler 的错误处理路径（`QueryParseError` → `invalid_data` envelope 不变）。

## 现状要点

- `QueryDecoder`（`Support/Parsing/QueryDecoder.swift`）当前 `internal`，注释明确"不进 public 表面"。提供 `bool`/`string`/`optionalNonNegativeInt`/`rangedInt`/`enumValue`/`requiredEnum` 六个声明式取值方法；内部 `accessedKeys` 追踪 key 一致性。`data: JSON` 为 internal，供库内手写领域逻辑（如 `UITapQuery` 坐标互斥）直接访问原始 data、绕过 `accessedKeys`。
- `parse(decoding:)` 在四个 query 上为 internal。
- `parse(from:)` 为 public，仅被各自命令 adapter 调用（全部在 `iOSExploreUIKit` 模块内）。
- `QueryParseError` 已是 public（`UIKitViewLookupTarget.parse` 为 public 且 throws 它，Swift 强制 public 方法的 throws 类型必须 public）。

## 设计

### 1. public protocol `UIKitQueryParsing`

新文件 `Support/Parsing/UIKitQueryParsing.swift`：

```swift
import Foundation
import iOSExploreServer

/// UIKit typed query 的解析能力约定。
///
/// 各 `ui.*` 命令的 query struct adopt 本协议，只实现领域解析 `parse(decoding:)`，
/// 即自动获得统一入口 `parse(from:)`，消除各 query 重复的 dispatcher 样板。
/// 同时作为业务方自定义命令复用 typed query 模式的 public 基建。
///
/// Foundation-only、`Sendable`：query 跨 actor 传给 `@MainActor` executor，
/// UIKit 类型不穿此边界。
public protocol UIKitQueryParsing: Sendable {
    /// 各命令的领域解析逻辑：按 `QueryDecoder` 读取字段、做命令特有校验，构造 typed query。
    ///
    /// 库内实现可直接访问 `QueryDecoder.data`（internal）做手写领域校验（互斥/成对等），
    /// 绕过 `accessedKeys`；业务方实现用 `QueryDecoder` 的 public 取值方法。
    ///
    /// - Parameter d: 声明式取值器。
    /// - Returns: 解析出的 typed query。
    /// - Throws: `QueryParseError`，文案可直接放入 `invalid_data` envelope。
    static func parse(decoding d: inout QueryDecoder) throws -> Self
}

extension UIKitQueryParsing {
    /// 从命令 `data` 解析查询参数（统一入口，消除各 query 的样板）。
    ///
    /// - Parameter data: `ExploreRequest.data`。
    /// - Returns: 解析出的 typed query。
    /// - Throws: `QueryParseError`，文案可直接放入 `invalid_data` envelope。
    public static func parse(from data: JSON) throws -> Self {
        var d = QueryDecoder(data)
        return try parse(decoding: &d)
    }
}
```

命名取 `…Parsing`（描述"可解析"能力）。不加 `Equatable` 约束：与解析入口无关，各 query 自身继续 `Equatable`。

### 2. `QueryDecoder` 分层升 public

- struct、`init(_ data:)`、六个取值方法升 **public**（业务方 typed query 解析基建）。
- `data: JSON` 显式标注 **internal**（库内手写领域逻辑用，业务方用取值方法）。
- `accessedKeys` 保持 **internal private(set)**（一致性测试追踪机制，不对外泄露）。
- 更新文档注释：原"`internal`：不进 public 表面"改写为"取值 API 为 public；`data`/`accessedKeys` 为内部机制保持 internal"。

### 3. 四个 query 迁移

- 删除各自的 `public static func parse(from data: JSON) throws -> Self`（方法体 + 文档注释）。
- 声明改为 `: UIKitQueryParsing`（保留既有 `Sendable, Equatable`）。
- `parse(decoding:)` 从 internal 升 **public**（满足 protocol requirement）。`UITapQuery`/`UIControlSendActionQuery` 方法体内 `d.data` 访问保持不变（同模块可见 internal 属性）。

adapter 调用点零变化：`XxxQuery.parse(from: data)` 静态分发到 protocol extension 默认实现。

## 关键决策与权衡

- **必须 public**：业务方自定义命令要复用，protocol / `parse(from:)` / `parse(decoding:)` / `QueryDecoder` 都必须 public。Swift 硬约束——public 方法不能暴露 internal 参数类型——决定 `QueryDecoder` 升 public 是必要连带，非可选。
- **分层保护内部机制**：`QueryDecoder` 只把"声明式取值能力"public；`data`/`accessedKeys` 锁 internal，不泄露一致性追踪机制。
- **推翻既有边界**：`QueryDecoder` 原注释"不进 public 表面"是有意决策；本方案为 typed query 公共基建推翻它（仅取值 API）。这是权衡核心，已确认接受。
- **YAGNI**：不补 `optionalDouble` 等；不抽 `hasIdentifierFilter`。

## public 表面变化

新增 public：`UIKitQueryParsing`（protocol）、`QueryDecoder.init` + 六个取值方法、四个 query 的 `parse(decoding:)`。

不变 public：四个 query 的 `parse(from:)`（语义不变，实现移到 protocol extension）、`QueryParseError`、各 query struct/init/字段。

保持 internal：`QueryDecoder.data`、`QueryDecoder.accessedKeys`。

## 业务方使用示例（说明性，非实现）

业务方自定义命令复用 typed query：

```swift
public struct MyGreeterQuery: UIKitQueryParsing {
    public let name: String
    public init(name: String) { self.name = name }

    public static func parse(decoding d: inout QueryDecoder) throws -> MyGreeterQuery {
        guard let name = d.string("name"), !name.isEmpty else {
            throw QueryParseError("name is required")
        }
        return MyGreeterQuery(name: name)
    }
}
// 自动获得 MyGreeterQuery.parse(from: data)
```

业务方用 `QueryDecoder` public 取值方法定义字段；需要手写领域校验时，用取值方法取值后自行校验（本次不提供 `data` 的 public 访问与 `optionalDouble` 等，后续按需扩展）。

## 文件改动清单

1. 新增 `Sources/iOSExploreUIKit/Support/Parsing/UIKitQueryParsing.swift`（protocol + extension + 完整注释）。
2. 改 `Sources/iOSExploreUIKit/Support/Parsing/QueryDecoder.swift`（struct/init/取值方法升 public；`data` 显式 internal；`accessedKeys` 保持 internal private(set)；更新文档注释）。
3. 改四个 model 文件，各删 `parse(from:)`、adopt `UIKitQueryParsing`、`parse(decoding:)` 升 public：
   - `Commands/TopViewHierarchy/UIViewHierarchyModels.swift`
   - `Commands/ViewTargets/UIViewTargetsModels.swift`
   - `Commands/Tap/UITapModels.swift`
   - `Commands/ControlAction/UIControlSendActionModels.swift`
4. 同步文档：
   - `docs/uikit/uikit-file-reference.md`：新增 `UIKitQueryParsing.swift` 档案、`QueryDecoder` 可见性变化。
   - `AGENTS.md` 模块边界节：补充 typed query 抽象（`UIKitQueryParsing`）与 `QueryDecoder` public 边界说明。

## 日志说明

`UIKitQueryParsing` 与 `parse(from:)` 默认实现是**编译期静态分发抽象**，无运行时生命周期（无 init/状态转移/资源占用）。解析失败日志已由各命令 handler 顶层 `catch QueryParseError → invalid_data` 统一记录（`UIKitCommandLogging`，category `command`，含 action / error code）。故 protocol 层刻意不加日志点，避免与 handler 层重复。此为 AGENTS.md"刻意不加日志须说明原因"的说明。

## 测试策略

- 行为零变化：四个 query 的现有 parse 测试（macOS `swift test` message 单测 + iOS framework 一致性测试）全部保留，回归通过即验证默认实现正确。
- protocol 默认实现 `parse(from:)` 由四个 query 的现有测试间接全覆盖，无需新增专门测试。
- 一致性测试（`accessedKeys ⊆ Command.parameters`）不受影响：`data`/`accessedKeys` 仍 internal，库内 `parse(decoding:)` 行为不变。
- 可选（非阻塞）：加一个针对 `UIKitQueryParsing` 默认实现的小型单测，用测试专用 conformance 验证 `parse(from:)` 正确转发到 `parse(decoding:)`。

## 兼容性

- protocol + extension 默认实现是 Swift 5 特性，`SWIFT_VERSION=5.0` + Swift 6.2 工具链完全支持，无 Swift-6-only 语法。
- `Sendable` 约束与现有 query 一致。
- SPM（Swift 6.2）与 framework 工程共享同一份 `Sources/iOSExploreUIKit/`，改动对两者一致。

## 验收

- `swift build` 通过。
- `swift test`（macOS）全绿，覆盖率不降。
- `xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' test` 全绿。
- 四个 model 文件中不再出现 `parse(from:)` 方法体定义；`parse(from:)` 实现仅存在于 `UIKitQueryParsing` 的 protocol extension 一处。
