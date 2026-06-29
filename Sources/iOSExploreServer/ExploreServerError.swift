import Foundation

/// 服务内部统一错误模型。
///
/// 同一个错误对象同时提供 HTTP 状态、envelope 错误码、对外 message 和内部日志文本，
/// 避免各层分别拼接 status/reason/code/message 造成语义漂移。
struct ExploreServerError: Error, Sendable, Equatable {
    /// 错误归属类别，决定日志 category 与 NSError domain 段。
    enum Category: String, Sendable {
        /// 监听器生命周期（端口、启停）。
        case listener
        /// 单连接生命周期。
        case connection
        /// HTTP 层（方法、路径、body 结构）。
        case http
        /// HTTP 协议解析（请求行、header、Content-Length）。
        case protocolParse
        /// 命令分发与执行。
        case command
        /// 资源上限（连接数、header/body 大小）。
        case resourceLimit
        /// 超时（读、命令）。
        case timeout
        /// 鉴权（预留，当前未启用）。
        case auth
    }

    /// 错误类别。
    let category: Category

    /// 对应 HTTP 响应状态码。
    let httpStatus: Int

    /// 对应 HTTP reason phrase。
    let httpReason: String

    /// envelope 顶层的业务错误码。
    let code: ExploreError

    /// 对外（envelope）展示的错误信息。
    let message: String

    /// 内部日志文本，通常含比 message 更多的上下文（如原始值、action 名）。
    let logMessage: String

