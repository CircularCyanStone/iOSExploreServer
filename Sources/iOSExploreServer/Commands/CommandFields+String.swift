import Foundation

public extension CommandFields {
    /// 可选字符串字段：缺失或 null 返回 nil，存在但非字符串抛出解析错误。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - description: 字段说明。
    /// - Returns: 解析为 `String?` 的命令字段。
    static func optionalString(_ name: String, description: String) -> CommandField<String?> {
        CommandField(name: name,
                     schema: CommandFieldSchema(type: .string,
                                                required: false,
                                                description: description,
                                                allowsNull: true)) { raw in
            guard let raw = raw, raw != .null else { return nil }
            guard let parsed = raw.stringValue else {
                throw CommandInputParseError("\(name) must be a string")
            }
            return parsed
        }
    }

    /// 必填字符串字段：缺失或 null 抛出解析错误，存在但非字符串也抛出解析错误。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - description: 字段说明。
    /// - Returns: 解析为 `String` 的命令字段。
    static func requiredString(_ name: String, description: String) -> CommandField<String> {
        CommandField(name: name,
                     schema: CommandFieldSchema(type: .string, required: true, description: description)) { raw in
            guard let raw = raw, raw != .null else {
                throw CommandInputParseError("missing required parameter '\(name)'")
            }
            guard let parsed = raw.stringValue else {
                throw CommandInputParseError("\(name) must be a string")
            }
            return parsed
        }
    }

    /// 必填 raw string 枚举字段：返回 wire 字符串，不引入领域枚举类型。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - values: 合同允许的字符串值。
    ///   - description: 字段说明。
    /// - Returns: 解析为 `String` 的命令字段。
    static func requiredStringEnum(_ name: String,
                                   values: [String],
                                   description: String) -> CommandField<String> {
        precondition(!values.isEmpty, "\(name) enum values must not be empty")
        return CommandField(name: name,
                            schema: CommandFieldSchema(type: .string,
                                                       required: true,
                                                       description: description,
                                                       enumValues: values)) { raw in
            guard let raw, raw != .null else {
                throw CommandInputParseError("missing required parameter '\(name)'")
            }
            guard let parsed = raw.stringValue, values.contains(parsed) else {
                throw CommandInputParseError("\(name) must be one of \(values.joined(separator: ", "))")
            }
            return parsed
        }
    }

    /// 带默认值的 raw string 枚举字段：缺失或兼容性 null 时返回合同默认字符串。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - values: 合同允许的字符串值。
    ///   - default: 字段缺失或显式为 null 时使用的默认值。
    ///   - description: 字段说明。
    /// - Returns: 解析为 `String` 的命令字段。
    static func stringEnum(_ name: String,
                           values: [String],
                           default value: String,
                           description: String) -> CommandField<String> {
        precondition(!values.isEmpty, "\(name) enum values must not be empty")
        precondition(values.contains(value), "\(name) default must be one of the enum values")
        return CommandField(name: name,
                            schema: CommandFieldSchema(type: .string,
                                                       required: false,
                                                       description: description,
                                                       defaultValue: .string(value),
                                                       enumValues: values)) { raw in
            guard let raw, raw != .null else { return value }
            guard let parsed = raw.stringValue, values.contains(parsed) else {
                throw CommandInputParseError("\(name) must be one of \(values.joined(separator: ", "))")
            }
            return parsed
        }
    }

    /// 可选 raw string 枚举字段：缺失或 null 返回 nil，其余值必须属于合同枚举。
    ///
    /// nullable schema 的 `enum` 会同步包含 JSON null，使 schema 与运行时可接受值一致。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - values: 合同允许的字符串值。
    ///   - description: 字段说明。
    /// - Returns: 解析为 `String?` 的命令字段。
    static func optionalStringEnum(_ name: String,
                                   values: [String],
                                   description: String) -> CommandField<String?> {
        precondition(!values.isEmpty, "\(name) enum values must not be empty")
        return CommandField(name: name,
                            schema: CommandFieldSchema(type: .string,
                                                       required: false,
                                                       description: description,
                                                       allowsNull: true,
                                                       enumValues: values)) { raw in
            guard let raw, raw != .null else { return nil }
            guard let parsed = raw.stringValue, values.contains(parsed) else {
                throw CommandInputParseError("\(name) must be one of \(values.joined(separator: ", "))")
            }
            return parsed
        }
    }

    /// 字符串枚举字段：缺失或兼容性 null 使用默认值，非法 rawValue 抛出解析错误。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - type: 字符串 rawValue 枚举类型。
    ///   - default: 字段缺失时使用的默认枚举值。
    ///   - description: 字段说明。
    /// - Returns: 解析为枚举值的命令字段。
    static func enumValue<E>(_ name: String,
                             type: E.Type,
                             default value: E,
                             description: String) -> CommandField<E>
        where E: RawRepresentable & CaseIterable & Sendable, E.RawValue == String {
        let enumValues = E.allCases.map { $0.rawValue }
        return CommandField(name: name,
                            schema: CommandFieldSchema(type: .string,
                                                       required: false,
                                                       description: description,
                                                       defaultValue: .string(value.rawValue),
                                                       enumValues: enumValues)) { raw in
            guard let raw = raw, raw != .null else { return value }
            guard let string = raw.stringValue, enumValues.contains(string), let parsed = E(rawValue: string) else {
                throw CommandInputParseError("\(name) must be one of \(enumValues.joined(separator: ", "))")
            }
            return parsed
        }
    }

    /// 必填字符串枚举字段：缺失或非法 rawValue 都抛出解析错误。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - type: 字符串 rawValue 枚举类型。
    ///   - description: 字段说明。
    /// - Returns: 解析为枚举值的命令字段。
    static func requiredEnum<E>(_ name: String,
                                type: E.Type,
                                description: String) -> CommandField<E>
        where E: RawRepresentable & CaseIterable & Sendable, E.RawValue == String {
        let enumValues = E.allCases.map { $0.rawValue }
        return CommandField(name: name,
                            schema: CommandFieldSchema(type: .string,
                                                       required: true,
                                                       description: description,
                                                       enumValues: enumValues)) { raw in
            guard let raw = raw, raw != .null else {
                throw CommandInputParseError("missing required parameter '\(name)'")
            }
            guard let string = raw.stringValue, enumValues.contains(string), let parsed = E(rawValue: string) else {
                throw CommandInputParseError("\(name) must be one of \(enumValues.joined(separator: ", "))")
            }
            return parsed
        }
    }
}
