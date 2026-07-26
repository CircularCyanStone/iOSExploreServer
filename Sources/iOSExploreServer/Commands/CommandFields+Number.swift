import Foundation

/// 常用命令输入字段工厂。
///
/// 工厂集中定义字段 schema 与运行时解析规则，后续命令只组合这些字段即可得到一致的
/// JSON Schema 输出、默认值处理和错误类型。
///
/// 带默认值的布尔、整数和字符串枚举在公共 schema 中保持单一非 null 类型；调用方应省略
/// 字段来使用默认值。显式 null 会按类型错误拒绝，使字段工厂与 generated wire validator 保持一致。
/// 有限数字是否公开 nullable 则直接遵循对应合同声明。
public enum CommandFields {
    /// JSON/JavaScript 可精确表达的最大安全整数，避免 Double 承载协议数字时接受已失真的整数。
    private static let jsonSafeIntegerLimit = 9_007_199_254_740_991
}

public extension CommandFields {
    /// 布尔字段；用于生成代码只需要执行定义、不需要重复保存字段说明的场景。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - value: 字段缺失时使用的默认值。
    /// - Returns: 解析为 `Bool` 的命令字段。
    static func bool(_ name: String, default value: Bool) -> CommandField<Bool> {
        bool(name, default: value, description: "")
    }

