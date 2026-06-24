import Testing
import Foundation
import Network
@testable import iOSExploreServer

/// 集成测试用固定端口，避开生产默认 38321。
private let testPort: UInt16 = 38399

/// 4 个用例共享同一 TCP 端口 38399：Swift Testing 默认并行执行会让多个
/// NWListener 同时 bind 同一端口，只有首个成功，其余静默失败，连接会被路由
/// 到错误的服务器实例（缺少该测试注册的自定义命令）。`.serialized` 强制串行。
@Suite(.serialized)
struct IntegrationTests {

@Test("stopAndWait 后新 server 可立即复用端口")
func stopAndWaitReleasesPort() async throws {
    let first = ExploreServer(port: testPort)
    try await first.start()
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
    #expect(text.contains(#""ok":true"#))
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
    #expect(text.contains(#""ok":false"#))
    #expect(text.contains(#""code":"unknown_action""#))
}

@Test("自定义注册命令经 HTTP 可达")
func endToEndCustom() async throws {
    let server = ExploreServer(port: testPort)
    server.register(action: "greet") { req in
        let name = req.data["name"]?.stringValue ?? "world"
        return .success(["message": .string("Hello, \(name)")])
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
    #expect(text.contains(#""ok":true"#))
    #expect(text.contains(#""action":"ping""#))
    #expect(text.contains(#""action":"help""#))
}

@Test("命令超过配置超时时返回 internal_error 并关闭连接")
func commandTimeoutReturnsErrorEnvelope() async throws {
    let server = ExploreServer(port: testPort,
                               listenerConfiguration: .testing(commandTimeoutNanoseconds: 50_000_000))
    server.register(action: "slow") { _ in
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        return .success(["done": true])
    }
    try await startWithPortRetry(server)
    defer { server.stop() }

    let text = try await send(action: "slow")
    #expect(text.contains(#""ok":false"#))
    #expect(text.contains(#""code":"internal_error""#))
    #expect(text.contains("timed out"))
}

@Test("超过连接上限时拒绝新连接并返回 503")
func connectionLimitRejectsAdditionalConnection() async throws {
    let server = ExploreServer(port: testPort,
                               listenerConfiguration: .testing(maxConnections: 1,
                                                              commandTimeoutNanoseconds: 1_000_000_000))
    server.register(action: "hold") { _ in
        try? await Task.sleep(nanoseconds: 200_000_000)
        return .success(["done": true])
    }
    try await startWithPortRetry(server)
    defer { server.stop() }

    async let first = send(action: "hold")
    try await Task.sleep(nanoseconds: 30_000_000)
    let second = try await send(action: "ping")

    #expect(second.contains("503 Service Unavailable"))
    #expect(second.contains(#""ok":false"#))
    _ = try await first
}

}

/// 发送一条命令并返回响应文本。
private func send(action: String, data: JSON = [:]) async throws -> String {
    let payload: JSON = ["action": .string(action), "data": .object(data)]
    let body = JSONCoder.encode(payload)
    let request = Data("POST / HTTP/1.1\r\nContent-Length: \(body.count)\r\n\r\n".utf8) + body

    let conn = NWConnection(host: .ipv4(.loopback),
                            port: NWEndpoint.Port(rawValue: testPort)!,
                            using: .tcp)
    conn.start(queue: .global())
    try await waitUntilReady(conn)

    return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
        conn.send(content: request, completion: .contentProcessed { _ in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: String(data: data ?? Data(), encoding: .utf8) ?? "")
            }
        })
    }
}

private func waitUntilReady(_ conn: NWConnection) async throws {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                cont.resume()
                conn.stateUpdateHandler = nil   // 防止后续 cancelled 回调重复 resume
            case .failed(let err):
                cont.resume(throwing: err)
                conn.stateUpdateHandler = nil
            default:
                break
            }
        }
    }
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
