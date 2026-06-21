import Foundation
import Network

// Task 7 将把 ServerEvent 移到 ExploreServer.swift。
public enum ServerEvent: Sendable {
    case started(port: UInt16)
    case stopped
    case received(method: String, path: String, action: String?)
    case responded(status: Int, ok: Bool)
    case error(String)
}

/// NWListener 封装：接连接 → 解析 HTTP → 路由 → 回写响应。
/// start/stop 由调用方串行调用（App 主线程按钮），不保证并发安全启停。
final class HTTPListener: @unchecked Sendable {
    private let port: UInt16
    private let router: Router
    private let onEvent: @Sendable (ServerEvent) -> Void
    private var listener: NWListener?

    init(port: UInt16, router: Router,
         onEvent: @escaping @Sendable (ServerEvent) -> Void) throws {
        self.port = port
        self.router = router
        self.onEvent = onEvent
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "HTTPListener", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "invalid port \(port)"])
        }
        self.listener = try NWListener(using: .tcp, on: nwPort)
    }

    func start() {
        guard let listener else { return }
        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        listener.start(queue: .global())
        onEvent(.started(port: port))
    }

    func stop() {
        listener?.cancel()
        listener = nil
        onEvent(.stopped)
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global())
        Task { [router, onEvent] in
            var buffer = Data()
            var request: HTTPRequest?
            while request == nil {
                guard let chunk = await Self.receive(conn) else { conn.cancel(); return }
                buffer.append(chunk)
                if buffer.count > 1_000_000 { conn.cancel(); return } // 上限保护
                request = HTTPParser.parseRequest(from: buffer)?.request
            }
            await Self.process(request: request!, on: conn, router: router, onEvent: onEvent)
        }
    }

    private static func process(request: HTTPRequest, on conn: NWConnection,
                                router: Router,
                                onEvent: @Sendable (ServerEvent) -> Void) async {
        // 非法方法/路径
        guard request.method == "POST", request.path == "/" else {
            send(HTTPParser.errorResponse(status: 400, reason: "Bad Request",
                                          code: .badRequest,
                                          message: "only POST / is supported"), on: conn)
            onEvent(.responded(status: 400, ok: false))
            return
        }
        // 解析 action
        guard let exploreReq = HTTPParser.exploreRequest(from: request.body) else {
            send(HTTPParser.errorResponse(status: 400, reason: "Bad Request",
                                          code: .badRequest,
                                          message: "invalid JSON or missing 'action'"), on: conn)
            onEvent(.responded(status: 400, ok: false))
            return
        }
        onEvent(.received(method: request.method, path: request.path, action: exploreReq.action))
        let result = await router.route(exploreReq)
        send(HTTPParser.response(for: result), on: conn)
        let ok: Bool
        if case .success = result { ok = true } else { ok = false }
        onEvent(.responded(status: 200, ok: ok))
    }

    private static func receive(_ conn: NWConnection) async -> Data? {
        await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                if error != nil { cont.resume(returning: nil) }
                else { cont.resume(returning: data) }
            }
        }
    }

    private static func send(_ response: HTTPResponse, on conn: NWConnection) {
        conn.send(content: response.serialized(), completion: .contentProcessed { _ in
            conn.cancel()   // Connection: close：发完响应即关闭连接
        })
    }
}
