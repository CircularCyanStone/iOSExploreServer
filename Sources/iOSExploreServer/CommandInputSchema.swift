import Foundation

/// 命令输入 schema 构造错误。
///
/// 当前主要用于在注册或测试阶段提前发现重复字段名，避免工具 schema 与运行时读取出现歧义。
public struct CommandInputSchemaError: Error, Sendable, Equatable {
    /// 面向日志和测试断言的错误说明。
    public let message: String

    /// 创建 schema 构造错误。
    ///
    /// - Parameter message: 错误说明。
    public init(_ message: String) {
        self.message = message
    }
}

/// 命令输入 schema 的跨字段约束。
///
/// JSON Schema 能表达一部分结构化约束；无法标准表达或暂不执行的业务约束会进入
/// `x-iosExplore-constraints`，供上层工具和文档展示。
public enum CommandInputConstraint: Sendable, Equatable {
    /// 要求给定字段中恰好一个出现。
    case exactlyOneOf([String])
    /// 以扩展字符串形式暴露的约束说明。
    case extensionMessage(String)
}

/// typed command 输入 schema。
///
/// 该类型把字段声明汇总成工具客户端可消费的 JSON Schema object，同时保留字段顺序、
/// 是否允许额外字段和跨字段约束。它只负责描述输入，不执行命令注册或路由校验。
public struct CommandInputSchema: Sendable, Equatable {
    /// 字段列表，顺序会同步输出到 `x-iosExplore-propertyOrder`。
    public let fields: [AnyCommandField]
    /// 是否允许 data object 携带 schema 未声明字段。
    public let additionalProperties: Bool
    /// 跨字段约束列表。
    public let constraints: [CommandInputConstraint]

    /// 空对象 schema。
    public static let empty = CommandInputSchema(fields: [])

    /// 创建输入 schema。
    ///
    /// - Parameters:
    ///   - fields: 字段列表。
    ///   - additionalProperties: 是否允许未声明字段。
    ///   - constraints: 跨字段约束列表。
    public init(fields: [AnyCommandField],
                additionalProperties: Bool = false,
                constraints: [CommandInputConstraint] = []) {
        self.fields = fields
        self.additionalProperties = additionalProperties
        self.constraints = constraints
    }

    /// 校验字段名唯一后创建输入 schema。
    ///
    /// - Parameters:
    ///   - fields: 字段列表。
    ///   - additionalProperties: 是否允许未声明字段。
    ///   - constraints: 跨字段约束列表。
    /// - Returns: 字段名唯一的输入 schema。
    /// - Throws: 发现重复字段名时抛出 `CommandInputSchemaError`。
    public static func validated(fields: [AnyCommandField],
                                 additionalProperties: Bool = false,
                                 constraints: [CommandInputConstraint] = []) throws -> CommandInputSchema {
        var seen: Set<String> = []
        for field in fields {
            if seen.contains(field.name) {
                throw CommandInputSchemaError("duplicate command input field '\(field.name)'")
            }
            seen.insert(field.name)
        }
        return CommandInputSchema(fields: fields,
                                  additionalProperties: additionalProperties,
                                  constraints: constraints)
    }

    /// 输出 JSON Schema object。
    ///
    /// - Returns: 包含 `type`、`properties`、`required`、`additionalProperties`、
    ///   `x-iosExplore-propertyOrder` 以及扩展约束的 JSON object。
    public func toJSON() -> JSON {
        var properties: [String: JSONValue] = [:]
        var required: [JSONValue] = []
        var order: [JSONValue] = []

        for field in fields {
            properties[field.name] = .object(field.schema.toJSON())
            order.append(.string(field.name))
            if field.schema.required {
                required.append(.string(field.name))
            }
        }

        var json: JSON = [
            "type": "object",
            "properties": .object(JSON(properties)),
            "required": .array(required),
            "additionalProperties": .bool(additionalProperties),
            "x-iosExplore-propertyOrder": .array(order),
        ]

        let exactlyOneOfGroups = constraints.compactMap { constraint -> [String]? in
            guard case .exactlyOneOf(let fieldNames) = constraint else { return nil }
            return fieldNames
        }
        let makeOneOfBranches: ([String]) -> [JSONValue] = { fieldNames in
            fieldNames.map { fieldName in
                .object(JSON(["required": .array([.string(fieldName)])]))
            }
        }
        if exactlyOneOfGroups.count == 1, let fieldNames = exactlyOneOfGroups.first {
            json["oneOf"] = .array(makeOneOfBranches(fieldNames))
        } else if exactlyOneOfGroups.count > 1 {
            json["allOf"] = .array(exactlyOneOfGroups.map { fieldNames in
                .object(JSON(["oneOf": .array(makeOneOfBranches(fieldNames))]))
            })
        }

        let extensionMessages = constraints.compactMap { constraint -> JSONValue? in
            guard case .extensionMessage(let message) = constraint else { return nil }
            return .string(message)
        }
        if !extensionMessages.isEmpty {
            json["x-iosExplore-constraints"] = .array(extensionMessages)
        }

        return json
    }
}
