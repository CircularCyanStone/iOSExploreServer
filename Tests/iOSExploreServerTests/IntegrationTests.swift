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

@Test("端到端 ping 经真实 TCP 往返")
func endToEndPing() async throws {
    let server = ExploreServer(port: testPort)
    try await server.start()
    defer { server.stop() }

    let text = try await send(action: "ping")
    #expect(text.contains(#""ok":true"#))
    #expect(text.contains(#""pong":true"#))
}

@Test("端到端 echo 回显")
func endToEndEcho() async throws {
    let server = ExploreServer(port: testPort)
    try await server.start()
    defer { server.stop() }

    let text = try await send(action: "echo", data: ["hi": "claude"])
    #expect(text.contains(#""hi":"claude""#))
}

@Test("未知 action 返回 unknown_action envelope")
func endToEndUnknown() async throws {
    let server = ExploreServer(port: testPort)
    try await server.start()
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
    try await server.start()
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
    try await server1.start()
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
    try await server.start()
    defer { server.stop() }

    let text = try await send(action: "help")
    #expect(text.contains(#""ok":true"#))
    #expect(text.contains(#""action":"ping""#))
    #expect(text.contains(#""action":"help""#))
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
