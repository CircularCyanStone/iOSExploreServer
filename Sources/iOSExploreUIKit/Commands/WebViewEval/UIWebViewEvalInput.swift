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

        /// 可选 JSON object 字段：传递给 function 的参数。
        static let arguments = CommandField<[String: Any]?>(
            name: "arguments",
            schema: CommandFieldSchema(type: .object,
                                       required: false,
                                       description: "传递给 function 的参数，只能与 function 一起",
                                       allowsNull: true)
        ) { raw in
            guard let raw = raw, raw != .null else { return nil }
            guard case .object(let dict) = raw else {
                throw CommandInputParseError("arguments must be an object")
            }
            // Convert JSON to [String: Any]
            return dict.storage.mapValues { Self.convertJSONValueToAny($0) }
        }

        /// 超时时间字段，默认 5.0 秒。
        static let timeout = CommandField<TimeInterval>(
            name: "timeout",
            schema: CommandFieldSchema(type: .number,
                                       required: false,
                                       description: "超时时间（秒），范围 1-30",
                                       defaultValue: .double(5.0))
        ) { raw in
            guard let raw = raw, raw != .null else { return 5.0 }
            guard let value = raw.doubleValue, value.isFinite else {
                throw CommandInputParseError("timeout must be a finite number")
            }
            return value
        }

        static let all: [AnyCommandField] = [
            accessibilityIdentifier.erased,
            path.erased,
            viewSnapshotID.erased,
            script.erased,
            function.erased,
            arguments.erased,
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

    /// 从声明式 decoder 解析输入。
    ///
    /// 读取定位字段、script/function 模式、arguments 与 timeout，执行互斥校验后产出 typed 输入。
    /// - Throws: 字段类型/互斥/范围校验失败时抛 `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIWebViewEvalInput {
        let viewSnapshotID = try decoder.read(Fields.viewSnapshotID)
        let script = try decoder.read(Fields.script)
        let function = try decoder.read(Fields.function)
        let arguments = try decoder.read(Fields.arguments)
        let timeout = try decoder.read(Fields.timeout)
        let target = try UIKitLocatorInput.parse(decoder: &decoder,
                                                  identifierField: Fields.accessibilityIdentifier,
                                                  pathField: Fields.path)

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
}

#endif
