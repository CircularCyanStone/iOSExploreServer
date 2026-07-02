import Testing
import Foundation
import Network
@testable import iOSExploreServer
#if canImport(UIKit)
@testable import iOSExploreUIKit
#endif

/// 集成测试用固定端口，避开生产默认 38321。
private let testPort: UInt16 = 38399

private struct IntegrationGreetingInput: CommandInput, Equatable {
    static let nameField = CommandFields.requiredString("name", description: "名字")
    static let inputSchema = CommandInputSchema(fields: [nameField.erased])

    let name: String

    static func parse(decoding decoder: inout CommandInputDecoder) throws -> IntegrationGreetingInput {
        IntegrationGreetingInput(name: try decoder.read(nameField))
    }
}

/// 4 个用例共享同一 TCP 端口 38399：Swift Testing 默认并行执行会让多个
/// NWListener 同时 bind 同一端口，只有首个成功，其余静默失败，连接会被路由
/// 到错误的服务器实例（缺少该测试注册的自定义命令）。`.serialized` 强制串行。
@Suite(.serialized)
struct IntegrationTests {

@Test("stopAndWait 后新 server 可立即复用端口")
func stopAndWaitReleasesPort() async throws {
    let first = ExploreServer(port: testPort)
    try await startWithPortRetry(first)
    await first.stopAndWait()

    let second = ExploreServer(port: testPort)
    try await second.start()
    await second.stopAndWait()
}

@Test("端到端 ping 经真实 TCP 往返")
func endToEndPing() async throws {
    let server = ExploreServer(port: testPort)
    try await startWithPortRetry(server)
    defer { server.stop() }

    let text = try await send(action: "ping")
    #expect(text.contains(#""code":"ok""#))
    #expect(text.contains(#""pong":true"#))
}

@Test("端到端 echo 回显")
func endToEndEcho() async throws {
    let server = ExploreServer(port: testPort)
    try await startWithPortRetry(server)
    defer { server.stop() }

    let text = try await send(action: "echo", data: ["hi": "claude"])
    #expect(text.contains(#""hi":"claude""#))
}

@Test("未知 action 返回 unknown_action envelope")
func endToEndUnknown() async throws {
    let server = ExploreServer(port: testPort)
    try await startWithPortRetry(server)
    defer { server.stop() }

    let text = try await send(action: "nope")
    #expect(text.contains(#""code":"unknown_action""#))
    #expect(!text.contains(#""ok":"#))
    #expect(!text.contains(#""error":"#))
}

@Test("自定义注册命令经 HTTP 可达")
func endToEndCustom() async throws {
    let server = ExploreServer(port: testPort)
    server.register(action: "greet", input: IntegrationGreetingInput.self) { input in
        .success(["message": .string("Hello, \(input.name)")])
    }
    try await startWithPortRetry(server)
    defer { server.stop() }

    let text = try await send(action: "greet", data: ["name": "Claude"])
    #expect(text.contains(#""message":"Hello, Claude""#))
}

@Test("init 后内置命令即已注册,无需 start")
func builtinRegisteredAfterInit() async {
    let server = ExploreServer(port: testPort)
    // 不 start,直接经 router 验证 ping 已注册
    let r = await server.routerSnapshotRoute(ExploreRequest(action: "ping"))
    if case .failure = r { Issue.record("ping should be registered at init") }
}

@Test("端口被占用时 start 抛错")
func startThrowsOnPortInUse() async throws {
    let server1 = ExploreServer(port: testPort)
    try await startWithPortRetry(server1)
    defer { server1.stop() }

    let server2 = ExploreServer(port: testPort)
    await #expect(throws: (any Error).self) {
        try await server2.start()
    }
    server2.stop()   // start 失败后 listener 未赋值,stop 无害
}

@Test("help 端到端返回全部命令")
func endToEndHelp() async throws {
    let server = ExploreServer(port: testPort)
    try await startWithPortRetry(server)
    defer { server.stop() }

    let text = try await send(action: "help")
    #expect(text.contains(#""code":"ok""#))
    #expect(text.contains(#""action":"ping""#))
    #expect(text.contains(#""action":"help""#))
    #expect(text.contains(#""inputSchema""#))
    #expect(text.contains(#""properties""#))
    #expect(!text.contains(#""parameters""#))
}

