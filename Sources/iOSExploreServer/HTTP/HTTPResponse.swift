import Foundation

/// 待发送的 HTTP 响应值类型。
///
/// body 一律是 JSON envelope 数据，header 在 `serialized()` 中统一生成。当前实现固定
/// `Connection: close`，每个 TCP 连接只服务一个请求。
struct HTTPResponse: Sendable {
    /// HTTP 状态码，例如 200 或 400。
    let status: Int

    /// HTTP reason phrase，例如 `OK` 或 `Bad Request`。
    let reason: String

    /// 响应 body 原始字节，通常由 `JSONCoder.encode` 生成。
    let body: Data

    /// 序列化为完整 HTTP/1.1 响应报文。
    ///
    /// 生成的报文包含状态行、JSON Content-Type、精确 Content-Length 和
    /// `Connection: close`，随后拼接 body。
    func serialized() -> Data {
        let headLines = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: application/json",
            "Content-Length: \(body.count)",
            "Connection: close",
        ]
        let head = headLines.joined(separator: "\r\n") + "\r\n\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }
}
