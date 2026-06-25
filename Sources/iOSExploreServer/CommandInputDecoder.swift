import Foundation

/// typed command 输入字段读取器。
///
/// decoder 绑定原始 data 与 schema，负责拒绝未知字段、阻止读取未声明字段，并把单字段解析
/// 委托给 `CommandField`。它是值类型，不保存读取状态，方便命令模型在纯 Swift 测试中覆盖。
public struct CommandInputDecoder: Sendable {
    /// 原始命令 data。
    internal let data: JSON
    /// 当前输入模型的 schema。
    internal let schema: CommandInputSchema

    /// 供 `RawJSONInput` 取回原始 data 的内部入口。
    internal var rawDataForInternalUse: JSON { data }

    /// 创建字段读取器。
    ///
    /// - Parameters:
    ///   - data: `ExploreRequest.data` 中的原始参数对象。
    ///   - schema: 当前输入模型的 schema。
    public init(_ data: JSON, schema: CommandInputSchema) {
        self.data = data
        self.schema = schema
    }

    /// 校验 data 中不存在 schema 未声明字段。
    ///
    /// - Throws: 当 `additionalProperties == false` 且 data 包含未声明字段时抛出
    ///   `CommandInputParseError`。
    public func validateNoUnknownFields() throws {
        guard !schema.additionalProperties else { return }
        let declared = Set(schema.fields.map { $0.name })
        for key in data.storage.keys where !declared.contains(key) {
            throw CommandInputParseError("unknown command input field '\(key)'")
        }
    }

    /// 读取声明字段。
    ///
    /// - Parameter field: 必须已包含在当前 schema 中，且 schema 与声明完全一致的 typed 字段。
    /// - Returns: 字段解析后的 Swift typed 值。
    /// - Throws: 字段未声明、同名字段 schema 不一致或字段值校验失败时抛出 `CommandInputParseError`。
    public func read<Value>(_ field: CommandField<Value>) throws -> Value {
        guard let declaredField = schema.fields.first(where: { $0.name == field.name }) else {
            throw CommandInputParseError("command input field '\(field.name)' is not declared in schema")
        }
        guard declaredField.schema == field.schema else {
            throw CommandInputParseError("command input field '\(field.name)' schema does not match declaration")
        }
        return try field.decode(data[field.name])
    }

    /// 判断请求 data 是否显式携带声明字段。
    ///
    /// 该方法用于少数需要区分“缺省值生效”和“调用方显式传入默认值”的命令规则，例如
    /// UIKit tap 中 `coordinateSpace` 只允许和 window 坐标一起出现。方法会复用字段声明校验，
    /// 避免调用方绕开 schema 直接访问原始 JSON。
    ///
    /// - Parameter field: 必须已包含在当前 schema 中，且 schema 与声明完全一致的 typed 字段。
    /// - Returns: 请求 data 中是否包含该字段名。
    /// - Throws: 字段未声明或同名字段 schema 不一致时抛出 `CommandInputParseError`。
    public func contains<Value>(_ field: CommandField<Value>) throws -> Bool {
        guard let declaredField = schema.fields.first(where: { $0.name == field.name }) else {
            throw CommandInputParseError("command input field '\(field.name)' is not declared in schema")
        }
        guard declaredField.schema == field.schema else {
            throw CommandInputParseError("command input field '\(field.name)' schema does not match declaration")
        }
        return data.storage.keys.contains(field.name)
    }
}
