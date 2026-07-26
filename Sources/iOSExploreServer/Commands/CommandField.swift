import Foundation

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
