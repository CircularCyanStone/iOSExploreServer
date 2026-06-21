import Testing
import Foundation
@testable import iOSExploreServer

@Test("解析完整 POST 请求（带 body）")
func parseFullRequest() throws {
    let raw = Data("POST / HTTP/1.1\r\nContent-Length: 17\r\n\r\n{\"action\":\"ping\"}".utf8)
    let parsed = HTTPParser.parseRequest(from: raw)
    let req = try #require(parsed?.request)
    #expect(req.method == "POST")
    #expect(req.path == "/")
    #expect(req.headers["content-length"] == "17")
    #expect(String(data: req.body, encoding: .utf8) == #"{"action":"ping"}"#)
}

@Test("数据不完整时返回 nil")
func parseIncomplete() {
    let raw = Data("POST / HTTP/1.1\r\nContent-Length: 100\r\n\r\n{}".utf8)
    #expect(HTTPParser.parseRequest(from: raw) == nil)
}

@Test("从 body 提取 ExploreRequest")
func exploreRequestFromBody() throws {
    let body = Data(#"{"action":"echo","data":{"x":1}}"#.utf8)
    let req = try #require(HTTPParser.exploreRequest(from: body))
    #expect(req.action == "echo")
    #expect(req.data["x"] == .double(1))
}

@Test("缺 action 返回 nil")
func exploreRequestMissingAction() {
    let body = Data(#"{"data":{}}"#.utf8)
    #expect(HTTPParser.exploreRequest(from: body) == nil)
}

@Test("success 结果序列化为 ok:true envelope")
func responseForSuccess() {
    let resp = HTTPParser.response(for: .success(["pong": true]))
    let text = String(data: resp.body, encoding: .utf8) ?? ""
    #expect(text.contains(#""ok":true"#))
    #expect(text.contains(#""data":{"pong":true}"#))
    #expect(resp.status == 200)
}

@Test("failure 结果序列化为 ok:false envelope")
func responseForFailure() {
    let resp = HTTPParser.response(for: .failure(code: .unknownAction, message: "no handler"))
    let text = String(data: resp.body, encoding: .utf8) ?? ""
    #expect(text.contains(#""ok":false"#))
    #expect(text.contains(#""code":"unknown_action""#))
    #expect(text.contains(#""message":"no handler""#))
}
