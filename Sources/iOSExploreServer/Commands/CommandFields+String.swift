import Foundation

public extension CommandFields {
    /// 可选字符串字段；用于生成代码只需要执行定义、不需要重复保存字段说明的场景。
    ///
    /// - Parameter name: 字段名。
    /// - Returns: 解析为 `String?` 的命令字段。
    static func optionalString(_ name: String) -> CommandField<String?> {
        optionalString(name, description: "")
    }

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

    /// 必填字符串字段；用于生成代码只需要执行定义、不需要重复保存字段说明的场景。
    ///
    /// - Parameter name: 字段名。
    /// - Returns: 解析为 `String` 的命令字段。
    static func requiredString(_ name: String) -> CommandField<String> {
        requiredString(name, description: "")
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

    /// 必填 raw string 枚举字段；用于生成代码只需要执行定义、不需要重复保存字段说明的场景。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - values: 合同允许的字符串值。
    /// - Returns: 解析为 `String` 的命令字段。
    static func requiredStringEnum(_ name: String, values: [String]) -> CommandField<String> {
        requiredStringEnum(name, values: values, description: "")
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

    /// 带默认值的 raw string 枚举字段；用于生成代码只需要执行定义、不需要重复保存字段说明的场景。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - values: 合同允许的字符串值。
    ///   - value: 字段缺失时使用的默认值。
    /// - Returns: 解析为 `String` 的命令字段。
    static func stringEnum(_ name: String, values: [String], default value: String) -> CommandField<String> {
        stringEnum(name, values: values, default: value, description: "")
    }

    /// 带默认值的 raw string 枚举字段：缺失时返回合同默认字符串，null 或非法值抛出解析错误。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - values: 合同允许的字符串值。
    ///   - default: 字段缺失时使用的默认值。
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

    /// 可选 raw string 枚举字段；用于生成代码只需要执行定义、不需要重复保存字段说明的场景。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - values: 合同允许的字符串值。
    /// - Returns: 解析为 `String?` 的命令字段。
    static func optionalStringEnum(_ name: String, values: [String]) -> CommandField<String?> {
        optionalStringEnum(name, values: values, description: "")
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

    /// 字符串枚举字段；用于生成代码只需要执行定义、不需要重复保存字段说明的场景。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - type: 字符串 rawValue 枚举类型。
    ///   - value: 字段缺失时使用的默认枚举值。
    /// - Returns: 解析为枚举值的命令字段。
    static func enumValue<E>(_ name: String,
                             type: E.Type,
                             default value: E) -> CommandField<E>
        where E: RawRepresentable & CaseIterable & Sendable, E.RawValue == String {
        enumValue(name, type: type, default: value, description: "")
    }

    /// 字符串枚举字段：缺失使用默认值，null 或非法 rawValue 抛出解析错误。
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
            guard let raw else { return value }
            guard raw != .null else {
                throw CommandInputParseError("\(name) must be one of \(enumValues.joined(separator: ", "))")
            }
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
