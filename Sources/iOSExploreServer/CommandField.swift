import Foundation

/// 类型擦除后的命令输入字段标识。
///
/// 它只用于把 generated 字段名交给 `CommandInputDefinition` 和 `CommandInputDecoder`；
/// schema、description、默认值等合同信息不在 Swift 中重复保存。
public struct AnyCommandField: Sendable, Equatable {
    /// 字段名，对应命令 data object 的 key。
    public let name: String

    /// 创建字段标识。
    public init(name: String) {
        self.name = name
    }
}

/// 单个 typed 命令输入字段。
///
/// 字段只携带名字和 Swift 转换闭包。wire 结构先由 generated `CommandInputDefinition`
/// 校验，转换闭包负责默认值和最终 Swift 类型转换。
public struct CommandField<Value: Sendable>: Sendable {
    /// 字段名，对应命令 data object 的 key。
    public let name: String
    /// 从原始 JSON 值解析出 Swift typed 值。
    internal let decode: @Sendable (JSONValue?) throws -> Value

    /// 类型擦除视图。
    public var erased: AnyCommandField { AnyCommandField(name: name) }

    internal init(name: String,
                  decode: @escaping @Sendable (JSONValue?) throws -> Value) {
        self.name = name
        self.decode = decode
    }
}

/// 常用命令输入字段转换工厂。
///
/// 公共 action 的类型、枚举和范围先由合同生成代码校验；这些工厂保留转换时的防御性检查，
/// 并集中实现缺省值到 Swift 值的映射。字段说明只存在于 `contracts/`，不在这里重复保存。
public enum CommandFields {
    private static let jsonSafeIntegerLimit = 9_007_199_254_740_991

    /// 读取带默认值的严格布尔字段。
    public static func bool(_ name: String,
                            default value: Bool) -> CommandField<Bool> {
        CommandField(name: name) { raw in
            guard let raw else { return value }
            guard raw != .null else {
                throw CommandInputParseError("\(name) must be a boolean")
            }
            guard let parsed = raw.boolValue else {
                throw CommandInputParseError("\(name) must be a boolean")
            }
            return parsed
        }
    }

    /// 读取可选字符串字段。
    public static func optionalString(_ name: String) -> CommandField<String?> {
        CommandField(name: name) { raw in
            guard let raw, raw != .null else { return nil }
            guard let parsed = raw.stringValue else {
                throw CommandInputParseError("\(name) must be a string")
            }
            return parsed
        }
    }

    /// 读取必填字符串字段。
    public static func requiredString(_ name: String) -> CommandField<String> {
        CommandField(name: name) { raw in
            guard let raw, raw != .null else {
                throw CommandInputParseError("missing required parameter '\(name)'")
            }
            guard let parsed = raw.stringValue else {
                throw CommandInputParseError("\(name) must be a string")
            }
            return parsed
        }
    }

    /// 读取必填字符串枚举字段并保留 wire 字符串。
    public static func requiredStringEnum(_ name: String,
                                          values: [String]) -> CommandField<String> {
        precondition(!values.isEmpty, "\(name) enum values must not be empty")
        return CommandField(name: name) { raw in
            guard let raw, raw != .null else {
                throw CommandInputParseError("missing required parameter '\(name)'")
            }
            guard let parsed = raw.stringValue, values.contains(parsed) else {
                throw CommandInputParseError("\(name) must be one of \(values.joined(separator: ", "))")
            }
            return parsed
        }
    }

    /// 读取带默认值的字符串枚举字段并保留 wire 字符串。
    public static func stringEnum(_ name: String,
                                  values: [String],
                                  default value: String) -> CommandField<String> {
        precondition(!values.isEmpty, "\(name) enum values must not be empty")
        precondition(values.contains(value), "\(name) default must be one of the enum values")
        return CommandField(name: name) { raw in
            guard let raw else { return value }
            guard raw != .null else {
                throw CommandInputParseError("\(name) must be one of \(values.joined(separator: ", "))")
            }
            guard let parsed = raw.stringValue, values.contains(parsed) else {
                throw CommandInputParseError("\(name) must be one of \(values.joined(separator: ", "))")
            }
            return parsed
        }
    }

