import Foundation
import Testing
@testable import iOSExploreServer

/// 锁定 `ExploreServerError` 各工厂到（HTTP status / envelope code / message）的映射契约。
///
/// 这些映射是 Mac 侧 / MCP 客户端做错误分流的唯一依据：通信失败看 HTTP 状态码，业务失败
/// 看 HTTP 200 + 顶层 `code`。任何回归都会让调用方静默误判失败类别。这里按「业务失败 vs
/// 通信失败」「超时二分」「code 归属」三个不变量分组锁定，而非逐字段重复，便于回归时
/// 一眼定位破坏点。配套 `ExploreServerErrorTests` 测的是单错误对象的字段语义，本文件
/// 专测跨工厂的契约一致性。

@Test("业务失败错误统一以 HTTP 200 + envelope code 返回，不关闭传输层")
func businessErrorsReturnHttp200() {
    let errors: [ExploreServerError] = [
        .unknownAction("ui.tap"),
        .invalidData(action: "ui.tap", message: "missing x"),
        .commandTimeout(action: "ui.tap"),
        .handlerThrown(action: "ui.tap", error: NSError(domain: "x", code: 1)),
        .unexpectedInputParseError(action: "ui.tap", error: NSError(domain: "x", code: 2)),
        .responseTooLarge(action: "ui.screenshot", bytes: 7_000_000, limit: 6_000_000),
    ]
    for error in errors {
        #expect(error.httpStatus == 200, "business error must stay on HTTP 200: \(error)")
        #expect(error.httpReason == "OK", "wrong reason for \(error)")
    }
}

@Test("通信/协议/资源/鉴权错误用 HTTP 状态码表达传输层失败")
func transportErrorsCarryHttpStatus() {
    let expectations: [(ExploreServerError, Int, String)] = [
        (.invalidPort(65535), 500, "Internal Server Error"),
        (.listenerCancelled(), 500, "Internal Server Error"),
        (.tooManyConnections(limit: 8), 503, "Service Unavailable"),
        (.requestTooLarge(), 400, "Bad Request"),
        (.headerTooLarge(), 400, "Bad Request"),
        (.bodyTooLarge(), 400, "Bad Request"),
        (.invalidHeaderEncoding(), 400, "Bad Request"),
        (.missingRequestLine(), 400, "Bad Request"),
        (.invalidRequestLine(), 400, "Bad Request"),
        (.readTimeout(), 408, "Request Timeout"),
        (.invalidMethod(method: "GET", path: "/"), 400, "Bad Request"),
        (.invalidCommandBody(bodyBytes: 99), 400, "Bad Request"),
        (.invalidCommandData(), 400, "Bad Request"),
        (.unauthorized(), 401, "Unauthorized"),
    ]
    for (error, status, reason) in expectations {
        #expect(error.httpStatus == status, "wrong status for \(error)")
        #expect(error.httpReason == reason, "wrong reason for \(error)")
    }
}

@Test("envelope code 映射是客户端 switch 的稳定依据")
func envelopeCodeMapping() {
    #expect(ExploreServerError.unknownAction("a").code == .unknownAction)
    #expect(ExploreServerError.invalidData(action: "a", message: "m").code == .invalidData)
    #expect(ExploreServerError.commandTimeout(action: "a").code == .timeout)
    #expect(ExploreServerError.responseTooLarge(action: "a", bytes: 1, limit: 2).code == .responseTooLarge)

    let internalErrors: [ExploreServerError] = [
        .handlerThrown(action: "a", error: NSError(domain: "x", code: 1)),
        .unexpectedInputParseError(action: "a", error: NSError(domain: "x", code: 2)),
        .invalidPort(65535),
        .listenerCancelled(),
        .tooManyConnections(limit: 1),
    ]
    for error in internalErrors {
        #expect(error.code == .internalError, "expected internal_error: \(error)")
    }

    let badRequestErrors: [ExploreServerError] = [
        .readTimeout(),
        .requestTooLarge(),
        .headerTooLarge(),
        .bodyTooLarge(),
        .invalidHeaderEncoding(),
        .missingRequestLine(),
        .invalidRequestLine(),
        .invalidContentLength("abc"),
        .invalidMethod(method: "GET", path: "/"),
        .invalidCommandBody(bodyBytes: 1),
        .invalidCommandData(),
        .unauthorized(),
    ]
    for error in badRequestErrors {
        #expect(error.code == .badRequest, "expected bad_request: \(error)")
    }
}

