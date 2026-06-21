import Foundation

enum HTTPParser {
    private static let headerSeparator = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n

    /// 从累积 buffer 解析一个完整 HTTP/1.1 请求；数据不完整返回 nil。
    static func parseRequest(from buffer: Data) -> (request: HTTPRequest, consumed: Int)? {
        guard let sepRange = buffer.range(of: headerSeparator) else { return nil }
        let headerData = buffer[..<sepRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }

        var lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        lines.removeFirst()

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count == 3 else { return nil }
        let method = parts[0]
        let path = parts[1]

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = sepRange.upperBound
        guard buffer.count - bodyStart >= contentLength else { return nil }
        let body = buffer[bodyStart..<(bodyStart + contentLength)]

        return (HTTPRequest(method: method, path: path, headers: headers, body: Data(body)),
                bodyStart + contentLength)
    }

    /// 从请求 body 解析出 ExploreRequest（缺 action 或非 JSON 返回 nil）。
    static func exploreRequest(from body: Data) -> ExploreRequest? {
        guard let json = JSONCoder.decode(body) else { return nil }
        guard case .string(let action)? = json["action"] else { return nil }
        let data: JSON = {
            if case .object(let o)? = json["data"] { return o }
            return JSON()
        }()
        return ExploreRequest(action: action, data: data)
    }

    /// 业务结果 → HTTP 响应（统一 envelope）。
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

    /// 通信层错误响应（非业务 ExploreResult）。
    static func errorResponse(status: Int, reason: String,
                              code: ExploreError, message: String) -> HTTPResponse {
        let error: JSON = ["code": .string(code.rawValue), "message": .string(message)]
        let body: JSON = ["ok": .bool(false), "error": .object(error)]
        return HTTPResponse(status: status, reason: reason, body: JSONCoder.encode(body))
    }
}