    /// 读取可选字符串枚举字段。
    public static func optionalStringEnum(_ name: String,
                                          values: [String]) -> CommandField<String?> {
        precondition(!values.isEmpty, "\(name) enum values must not be empty")
        return CommandField(name: name) { raw in
            guard let raw, raw != .null else { return nil }
            guard let parsed = raw.stringValue, values.contains(parsed) else {
                throw CommandInputParseError("\(name) must be one of \(values.joined(separator: ", "))")
            }
            return parsed
        }
    }

    /// 读取必填原始数组。
    public static func requiredArray(_ name: String,
                                     minimumCount: Int? = nil,
                                     maximumCount: Int? = nil) -> CommandField<[JSONValue]> {
        precondition(minimumCount == nil || minimumCount! >= 0, "\(name) minimumCount must be non-negative")
        precondition(maximumCount == nil || maximumCount! >= 0, "\(name) maximumCount must be non-negative")
        if let minimumCount, let maximumCount {
            precondition(minimumCount <= maximumCount, "\(name) minimumCount must be <= maximumCount")
        }
        return CommandField(name: name) { raw in
            guard let raw, raw != .null else {
                throw CommandInputParseError("missing required parameter '\(name)'")
            }
            guard case .array(let values) = raw else {
                throw CommandInputParseError("\(name) must be an array")
            }
            if let minimumCount, values.count < minimumCount {
                throw CommandInputParseError("\(name) must contain at least \(minimumCount) item(s)")
            }
            if let maximumCount, values.count > maximumCount {
                throw CommandInputParseError("\(name) must contain at most \(maximumCount) item(s)")
            }
            return values
        }
    }

    /// 读取可选字符串枚举数组；保留输入顺序和重复元素。
    public static func optionalStringEnumArray(_ name: String,
                                               values: [String]) -> CommandField<[String]?> {
        precondition(!values.isEmpty, "\(name) item enum values must not be empty")
        return CommandField(name: name) { raw in
            guard let raw, raw != .null else { return nil }
            guard case .array(let items) = raw else {
                throw CommandInputParseError("\(name) must be an array")
            }
            return try items.map { item in
                guard let parsed = item.stringValue, values.contains(parsed) else {
                    throw CommandInputParseError("\(name) items must be one of \(values.joined(separator: ", "))")
                }
                return parsed
            }
        }
    }

    /// 读取可选有限数字字段。
    public static func optionalFiniteNumber(_ name: String,
                                            minimum: Double? = nil,
                                            maximum: Double? = nil,
                                            exclusiveMinimum: Bool = false,
                                            exclusiveMaximum: Bool = false) -> CommandField<Double?> {
        validateFiniteNumberBounds(name: name,
                                   minimum: minimum,
                                   maximum: maximum,
                                   exclusiveMinimum: exclusiveMinimum,
                                   exclusiveMaximum: exclusiveMaximum)
        return CommandField(name: name) { raw in
            guard let raw, raw != .null else { return nil }
            guard let parsed = raw.doubleValue,
                  finiteNumberIsWithinBounds(parsed,
                                             minimum: minimum,
                                             maximum: maximum,
                                             exclusiveMinimum: exclusiveMinimum,
                                             exclusiveMaximum: exclusiveMaximum) else {
                let range = minimum == nil && maximum == nil ? "" : " within the declared range"
                throw CommandInputParseError("\(name) must be a finite number\(range)")
            }
            return parsed
        }
    }

