import Foundation

/// 已解析的 HTTP 请求值类型。
///
/// 这是传输层内部模型，不直接暴露给集成方。它只保留本库处理所需字段：请求方法、
/// 路径、header 字典和 body 数据。
struct HTTPRequest: Sendable, Equatable {
    /// HTTP 方法，例如 `POST`。
    let method: String

    /// 请求路径。本库只接受 `/`。
    let path: String

    /// HTTP headers。
    ///
    /// `HTTPParser` 会把 header 名统一转为小写，便于按 `content-length` 查询。
    let headers: [String: String]

    /// HTTP body 原始字节。
    let body: Data

    /// 创建一个 HTTP 请求值。
    init(method: String, path: String,
         headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }
}
