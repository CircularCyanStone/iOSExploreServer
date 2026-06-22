import Foundation
import Network

public enum ServerEvent: Sendable {
    case started(port: UInt16)
    case stopped
    case received(method: String, path: String, action: String?)
    case responded(status: Int, ok: Bool)
    case error(String)
}

/// 对外门面：组合 Router + HTTPListener + 内置命令，暴露最简 API 与事件流。
public final class ExploreServer: Sendable {
    private let port: UInt16
    private let router: Router
    private let listener = Mutex<HTTPListener?>(nil)
    private let eventContinuation: AsyncStream<ServerEvent>.Continuation
    private let eventStream: AsyncStream<ServerEvent>

    /// 预留鉴权令牌：设置后未来版本会校验请求头 `X-Auth-Token`（MVP 不校验）。
    public let authToken: String?

    public init(port: UInt16 = 38321, authToken: String? = nil) {
        self.port = port
        self.authToken = authToken
        self.router = Router()
        var continuation: AsyncStream<ServerEvent>.Continuation!
        self.eventStream = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
        BuiltinHandlers.registerAll(into: router)
    }

    public func register(_ command: any Command) {
        router.register(command)
    }

    public func register(action: String,
                         description: String = "",
                         parameters: [CommandParameter] = [],
                         _ handler: @escaping @Sendable (ExploreRequest) async throws -> ExploreResult) {
        router.register(action: action, description: description, parameters: parameters, handler)
    }

    public func start() async throws {
        let l = try HTTPListener(port: port, router: router) { [eventContinuation] event in
            eventContinuation.yield(event)
        }
        try await l.start()
        listener.withLock { $0 = l }
    }

    public func stop() {
        let previous = listener.withLock { let prev = $0; $0 = nil; return prev }
        previous?.stop()
    }

    public func events() -> AsyncStream<ServerEvent> {
        eventStream
    }

    /// 测试辅助:不经网络直接路由,验证命令注册状态。
    func routerSnapshotRoute(_ request: ExploreRequest) async -> ExploreResult {
        await router.route(request)
    }
}