@Test("命令超过配置超时时返回 timeout 业务码（HTTP 200 envelope）")
func commandTimeoutReturnsErrorEnvelope() async throws {
    let server = ExploreServer(port: testPort,
                               listenerConfiguration: .testing(commandTimeoutNanoseconds: 50_000_000))
    server.register(action: "slow", input: EmptyCommandInput.self) { _ in
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        return .success(["done": true])
    }
    try await startWithPortRetry(server)
    defer { server.stop() }

    let text = try await send(action: "slow")
    #expect(text.contains(#""code":"timeout""#))
    #expect(text.contains("timed out"))
    #expect(!text.contains(#""ok":"#))
    #expect(!text.contains(#""error":"#))
}

@Test("超过连接上限时拒绝新连接并返回 503")
func connectionLimitRejectsAdditionalConnection() async throws {
    let server = ExploreServer(port: testPort,
                               listenerConfiguration: .testing(maxConnections: 1,
                                                              commandTimeoutNanoseconds: 1_000_000_000))
    server.register(action: "hold", input: EmptyCommandInput.self) { _ in
        try? await Task.sleep(nanoseconds: 200_000_000)
        return .success(["done": true])
    }
    try await startWithPortRetry(server)
    defer { server.stop() }

    async let first = send(action: "hold")
    try await Task.sleep(nanoseconds: 30_000_000)
    let second = try await send(action: "ping")

    #expect(second.contains("503 Service Unavailable"))
    #expect(second.contains(#""code":"internal_error""#))
    #expect(!second.contains(#""ok":"#))
    #expect(!second.contains(#""error":"#))
    _ = try await first
}

@Test("短连接快速连续请求完成后释放连接槽")
func rapidSequentialRequestsReleaseConnectionSlots() async throws {
    let server = ExploreServer(port: testPort,
                               listenerConfiguration: .testing(maxConnections: 1))
    try await startWithPortRetry(server)
    defer { server.stop() }

    var lastResponse = ""
    for _ in 0..<6 {
        lastResponse = try await send(action: "ping", timeoutNanoseconds: 1_000_000_000)
    }

    #expect(envelopeCode(lastResponse) == "ok")
    #expect(lastResponse.contains(#""pong":true"#))
}

