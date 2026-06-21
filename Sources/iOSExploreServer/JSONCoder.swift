import Foundation

/// JSON 与 Data/Any 之间的编解码（基于 JSONSerialization）。
enum JSONCoder {
    static func encode(_ json: JSON) -> Data {
        (try? JSONSerialization.data(withJSONObject: toAny(json),
                                     options: [.sortedKeys])) ?? Data()
    }

    static func decode(_ data: Data) -> JSON? {
        guard let any = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return fromAny(any)
    }

    static func toAny(_ json: JSON) -> [String: Any] {
        var dict: [String: Any] = [:]
        for (k, v) in json.storage { dict[k] = toAny(v) }
        return dict
    }

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

    static func fromAny(_ any: Any) -> JSON {
        guard let dict = any as? [String: Any] else { return JSON() }
        var storage: [String: JSONValue] = [:]
        for (k, v) in dict { storage[k] = fromAnyValue(v) }
        return JSON(storage)
    }

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