    /// 读取带默认值的有限数字字段。
    public static func finiteNumber(_ name: String,
                                    default value: Double,
                                    minimum: Double? = nil,
                                    maximum: Double? = nil,
                                    exclusiveMinimum: Bool = false,
                                    exclusiveMaximum: Bool = false) -> CommandField<Double> {
        validateFiniteNumberBounds(name: name,
                                   minimum: minimum,
                                   maximum: maximum,
                                   exclusiveMinimum: exclusiveMinimum,
                                   exclusiveMaximum: exclusiveMaximum)
        precondition(finiteNumberIsWithinBounds(value,
                                                minimum: minimum,
                                                maximum: maximum,
                                                exclusiveMinimum: exclusiveMinimum,
                                                exclusiveMaximum: exclusiveMaximum),
                     "\(name) default must be finite and within the declared range")
        return CommandField(name: name) { raw in
            guard let raw, raw != .null else { return value }
            guard let parsed = raw.doubleValue,
                  finiteNumberIsWithinBounds(parsed,
                                             minimum: minimum,
                                             maximum: maximum,
                                             exclusiveMinimum: exclusiveMinimum,
                                             exclusiveMaximum: exclusiveMaximum) else {
                throw CommandInputParseError("\(name) must be a finite number within the declared range")
            }
            return parsed
        }
    }

    /// 读取可选原始 number/bool 值；供 control value 等联合类型使用。
    public static func number(_ name: String,
                              required: Bool) -> CommandField<JSONValue?> {
        CommandField(name: name) { raw in
            guard let raw, raw != .null else {
                if required { throw CommandInputParseError("missing required parameter '\(name)'") }
                return nil
            }
            if let parsed = raw.doubleValue, parsed.isFinite { return .double(parsed) }
            if let parsed = raw.boolValue { return .bool(parsed) }
            throw CommandInputParseError("\(name) must be a finite number")
        }
    }

    /// 读取可选非负 JSON safe integer。
    public static func optionalNonNegativeInt(_ name: String) -> CommandField<Int?> {
        CommandField(name: name) { raw in
            guard let raw, raw != .null else { return nil }
            guard let parsed = try parseInteger(raw, name: name), parsed >= 0 else {
                throw CommandInputParseError("\(name) must be a non-negative integer")
            }
            return parsed
        }
    }

    /// 读取可选限定范围 JSON safe integer。
    public static func optionalInt(_ name: String,
                                   minimum: Int? = nil,
                                   maximum: Int? = nil) -> CommandField<Int?> {
        validateIntegerBounds(name: name, minimum: minimum, maximum: maximum)
        return CommandField(name: name) { raw in
            guard let raw, raw != .null else { return nil }
            guard let parsed = try parseInteger(raw, name: name),
                  minimum.map({ parsed >= $0 }) ?? true,
                  maximum.map({ parsed <= $0 }) ?? true else {
                throw CommandInputParseError("\(name) must be an integer within the declared range")
            }
            return parsed
        }
    }

    /// 读取必填限定范围 JSON safe integer。
    public static func requiredInt(_ name: String,
                                   range: ClosedRange<Int>) -> CommandField<Int> {
        precondition(range.lowerBound <= jsonSafeIntegerLimit && range.upperBound >= -jsonSafeIntegerLimit,
                     "\(name) range must include at least one JSON safe integer")
        return CommandField(name: name) { raw in
            guard let raw, raw != .null else {
                throw CommandInputParseError("missing required parameter '\(name)'")
            }
            guard let parsed = try parseInteger(raw, name: name), range.contains(parsed) else {
                throw CommandInputParseError("\(name) must be an integer between \(range.lowerBound) and \(range.upperBound)")
            }
            return parsed
        }
    }

    /// 读取带默认值的限定范围 JSON safe integer。
    public static func int(_ name: String,
                           range: ClosedRange<Int>,
                           default value: Int) -> CommandField<Int> {
        precondition(range.contains(value), "\(name) default must be within range \(range)")
        precondition(isJSONSafeInteger(value), "\(name) default must be a JSON safe integer")
        return CommandField(name: name) { raw in
            guard let raw else { return value }
            guard raw != .null else {
                throw CommandInputParseError("\(name) must be an integer between \(range.lowerBound) and \(range.upperBound)")
            }
            guard let parsed = try parseInteger(raw, name: name), range.contains(parsed) else {
                throw CommandInputParseError("\(name) must be an integer between \(range.lowerBound) and \(range.upperBound)")
            }
            return parsed
        }
    }

