import Foundation
import iOSExploreServer

/// UIKit 命令参数的声明式取值器。
///
/// 把"从 `JSON` 按 key 取值 + 类型转换 + 默认值 + 范围/枚举校验 + 错误文案"封装成方法链，
/// 取代各 parse 里重复的 if-let/guard/?? 样板。内部失败统一抛 `QueryParseError`，
/// 文案可直接进入 `invalid_data` envelope。
///
/// 取值 API 为 public，供库内 `ui.*` query 与业务方自定义命令的 typed query 复用（见
/// `UIKitQueryParsing`）。`data` 与 `accessedKeys` 为内部机制保持 internal：`data` 供
/// 库内手写领域校验直接访问原始 JSON、绕过 `accessedKeys`；`accessedKeys` 供一致性测试
/// 断言"走 builder 的 key ⊆ Command.parameters 声明的 key"（仅覆盖走 builder 的字段；
/// 部分手写领域 key 不覆盖，靠人 + review）。
///
/// Foundation-only、`Sendable`，不携带 UIKit 类型；message 单测可在 macOS `swift test`
/// 覆盖，一致性测试因读 `Command.parameters` 归 iOS framework test target。
public struct QueryDecoder: Sendable {
    /// 待解码的命令 data（internal，供 `parse(decoding:)` 的手写领域字段直接访问，不进 `accessedKeys`）。
    internal let data: JSON
    /// 累积已读取的 key，供一致性测试断言 ⊆ `Command.parameters`。
    internal private(set) var accessedKeys: Set<String> = []

    /// 创建取值器。
    ///
    /// - Parameter data: `ExploreRequest.data`。
    public init(_ data: JSON) { self.data = data }

    /// 布尔字段：缺失或非布尔都取默认值（保持现状语义，不抛错）。
    public mutating func bool(_ key: String, default value: Bool) -> Bool {
        accessedKeys.insert(key)
        return data[key]?.boolValue ?? value
    }

    /// 可选字符串字段：缺失返回 nil。
    public mutating func string(_ key: String) -> String? {
        accessedKeys.insert(key)
        return data[key]?.stringValue
    }

    /// 可选非负整数：缺失返回 nil；存在但非有限/非整数/为负抛错。
    public mutating func optionalNonNegativeInt(_ key: String) throws -> Int? {
        accessedKeys.insert(key)
        guard let raw = data[key]?.doubleValue else { return nil }
        guard let value = UIKitQueryNumber.nonNegativeInteger(raw) else {
            throw QueryParseError("\(key) must be a non-negative integer")
        }
        return value
    }

    /// 限定范围整数：缺失取默认；存在但越界/非整数抛错。
    public mutating func rangedInt(_ key: String, in range: ClosedRange<Int>, default value: Int) throws -> Int {
        accessedKeys.insert(key)
        guard let raw = data[key]?.doubleValue else { return value }
        guard let parsed = UIKitQueryNumber.integer(raw, in: range) else {
            throw QueryParseError("\(key) must be an integer between \(range.lowerBound) and \(range.upperBound)")
        }
        return parsed
    }

    /// String 原始值枚举（带默认）：缺失取默认；存在但非合法抛错。
    public mutating func enumValue<E: RawRepresentable & CaseIterable>(_ key: String, default value: E) throws -> E
        where E.RawValue == String {
        accessedKeys.insert(key)
        guard let raw = data[key]?.stringValue else { return value }
        guard let parsed = E(rawValue: raw) else {
            throw QueryParseError("\(key) must be one of \(E.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        return parsed
    }

    /// 必填 String 原始值枚举：缺失抛 "missing required parameter"；非合法抛 must be one of。
    public mutating func requiredEnum<E: RawRepresentable & CaseIterable>(_ key: String) throws -> E
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
