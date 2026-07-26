import Foundation

public extension CommandFields {
    /// 必填数组字段；用于生成代码只需要执行定义、不需要重复保存字段说明的场景。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - itemsSchema: 数组元素的 JSON Schema object。
    ///   - minimumCount: 数组最小长度。
    ///   - maximumCount: 数组最大长度。
    /// - Returns: 解析为 `[JSONValue]` 的命令字段。
    static func requiredArray(_ name: String,
                              itemsSchema: JSON? = nil,
                              minimumCount: Int? = nil,
                              maximumCount: Int? = nil) -> CommandField<[JSONValue]> {
        requiredArray(name,
                      description: "",
                      itemsSchema: itemsSchema,
                      minimumCount: minimumCount,
                      maximumCount: maximumCount)
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
    static func requiredArray(_ name: String,
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

    /// 可选 nullable 字符串枚举数组；用于生成代码只需要执行定义、不需要重复保存字段说明的场景。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - values: 每个字符串元素允许的枚举值。
    ///   - itemDescription: 数组元素的可选 schema 说明。
    /// - Returns: 解析为 `[String]?` 的命令字段。
    static func optionalStringEnumArray(_ name: String,
                                        values: [String],
                                        itemDescription: String? = nil) -> CommandField<[String]?> {
        optionalStringEnumArray(name, values: values, itemDescription: itemDescription, description: "")
    }

    /// 可选 nullable 字符串枚举数组：缺失或 null 返回 nil，数组元素必须属于合同枚举。
    ///
    /// 该工厂有意保留重复元素，不输出 `uniqueItems`；需要去重的领域行为应由对应合同和 parser
    /// 单独声明，不能在通用 wire 字段中隐式改变输入顺序或数量。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - values: 每个字符串元素允许的枚举值。
    ///   - itemDescription: 数组元素的可选 schema 说明。
    ///   - description: 字段说明。
    /// - Returns: 解析为 `[String]?` 的命令字段。
    static func optionalStringEnumArray(_ name: String,
                                        values: [String],
                                        itemDescription: String? = nil,
                                        description: String) -> CommandField<[String]?> {
        precondition(!values.isEmpty, "\(name) item enum values must not be empty")
        var itemsSchema: JSON = [
            "type": .string("string"),
            "enum": .array(values.map(JSONValue.string)),
        ]
        if let itemDescription {
            itemsSchema["description"] = .string(itemDescription)
        }
        return CommandField(name: name,
                            schema: CommandFieldSchema(type: .array,
                                                       required: false,
                                                       description: description,
                                                       allowsNull: true,
                                                       extraSchema: ["items": .object(itemsSchema)])) { raw in
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
}
