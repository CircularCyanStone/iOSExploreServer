#if canImport(UIKit)
import Foundation
import iOSExploreServer

/// `ui.webView.eval` 命令的输入模型。
///
/// 通过 `accessibilityIdentifier` 或 `path` 定位 WKWebView，执行 JavaScript 代码。
/// 支持两种模式：
/// - `script`（同步）：直接执行 JS 代码，最后一个表达式的值自动作为返回值
/// - `function`（异步）：执行 async function body（iOS 14+，自动降级）
///
/// `arguments` 只能与 `function` 一起使用，作为函数的第一个参数传入。
/// `timeout` 范围 1-30 秒，默认 5 秒。
public struct UIWebViewEvalInput: CommandInput, Sendable {
    private enum Fields {
        static let accessibilityIdentifier = UIKitLocatorFields.accessibilityIdentifier
        static let path = UIKitLocatorFields.path
        static let viewSnapshotID = UIKitLocatorFields.viewSnapshotID

        static let script = CommandFields.optionalString(
            "script", description: "JS 代码字符串（同步模式），与 function 互斥"
        )
        static let function = CommandFields.optionalString(
            "function", description: "JS 函数体（异步模式），与 script 互斥"
        )

        /// arguments 是 JSON object，无法用标量 `CommandField<Value>` 表达，故只用 `AnyCommandField`
        /// 声明 schema；实际解析在 `parse(from:)` 手写。
        static let arguments = AnyCommandField(
            name: "arguments",
            schema: CommandFieldSchema(type: .object,
                                       required: false,
                                       description: "传递给 function 的参数，只能与 function 一起使用",
                                       allowsNull: true)
        )

        static let timeout = CommandFields.optionalFiniteNumber(
            "timeout", description: "超时时间（秒），范围 1-30，默认 5.0"
        )

        static let all: [AnyCommandField] = [
            accessibilityIdentifier.erased,
            path.erased,
            viewSnapshotID.erased,
            script.erased,
            function.erased,
            arguments,
            timeout.erased,
        ]
    }

    /// 目标 WKWebView 定位方式。
    public let target: UIKitViewLookupTarget
    /// 陈旧校验快照 ID（来自 `ui.inspect`）。
    public let viewSnapshotID: String?
    /// JS 代码字符串（同步模式）。
    public let script: String?
    /// JS 函数体（异步模式）。
    public let function: String?
    /// 传递给 function 的参数。
    public let arguments: [String: Any]?
    /// 超时时间（秒）。
    public let timeout: TimeInterval

    /// 创建输入。
    public init(target: UIKitViewLookupTarget,
                viewSnapshotID: String?,
                script: String?,
                function: String?,
                arguments: [String: Any]?,
                timeout: TimeInterval) {
        self.target = target
        self.viewSnapshotID = viewSnapshotID
        self.script = script
        self.function = function
        self.arguments = arguments
        self.timeout = timeout
    }

    /// 输入 schema（暴露给 MCP 客户端）。
    public static let inputSchema = CommandInputSchema(
        fields: Fields.all,
        constraints: []
    )

    /// 从原始 JSON data 解析输入。
    ///
    /// arguments 是 JSON object，无法走 `CommandField<Value>` + `decoder.read` 的标量机制，故在此手写：
    /// 先用 decoder 拒绝未知顶层字段并读取标量字段，再从 data 手写解析 arguments。
    ///
    /// - Parameter data: `ExploreRequest.data` 中的原始参数对象。
    /// - Returns: 已解析的 webView.eval 输入。
    /// - Throws: 字段类型/互斥/范围校验失败时抛 `CommandInputParseError`。
    public static func parse(from data: JSON) throws -> UIWebViewEvalInput {
        var decoder = CommandInputDecoder(data, schema: inputSchema)
        try decoder.validateNoUnknownFields()
        let viewSnapshotID = try decoder.read(Fields.viewSnapshotID)
        let script = try decoder.read(Fields.script)
        let function = try decoder.read(Fields.function)
        let timeout = try decoder.read(Fields.timeout) ?? 5.0
        let target = try UIKitLocatorInput.parse(decoder: &decoder,
                                                  identifierField: Fields.accessibilityIdentifier,
                                                  pathField: Fields.path)

        // 手动解析 arguments（object 类型无法用 CommandField<Value> 表达）
        let argumentsRaw = data["arguments"]
        let arguments: [String: Any]?
        if let raw = argumentsRaw, raw != JSONValue.null {
            guard case .object(let dict) = raw else {
                throw CommandInputParseError("arguments must be an object")
            }
            arguments = dict.storage.mapValues { convertJSONValueToAny($0) }
        } else {
            arguments = nil
        }

        // 约束：script 与 function 互斥
        guard (script != nil) != (function != nil) else {
            throw CommandInputParseError(
                "script 与 function 必须提供且只能提供其中一个"
            )
        }

        // 约束：arguments 只能与 function 一起
        if arguments != nil && function == nil {
            throw CommandInputParseError(
                "arguments 只能与 function 一起使用"
            )
        }

        // 约束：timeout 范围 1-30
        guard timeout >= 1.0 && timeout <= 30.0 else {
            throw CommandInputParseError(
                "timeout 必须在 1-30 秒范围内（当前 \(timeout)）"
            )
        }

        return UIWebViewEvalInput(
            target: target,
            viewSnapshotID: viewSnapshotID,
            script: script,
            function: function,
            arguments: arguments,
            timeout: timeout
        )
    }

    /// 协议要求的 decoder 入口。
    ///
    /// webView.eval 的 arguments object 只能整体从原始 data 解析，而 `CommandInputDecoder` 不向
    /// 扩展模块暴露原始 data，故真实解析在 `parse(from:)`。`AnyCommand` 始终走 `parse(from:)`，
    /// 本方法不会被调用，仅满足协议签名；若被调用则明确报错而非静默。
    ///
    /// - Parameter decoder: 绑定 `inputSchema` 与请求 data 的字段读取器。
    /// - Returns: 已解析的 webView.eval 输入。
    /// - Throws: 始终抛出 `CommandInputParseError`，提示改用 `parse(from:)`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIWebViewEvalInput {
        throw CommandInputParseError("UIWebViewEvalInput must be parsed via parse(from:)")
    }

    /// 将 JSONValue 转换为 Any（用于 arguments 字段）。
    private static func convertJSONValueToAny(_ value: JSONValue) -> Any {
        switch value {
        case .string(let s): return s
        case .double(let d): return d
        case .bool(let b): return b
        case .null: return NSNull()
        case .array(let arr): return arr.map { convertJSONValueToAny($0) }
        case .object(let obj): return obj.storage.mapValues { convertJSONValueToAny($0) }
        }
    }
}

#endif
