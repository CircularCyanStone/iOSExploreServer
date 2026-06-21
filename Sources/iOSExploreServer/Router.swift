import Foundation

/// 命令分发：action 名称 → handler。共享可变状态用 actor 保护。
public actor Router {
    public typealias Handler = @Sendable (ExploreRequest) async throws -> ExploreResult

    private var handlers: [String: Handler] = [:]

    public init() {}

    public func register(action: String, _ handler: @escaping Handler) {
        handlers[action] = handler
    }

    /// 按 action 查表分发；未命中或 handler 抛错都返回业务失败，不向外抛。
    func route(_ request: ExploreRequest) async -> ExploreResult {
        guard let handler = handlers[request.action] else {
            return .failure(code: .unknownAction,
                            message: "no handler for '\(request.action)'")
        }
        do {
            return try await handler(request)
        } catch {
            return .failure(code: .internalError, message: error.localizedDescription)
        }
    }
}