@Test("responseTooLarge: HTTP 200 + response_too_large，记 bytes/limit 不泄露 body")
func responseTooLargeEnvelope() throws {
    let error = ExploreServerError.responseTooLarge(action: "ui.screenshot", bytes: 7_000_000, limit: 6_000_000)
    #expect(error.code == .responseTooLarge)
    #expect(error.httpStatus == 200)
    #expect(error.httpReason == "OK")
    #expect(error.category == .command)
    #expect(error.message == "response body too large")
    #expect(error.logMessage.contains("ui.screenshot"))
    #expect(error.logMessage.contains("7000000"))
    #expect(error.logMessage.contains("6000000"))
}

@Test("超时二分：commandTimeout 不断开传输层(200)，readTimeout 关闭传输层(408)")
func timeoutSplitBetweenBusinessAndTransport() {
    let command = ExploreServerError.commandTimeout(action: "ui.tap")
    #expect(command.httpStatus == 200)
    #expect(command.code == .timeout)
    #expect(command.category == .timeout)

    let read = ExploreServerError.readTimeout()
    #expect(read.httpStatus == 408)
    #expect(read.code == .badRequest)
    #expect(read.category == .timeout)
}

@Test("鉴权失败的 envelope code 归为 bad_request（非独立 auth 码），锁住现有契约")
func unauthorizedMapsToBadRequestCode() {
    let error = ExploreServerError.unauthorized()
    #expect(error.httpStatus == 401)
    #expect(error.code == .badRequest)
    #expect(error.category == .auth)
}

@Test("对外 message 保持协议约定的稳定文案")
func stableUserFacingMessages() {
    #expect(ExploreServerError.commandTimeout(action: "x").message == "command timed out")
    #expect(ExploreServerError.invalidCommandData().message == "field 'data' must be a JSON object")
    #expect(ExploreServerError.invalidMethod(method: "GET", path: "/x").message == "only POST / is supported")
    #expect(ExploreServerError.unauthorized().message == "unauthorized")
    #expect(ExploreServerError.tooManyConnections(limit: 3).message == "too many active connections")
}

@Test("logMessage 携带 action/port/bytes/rawValue 等排障上下文")
func logMessagesCarryDiagnosticContext() {
    #expect(ExploreServerError.commandTimeout(action: "ui.tap").logMessage.contains("ui.tap"))
    #expect(ExploreServerError.invalidPort(65535).logMessage.contains("65535"))
    #expect(ExploreServerError.invalidCommandBody(bodyBytes: 4242).logMessage.contains("4242"))
    #expect(ExploreServerError.invalidContentLength("abc").logMessage.contains("abc"))
    #expect(ExploreServerError.unknownAction("ui.tap").logMessage.contains("ui.tap"))
}

@Test("新增 ExploreError code 的 rawValue 契约（ui.screenshot/input/scroll 业务码落点）")
func newErrorCodesRawValues() {
    #expect(ExploreError.timeout.rawValue == "timeout")
    #expect(ExploreError.responseTooLarge.rawValue == "response_too_large")
    #expect(ExploreError.staleLocator.rawValue == "stale_locator")
    #expect(ExploreError.inputRejected.rawValue == "input_rejected")
    #expect(ExploreError.transitionInProgress.rawValue == "transition_in_progress")
    #expect(ExploreError.unsupportedTextInputType.rawValue == "unsupported_text_input_type")
    #expect(ExploreError.becomeFirstResponderFailed.rawValue == "become_first_responder_failed")
    #expect(ExploreError.renderingFailed.rawValue == "rendering_failed")
    #expect(ExploreError.scrollContainerUnavailable.rawValue == "scroll_container_unavailable")
    #expect(ExploreError.containerNotScrollable.rawValue == "container_not_scrollable")
}

@Test("handlerThrown 透传底层错误文案便于排障；unexpectedInputParseError 收敛为通用文案不泄露实现")
func handlerThrownVsUnexpectedParseErrorMessages() {
    struct Boom: Error, LocalizedError {
        var errorDescription: String? { "boom-detail" }
    }

    let handlerError = ExploreServerError.handlerThrown(action: "ui.tap", error: Boom())
    #expect(handlerError.message == "boom-detail")
    #expect(handlerError.logMessage.contains("ui.tap"))

    let unexpected = ExploreServerError.unexpectedInputParseError(action: "ui.tap", error: Boom())
    #expect(unexpected.message == "internal command input parse error")
    #expect(unexpected.logMessage.contains("boom-detail"))
}
