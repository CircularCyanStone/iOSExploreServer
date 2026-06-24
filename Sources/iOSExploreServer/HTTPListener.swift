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
    struct Configuration: Sendable, Equatable {
        let maxConnections: Int
        let session: ClientSession.Configuration

        init(maxConnections: Int = 4,
             session: ClientSession.Configuration = ClientSession.Configuration()) {
            self.maxConnections = maxConnections
            self.session = session
        }

        static let `default` = Configuration()

        static func testing(maxConnections: Int = 4,
                            maxHeaderBytes: Int = 16 * 1024,
                            maxBodyBytes: Int = 1024 * 1024,
                            maxRequestBytes: Int = 1024 * 1024,
                            readTimeoutNanoseconds: UInt64 = 10_000_000_000,
                            commandTimeoutNanoseconds: UInt64 = 10_000_000_000) -> Configuration {
            Configuration(maxConnections: maxConnections,
                          session: ClientSession.Configuration(
                            parseLimits: HTTPParseLimits(maxHeaderBytes: maxHeaderBytes,
                                                         maxBodyBytes: maxBodyBytes,
                                                         maxRequestBytes: maxRequestBytes),
                            readTimeoutNanoseconds: readTimeoutNanoseconds,
                            commandTimeoutNanoseconds: commandTimeoutNanoseconds))
        }
    }

    private struct ListenerState {
        var nextSessionNumber = 0
        var sessions: [String: ClientSession] = [:]
    }

    /// TCP 监听端口。
    private let port: UInt16

    /// 命令路由器。连接处理任务只捕获该引用，不捕获 `self`。
    private let router: Router

    /// listener/session 资源限制配置。
    private let configuration: Configuration

    /// 事件回调。由 `ExploreServer` 转发到 `AsyncStream`。
    private let onEvent: @Sendable (ServerEvent) -> Void

    /// Network.framework 回调使用的串行队列。
    private let networkQueue = DispatchQueue(label: "iOSExploreServer.network")

    /// 当前活跃 session。所有访问必须通过锁。
    private let state = Mutex(ListenerState())
    /// listener 是否已进入终态；`stopAndWait` 用它等待底层 socket 真正释放。
    private let isTerminated = Mutex(false)

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
         configuration: Configuration = .default,
         onEvent: @escaping @Sendable (ServerEvent) -> Void) throws {
        self.port = port
        self.router = router
        self.configuration = configuration
        self.onEvent = onEvent
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            let error = ExploreServerError.invalidPort(port)
            ExploreLogger.error(.listener, error.logMessage)
            throw error.nsError
        }
        self.listener = try NWListener(using: .tcp, on: nwPort)
        self.listener?.newConnectionLimit = max(configuration.maxConnections + 1, 2)
        ExploreLogger.debug(.listener, "listener initialized port=\(port)")
    }

    /// 启动监听并等待端口 ready。
    ///
    /// 返回时端口已经可连接；如果端口被占用或 listener 进入 failed/cancelled 状态，会向
    /// 调用方抛错。
    func start() async throws {
        guard let listener else { return }
        ExploreLogger.info(.listener, "listener start requested port=\(port)")
        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        try await startAndWaitUntilReady(listener)
        onEvent(.started(port: port))
        ExploreLogger.info(.listener, "listener ready port=\(port)")
    }

    /// 启动 `NWListener` 并等待它从 setup 进入 ready 状态。
    ///
    /// `NWListener.start(queue:)` 本身立即返回，不能表示端口已经可用。这里先绑定
    /// `stateUpdateHandler` 再启动 listener，避免 ready/failed 状态在 handler 安装前发生，
    /// 导致 `start()` 永远等不到 continuation 回调。
    private func startAndWaitUntilReady(_ listener: NWListener) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let didResume = Mutex(false)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    ExploreLogger.info(.listener, "listener state ready")
                    if didResume.withLock({ value in
                        if value { return false }
                        value = true
                        return true
                    }) {
                        cont.resume()
                    }
                case .failed(let err):
                    self?.isTerminated.withLock { $0 = true }
                    ExploreLogger.error(.listener, "listener state failed error=\(err)")
                    if didResume.withLock({ value in
                        if value { return false }
                        value = true
                        return true
                    }) {
                        cont.resume(throwing: err)
                    } else {
                        self?.onEvent(.error("listener failed: \(err)"))
                    }
                case .cancelled:
                    self?.isTerminated.withLock { $0 = true }
                    ExploreLogger.error(.listener, "listener state cancelled before ready")
                    if didResume.withLock({ value in
                        if value { return false }
                        value = true
                        return true
                    }) {
                        cont.resume(throwing: ExploreServerError.listenerCancelled().nsError)
                    }
                case .waiting(let err):
                    ExploreLogger.error(.listener, "listener state waiting error=\(err)")
                default:
                    break   // .setup 等中间态忽略
                }
            }
            listener.start(queue: networkQueue)
        }
    }

    /// 停止监听并发送 stopped 事件。
    func stop() {
        ExploreLogger.info(.listener, "listener stop requested")
        let sessions = state.withLock { state -> [ClientSession] in
            let sessions = Array(state.sessions.values)
            state.sessions.removeAll()
            return sessions
        }
        for session in sessions {
            session.close(reason: "listener_stop")
        }
        listener?.cancel()
        onEvent(.stopped)
        ExploreLogger.info(.listener, "listener stopped")
    }

    /// 停止 listener 并等待 Network.framework 报告终态，确保端口可安全复用。
    func stopAndWait() async {
        stop()
        while !isTerminated.withLock({ $0 }) {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        listener?.stateUpdateHandler = nil
        listener = nil
    }

    /// 处理单条 TCP 连接。
    ///
    /// 当前协议是一请求一响应：读取到完整 HTTP 请求后立即处理并关闭连接，不支持 keep-alive、
    /// pipelining 或 chunked transfer encoding。
    private func handle(_ conn: NWConnection) {
        ExploreLogger.debug(.listener, "connection accepted")
        let sessionID = state.withLock { state -> String? in
            guard state.sessions.count < configuration.maxConnections else { return nil }
            state.nextSessionNumber += 1
            return "s\(state.nextSessionNumber)"
        }
        guard let sessionID else {
            let error = ExploreServerError.tooManyConnections(limit: configuration.maxConnections)
            ExploreLogger.error(.listener, error.logMessage)
            Self.reject(conn, queue: networkQueue, error: error)
            return
        }
        let session = ClientSession(sessionID: sessionID,
                                    connection: conn,
                                    router: router,
                                    configuration: configuration.session,
                                    networkQueue: networkQueue,
                                    onEvent: onEvent) { [weak self] closedID in
            self?.removeSession(closedID)
        }
        state.withLock { $0.sessions[sessionID] = session }
        session.start()
    }

    private func removeSession(_ sessionID: String) {
        let remaining = state.withLock { state -> Int in
            state.sessions.removeValue(forKey: sessionID)
            return state.sessions.count
        }
        ExploreLogger.debug(.listener, "session removed id=\(sessionID) active=\(remaining)")
    }

    private static func reject(_ conn: NWConnection, queue: DispatchQueue, error: ExploreServerError) {
        let response = HTTPParser.errorResponse(for: error)
        conn.start(queue: queue)
        conn.send(content: response.serialized(), completion: .contentProcessed { error in
            if let error {
                ExploreLogger.error(.http, "http reject send error=\(error)")
            }
            conn.cancel()
        })
    }
}
