import Foundation

/// 类型擦除的 JSON 值，承载命令的 data 载荷。
public enum JSONValue: Sendable, Equatable {
    case string(String)
    case double(Double)
    case bool(Bool)
    case object(JSON)
    case array([JSONValue])
    case null
}

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}
extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .double(Double(value)) }
}
extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .double(value) }
}
extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}
extension JSONValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) { self = .null }
}

extension JSONValue {
    public var stringValue: String? { if case .string(let v) = self { return v } else { return nil } }
    public var doubleValue: Double? { if case .double(let v) = self { return v } else { return nil } }
    public var boolValue: Bool? { if case .bool(let v) = self { return v } else { return nil } }
}

/// JSON 对象容器：String 键 → JSONValue。
public struct JSON: Sendable, Equatable {
    public var storage: [String: JSONValue]
    public init(_ storage: [String: JSONValue] = [:]) { self.storage = storage }

    public subscript(key: String) -> JSONValue? {
        get { storage[key] }
        set { storage[key] = newValue }
    }
}

extension JSON: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self.storage = Dictionary(uniqueKeysWithValues: elements)
    }
}

/// 命令请求。
public struct ExploreRequest: Sendable, Equatable {
    public let action: String
    public let data: JSON
    public init(action: String, data: JSON = [:]) {
        self.action = action
        self.data = data
    }
}

/// 命令结果。
public enum ExploreResult: Sendable, Equatable {
    case success(JSON)
    case failure(code: ExploreError, message: String)
}

/// 错误码（与 envelope 中 error.code 一致）。
public enum ExploreError: String, Sendable {
    case unknownAction = "unknown_action"
    case invalidData = "invalid_data"
    case internalError = "internal_error"
    case badRequest = "bad_request"
}
