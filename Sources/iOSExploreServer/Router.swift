import Foundation

/// 命令分发器。
///
/// `Router` 维护 `action -> Command` 的注册表，是 HTTP 协议与具体业务 handler 的边界。
/// 它是 `final class` 而不是 actor：共享可变状态由 `Mutex` 保护，`route` 只在锁内取出
/// 命令快照，参数校验和 `await handle` 都在锁外执行，避免持锁跨异步边界。
public final class Router: Sendable {
    /// 已注册命令表。
    ///
    /// key 为 action，value 为对应命令。所有读写必须通过 `withLock` 进行。
    private let handlers = Mutex<[String: any Command]>([:])

    /// 创建一个空路由器。
    public init() {}

    /// 注册一个协议命令对象。
    ///
    /// 如果同名 action 已存在，新命令会覆盖旧命令。注册过程同步完成，不会触发 handler。
    public func register(_ command: any Command) {
        handlers.withLock { $0[command.action] = command }
    }

    /// 注册一个闭包命令。
    ///
    /// 这是集成方最轻量的扩展入口，适合在 App 启动时注册少量命令。内部会适配成
    /// `ClosureCommand`，因此它和协议命令共享同一条路由路径。
    ///
    /// - Parameters:
    ///   - action: 命令名。
    ///   - description: 命令说明，供 `help` 输出。
    ///   - parameters: 参数 schema，进入 handler 前会被校验。
    ///   - handler: 实际业务处理闭包。
    public func register(action: String,
                         description: String = "",
                         parameters: [CommandParameter] = [],
                         _ handler: @escaping @Sendable (ExploreRequest) async throws -> ExploreResult) {
        register(ClosureCommand(action: action, description: description,
                                parameters: parameters, handler: handler))
    }

    /// 按 action 查表并执行命令。
    ///
    /// 路由层不会向 HTTP 层抛业务异常：未注册 action、参数不合法、handler 抛错都会被转换为
    /// `ExploreResult.failure`，再由 `HTTPParser.response(for:)` 包装为 HTTP 200 的业务失败
    /// envelope。
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

    /// 返回当前已注册命令的元数据快照。
    ///
    /// `help` 命令用它生成工具列表。方法只在锁内读取字典并生成轻量元组，不执行任何
    /// handler，也不保证返回顺序稳定。
    func commandMetadata() -> [(action: String, description: String, parameters: [CommandParameter])] {
        handlers.withLock { dict in
            dict.values.map { ($0.action, $0.description, $0.parameters) }
        }
    }

    /// 根据命令声明的参数 schema 校验请求 data。
    ///
    /// 只做顶层字段校验，不递归校验 object/array 内部结构；复杂业务约束留给 handler。
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

    /// 判断单个 JSON 值是否匹配参数类型声明。
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
