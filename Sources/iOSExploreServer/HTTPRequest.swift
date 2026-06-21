import Foundation

struct HTTPRequest: Sendable, Equatable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    init(method: String, path: String,
         headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }
}
