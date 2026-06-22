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
    /// body 必须是 JSON 对象并包含字符串类型 `action`。`data` 可省略；如果存在但不是对象，
    /// 会被当作空对象处理，复杂参数合法性由 `Router` 的参数 schema 校验负责。
    static func exploreRequest(from body: Data) -> ExploreRequest? {
        guard let json = JSONCoder.decode(body) else { return nil }
        guard case .string(let action)? = json["action"] else { return nil }
        let data: JSON = {
            if case .object(let o)? = json["data"] { return o }
            return JSON()
        }()
        return ExploreRequest(action: action, data: data)
    }

    /// 把业务结果包装为统一 HTTP 响应。
    ///
    /// `ExploreResult.failure` 表示业务失败，不是通信失败，因此仍返回 HTTP 200，并在 body
    /// 中使用 `{"ok": false, "error": ...}` 表达。
    static func response(for result: ExploreResult) -> HTTPResponse {
        switch result {
        case .success(let data):
            let body: JSON = ["ok": .bool(true), "data": .object(data)]
            return HTTPResponse(status: 200, reason: "OK", body: JSONCoder.encode(body))
        case .failure(let code, let message):
            let error: JSON = ["code": .string(code.rawValue), "message": .string(message)]
            let body: JSON = ["ok": .bool(false), "error": .object(error)]
            return HTTPResponse(status: 200, reason: "OK", body: JSONCoder.encode(body))
        }
    }

    /// 构造通信层错误响应。
    ///
    /// 非 `POST /`、非法 JSON、缺少 action 等问题无法进入业务路由，因此用非 200 HTTP
    /// 状态码配合同样的 envelope 结构返回。
    private static func errorResponse(status: Int, reason: String,
                                      code: ExploreError, message: String) -> HTTPResponse {
        let error: JSON = ["code": .string(code.rawValue), "message": .string(message)]
        let body: JSON = ["ok": .bool(false), "error": .object(error)]
        return HTTPResponse(status: status, reason: reason, body: JSONCoder.encode(body))
    }

    /// 用统一错误对象构造通信层错误响应。
    static func errorResponse(for error: ExploreServerError) -> HTTPResponse {
        errorResponse(status: error.httpStatus,
                      reason: error.httpReason,
                      code: error.code,
                      message: error.message)
    }
}
