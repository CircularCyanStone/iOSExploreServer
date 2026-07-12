import Foundation

/// 命令分发器。
///
/// `Router` 维护 `action -> AnyCommand` 的注册表，是 HTTP 协议与具体业务 handler 的边界。
/// 它是 `final class` 而不是 actor：共享可变状态由 `Mutex` 保护，`route` 只在锁内取出
/// 命令快照，typed input 解析和 `await handle` 都在锁外执行，避免持锁跨异步边界。
public final class Router: Sendable {
    /// 已注册命令表。
    ///
    /// key 为 action，value 为类型擦除后的命令。所有读写必须通过 `withLock` 进行。
    private let handlers = Mutex<[String: AnyCommand]>([:])

    /// 创建一个空路由器。
    public init() {}

    /// 注册一个协议命令对象。
    ///
    /// 如果同名 action 已存在，新命令会覆盖旧命令。注册过程同步完成，不会触发 handler。
    ///
    /// - Parameters:
    ///   - command: 具体命令对象。
    ///   - logCategory: 命令执行日志归属。
    public func register<C: Command>(_ command: C, logCategory: CommandLogCategory = .core) {
        register(AnyCommand(command, logCategory: logCategory))
    }

    /// 注册一个已类型擦除的命令。
    ///
    /// - Parameter command: 已完成 typed input 适配和日志归属配置的命令。
    public func register(_ command: AnyCommand) {
        handlers.withLock { $0[command.action] = command }
        ExploreLogger.info(.router, "router registered action=\(command.action) schemaFields=\(command.inputSchema.fields.count) constraints=\(command.inputSchema.constraints.count)")
    }

    /// 注册一个 typed 闭包命令。
    ///
    /// 这是集成方最轻量的扩展入口，适合在 App 启动时注册少量命令。内部会适配成
    /// `AnyCommand`，因此它和协议命令共享同一条路由路径。
    ///
    /// - Parameters:
    ///   - action: 命令名。
    ///   - description: 命令说明，供 `help` 输出。
    ///   - input: 命令输入类型，负责 schema 暴露与 data 解析。
    ///   - logCategory: 命令执行日志归属。
    ///   - handler: 实际业务处理闭包，入参已经是 typed input。
    public func register<Input: CommandInput>(action: String,
                                              description: String = "",
                                              input: Input.Type,
                                              logCategory: CommandLogCategory = .core,
                                              _ handler: @escaping @Sendable (Input) async throws -> ExploreResult) {
        register(AnyCommand(action: action,
                            description: description,
                            input: input,
                            logCategory: logCategory,
                            handler: handler))
    }

    /// 按 action 查表并执行命令。
    ///
    /// 路由层不会向 HTTP 层抛业务异常：未注册 action 由 `Router` 转换为
    /// `unknown_action`，输入解析失败和 handler 抛错由 `AnyCommand` 转换为业务失败
    /// envelope。
    func route(_ request: ExploreRequest) async -> ExploreResult {
        ExploreLogger.debug(.router, "router route start action=\(request.action) payloadKeys=\(request.data.storage.count)")
        let command = handlers.withLock { $0[request.action] }
        guard let command else {
            let error = ExploreServerError.unknownAction(request.action)
            ExploreLogger.error(.router, "router route failed category=\(error.category.rawValue) message=\(error.logMessage)")
            return .failure(code: error.code, message: error.message)
        }
        let result = await command.handle(request)
        switch result {
        case .success:
            ExploreLogger.info(.router, "router route success action=\(request.action)")
        case .failure(let code, let message, _):
            ExploreLogger.error(.router, "router route business failure action=\(request.action) code=\(code.rawValue) message=\(message)")
        }
        return result
    }

    /// 按 action 查表返回命令自声明的执行超时（纳秒）。
    ///
    /// 供 `ClientSession.process` 在 `withTimeout` 包裹 `route` **之前**调用：超时上限
    /// 必须在路由前确定，而命令的 timeout 又只有锁内取到 `AnyCommand` 后才能读到，故
    /// 单独提供此轻量查表入口。方法只在锁内读取 `timeoutNanoseconds` 字段，不执行任何
    /// handler，无 `await`，符合「锁内禁止 await」约束。返回 nil 表示该命令未自声明，
    /// 由调用方回退到全局 `commandTimeoutNanoseconds`。
    ///
    /// - Parameter action: HTTP body 中的 `action` 字段。
    /// - Returns: 命令自声明超时（纳秒），未注册或未自声明时为 nil。
    func commandTimeout(for action: String) -> UInt64? {
        handlers.withLock { $0[action]?.timeoutNanoseconds }
    }

    /// 返回当前已注册命令的元数据快照。
    ///
    /// `help` 命令用它生成工具列表。方法只在锁内读取字典并生成轻量元组，不执行任何
    /// handler，并按 action 排序，保证 `help` 输出和工具发现结果稳定。
    func commandMetadata() -> [(action: String, description: String, inputSchema: CommandInputSchema)] {
        let metadata = handlers.withLock { dict in
            let snapshot: [(action: String, description: String, inputSchema: CommandInputSchema)] = dict.values.map {
                ($0.action, $0.description, $0.inputSchema)
            }
            return snapshot.sorted(by: { lhs, rhs in lhs.action < rhs.action })
        }
        ExploreLogger.debug(.router, "router metadata snapshot count=\(metadata.count)")
        return metadata
    }
}
