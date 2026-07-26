import Foundation

/// 命令输入字段可暴露的 JSON Schema 基础类型。
///
/// 该枚举只描述协议层 JSON 类型，不承载 Swift 具体类型；整数语义通过 `.integer`
/// 和字段 decoder 的有限整数校验共同保证。
public enum CommandJSONSchemaType: String, Sendable, Equatable {
    /// JSON string。
    case string
    /// JSON number。
    case number
    /// JSON integer。
    case integer
    /// JSON boolean。
    case boolean
    /// JSON object。
    case object
    /// JSON array。
    case array
}

/// 单个命令输入字段的 JSON Schema 描述。
///
/// `CommandField` 用它生成工具可读 schema；运行时解析仍由字段自己的 decode 闭包负责，
/// 这样 schema 输出和 Swift typed 读取能保持在同一个声明来源。
public struct CommandFieldSchema: Sendable, Equatable {
    /// 字段 JSON 类型。
    public let type: CommandJSONSchemaType
    /// 字段是否必填；最终汇总到 `CommandInputSchema.required`。
    public let required: Bool
    /// 面向工具客户端和人的字段说明。
    public let description: String
    /// 缺省值，缺失字段读取时会使用同一值。
    public let defaultValue: JSONValue?
    /// 字段是否接受显式 JSON null；可选字段运行时会把 null 解析为 nil，schema 也必须同步暴露。
    public let allowsNull: Bool
    /// 数值或整数下界。
    public let minimum: Double?
    /// 数值或整数上界。
    public let maximum: Double?
    /// 字符串枚举允许值。
    public let enumValues: [String]?
    /// 额外 schema 键值，用于表达 `items` / `properties` 等基础标量字段工厂未覆盖的结构。
    public let extraSchema: JSON

    /// 创建字段 schema 描述。
    ///
    /// - Parameters:
    ///   - type: 字段 JSON 类型。
    ///   - required: 字段是否必填。
    ///   - description: 字段说明。
    ///   - defaultValue: 缺省值。
    ///   - allowsNull: 字段是否接受显式 JSON null。
    ///   - minimum: 数值或整数下界。
    ///   - maximum: 数值或整数上界。
    ///   - enumValues: 字符串枚举允许值。
    ///   - extraSchema: 额外 schema 键值，用于补充数组元素、对象属性等复杂结构约束。
    public init(type: CommandJSONSchemaType,
                required: Bool,
                description: String,
                defaultValue: JSONValue? = nil,
                allowsNull: Bool = false,
                minimum: Double? = nil,
                maximum: Double? = nil,
                enumValues: [String]? = nil,
                extraSchema: JSON = JSON()) {
        self.type = type
        self.required = required
        self.description = description
        self.defaultValue = defaultValue
        self.allowsNull = allowsNull
        self.minimum = minimum
        self.maximum = maximum
        self.enumValues = enumValues
        self.extraSchema = extraSchema
    }

    /// 输出单字段 JSON Schema object。
    ///
    /// - Returns: 可嵌入 `properties` 的 JSON object。
    public func toJSON() -> JSON {
        let schemaType: JSONValue
        if allowsNull {
            schemaType = .array([.string(type.rawValue), .string("null")])
        } else {
            schemaType = .string(type.rawValue)
        }
        var json: JSON = [
            "type": schemaType,
            "description": .string(description),
        ]
        if let defaultValue = defaultValue {
            json["default"] = defaultValue
        }
        if let minimum = minimum {
            json["minimum"] = .double(minimum)
        }
        if let maximum = maximum {
            json["maximum"] = .double(maximum)
        }
        if let enumValues = enumValues {
            var values = enumValues.map { JSONValue.string($0) }
            if allowsNull {
                values.append(.null)
            }
            json["enum"] = .array(values)
        }
        for (key, value) in extraSchema.storage {
            json[key] = value
        }
        return json
    }
}

/// 类型擦除后的命令输入字段。
///
/// `CommandInputSchema` 只需要字段名与 schema，不需要知道字段最终解析成哪种 Swift 类型。
public struct AnyCommandField: Sendable, Equatable {
    /// 字段名，对应命令 data object 的 key。
    public let name: String
    /// 字段 schema 描述。
    public let schema: CommandFieldSchema

    /// 创建类型擦除字段。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - schema: 字段 schema 描述。
    public init(name: String, schema: CommandFieldSchema) {
        self.name = name
        self.schema = schema
    }
}
