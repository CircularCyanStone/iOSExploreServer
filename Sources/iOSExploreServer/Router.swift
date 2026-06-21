import Foundation

/// 命令分发:action 名称 → Command。字典由 Mutex 保护;route 锁内取命令、锁外校验与 handle。
public final class Router: Sendable {
    private let handlers = Mutex<[String: any Command]>([:])

    public init() {}

    /// 协议对象注册(首选)。
    public func register(_ command: any Command) {
        handlers.withLock { $0[command.action] = command }
    }

    /// 闭包便捷入口(内部适配成 ClosureCommand,与协议入口共享路由)。
    public func register(action: String,
                         description: String = "",
                         parameters: [CommandParameter] = [],
                         _ handler: @escaping @Sendable (ExploreRequest) async throws -> ExploreResult) {
        register(ClosureCommand(action: action, description: description,
                                parameters: parameters, handler: handler))
    }

    /// 按 action 查表分发;未命中/参数非法/handler 抛错都返回业务失败,不向外抛。
    func route(_ request: ExploreRequest) async -> ExploreResult {
        let command = handlers.withLock { $0[request.action] }
        guard let command else {
            return .failure(code: .unknownAction,
                            message: "no handler for '\(request.action)'")
        }
        if let msg = Self.validate(request.data, against: command.parameters) {
            return .failure(code: .invalidData, message: msg)
        }
        do {
            return try await command.handle(request)
        } catch {
            return .failure(code: .internalError, message: error.localizedDescription)
        }
    }

    /// 供 help 命令自省:列出全部命令元数据(锁内取快照)。
    func commandMetadata() -> [(action: String, description: String, parameters: [CommandParameter])] {
        handlers.withLock { dict in
            dict.values.map { ($0.action, $0.description, $0.parameters) }
        }
    }

    private static func validate(_ data: JSON, against parameters: [CommandParameter]) -> String? {
        for p in parameters {
            let v = data[p.name]
            if v == nil || v == .null {
                if p.required { return "missing required parameter '\(p.name)'" }
                continue
            }
            if let v = v, !typeMatches(v, kind: p.kind) {
                return "parameter '\(p.name)' expects \(p.kind.rawValue)"
            }
        }
        return nil
    }

    private static func typeMatches(_ v: JSONValue, kind: ParameterKind) -> Bool {
        switch (v, kind) {
        case (.string, .string), (.double, .number), (.bool, .boolean),
             (.object, .object), (.array, .array):
            return true
        default:
            return false
        }
    }
}
