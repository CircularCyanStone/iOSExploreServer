import Foundation
import iOSExploreServer

/// UIKit typed query 的解析能力约定。
///
/// 各 `ui.*` 命令的 query struct adopt 本协议，只实现领域解析 `parse(decoding:)`，
/// 即自动获得统一入口 `parse(from:)`，消除各 query 重复的 dispatcher 样板。
/// 同时作为业务方（集成方 App）自定义命令复用 typed query 模式的 public 基建：
/// 声明 query struct → adopt 本协议 → 只写领域 `parse(decoding:)` → 自动获得 `parse(from:)`。
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

public extension UIKitQueryParsing {
    /// 从命令 `data` 解析查询参数（统一入口，消除各 query 的 `parse(from:)` 样板）。
    ///
    /// 默认实现：构造 `QueryDecoder` 并转交给领域 `parse(decoding:)`，各 query 无需再各自重复。
    ///
    /// - Parameter data: `ExploreRequest.data`。
    /// - Returns: 解析出的 typed query。
    /// - Throws: `QueryParseError`，文案可直接放入 `invalid_data` envelope。
    static func parse(from data: JSON) throws -> Self {
        var d = QueryDecoder(data)
        return try parse(decoding: &d)
    }
}