    /// 读取带默认值的领域字符串枚举。
    public static func enumValue<E>(_ name: String,
                                    type: E.Type,
                                    default value: E) -> CommandField<E>
        where E: RawRepresentable & CaseIterable & Sendable, E.RawValue == String {
        let values = E.allCases.map(\.rawValue)
        return CommandField(name: name) { raw in
            guard let raw else { return value }
            guard raw != .null else {
                throw CommandInputParseError("\(name) must be one of \(values.joined(separator: ", "))")
            }
            guard let string = raw.stringValue,
                  values.contains(string),
                  let parsed = E(rawValue: string) else {
                throw CommandInputParseError("\(name) must be one of \(values.joined(separator: ", "))")
            }
            return parsed
        }
    }

    /// 读取必填领域字符串枚举。
    public static func requiredEnum<E>(_ name: String,
                                       type: E.Type) -> CommandField<E>
        where E: RawRepresentable & CaseIterable & Sendable, E.RawValue == String {
        let values = E.allCases.map(\.rawValue)
        return CommandField(name: name) { raw in
            guard let raw, raw != .null else {
                throw CommandInputParseError("missing required parameter '\(name)'")
            }
            guard let string = raw.stringValue,
                  values.contains(string),
                  let parsed = E(rawValue: string) else {
                throw CommandInputParseError("\(name) must be one of \(values.joined(separator: ", "))")
            }
            return parsed
        }
    }

    private static func parseInteger(_ raw: JSONValue, name: String) throws -> Int? {
        guard let number = raw.doubleValue,
              number.isFinite,
              abs(number) <= Double(jsonSafeIntegerLimit),
              number.rounded(.towardZero) == number,
              let value = Int(exactly: number) else {
            throw CommandInputParseError("\(name) must be an integer")
        }
        return value
    }

    private static func validateIntegerBounds(name: String,
                                              minimum: Int?,
                                              maximum: Int?) {
        precondition(minimum.map(isJSONSafeInteger) ?? true, "\(name) minimum must be a JSON safe integer")
        precondition(maximum.map(isJSONSafeInteger) ?? true, "\(name) maximum must be a JSON safe integer")
        if let minimum, let maximum {
            precondition(minimum <= maximum, "\(name) minimum must be <= maximum")
        }
    }

    private static func validateFiniteNumberBounds(name: String,
                                                   minimum: Double?,
                                                   maximum: Double?,
                                                   exclusiveMinimum: Bool,
                                                   exclusiveMaximum: Bool) {
        precondition(minimum?.isFinite ?? true, "\(name) minimum must be finite")
        precondition(maximum?.isFinite ?? true, "\(name) maximum must be finite")
        precondition(!exclusiveMinimum || minimum != nil, "\(name) exclusiveMinimum requires minimum")
        precondition(!exclusiveMaximum || maximum != nil, "\(name) exclusiveMaximum requires maximum")
        if let minimum, let maximum {
            precondition(minimum < maximum || (minimum == maximum && !exclusiveMinimum && !exclusiveMaximum),
                         "\(name) numeric bounds must describe a non-empty range")
        }
    }

    private static func finiteNumberIsWithinBounds(_ value: Double,
                                                   minimum: Double?,
                                                   maximum: Double?,
                                                   exclusiveMinimum: Bool,
                                                   exclusiveMaximum: Bool) -> Bool {
        guard value.isFinite else { return false }
        if let minimum, exclusiveMinimum ? value <= minimum : value < minimum { return false }
        if let maximum, exclusiveMaximum ? value >= maximum : value > maximum { return false }
        return true
    }

    private static func isJSONSafeInteger(_ value: Int) -> Bool {
        value >= -jsonSafeIntegerLimit && value <= jsonSafeIntegerLimit
    }
}
