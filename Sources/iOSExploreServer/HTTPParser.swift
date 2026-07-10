import Foundation

/// 从累积 buffer 解析 HTTP 请求时使用的大小限制。
struct HTTPParseLimits: Sendable, Equatable {
    let maxHeaderBytes: Int
    let maxBodyBytes: Int
    let maxRequestBytes: Int

    init(maxHeaderBytes: Int = 16 * 1024,
         maxBodyBytes: Int = 1024 * 1024,
         maxRequestBytes: Int = 1024 * 1024) {
        self.maxHeaderBytes = maxHeaderBytes
        self.maxBodyBytes = maxBodyBytes
        self.maxRequestBytes = maxRequestBytes
    }
}

/// HTTP 请求解析三态：完整、未完成、明确非法。
enum HTTPParseResult: Sendable, Equatable {
    case complete(request: HTTPRequest, consumed: Int)
    case incomplete
    case invalid(ExploreServerError)
}

/// HTTP 报文和命令 envelope 的解析/组装工具。
///
/// 该类型没有状态，只负责把字节层 HTTP 请求转换为库内部值类型，并把 `ExploreResult`
/// 转换为统一 JSON envelope。它不是完整 HTTP 实现，只覆盖本库需要的 `POST /` +
/// `Content-Length` 请求。
enum HTTPParser {
    /// HTTP header 和 body 的分隔符：`\r\n\r\n`。
    private static let headerSeparator = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n

    /// 从累积 buffer 解析一个完整 HTTP/1.1 请求。
    ///
    /// 如果 header 未收齐或 body 长度不足 `Content-Length`，返回 `nil`，调用方应继续读取。
    /// 返回值中的 `consumed` 表示本次请求消耗的字节数，当前 listener 一连接只处理一个请求，
    /// 因此暂不使用剩余字节。
    static func parseRequest(from buffer: Data) -> (request: HTTPRequest, consumed: Int)? {
        if case .complete(let request, let consumed) = parseRequestResult(from: buffer) {
            return (request, consumed)
        }
        return nil
    }

    /// 从累积 buffer 解析一个完整 HTTP/1.1 请求，并区分未完成与明确非法。
    static func parseRequestResult(from buffer: Data,
                                   limits: HTTPParseLimits = HTTPParseLimits()) -> HTTPParseResult {
        if buffer.count > limits.maxRequestBytes {
            return .invalid(.requestTooLarge())
        }
        guard let sepRange = buffer.range(of: headerSeparator) else {
            if buffer.count > limits.maxHeaderBytes {
                return .invalid(.headerTooLarge())
            }
            return .incomplete
        }
        guard sepRange.lowerBound <= limits.maxHeaderBytes else {
            return .invalid(.headerTooLarge())
        }
        let headerData = buffer[..<sepRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return .invalid(.invalidHeaderEncoding())
        }

        var lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            return .invalid(.missingRequestLine())
        }
        lines.removeFirst()

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count == 3 else {
            return .invalid(.invalidRequestLine())
        }
        let method = parts[0]
        let path = parts[1]

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let contentLength: Int
        if let rawContentLength = headers["content-length"] {
            guard let parsedLength = Int(rawContentLength), parsedLength >= 0 else {
                return .invalid(.invalidContentLength(rawContentLength))
            }
            guard parsedLength <= limits.maxBodyBytes else {
                return .invalid(.bodyTooLarge())
            }
            contentLength = parsedLength
        } else {
            contentLength = 0
        }
        let bodyStart = sepRange.upperBound
        guard buffer.count - bodyStart >= contentLength else { return .incomplete }
        let body = buffer[bodyStart..<(bodyStart + contentLength)]

        return .complete(request: HTTPRequest(method: method, path: path, headers: headers, body: Data(body)),
                         consumed: bodyStart + contentLength)
    }

    /// 从 HTTP body 解析出命令请求。
    ///
    /// body 必须是 JSON 对象并包含字符串类型 `action`。`data` 可省略；如果存在但不是
    /// JSON 对象（数组、字符串、数字等），返回 `invalidCommandData` 失败——协议要求 `data`
    /// 是对象，在这里报精确错误，避免调用方传错格式时只收到命令参数层的模糊缺参错误。
    ///
    /// - Parameter body: HTTP body 原始字节。
    /// - Returns: 成功时携带 `ExploreRequest`；失败时携带对应的 `ExploreServerError`。
    static func exploreRequest(from body: Data) -> Result<ExploreRequest, ExploreServerError> {
        guard let json = JSONCoder.decode(body) else {
            return .failure(.invalidCommandBody(bodyBytes: body.count))
        }
        guard case .string(let action)? = json["action"] else {
            return .failure(.invalidCommandBody(bodyBytes: body.count))
        }
        switch json["data"] {
        case nil:
            return .success(ExploreRequest(action: action, data: JSON()))
        case .object(let object)?:
            return .success(ExploreRequest(action: action, data: object))
        default:
            return .failure(.invalidCommandData())
        }
    }

    /// 把业务结果包装为统一 HTTP 响应。
    ///
    /// `ExploreResult.failure` 表示业务失败，不是通信失败，因此仍返回 HTTP 200，并在 body
    /// 顶层 `code` 中表达失败原因。成功响应使用 `code: "ok"`。
    static func response(for result: ExploreResult) -> HTTPResponse {
        switch result {
        case .success(let data):
            let body: JSON = ["code": .string("ok"), "data": .object(data)]
            return HTTPResponse(status: 200, reason: "OK", body: JSONCoder.encode(body))
        case .failure(let code, let message):
            let body: JSON = ["code": .string(code.rawValue), "message": .string(message)]
            return HTTPResponse(status: 200, reason: "OK", body: JSONCoder.encode(body))
        }
    }

    /// 按 status/reason/code/message 构造 HTTP 错误响应。
    ///
    /// 调用方决定 HTTP 状态码：通信层错误（非 `POST /`、非法 JSON、缺少 action、body 超
    /// 上限等）传非 200 状态码；命令超时、响应过大等业务终态传 200 + envelope。
    private static func errorResponse(status: Int, reason: String,
                                      code: ExploreError, message: String) -> HTTPResponse {
        let body: JSON = ["code": .string(code.rawValue), "message": .string(message)]
        return HTTPResponse(status: status, reason: reason, body: JSONCoder.encode(body))
    }

    /// 用统一错误对象构造通信层错误响应。
    ///
    /// HTTP 状态码取 `error.httpStatus`，不强制 200：通信/资源层错误抛 400/500/503，
    /// 命令超时、响应过大等业务终态可抛 200 + envelope。
    static func errorResponse(for error: ExploreServerError) -> HTTPResponse {
        errorResponse(status: error.httpStatus,
                      reason: error.httpReason,
                      code: error.code,
                      message: error.message)
    }
}
