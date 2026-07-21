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
            json["enum"] = .array(enumValues.map { .string($0) })
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

/// 单个 typed 命令输入字段。
///
/// 字段同时携带 schema 与解析闭包；调用方通过 `CommandInputDecoder.read(_:)` 得到强类型值，
/// 避免在各命令里重复散写 JSON 类型判断、默认值和范围校验。
public struct CommandField<Value: Sendable>: Sendable {
    /// 字段名，对应命令 data object 的 key。
    public let name: String
    /// 字段 schema 描述。
    public let schema: CommandFieldSchema
    /// 从原始 JSON 值解析出 Swift typed 值。
    internal let decode: @Sendable (JSONValue?) throws -> Value

    /// 类型擦除视图，供 `CommandInputSchema` 汇总字段列表。
    public var erased: AnyCommandField {
        AnyCommandField(name: name, schema: schema)
    }

    /// 创建 typed 命令字段。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - schema: 字段 schema 描述。
    ///   - decode: 从原始 JSON 值解析出 Swift typed 值的闭包。
    internal init(name: String,
                  schema: CommandFieldSchema,
                  decode: @escaping @Sendable (JSONValue?) throws -> Value) {
        self.name = name
        self.schema = schema
        self.decode = decode
    }
}

/// 常用命令输入字段工厂。
///
/// 工厂集中定义字段 schema 与运行时解析规则，后续命令只组合这些字段即可得到一致的
/// JSON Schema 输出、默认值处理和错误类型。
public enum CommandFields {
    /// JSON/JavaScript 可精确表达的最大安全整数，避免 Double 承载协议数字时接受已失真的整数。
    private static let jsonSafeIntegerLimit = 9_007_199_254_740_991

    /// 布尔字段：缺失使用默认值，存在但非布尔抛出解析错误。
    ///
    /// - Important (设计特性 F-26，勿当 bug 重提): 本工厂对"布尔"采用**严格**判定——只接受
    ///   JSON `true`/`false`，JSON number 一律拒绝。例如 `"submit": 1` 或 `"animated": 0`
    ///   会被判为非布尔，抛出 `"<name> must be a boolean"`（运行时映射为 `invalid_data`）。
    ///   这是有意的严格设计，保证布尔字段不接受隐式数字→布尔转换。**唯一的例外**是
    ///   `ui.control.sendAction` 写 UISwitch 时的 `value` 字段——它走 `UIKitActionExecutor`
    ///   的 `switchBoolValue`，额外接受 JSON number `0`/`1` 当 bool，详见该处注释。该例外
    ///   **仅限 UISwitch 的 value**，不要推广到 submit/animated/includeHidden 等其它布尔
    ///   字段，它们仍严格拒数字。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - default: 字段缺失时使用的默认值。
    ///   - description: 字段说明。
    /// - Returns: 解析为 `Bool` 的命令字段。
    public static func bool(_ name: String, default value: Bool, description: String) -> CommandField<Bool> {
        CommandField(name: name,
                     schema: CommandFieldSchema(type: .boolean,
                                                required: false,
                                                description: description,
                                                defaultValue: .bool(value))) { raw in
            guard let raw = raw, raw != .null else { return value }
            guard let parsed = raw.boolValue else {
                throw CommandInputParseError("\(name) must be a boolean")
            }
            return parsed
        }
    }

