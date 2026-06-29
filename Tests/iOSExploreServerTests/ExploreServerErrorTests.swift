import Foundation
import Testing
@testable import iOSExploreServer

@Test("统一错误对象同时描述 HTTP、响应 code/message 和日志信息")
func serverErrorCarriesTransportEnvelopeAndLogFields() {
    let error = ExploreServerError.tooManyConnections(limit: 4)

    #expect(error.category == .resourceLimit)
    #expect(error.httpStatus == 503)
    #expect(error.httpReason == "Service Unavailable")
    #expect(error.code == .internalError)
    #expect(error.message == "too many active connections")
    #expect(error.logMessage.contains("limit=4"))
}

@Test("错误响应由统一错误对象生成")
func errorResponseUsesUnifiedServerError() {
    let error = ExploreServerError.invalidContentLength("abc")
    let response = HTTPParser.errorResponse(for: error)
    let text = String(data: response.body, encoding: .utf8) ?? ""

    #expect(response.status == 400)
    #expect(response.reason == "Bad Request")
    #expect(text.contains(#""code":"bad_request""#))
    #expect(text.contains("invalid Content-Length"))
    #expect(!text.contains(#""ok":"#))
    #expect(!text.contains(#""error":"#))
}

@Test("parser invalid 结果返回统一错误对象")
func parserInvalidResultCarriesUnifiedServerError() {
    let raw = Data("POST / HTTP/1.1\r\nContent-Length: abc\r\n\r\n{}".utf8)
    let result = HTTPParser.parseRequestResult(from: raw)

    if case .invalid(let error) = result {
        #expect(error.category == .protocolParse)
        #expect(error.httpStatus == 400)
        #expect(error.code == .badRequest)
        #expect(error.message.contains("Content-Length"))
    } else {
        Issue.record("expected invalid parse result")
    }
}
