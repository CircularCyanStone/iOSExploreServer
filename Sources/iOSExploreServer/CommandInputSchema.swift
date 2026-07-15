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

/// `oneOf` 约束中的单个分支。
///
/// 分支用必填字段表达一种合法输入形态，并可通过 `forbiddenAnyOf` 排除同请求中不应同时
/// 出现的字段组合。它只用于 schema 输出；运行时仍由具体 `CommandInput.parse` 做精确校验。
public struct CommandInputOneOfBranch: Sendable, Equatable {
    /// 当前分支要求同时存在的字段。
    public let required: [String]
    /// 当前分支禁止出现的字段组合；每个内层数组会输出为一个 `required` 条件。
    public let forbiddenAnyOf: [[String]]

    /// 创建 `oneOf` 分支。
    ///
    /// - Parameters:
    ///   - required: 当前分支要求同时存在的字段。
    ///   - forbiddenAnyOf: 当前分支禁止出现的字段组合。
    public init(required: [String], forbiddenAnyOf: [[String]] = []) {
        self.required = required
        self.forbiddenAnyOf = forbiddenAnyOf
    }

    /// 输出 JSON Schema 分支 object。
    ///
    /// - Returns: 可放入 `oneOf` 数组的 schema object。
    public func toJSON() -> JSON {
        var json: JSON = ["required": .array(required.map { .string($0) })]
        if !forbiddenAnyOf.isEmpty {
            let anyOf = forbiddenAnyOf.map { fields -> JSONValue in
                .object(JSON(["required": .array(fields.map { .string($0) })]))
            }
            json["not"] = .object(JSON(["anyOf": .array(anyOf)]))
        }
        return json
    }
}

/// 命令输入 schema 的跨字段约束。
///
/// JSON Schema 能表达一部分结构化约束；无法标准表达或暂不执行的业务约束会进入
/// `x-iosExplore-constraints`，供上层工具和文档展示。
///
/// - Important (设计特性 F-25，勿当 bug 重提): 本枚举的所有约束（含 `exactlyOneOf` 与
///   `oneOf`）**只在 `CommandInputSchema.toJSON()` 生成给 MCP 客户端的 JSON Schema
///   描述时被消费**，作用是向工具客户端声明字段之间的互斥/必选关系。**运行时
///   `CommandInput.parse(from:)` 不会评估这些约束**——默认解析入口只做三件事：拒绝未知
///   字段、逐字段按声明类型读取、断言每个声明字段都被读到（`assertAllDeclaredFieldsRead`）。
///   它不会因为"互斥字段同时出现"或"必选字段都没出现"而报错。因此，凡是 schema 里声明了
///   `exactlyOneOf` 的命令，**必须**在自身的 `parse(decoding:)` 里手写互斥/必选校验，
///   参考实现见 `UIKitViewLookupTarget.parse`（identifier 与 path 二选一的互斥兜底就写在
///   那里）。若漏写，运行时会静默接受 schema 上声明互斥的两个字段，只在客户端侧靠 schema
///   提示拦截，服务端不拦——这是已知设计特性，不是 bug。新增带互斥字段的命令时，务必
///   同步补上手写校验，别误以为"声明了 exactlyOneOf 就安全"。
public enum CommandInputConstraint: Sendable, Equatable {
    /// 要求给定字段中恰好一个出现。
    ///
    /// - Warning (F-25): 该约束只影响 `toJSON()` 输出的 schema 描述，`CommandInput.parse(from:)`
    ///   运行时**不**强制。使用此约束的命令必须在 `parse(decoding:)` 里自行实现"恰好一个"
    ///   的校验（参考 `UIKitViewLookupTarget.parse`），否则运行时会静默接受两个字段。
    case exactlyOneOf([String])
    /// 输出显式 `oneOf` 分支，用于表达成对字段、互斥字段和补充禁止条件。
    case oneOf([CommandInputOneOfBranch])
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
        if let duplicate = Self.duplicateFieldName(in: fields) {
            preconditionFailure(Self.duplicateFieldMessage(for: duplicate))
        }
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
        if let duplicate = duplicateFieldName(in: fields) {
            throw CommandInputSchemaError(duplicateFieldMessage(for: duplicate))
        }
        return CommandInputSchema(fields: fields,
                                  additionalProperties: additionalProperties,
                                  constraints: constraints)
    }

    private static func duplicateFieldName(in fields: [AnyCommandField]) -> String? {
        var seen: Set<String> = []
        for field in fields {
            if !seen.insert(field.name).inserted {
                return field.name
            }
        }
        return nil
    }

    private static func duplicateFieldMessage(for name: String) -> String {
        "duplicate command input field '\(name)'"
    }

    /// 输出 JSON Schema object。
    ///
    /// - Returns: 包含 `type`、`properties`、`required`、`additionalProperties`、
    ///   `x-iosExplore-propertyOrder` 的 JSON object；并视跨字段约束输出 `oneOf`
    ///   （单约束单元）或 `allOf` 嵌套 `oneOf`（多约束单元），以及
    ///   `x-iosExplore-constraints` 扩展说明。
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

        // 收集所有会产生 oneOf 语义的约束单元：每个 `exactlyOneOf` 是一个单元，每个
        // `oneOf(branches)` 整体也是一个单元。单元数决定输出形态——
        //   0 个：不输出；
        //   1 个：直接作为顶层 `oneOf`；
        //  >=2 个：用 `allOf` 嵌套多组 `oneOf`。
        // 统一收集是为了避免“顶层 `oneOf` 键被后写单元静默覆盖”：`exactlyOneOf` 与
        // `oneOf(branches)` 若分别写顶层 `oneOf`，后者会覆盖前者，丢掉一组约束。
        var oneOfUnits: [[JSONValue]] = []
        for constraint in constraints {
            switch constraint {
            case .exactlyOneOf(let fieldNames):
                oneOfUnits.append(fieldNames.map { fieldName in
                    .object(JSON(["required": .array([.string(fieldName)])]))
                })
            case .oneOf(let branches):
                oneOfUnits.append(branches.map { .object($0.toJSON()) })
            case .extensionMessage:
                continue
            }
        }
        switch oneOfUnits.count {
        case 0:
            break
        case 1:
            json["oneOf"] = .array(oneOfUnits[0])
        default:
            json["allOf"] = .array(oneOfUnits.map { unit in
                .object(JSON(["oneOf": .array(unit)]))
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