    /// 可选字符串字段：缺失或 null 返回 nil，存在但非字符串抛出解析错误。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - description: 字段说明。
    /// - Returns: 解析为 `String?` 的命令字段。
    public static func optionalString(_ name: String, description: String) -> CommandField<String?> {
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
    public static func requiredString(_ name: String, description: String) -> CommandField<String> {
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

    /// 必填数组字段：缺失或 null 抛出解析错误，存在但非数组也抛出解析错误。
    ///
    /// 该工厂用于需要在 schema 里声明 `items` 的命令输入，例如批量字段数组。调用方可以通过
    /// `itemsSchema` 让工具客户端看见数组元素结构，同时在 `decode` 里拿到原始数组值做后续逐项解析。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - description: 字段说明。
    ///   - itemsSchema: 数组元素的 JSON Schema object。
    ///   - minimumCount: 数组最小长度。
    ///   - maximumCount: 数组最大长度。
    /// - Returns: 解析为 `[JSONValue]` 的命令字段。
    public static func requiredArray(_ name: String,
                                     description: String,
                                     itemsSchema: JSON? = nil,
                                     minimumCount: Int? = nil,
                                     maximumCount: Int? = nil) -> CommandField<[JSONValue]> {
        precondition(minimumCount == nil || minimumCount! >= 0, "\(name) minimumCount must be non-negative")
        precondition(maximumCount == nil || maximumCount! >= 0, "\(name) maximumCount must be non-negative")
        if let minimumCount, let maximumCount, minimumCount > maximumCount {
            preconditionFailure("\(name) minimumCount must be <= maximumCount")
        }
        var extra = JSON()
        if let itemsSchema {
            extra["items"] = .object(itemsSchema)
        }
        if let minimumCount {
            extra["minItems"] = .double(Double(minimumCount))
        }
        if let maximumCount {
            extra["maxItems"] = .double(Double(maximumCount))
        }
        return CommandField(name: name,
                            schema: CommandFieldSchema(type: .array,
                                                       required: true,
                                                       description: description,
                                                       extraSchema: extra)) { raw in
            guard let raw = raw, raw != .null else {
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

    /// 可选有限数字字段：缺失或 null 返回 nil，存在但非有限数字抛出解析错误。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - description: 字段说明。
    /// - Returns: 解析为 `Double?` 的命令字段。
    public static func optionalFiniteNumber(_ name: String, description: String) -> CommandField<Double?> {
        CommandField(name: name,
                     schema: CommandFieldSchema(type: .number,
                                                required: false,
                                                description: description,
                                                allowsNull: true)) { raw in
            guard let raw = raw, raw != .null else { return nil }
            guard let parsed = raw.doubleValue, parsed.isFinite else {
                throw CommandInputParseError("\(name) must be a finite number")
            }
            return parsed
        }
    }

    /// JSON number 字段：按 required 决定是否必填，并保留原始 `JSONValue` 供执行层区分数字/布尔。
    ///
    /// 常规数值命令优先使用 `optionalFiniteNumber` 或整数工厂；本工厂用于需要把可选原始 JSON
    /// 值穿过 typed input 边界的命令，例如 `ui.control.sendAction` 的 `value`。schema 对外声明
    /// 为 number；运行时额外接受 boolean，供 UISwitch 这类布尔值控件在同一个字段里表达开关状态。
    /// 既非有限 number 也非 boolean 的值会以 `"\(name) must be a finite number"` 文案报错
    /// （文案沿用 number 工厂历史口径，未单独提及 boolean 例外）。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - required: 字段是否必填。
    ///   - description: 字段说明。
    /// - Returns: 解析为可选 `JSONValue` 的命令字段。
    public static func number(_ name: String, required: Bool, description: String) -> CommandField<JSONValue?> {
        CommandField(name: name,
                     schema: CommandFieldSchema(type: .number,
                                                required: required,
                                                description: description,
                                                allowsNull: !required)) { raw in
            guard let raw = raw, raw != .null else {
                if required {
                    throw CommandInputParseError("missing required parameter '\(name)'")
                }
                return nil
            }
            if let parsed = raw.doubleValue, parsed.isFinite {
                return .double(parsed)
            }
            if let parsed = raw.boolValue {
                return .bool(parsed)
            }
            throw CommandInputParseError("\(name) must be a finite number")
        }
    }

    /// 可选非负整数字段：缺失或 null 返回 nil，存在但非 JSON safe integer 范围内的有限整数或小于 0 抛出解析错误。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - description: 字段说明。
    /// - Returns: 解析为 `Int?` 的命令字段。
    public static func optionalNonNegativeInt(_ name: String, description: String) -> CommandField<Int?> {
        CommandField(name: name,
                     schema: CommandFieldSchema(type: .integer,
                                                required: false,
                                                description: description,
                                                allowsNull: true,
                                                minimum: 0,
                                                maximum: Double(jsonSafeIntegerLimit))) { raw in
            guard let raw = raw, raw != .null else { return nil }
            guard let parsed = try parseInteger(raw, name: name), parsed >= 0 else {
                throw CommandInputParseError("\(name) must be a non-negative integer")
            }
            return parsed
        }
    }

    /// 必填限定范围整数字段：缺失、null、非 JSON safe integer、非有限整数或越界时抛出解析错误。
    ///
    /// 用于调用方必须明确选择目标的场景，例如导航栏按钮下标。与带默认值的 `int` 不同，本字段
    /// 会在 schema 的 required 列表里出现，避免工具客户端误以为可以省略。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - range: 允许的闭区间。
    ///   - description: 字段说明。
    /// - Returns: 解析为 `Int` 的命令字段。
    public static func requiredInt(_ name: String,
                                   range: ClosedRange<Int>,
                                   description: String) -> CommandField<Int> {
        precondition(range.lowerBound <= jsonSafeIntegerLimit && range.upperBound >= -jsonSafeIntegerLimit,
                     "\(name) range must include at least one JSON safe integer")

        let schemaMinimum = Double(Swift.max(range.lowerBound, -jsonSafeIntegerLimit))
        let schemaMaximum = Double(Swift.min(range.upperBound, jsonSafeIntegerLimit))
        return CommandField(name: name,
                            schema: CommandFieldSchema(type: .integer,
                                                       required: true,
                                                       description: description,
                                                       minimum: schemaMinimum,
                                                       maximum: schemaMaximum)) { raw in
            guard let raw = raw, raw != .null else {
                throw CommandInputParseError("missing required parameter '\(name)'")
            }
            guard let parsed = try parseInteger(raw, name: name), range.contains(parsed) else {
                throw CommandInputParseError("\(name) must be an integer between \(range.lowerBound) and \(range.upperBound)")
            }
            return parsed
        }
    }

    /// 限定范围整数字段：缺失使用默认值，存在但非 JSON safe integer、非有限整数或越界抛出解析错误。
    ///
    /// `default` 必须落在 `range` 内；这是声明字段时的开发期不变量。工厂本身非 throwing，
    /// 因此发现不一致时用 `preconditionFailure` 立即暴露，避免 schema 默认值与运行时校验漂移。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - range: 允许的闭区间。
    ///   - default: 字段缺失时使用的默认值。
    ///   - description: 字段说明。
    /// - Returns: 解析为 `Int` 的命令字段。
    public static func int(_ name: String,
                           range: ClosedRange<Int>,
                           default value: Int,
                           description: String) -> CommandField<Int> {
        guard range.contains(value) else {
            preconditionFailure("\(name) default must be within range \(range.lowerBound)...\(range.upperBound)")
        }
        precondition(isJSONSafeInteger(value), "\(name) default must be a JSON safe integer")
        precondition(range.lowerBound <= jsonSafeIntegerLimit && range.upperBound >= -jsonSafeIntegerLimit,
                     "\(name) range must include at least one JSON safe integer")

        let schemaMinimum = Double(Swift.max(range.lowerBound, -jsonSafeIntegerLimit))
        let schemaMaximum = Double(Swift.min(range.upperBound, jsonSafeIntegerLimit))
        return CommandField(name: name,
                            schema: CommandFieldSchema(type: .integer,
                                                       required: false,
                                                       description: description,
                                                       defaultValue: .double(Double(value)),
                                                       minimum: schemaMinimum,
                                                       maximum: schemaMaximum)) { raw in
            guard let raw = raw, raw != .null else { return value }
            guard let parsed = try parseInteger(raw, name: name), range.contains(parsed) else {
                throw CommandInputParseError("\(name) must be an integer between \(range.lowerBound) and \(range.upperBound)")
            }
            return parsed
        }
    }

    /// 字符串枚举字段：缺失或 null 使用默认值，不在枚举 rawValue 集合中抛出解析错误。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - type: 字符串 rawValue 枚举类型。
    ///   - default: 字段缺失时使用的默认枚举值。
    ///   - description: 字段说明。
    /// - Returns: 解析为枚举值的命令字段。
    public static func enumValue<E>(_ name: String,
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
    public static func requiredEnum<E>(_ name: String,
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

    /// 从 JSON number 解析有限且处于 JSON safe integer 范围内的整数。
    ///
    /// - Parameters:
    ///   - raw: 原始 JSON 值。
    ///   - name: 字段名，用于错误文案。
    /// - Returns: 可精确表示且未超过 JSON safe integer 边界的 Swift `Int`。
    /// - Throws: 原始值不是有限整数或超过 JSON safe integer 边界时抛出 `CommandInputParseError`。
    private static func parseInteger(_ raw: JSONValue, name: String) throws -> Int? {
        guard let double = raw.doubleValue, double.isFinite,
              abs(double) <= Double(jsonSafeIntegerLimit),
              double.rounded(.towardZero) == double,
              let value = Int(exactly: double) else {
            throw CommandInputParseError("\(name) must be an integer")
        }
        return value
    }

    /// 判断 Swift 整数是否可作为 JSON safe integer 精确暴露到协议层。
    private static func isJSONSafeInteger(_ value: Int) -> Bool {
        value >= -jsonSafeIntegerLimit && value <= jsonSafeIntegerLimit
    }
}
