import Foundation

/// 命令输入在 Swift 执行端需要的最小定义。
///
/// 该类型不是 JSON Schema，也不负责生成工具 metadata。它只保存 parser 可读取的字段名，
/// 以及由 `contracts/` 生成的 wire 校验闭包。公共 action 的校验闭包由合同生成器产生；
/// runtime extension 也可以只使用字段清单和顶层未知字段检查。
public struct CommandInputDefinition: Sendable {
    /// parser 必须读取的字段清单。
    public let fields: [AnyCommandField]

    /// 是否允许顶层 data object 携带未声明字段。
    public let additionalProperties: Bool

    private let validateWireInput: @Sendable (JSON) throws -> Void

    /// 没有字段且拒绝额外字段的输入定义。
    public static let empty = CommandInputDefinition(fields: [])

    /// 创建命令输入定义。
    ///
    /// - Parameters:
    ///   - fields: parser 可读取的字段。
    ///   - additionalProperties: 是否允许顶层未知字段。
    ///   - validate: 由合同生成器产生的额外 wire 结构校验；默认不增加规则。
    public init(fields: [AnyCommandField],
                additionalProperties: Bool = false,
                validate: @escaping @Sendable (JSON) throws -> Void = { _ in }) {
        let names = fields.map(\.name)
        precondition(Set(names).count == names.count, "command input fields must have unique names")
        self.fields = fields
        self.additionalProperties = additionalProperties
        self.validateWireInput = validate
    }

    /// 校验 wire data 并创建字段读取器。
    ///
    /// - Parameter data: `ExploreRequest.data` 中的原始对象。
    /// - Returns: 已完成合同结构校验的字段读取器。
    /// - Throws: 顶层未知字段或 generated wire 规则不满足时抛出 `CommandInputParseError`。
    public func makeDecoder(for data: JSON) throws -> CommandInputDecoder {
        if !additionalProperties {
            let declared = Set(fields.map(\.name))
            if let unknown = data.storage.keys.first(where: { !declared.contains($0) }) {
                throw CommandInputParseError("unknown command input field '\(unknown)'")
            }
        }
        try validateWireInput(data)
        return CommandInputDecoder(data, definition: self)
    }
}

/// 合同生成代码使用的 JSON wire 类型。
public enum CommandWireType: String, Sendable {
    case object
    case array
    case string
    case number
    case integer
    case boolean
    case null
}

/// generated Swift wire decoder 复用的 Foundation-only 校验原语。
///
/// 这里不解释 JSON Schema object。合同生成器已经把 schema 编译成对这些方法的直接调用，
/// 因此运行时没有第二套 schema parser，也不会把 description/default 等 annotation 当作规则。
public enum CommandWireValidation {
    private static let jsonSafeIntegerLimit = 9_007_199_254_740_991.0

    /// 校验一个字段的 JSON 类型、枚举、数字范围和数组长度。
    public static func value(_ raw: JSONValue?,
                             path: String,
                             required: Bool,
                             types: [CommandWireType],
                             enumValues: [JSONValue] = [],
                             minimum: Double? = nil,
                             maximum: Double? = nil,
                             exclusiveMinimum: Double? = nil,
                             exclusiveMaximum: Double? = nil,
                             minimumItems: Int? = nil,
                             maximumItems: Int? = nil,
                             uniqueItems: Bool = false) throws {
        guard let raw else {
            if required { throw CommandInputParseError("missing required parameter '\(path)'") }
            return
        }

        let actualType = try wireType(of: raw, path: path)
        let typeMatches = types.contains(actualType) || (actualType == .integer && types.contains(.number))
        guard typeMatches else {
            throw CommandInputParseError("\(path) must be \(typeDescription(types))")
        }
        if !enumValues.isEmpty, !enumValues.contains(raw) {
            throw CommandInputParseError("\(path) contains a value outside the declared enum")
        }

        if actualType == .number || actualType == .integer {
            guard let number = raw.doubleValue, number.isFinite else {
                throw CommandInputParseError("\(path) must be a finite number")
            }
            if actualType == .integer,
               (abs(number) > jsonSafeIntegerLimit || number.rounded(.towardZero) != number) {
                throw CommandInputParseError("\(path) must be a JSON safe integer")
            }
            if let minimum, number < minimum {
                throw CommandInputParseError("\(path) must be >= \(minimum)")
            }
            if let maximum, number > maximum {
                throw CommandInputParseError("\(path) must be <= \(maximum)")
            }
            if let exclusiveMinimum, number <= exclusiveMinimum {
                throw CommandInputParseError("\(path) must be > \(exclusiveMinimum)")
            }
            if let exclusiveMaximum, number >= exclusiveMaximum {
                throw CommandInputParseError("\(path) must be < \(exclusiveMaximum)")
            }
        }

        if case .array(let values) = raw {
            if let minimumItems, values.count < minimumItems {
                throw CommandInputParseError("\(path) must contain at least \(minimumItems) item(s)")
            }
            if let maximumItems, values.count > maximumItems {
                throw CommandInputParseError("\(path) must contain at most \(maximumItems) item(s)")
            }
            if uniqueItems {
                for index in values.indices {
                    if values[..<index].contains(values[index]) {
                        throw CommandInputParseError("\(path) must contain unique items")
                    }
                }
            }
        }
    }

    /// 校验对象中不存在合同未声明的属性。
    public static func object(_ object: JSON,
                              path: String,
                              allowedFields: Set<String>,
                              additionalProperties: Bool) throws {
        guard !additionalProperties else { return }
        if let unknown = object.storage.keys.first(where: { !allowedFields.contains($0) }) {
            throw CommandInputParseError("unknown field '\(path).\(unknown)'")
        }
    }

    private static func wireType(of value: JSONValue, path: String) throws -> CommandWireType {
        switch value {
        case .object: return .object
        case .array: return .array
        case .string: return .string
        case .bool: return .boolean
        case .null: return .null
        case .double(let number):
            guard number.isFinite else {
                throw CommandInputParseError("\(path) must be a finite number")
            }
            if abs(number) <= jsonSafeIntegerLimit, number.rounded(.towardZero) == number {
                return .integer
            }
            return .number
        }
    }

    private static func typeDescription(_ types: [CommandWireType]) -> String {
        types.map(\.rawValue).joined(separator: " or ")
    }
}
