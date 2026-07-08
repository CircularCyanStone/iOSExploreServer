import Testing
import Foundation
@testable import iOSExploreServer

/// `ExploreError.notActionable` 业务错误码契约。
///
/// `not_actionable` 是业务码（HTTP 200 + body 顶层 `code`），不经传输层
/// `ExploreServerError`。这里锁定两条不变量，供后续 `ui.inspect` 重设计里
/// minimal 节点 tap 失败分流依赖：
/// - rawValue 字符串稳定（Mac 侧 / MCP 客户端按此 switch 分流）；
/// - 经 `ExploreResult.failure` → `HTTPParser.response(for:)` 序列化后，
///   envelope 形状为 HTTP 200 + `{"code":"not_actionable","message":...}`，
///   与其它业务码同模式（参 `ExploreServerErrorContractTests.businessErrorsReturnHttp200`）。
@Test("not_actionable 错误码 rawValue 与 envelope 序列化")
func notActionableErrorCode() throws {
    // rawValue 契约：客户端 switch 的稳定依据。
    #expect(ExploreError.notActionable.rawValue == "not_actionable")

    // envelope 契约：业务失败统一 HTTP 200 + 顶层 code/message，不断开传输层。
    let result = ExploreResult.failure(code: .notActionable,
                                       message: "target has no available action")
    let response = HTTPParser.response(for: result)
    #expect(response.status == 200)
    #expect(response.reason == "OK")

    let body = try #require(JSONCoder.decode(response.body))
    let code = try #require(body["code"])
    #expect(code == .string("not_actionable"))
    let message = try #require(body["message"])
    #expect(message == .string("target has no available action"))
}