    /// 布尔字段：缺失使用默认值，存在但为 null 或非布尔时抛出解析错误。
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
    static func bool(_ name: String, default value: Bool, description: String) -> CommandField<Bool> {
        CommandField(name: name,
                     schema: CommandFieldSchema(type: .boolean,
                                                required: false,
                                                description: description,
                                                defaultValue: .bool(value))) { raw in
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

    /// 可选有限数字字段；用于生成代码只需要执行定义、不需要重复保存字段说明的场景。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - minimum: 可选下界。
    ///   - maximum: 可选上界。
    ///   - exclusiveMinimum: 是否排除下界值。
    ///   - exclusiveMaximum: 是否排除上界值。
    /// - Returns: 解析为 `Double?` 的命令字段。
    static func optionalFiniteNumber(_ name: String,
                                     minimum: Double? = nil,
                                     maximum: Double? = nil,
                                     exclusiveMinimum: Bool = false,
                                     exclusiveMaximum: Bool = false) -> CommandField<Double?> {
        optionalFiniteNumber(name,
                             minimum: minimum,
                             maximum: maximum,
                             exclusiveMinimum: exclusiveMinimum,
                             exclusiveMaximum: exclusiveMaximum,
                             description: "")
    }

    /// 可选有限数字字段：缺失或 null 返回 nil，非有限数字或越界时抛出解析错误。
    ///
    /// `minimum` / `maximum` 与对应的 exclusive 开关同时驱动 schema 输出和运行时比较；
    /// exclusive 边界按 JSON Schema 数值关键字 `exclusiveMinimum` / `exclusiveMaximum` 输出。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - minimum: 可选下界。
    ///   - maximum: 可选上界。
    ///   - exclusiveMinimum: 是否排除下界值；仅在提供 `minimum` 时可设为 true。
    ///   - exclusiveMaximum: 是否排除上界值；仅在提供 `maximum` 时可设为 true。
    ///   - description: 字段说明。
    /// - Returns: 解析为 `Double?` 的命令字段。
    static func optionalFiniteNumber(_ name: String,
                                     minimum: Double? = nil,
                                     maximum: Double? = nil,
                                     exclusiveMinimum: Bool = false,
                                     exclusiveMaximum: Bool = false,
                                     description: String) -> CommandField<Double?> {
        validateFiniteNumberBounds(name: name,
                                   minimum: minimum,
                                   maximum: maximum,
                                   exclusiveMinimum: exclusiveMinimum,
                                   exclusiveMaximum: exclusiveMaximum)
        return CommandField(name: name,
                            schema: finiteNumberSchema(description: description,
                                                       defaultValue: nil,
                                                       minimum: minimum,
                                                       maximum: maximum,
                                                       exclusiveMinimum: exclusiveMinimum,
                                                       exclusiveMaximum: exclusiveMaximum)) { raw in
            guard let raw = raw, raw != .null else { return nil }
            let errorMessage = minimum == nil && maximum == nil
                ? "\(name) must be a finite number"
                : "\(name) must be a finite number within the declared range"
            guard let parsed = raw.doubleValue,
                  finiteNumberIsWithinBounds(parsed,
                                             minimum: minimum,
                                             maximum: maximum,
                                             exclusiveMinimum: exclusiveMinimum,
                                             exclusiveMaximum: exclusiveMaximum) else {
                throw CommandInputParseError(errorMessage)
            }
            return parsed
        }
    }

    /// 带默认值的有限数字字段；用于生成代码只需要执行定义、不需要重复保存字段说明的场景。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - value: 字段缺失时使用的默认值。
    ///   - minimum: 可选下界。
    ///   - maximum: 可选上界。
    ///   - exclusiveMinimum: 是否排除下界值。
    ///   - exclusiveMaximum: 是否排除上界值。
    /// - Returns: 解析为 `Double` 的命令字段。
    static func finiteNumber(_ name: String,
                             default value: Double,
                             minimum: Double? = nil,
                             maximum: Double? = nil,
                             exclusiveMinimum: Bool = false,
                             exclusiveMaximum: Bool = false) -> CommandField<Double> {
        finiteNumber(name,
                     default: value,
                     minimum: minimum,
                     maximum: maximum,
                     exclusiveMinimum: exclusiveMinimum,
                     exclusiveMaximum: exclusiveMaximum,
                     description: "")
    }

    /// 带默认值的有限数字字段：缺失返回默认值，null、非有限数字或越界时抛出解析错误。
    ///
    /// 默认值、inclusive/exclusive 边界和运行时校验来自同一声明；默认值必须为有限数且落在
    /// 声明范围内，否则在字段初始化时触发开发期断言。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - default: 字段缺失时使用的默认值。
    ///   - minimum: 可选下界。
    ///   - maximum: 可选上界。
    ///   - exclusiveMinimum: 是否排除下界值；仅在提供 `minimum` 时可设为 true。
    ///   - exclusiveMaximum: 是否排除上界值；仅在提供 `maximum` 时可设为 true。
    ///   - description: 字段说明。
    /// - Returns: 解析为 `Double` 的命令字段。
    static func finiteNumber(_ name: String,
                             default value: Double,
                             minimum: Double? = nil,
                             maximum: Double? = nil,
                             exclusiveMinimum: Bool = false,
                             exclusiveMaximum: Bool = false,
                             description: String) -> CommandField<Double> {
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
        return CommandField(name: name,
                            schema: finiteNumberSchema(description: description,
                                                       defaultValue: value,
                                                       minimum: minimum,
                                                       maximum: maximum,
                                                       exclusiveMinimum: exclusiveMinimum,
                                                       exclusiveMaximum: exclusiveMaximum)) { raw in
            guard let raw else { return value }
            guard raw != .null else {
                throw CommandInputParseError("\(name) must be a finite number within the declared range")
            }
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

    /// JSON number 字段；用于生成代码只需要执行定义、不需要重复保存字段说明的场景。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - required: 字段是否必填。
    /// - Returns: 解析为可选 `JSONValue` 的命令字段。
    static func number(_ name: String, required: Bool) -> CommandField<JSONValue?> {
        number(name, required: required, description: "")
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
    static func number(_ name: String, required: Bool, description: String) -> CommandField<JSONValue?> {
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

    /// 可选非负整数字段；用于生成代码只需要执行定义、不需要重复保存字段说明的场景。
    ///
    /// - Parameter name: 字段名。
    /// - Returns: 解析为 `Int?` 的命令字段。
    static func optionalNonNegativeInt(_ name: String) -> CommandField<Int?> {
        optionalNonNegativeInt(name, description: "")
    }

    /// 可选非负整数字段：缺失或 null 返回 nil，存在但非 JSON safe integer 范围内的有限整数或小于 0 抛出解析错误。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - description: 字段说明。
    /// - Returns: 解析为 `Int?` 的命令字段。
    static func optionalNonNegativeInt(_ name: String, description: String) -> CommandField<Int?> {
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

    /// 可选限定范围整数字段；用于生成代码只需要执行定义、不需要重复保存字段说明的场景。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - minimum: 可选闭区间下界。
    ///   - maximum: 可选闭区间上界。
    /// - Returns: 解析为 `Int?` 的命令字段。
    static func optionalInt(_ name: String, minimum: Int? = nil, maximum: Int? = nil) -> CommandField<Int?> {
        optionalInt(name, minimum: minimum, maximum: maximum, description: "")
    }

    /// 可选限定范围整数字段：缺失或 null 返回 nil，非有限整数、非 JSON safe integer 或越界时抛出解析错误。
    ///
    /// 该工厂供 generated wire 字段直接复用合同中的上下界；schema 输出和运行时校验共享同一组
    /// `minimum` / `maximum` 参数，避免生成声明与 parser 范围漂移。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - minimum: 可选闭区间下界。
    ///   - maximum: 可选闭区间上界。
    ///   - description: 字段说明。
    /// - Returns: 解析为 `Int?` 的命令字段。
    static func optionalInt(_ name: String,
                            minimum: Int? = nil,
                            maximum: Int? = nil,
                            description: String) -> CommandField<Int?> {
        if let minimum {
            precondition(isJSONSafeInteger(minimum), "\(name) minimum must be a JSON safe integer")
        }
        if let maximum {
            precondition(isJSONSafeInteger(maximum), "\(name) maximum must be a JSON safe integer")
        }
        if let minimum, let maximum {
            precondition(minimum <= maximum, "\(name) minimum must be <= maximum")
        }

        return CommandField(name: name,
                            schema: CommandFieldSchema(type: .integer,
                                                       required: false,
                                                       description: description,
                                                       allowsNull: true,
                                                       minimum: minimum.map(Double.init),
                                                       maximum: maximum.map(Double.init))) { raw in
            guard let raw, raw != .null else { return nil }
            guard let parsed = try parseInteger(raw, name: name),
                  minimum.map({ parsed >= $0 }) ?? true,
                  maximum.map({ parsed <= $0 }) ?? true else {
                throw CommandInputParseError("\(name) must be an integer within the declared range")
            }
            return parsed
        }
    }

    /// 必填限定范围整数字段；用于生成代码只需要执行定义、不需要重复保存字段说明的场景。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - range: 允许的闭区间。
    /// - Returns: 解析为 `Int` 的命令字段。
    static func requiredInt(_ name: String, range: ClosedRange<Int>) -> CommandField<Int> {
        requiredInt(name, range: range, description: "")
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
    static func requiredInt(_ name: String,
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

    /// 限定范围整数字段；用于生成代码只需要执行定义、不需要重复保存字段说明的场景。
    ///
    /// - Parameters:
    ///   - name: 字段名。
    ///   - range: 允许的闭区间。
    ///   - value: 字段缺失时使用的默认值。
    /// - Returns: 解析为 `Int` 的命令字段。
    static func int(_ name: String, range: ClosedRange<Int>, default value: Int) -> CommandField<Int> {
        int(name, range: range, default: value, description: "")
    }

    /// 限定范围整数字段：缺失使用默认值，null、非法整数或越界时抛出解析错误。
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
    static func int(_ name: String,
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

    /// 构造有限数字字段 schema，确保 exclusive 关键字与运行时边界使用相同输入。
    private static func finiteNumberSchema(description: String,
                                           defaultValue: Double?,
                                           minimum: Double?,
                                           maximum: Double?,
                                           exclusiveMinimum: Bool,
                                           exclusiveMaximum: Bool) -> CommandFieldSchema {
        var extra = JSON()
        if exclusiveMinimum, let minimum {
            extra["exclusiveMinimum"] = .double(minimum)
        }
        if exclusiveMaximum, let maximum {
            extra["exclusiveMaximum"] = .double(maximum)
        }
        return CommandFieldSchema(type: .number,
                                  required: false,
                                  description: description,
                                  defaultValue: defaultValue.map(JSONValue.double),
                                  allowsNull: true,
                                  minimum: exclusiveMinimum ? nil : minimum,
                                  maximum: exclusiveMaximum ? nil : maximum,
                                  extraSchema: extra)
    }

    /// 校验有限数字边界声明本身可形成非空区间。
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

    /// 判断有限数字是否满足声明的 inclusive/exclusive 边界。
    private static func finiteNumberIsWithinBounds(_ value: Double,
                                                   minimum: Double?,
                                                   maximum: Double?,
                                                   exclusiveMinimum: Bool,
                                                   exclusiveMaximum: Bool) -> Bool {
        guard value.isFinite else { return false }
        if let minimum, exclusiveMinimum ? value <= minimum : value < minimum {
            return false
        }
        if let maximum, exclusiveMaximum ? value >= maximum : value > maximum {
            return false
        }
        return true
    }

    /// 判断 Swift 整数是否可作为 JSON safe integer 精确暴露到协议层。
    private static func isJSONSafeInteger(_ value: Int) -> Bool {
        value >= -jsonSafeIntegerLimit && value <= jsonSafeIntegerLimit
    }
}