#if canImport(UIKit)
// MARK: - UIKit 操作三件套（screenshot/input/scroll）端到端
//
// 以下三个用例与同 suite 的其它用例共享 TCP 端口 38399。本 suite 整体 `.serialized`，
// 故它们与上面的 core 用例串行执行，不会并发 bind 同一端口（曾尝试拆成独立
// `@Suite(.serialized)` struct，但 Swift Testing 会在不同 suite 之间并发，导致端口冲突；
// 合并进同一 suite 是唯一安全的写法）。仅在 iOS（framework 工程 `xcodebuild ... test`）
// 下编译运行；macOS SPM 下 `canImport(UIKit)` 为 false，三段代码不参与编译。
//
// **宿主 UI 限制（重要）：** unit/framework test 进程没有真实 `UIApplication` 前台 scene，
// `UIKitContextProvider.currentContext` 会抛 `hierarchyUnavailable`。因此：
// - 真实的 screenshot base64 往返（解码出合法 PNG + 维度）需宿主 App 上屏，只能在
//   `Examples/SPMExample` 真机/模拟器手测（见 task-10-report）；
// - `ui.input`/`ui.scroll` 的正向交互同样需可交互 view，亦在 SPMExample 手测；
// - 这里覆盖的是「命令经 HTTP 可达 + 失败 envelope 形态正确」这一层契约，以及
//   `ClientSession` 体积上限改发 `response_too_large` 的负向契约（生产中会改发超大
//   截图响应的同一条代码路径；UIKit 侧 base64 前置拦截由
//   `UIScreenshotTests.screenshotRejectsTooLargeResponse` 单测覆盖）。

    /// 截图命令经真实 TCP 可达，失败时返回 `internal_error` + hierarchy 不可用语义。
    ///
    /// test 进程无前台 scene，`currentContext` 抛 `hierarchyUnavailable`，handler 顶层
    /// catch 转 `.internalError` envelope（HTTP 200 + `code=internal_error`）。该用例锁定：
    /// `ui.screenshot` 已被 `registerUIKitCommands` 注册、经 HTTP 路由可达、且失败 envelope
    /// 形态稳定（顶层 `code/message`，无遗留 `ok`/`error` 字段）。
    @Test("ui.screenshot 经 HTTP 可达,无前台 scene 时返回 internal_error envelope")
    func screenshotReachableViaHTTP() async throws {
        let server = ExploreServer(port: testPort, maxResponseBodyBytes: 8 * 1024 * 1024)
        server.registerUIKitCommands(maxResponseBodyBytes: 8 * 1024 * 1024)
        try await startWithPortRetry(server)
        defer { server.stop() }

        let text = try await send(action: "ui.screenshot")
        let code = envelopeCode(text)
        // 无前台 scene → hierarchyUnavailable → internal_error。
        // 仅断言 code 契约,不耦合 UIKit 内部 message 文案（final review I-1）。
        #expect(code == "internal_error")
        // envelope 形态：失败只走顶层 code/message，不应出现遗留字段。
        #expect(!text.contains(#""ok":"#))
        #expect(!text.contains(#""error":"#))
    }

    /// 显式注册后 `help` 必须经 HTTP 列出全部 13 个 UIKit action（registrar count=13）。
    ///
    /// 这是 registrar 计数的端到端回归点：经真实 HTTP `help` 取回命令列表，断言全部 13 个 `ui.*` action 都已注册并可被发现。
    @Test("registerUIKitCommands 后 help 经 HTTP 含 13 个 ui.* action")
    func helpListsAllUIKitActions() async throws {
        let server = ExploreServer(port: testPort)
        server.registerUIKitCommands()
        try await startWithPortRetry(server)
        defer { server.stop() }

        let text = try await send(action: "help")
        #expect(envelopeCode(text) == "ok")
        // 四个旧命令 + screenshot/input/keyboard.dismiss/scroll/navigation.back/navigation.tapBarButton。
        #expect(text.contains(#""action":"ui.topViewHierarchy""#))
        #expect(text.contains(#""action":"ui.viewTargets""#))
        #expect(text.contains(#""action":"ui.control.sendAction""#))
        #expect(text.contains(#""action":"ui.tap""#))
        #expect(text.contains(#""action":"ui.screenshot""#))
        #expect(text.contains(#""action":"ui.input""#))
        #expect(text.contains(#""action":"ui.keyboard.dismiss""#))
        #expect(text.contains(#""action":"ui.scroll""#))
        #expect(text.contains(#""action":"ui.navigation.back""#))
        #expect(text.contains(#""action":"ui.navigation.tapBarButton""#))
        #expect(text.contains(#""action":"ui.wait""#))
        #expect(text.contains(#""action":"ui.scrollToElement""#))
        #expect(text.contains(#""action":"ui.alert.respond""#))
        // help 输出每个命令的 inputSchema。
        #expect(text.contains(#""inputSchema""#))
    }

    /// 响应 body 超过 `maxResponseBodyBytes` 时改发 `response_too_large` envelope。
    ///
    /// 这是 `ClientSession.send` 体积上限路径的负向契约：注册一个返回超大 body 的自定义
    /// 命令，server 以 1MB 上限启动，断言响应被改写为 HTTP 200 + `code=response_too_large`。
    /// 生产中 UIKit 截图响应过大正是走这条路径被拦截，UIKit 侧 base64 前置估算拦截则由
    /// `UIScreenshotTests.screenshotRejectsTooLargeResponse` 单测覆盖；两条路径合并即构成
    /// `response_too_large` 的完整覆盖。
    @Test("响应 body 超限时改发 response_too_large envelope")
    func responseTooLargeWhenBodyExceedsLimit() async throws {
        // 1MB 上限：超过即改发，无需 UIKit 截图参与。
        let server = ExploreServer(port: testPort, maxResponseBodyBytes: 1 * 1024 * 1024)
        server.register(action: "big", input: EmptyCommandInput.self) { _ in
            // 2MB body，稳超 1MB 上限。
            let payload = String(repeating: "x", count: 2 * 1024 * 1024)
            return .success(["blob": .string(payload)])
        }
        try await startWithPortRetry(server)
        defer { server.stop() }

        let text = try await send(action: "big")
        #expect(envelopeCode(text) == "response_too_large")
        #expect(text.contains("response body too large"))
        #expect(!text.contains(#""ok":"#))
        #expect(!text.contains(#""error":"#))
    }
#endif

}

