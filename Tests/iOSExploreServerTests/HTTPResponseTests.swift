import Testing
import Foundation
@testable import iOSExploreServer

@Test("响应报文序列化包含状态行、头与 body")
func responseSerialized() {
    let body = Data(#"{"ok":true}"#.utf8)
    let resp = HTTPResponse(status: 200, reason: "OK", body: body)
    let text = String(data: resp.serialized(), encoding: .utf8) ?? ""

    #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
    #expect(text.contains("Content-Type: application/json"))
    #expect(text.contains("Content-Length: \(body.count)"))
    #expect(text.contains("\r\n\r\n{\"ok\":true}"))
}
