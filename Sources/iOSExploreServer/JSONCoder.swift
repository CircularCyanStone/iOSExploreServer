import Foundation

/// `JSON` 与 `Data`/Foundation JSON 对象之间的转换工具。
///
/// 库协议只需要动态 JSON 对象，不需要为每个命令定义 `Codable` 模型。这里用
/// `JSONSerialization` 作为边界，把 Foundation 的 `[String: Any]`、`NSNumber`、
/// `NSNull` 转换为强约束的 `JSON`/`JSONValue`。
enum JSONCoder {
    /// 把 `JSON` 编码为 UTF-8 JSON 数据。
    ///
    /// 输出使用 `.sortedKeys`，让测试断言和日志更稳定。编码理论上不应失败；若
    /// `JSONSerialization` 返回错误，兜底返回空 `Data`。
    static func encode(_ json: JSON) -> Data {
        (try? JSONSerialization.data(withJSONObject: toAny(json),
                                     options: [.sortedKeys])) ?? Data()
    }

    /// 把 UTF-8 JSON 数据解码为 `JSON` 对象。
    ///
    /// 只有顶层为对象时才会得到有内容的 `JSON`；解析失败返回 `nil`。
    static func decode(_ data: Data) -> JSON? {
        guard let any = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return fromAny(any)
    }

    /// 把 `JSON` 转为 `JSONSerialization` 可接受的字典。
    static func toAny(_ json: JSON) -> [String: Any] {
        var dict: [String: Any] = [:]
        for (k, v) in json.storage { dict[k] = toAny(v) }
        return dict
    }

    /// 把单个 `JSONValue` 转为 Foundation JSON 值。
    static func toAny(_ value: JSONValue) -> Any {
        switch value {
        case .string(let s): return s
        case .double(let d): return d
        case .bool(let b): return b
        case .object(let o): return toAny(o)
        case .array(let a): return a.map { toAny($0) }
        case .null: return NSNull()
        }
    }

    /// 把 Foundation JSON 对象转为 `JSON`。
    ///
    /// 非对象顶层会被转换为空对象；调用方如需拒绝非对象顶层，应在更上层检查协议字段。
    static func fromAny(_ any: Any) -> JSON {
        guard let dict = any as? [String: Any] else { return JSON() }
        var storage: [String: JSONValue] = [:]
        for (k, v) in dict { storage[k] = fromAnyValue(v) }
        return JSON(storage)
    }

    /// 把 Foundation JSON 值递归转为 `JSONValue`。
    static func fromAnyValue(_ any: Any) -> JSONValue {
        switch any {
        case let s as String:
            return .string(s)
        case let n as NSNumber:
            // NSNumber 可能包装 bool，用 CFBooleanGetTypeID 区分。
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return .bool(n.boolValue)
            }
            return .double(n.doubleValue)
        case let d as [String: Any]:
            return .object(fromAny(d))
        case let a as [Any]:
            return .array(a.map { fromAnyValue($0) })
        default:
            return .null
        }
    }
}