/// 发送一条命令并返回响应文本。
private func send(action: String,
                  data: JSON = [:],
                  timeoutNanoseconds: UInt64 = 5_000_000_000) async throws -> String {
    let payload: JSON = ["action": .string(action), "data": .object(data)]
    let body = JSONCoder.encode(payload)
    let request = Data("POST / HTTP/1.1\r\nContent-Length: \(body.count)\r\n\r\n".utf8) + body

    let conn = NWConnection(host: .ipv4(.loopback),
                            port: NWEndpoint.Port(rawValue: testPort)!,
                            using: .tcp)
    try await startClientConnection(conn, timeoutNanoseconds: timeoutNanoseconds)
    defer { conn.cancel() }

    return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
        let didResume = Mutex(false)
        let resume: @Sendable (Result<String, Error>) -> Void = { result in
            guard didResume.withLock({ value in
                if value { return false }
                value = true
                return true
            }) else { return }
            conn.cancel()
            switch result {
            case .success(let text):
                cont.resume(returning: text)
            case .failure(let error):
                cont.resume(throwing: error)
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + .nanoseconds(Int(timeoutNanoseconds))) {
            resume(.failure(TestTimeoutError.timedOut))
        }
        conn.send(content: request, completion: .contentProcessed { _ in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                if let error { resume(.failure(error)); return }
                resume(.success(String(data: data ?? Data(), encoding: .utf8) ?? ""))
            }
        })
    }
}

private func startClientConnection(_ conn: NWConnection, timeoutNanoseconds: UInt64) async throws {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
        let didResume = Mutex(false)
        let resume: @Sendable (Result<Void, Error>) -> Void = { result in
            guard didResume.withLock({ value in
                if value { return false }
                value = true
                return true
            }) else { return }
            conn.stateUpdateHandler = nil
            switch result {
            case .success:
                cont.resume()
            case .failure(let error):
                conn.cancel()
                cont.resume(throwing: error)
            }
        }
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                resume(.success(()))
            case .failed(let err):
                resume(.failure(err))
            default:
                break
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + .nanoseconds(Int(timeoutNanoseconds))) {
            resume(.failure(TestTimeoutError.timedOut))
        }
        conn.start(queue: .global())
    }
}

private enum TestTimeoutError: Error {
    case timedOut
}

/// 启动 server，遇到端口占用时短暂重试。
///
/// `@Suite(.serialized)` 保证串行用例不并发 bind 同一端口，但 `HTTPListener.stop()` 内的
/// `NWListener.cancel()` 是异步的：返回时底层 socket 尚未关闭。在 **iOS 模拟器** 上，下一个
/// 用例的 `start()` 偶尔会在端口释放前 bind，抛 `Address already in use`（用例间竞态，与本
/// 任务改动无关，macOS SPM 下因时序宽松从未暴露）。这里在端口占用时退避重试几秒，让模拟器
/// 有时间真正释放端口；macOS 下首次即成功，行为不变。
///
/// - Parameters:
///   - server: 待启动的 server。
///   - attempts: 最大重试次数（含首次）。
private func startWithPortRetry(_ server: ExploreServer, attempts: Int = 40) async throws {
    var lastError: (any Error)?
    for _ in 0..<attempts {
        do {
            try await server.start()
            return
        } catch let error as NWError where error.isAddressInUse {
            // 端口尚未释放：退避后重试。
            lastError = error
            try? await Task.sleep(nanoseconds: 50_000_000)
            continue
        } catch {
            // 非端口占用错误：立即抛出，不掩盖真实失败。
            throw error
        }
    }
    throw lastError ?? POSIXError(.EADDRINUSE)
}

private extension NWError {
    /// 判断是否为端口占用（bind EADDRINUSE）。
    var isAddressInUse: Bool {
        switch self {
        case .posix(let code): return code == .EADDRINUSE
        default: return false
        }
    }
}

/// 从 HTTP 响应文本中解出 envelope 顶层 `code` 字段值。
///
/// `send` helper 返回的是完整 HTTP 响应文本（含 status line + body）。本函数只取 body
/// 部分按 JSON 解码为 `JSON` 对象（envelope 顶层必为对象），再用 `JSON.subscript` 取出
/// 顶层 `code` 的字符串值。解析失败会记录明确的测试失败信息，并返回 `nil` 供调用方继续断言。
///
/// - Parameter text: `send` 返回的完整 HTTP 响应文本。
/// - Returns: envelope 顶层 `code` 值（如 `"ok"`/`"internal_error"`/`"response_too_large"`）；
///   body 缺失或非 JSON 对象时记录 `Issue` 并返回 `nil`。
private func envelopeCode(_ text: String) -> String? {
    guard let bodyStart = text.range(of: "\r\n\r\n") else {
        Issue.record("HTTP response missing header/body separator: \(text.prefix(200))")
        return nil
    }
    let body = String(text[bodyStart.upperBound...])
    guard let envelope = JSONCoder.decode(Data(body.utf8)) else {
        Issue.record("HTTP response body is not a JSON envelope: \(body.prefix(200))")
        return nil
    }
    guard let code = envelope["code"]?.stringValue else {
        Issue.record("HTTP response envelope missing string code: \(body.prefix(200))")
        return nil
    }
    return code
}