    /// 转成 `NSError`，便于桥接到 Cocoa 错误处理。
    var nsError: NSError {
        NSError(domain: "iOSExploreServer.\(category.rawValue)",
                code: httpStatus,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    /// 端口非法（如 0），监听器无法启动。
    static func invalidPort(_ port: UInt16) -> ExploreServerError {
        ExploreServerError(category: .listener,
                           httpStatus: 500,
                           httpReason: "Internal Server Error",
                           code: .internalError,
                           message: "invalid port \(port)",
                           logMessage: "listener invalid port=\(port)")
    }

    /// 监听器在启动过程中被取消。
    static func listenerCancelled() -> ExploreServerError {
        ExploreServerError(category: .listener,
                           httpStatus: 500,
                           httpReason: "Internal Server Error",
                           code: .internalError,
                           message: "listener cancelled",
                           logMessage: "listener cancelled")
    }

    /// 活跃连接数达上限，新连接被直接拒绝（503）。
    static func tooManyConnections(limit: Int) -> ExploreServerError {
        ExploreServerError(category: .resourceLimit,
                           httpStatus: 503,
                           httpReason: "Service Unavailable",
                           code: .internalError,
                           message: "too many active connections",
                           logMessage: "connection rejected limit=\(limit)")
    }

    /// 请求整体（header + body）超过最大尺寸。
    static func requestTooLarge() -> ExploreServerError {
        ExploreServerError(category: .resourceLimit,
                           httpStatus: 400,
                           httpReason: "Bad Request",
                           code: .badRequest,
                           message: "request exceeds max size",
                           logMessage: "request exceeds max size")
    }

    /// HTTP header 部分超过最大尺寸。
    static func headerTooLarge() -> ExploreServerError {
        ExploreServerError(category: .resourceLimit,
                           httpStatus: 400,
                           httpReason: "Bad Request",
                           code: .badRequest,
                           message: "HTTP header exceeds max size",
                           logMessage: "HTTP header exceeds max size")
    }

    /// HTTP body 部分超过最大尺寸。
    static func bodyTooLarge() -> ExploreServerError {
        ExploreServerError(category: .resourceLimit,
                           httpStatus: 400,
                           httpReason: "Bad Request",
                           code: .badRequest,
                           message: "HTTP body exceeds max size",
                           logMessage: "HTTP body exceeds max size")
    }

    /// HTTP header 不是合法 UTF-8。
    static func invalidHeaderEncoding() -> ExploreServerError {
        ExploreServerError(category: .protocolParse,
                           httpStatus: 400,
                           httpReason: "Bad Request",
                           code: .badRequest,
                           message: "HTTP header is not valid UTF-8",
                           logMessage: "HTTP header is not valid UTF-8")
    }

    /// 缺少 HTTP 请求行。
    static func missingRequestLine() -> ExploreServerError {
        ExploreServerError(category: .protocolParse,
                           httpStatus: 400,
                           httpReason: "Bad Request",
                           code: .badRequest,
                           message: "missing HTTP request line",
                           logMessage: "missing HTTP request line")
    }

    /// HTTP 请求行格式非法。
    static func invalidRequestLine() -> ExploreServerError {
        ExploreServerError(category: .protocolParse,
                           httpStatus: 400,
                           httpReason: "Bad Request",
                           code: .badRequest,
                           message: "invalid HTTP request line",
                           logMessage: "invalid HTTP request line")
    }

    /// Content-Length 值无法解析为整数。
    static func invalidContentLength(_ rawValue: String) -> ExploreServerError {
        ExploreServerError(category: .protocolParse,
                           httpStatus: 400,
                           httpReason: "Bad Request",
                           code: .badRequest,
                           message: "invalid Content-Length",
                           logMessage: "invalid Content-Length value=\(rawValue)")
    }

    /// 读完整请求超时（408），连接被关闭。
    static func readTimeout() -> ExploreServerError {
        ExploreServerError(category: .timeout,
                           httpStatus: 408,
                           httpReason: "Request Timeout",
                           code: .badRequest,
                           message: "read timed out",
                           logMessage: "read timed out")
    }

    /// 命令执行超时。仍以 HTTP 200 + 顶层 `internal_error` 返回，不断开传输层。
    static func commandTimeout(action: String) -> ExploreServerError {
        ExploreServerError(category: .timeout,
                           httpStatus: 200,
                           httpReason: "OK",
                           code: .internalError,
                           message: "command timed out",
                           logMessage: "command timed out action=\(action)")
    }

    /// 仅支持 `POST /`，实际方法或路径不符。
    static func invalidMethod(method: String, path: String) -> ExploreServerError {
        ExploreServerError(category: .http,
                           httpStatus: 400,
                           httpReason: "Bad Request",
                           code: .badRequest,
                           message: "only POST / is supported",
                           logMessage: "http rejected method=\(method) path=\(path)")
    }

    /// body 不是合法 JSON 或缺少 `action` 字段。
    static func invalidCommandBody(bodyBytes: Int) -> ExploreServerError {
        ExploreServerError(category: .http,
                           httpStatus: 400,
                           httpReason: "Bad Request",
                           code: .badRequest,
                           message: "invalid JSON or missing 'action'",
                           logMessage: "invalid command body bytes=\(bodyBytes)")
    }

    /// body 的 `data` 字段存在但不是 JSON 对象。
    ///
    /// 区别于 `invalidCommandBody`（body 整体非法）：这里 body 是合法 JSON 且含 `action`，
    /// 但 `data` 写成了数组、字符串或数字。协议要求 `data` 是对象，单独报错让调用方定位
    /// “是 data 格式错了”，而不是被后续命令参数校验降级成模糊的缺参错误。
    static func invalidCommandData() -> ExploreServerError {
        ExploreServerError(category: .http,
                           httpStatus: 400,
                           httpReason: "Bad Request",
                           code: .badRequest,
                           message: "field 'data' must be a JSON object",
                           logMessage: "command body field 'data' is not a JSON object")
    }

    /// handler 抛出未转换异常，统一收敛为 `internal_error`。
    static func handlerThrown(action: String, error: Error) -> ExploreServerError {
        ExploreServerError(category: .command,
                           httpStatus: 200,
                           httpReason: "OK",
                           code: .internalError,
                           message: error.localizedDescription,
                           logMessage: "handler threw action=\(action) error=\(error.localizedDescription)")
    }

    /// typed input 解析阶段抛出非 `CommandInputParseError`，代表命令实现 bug。
    static func unexpectedInputParseError(action: String, error: Error) -> ExploreServerError {
        ExploreServerError(category: .command,
                           httpStatus: 200,
                           httpReason: "OK",
                           code: .internalError,
                           message: "internal command input parse error",
                           logMessage: "unexpected parse error action=\(action) error=\(error.localizedDescription)")
    }

    /// 没有注册该 action 的 handler。
    static func unknownAction(_ action: String) -> ExploreServerError {
        ExploreServerError(category: .command,
                           httpStatus: 200,
                           httpReason: "OK",
                           code: .unknownAction,
                           message: "no handler for '\(action)'",
                           logMessage: "unknown action=\(action)")
    }

    /// 命令参数校验失败（必填缺失 / 类型不符）。
    static func invalidData(action: String, message: String) -> ExploreServerError {
        ExploreServerError(category: .command,
                           httpStatus: 200,
                           httpReason: "OK",
                           code: .invalidData,
                           message: message,
                           logMessage: "invalid data action=\(action) message=\(message)")
    }

    /// 鉴权失败（预留，当前 USB 物理隔离未启用校验）。
    static func unauthorized() -> ExploreServerError {
        ExploreServerError(category: .auth,
                           httpStatus: 401,
                           httpReason: "Unauthorized",
                           code: .badRequest,
                           message: "unauthorized",
                           logMessage: "auth rejected")
    }
}
