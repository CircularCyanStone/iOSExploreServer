import Foundation

/// typed command 输入解析失败。
///
/// 该错误面向命令 adapter 层：字段缺失、类型不匹配、范围越界、读取未声明字段等输入问题
/// 都应转换成这个轻量错误，再由上层命令决定如何映射到业务 envelope。
public struct CommandInputParseError: Error, Sendable, Equatable {
    /// 可直接进入日志或 `invalid_data` envelope 的错误说明。
    public let message: String

    /// 创建输入解析错误。
    ///
    /// - Parameter message: 面向调用方和日志的错误说明。
    public init(_ message: String) {
        self.message = message
    }
}

/// typed command 输入模型协议。
///
/// 命令可以把动态 `JSON` data 先解析为实现该协议的值类型，再进入业务执行逻辑。默认解析流程
/// 会先按 `inputSchema` 拒绝未知字段，再调用具体类型的 `parse(decoding:)` 读取字段。
public protocol CommandInput: Sendable {
    /// 当前输入模型暴露给工具客户端的字段 schema。
    static var inputSchema: CommandInputSchema { get }

    /// 从原始 JSON data 解析输入模型。
    ///
    /// - Parameter data: `ExploreRequest.data` 中的原始参数对象。
    /// - Returns: 已完成类型校验和默认值填充的输入模型。
    /// - Throws: 字段校验或模型自定义校验失败时抛出 `CommandInputParseError`。
    static func parse(from data: JSON) throws -> Self

    /// 从声明式 decoder 解析输入模型。
    ///
    /// - Parameter decoder: 绑定了 `inputSchema` 与原始 data 的字段读取器。
    /// - Returns: 已完成类型校验和默认值填充的输入模型。
    /// - Throws: 字段校验或模型自定义校验失败时抛出 `CommandInputParseError`。
    static func parse(decoding decoder: inout CommandInputDecoder) throws -> Self
}

public extension CommandInput {
    /// 默认解析入口：先拒绝未知字段，再交给模型读取声明字段。
    ///
    /// - Parameter data: `ExploreRequest.data` 中的原始参数对象。
    /// - Returns: 已完成类型校验和默认值填充的输入模型。
    /// - Throws: 字段校验或模型自定义校验失败时抛出 `CommandInputParseError`。
    static func parse(from data: JSON) throws -> Self {
        var decoder = CommandInputDecoder(data, schema: inputSchema)
        try decoder.validateNoUnknownFields()
        let value = try parse(decoding: &decoder)
        // 守卫：所有声明字段都必须在 parse(decoding:) 中被读取，避免“schema 暴露了字段
        // 但 parse 没读、调用方传值永远不生效”的静默漂移。详见 CommandInputDecoder。
        try decoder.assertAllDeclaredFieldsRead()
        return value
    }
}

/// 无参数命令的输入模型。
///
/// 该类型让命令可以显式声明“没有 data 字段”，默认 schema 会拒绝任何未知字段。
public struct EmptyCommandInput: CommandInput, Sendable, Equatable {
    /// 空对象 schema。
    public static let inputSchema = CommandInputSchema.empty

    /// 创建空输入。
    public init() {}

    /// 解析空输入。
    ///
    /// - Parameter decoder: 已通过未知字段校验的 decoder；该方法不会读取任何字段。
    /// - Returns: 空输入值。
    /// - Throws: 当前实现不抛出错误，签名保持与协议一致。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> EmptyCommandInput {
        EmptyCommandInput()
    }
}

/// 保留原始 JSON 的输入模型。
///
/// 该类型用于仍需手写解析或透传全部 data 的命令。它会绕过默认未知字段校验，避免 schema
/// 提前丢弃未来扩展字段。
public struct RawJSONInput: CommandInput, Sendable, Equatable {
    /// 允许任意字段的对象 schema。
    public static let inputSchema = CommandInputSchema(fields: [], additionalProperties: true)

    /// 原始 `ExploreRequest.data`。
    public let data: JSON

    /// 创建原始 JSON 输入。
    ///
    /// - Parameter data: 要保留的原始参数对象。
    public init(data: JSON) {
        self.data = data
    }

    /// 直接保留原始 JSON，跳过未知字段校验。
    ///
    /// - Parameter data: `ExploreRequest.data` 中的原始参数对象。
    /// - Returns: 包装了原始 data 的输入模型。
    /// - Throws: 当前实现不抛出错误，签名保持与协议一致。
    public static func parse(from data: JSON) throws -> RawJSONInput {
        RawJSONInput(data: data)
    }

    /// 从 decoder 中取回原始 JSON。
    ///
    /// - Parameter decoder: 绑定原始 data 的 decoder。
    /// - Returns: 包装了原始 data 的输入模型。
    /// - Throws: 当前实现不抛出错误，签名保持与协议一致。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> RawJSONInput {
        RawJSONInput(data: decoder.rawDataForInternalUse)
    }
}
