import Foundation

struct HTTPResponse: Sendable {
    let status: Int
    let reason: String
    let body: Data

    /// 序列化为完整 HTTP/1.1 响应报文。
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
