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
public final class ExploreServer: @unchecked Sendable {
    private let port: UInt16
    private let router: Router
    private var listener: HTTPListener?
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
        self.listener = l
    }

    public func stop() {
        listener?.stop()
        listener = nil
    }

    public func events() -> AsyncStream<ServerEvent> {
        eventStream
    }
}
