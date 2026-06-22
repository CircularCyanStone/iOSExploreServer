import Foundation
import Network

/// 基于 `NWListener` 的最小 HTTP/1.1 server 封装。
///
/// 它只负责传输层工作：接收 TCP 连接、累积请求字节、调用 `HTTPParser` 解析、交给
/// `Router` 分发，再把 `HTTPResponse` 写回并关闭连接。命令语义不放在这里，新增能力应
/// 通过注册 action 完成。
///
/// `start`/`stop` 约定由调用方串行调用（通常是 App 主线程按钮），因此该类以
/// `@unchecked Sendable` 标注。共享可变状态不会跨模块暴露。
final class HTTPListener: @unchecked Sendable {
    /// TCP 监听端口。
    private let port: UInt16

    /// 命令路由器。连接处理任务只捕获该引用，不捕获 `self`。
    private let router: Router

    /// 事件回调。由 `ExploreServer` 转发到 `AsyncStream`。
    private let onEvent: @Sendable (ServerEvent) -> Void

    /// Network.framework listener 实例。
    private var listener: NWListener?

    /// 创建一个 TCP listener。
    ///
    /// - Parameters:
    ///   - port: 要绑定的端口。
    ///   - router: 请求解析成功后使用的命令路由器。
    ///   - onEvent: 服务事件回调。
    /// - Throws: 端口非法或 `NWListener` 创建失败时抛错。
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

    /// 启动监听并等待端口 ready。
    ///
    /// 返回时端口已经可连接；如果端口被占用或 listener 进入 failed/cancelled 状态，会向
    /// 调用方抛错。
    func start() async throws {
        guard let listener else { return }
        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        try await Self.startAndWaitUntilReady(listener)
        onEvent(.started(port: port))
    }

    /// 启动 `NWListener` 并等待它从 setup 进入 ready 状态。
    ///
    /// `NWListener.start(queue:)` 本身立即返回，不能表示端口已经可用。这里先绑定
    /// `stateUpdateHandler` 再启动 listener，避免 ready/failed 状态在 handler 安装前发生，
    /// 导致 `start()` 永远等不到 continuation 回调。
    private static func startAndWaitUntilReady(_ listener: NWListener) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil   // 防 continuation 重入
                    cont.resume()
                case .failed(let err):
                    listener.stateUpdateHandler = nil
                    cont.resume(throwing: err)
                case .cancelled:
                    listener.stateUpdateHandler = nil
                    cont.resume(throwing: NSError(domain: "HTTPListener", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "listener cancelled"]))
                default:
                    break   // .setup 等中间态忽略
                }
            }
            listener.start(queue: .global())
        }
    }

    /// 停止监听并发送 stopped 事件。
    func stop() {
        listener?.cancel()
        listener = nil
        onEvent(.stopped)
    }

    /// 处理单条 TCP 连接。
    ///
    /// 当前协议是一请求一响应：读取到完整 HTTP 请求后立即处理并关闭连接，不支持 keep-alive、
    /// pipelining 或 chunked transfer encoding。
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

    /// 执行单条已解析 HTTP 请求。
    ///
    /// 通信层错误直接生成非 200 响应；成功解析出的命令请求交给 `Router`，业务失败仍以
    /// HTTP 200 + `ok:false` envelope 返回。
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

    /// 从连接中异步读取一段数据。
    ///
    /// 返回 `nil` 表示读取失败或连接错误；调用方会直接关闭连接。
    private static func receive(_ conn: NWConnection) async -> Data? {
        await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                if error != nil { cont.resume(returning: nil) }
                else { cont.resume(returning: data) }
            }
        }
    }

    /// 序列化并发送 HTTP 响应，发送完成后主动关闭连接。
    private static func send(_ response: HTTPResponse, on conn: NWConnection) {
        conn.send(content: response.serialized(), completion: .contentProcessed { _ in
            conn.cancel()   // Connection: close：发完响应即关闭连接
        })
    }
}
