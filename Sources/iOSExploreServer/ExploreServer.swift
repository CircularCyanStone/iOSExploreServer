import Foundation
import Network

/// 服务运行期间产生的轻量事件。
///
/// 事件流用于测试 App 或宿主 App 展示日志、调试连接状态。它不是命令响应的一部分，
/// 不会通过 HTTP 返回给 Mac 侧调用方。
public enum ServerEvent: Sendable {
    /// TCP listener 已经进入 ready 状态并开始监听端口。
    case started(port: UInt16)

    /// listener 已停止。
    case stopped

    /// 已收到并解析出一条 HTTP 请求。
    ///
    /// `action` 只有在 body 成功解析为 `ExploreRequest` 后才有值；通信层 bad request
    /// 不一定会产生该事件。
    case received(method: String, path: String, action: String?)

    /// 已发送响应。
    ///
    /// `status` 是 HTTP 状态码；`ok` 是响应结果摘要，供宿主日志面板显示。
    case responded(status: Int, ok: Bool)

    /// 预留的错误事件，供未来监听器或接入层上报不可恢复问题。
    case error(String)
}

/// 手机端命令服务器的对外门面。
///
/// `ExploreServer` 组合 `Router` 和 `HTTPListener`，向集成方暴露最少 API：
/// 注册命令、启动监听、停止监听、订阅事件。库默认监听 38321 端口，Mac 侧可通过
/// `iproxy` 把本地端口转发到手机端同端口后用 `curl` 发送 JSON 命令。
public final class ExploreServer: Sendable {
    /// 监听端口。默认值与 `scripts/proxy.sh` 保持一致。
    private let port: UInt16

    /// 命令注册表与分发器。
    private let router: Router

    /// listener/session 资源限制配置。
    private let listenerConfiguration: HTTPListener.Configuration

    /// 当前 listener 实例。
    ///
    /// `HTTPListener` 本身有可变状态；这里用 `Mutex` 保护引用替换，使 `start`/`stop`
    /// 的状态读写满足 `Sendable` 要求。
    private let listener = Mutex<HTTPListener?>(nil)
    /// 已请求停止但尚未收到终态的 listener，必须强持有至 socket 释放。
    private let stoppingListener = Mutex<HTTPListener?>(nil)

    /// 事件流写入端，由 listener 回调持有。
    private let eventContinuation: AsyncStream<ServerEvent>.Continuation

    /// 事件流读取端，返回给集成方消费。
    private let eventStream: AsyncStream<ServerEvent>

    /// 预留鉴权令牌：设置后未来版本会校验请求头 `X-Auth-Token`（MVP 不校验）。
    public let authToken: String?

    /// 创建命令服务器。
    ///
    /// 初始化时会同步注册内置命令 `ping`、`echo`、`info`、`help`。这些命令在
    /// `start()` 前已经存在，便于测试和宿主 App 提前自省。
    ///
    /// - Parameters:
    ///   - port: TCP 监听端口，默认 38321。
    ///   - authToken: 预留鉴权令牌，当前版本不校验。
    ///   - maxResponseBodyBytes: 单条响应 body 软上限（字节），默认 6MB；超过此值的响应
    ///     会被替换为 `response_too_large` envelope，避免大产物（如截图）压垮传输。
    public init(port: UInt16 = 38321,
                authToken: String? = nil,
                maxResponseBodyBytes: Int = 6 * 1024 * 1024) {
        self.port = port
        self.authToken = authToken
        let baseConfig = HTTPListener.Configuration.default
        self.listenerConfiguration = HTTPListener.Configuration(
            maxConnections: baseConfig.maxConnections,
            session: ClientSession.Configuration(
                parseLimits: baseConfig.session.parseLimits,
                readTimeoutNanoseconds: baseConfig.session.readTimeoutNanoseconds,
                commandTimeoutNanoseconds: baseConfig.session.commandTimeoutNanoseconds,
                receiveMaximumLength: baseConfig.session.receiveMaximumLength,
                maxResponseBodyBytes: maxResponseBodyBytes))
        self.router = Router()
        var continuation: AsyncStream<ServerEvent>.Continuation!
        self.eventStream = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
        BuiltinHandlers.registerAll(into: router)
        ExploreLogger.info(.server, "server initialized port=\(port) authTokenConfigured=\(authToken != nil) maxResponseBodyBytes=\(maxResponseBodyBytes)")
    }

    /// 测试/内部入口：允许注入 listener 资源限制配置。
    init(port: UInt16,
         authToken: String? = nil,
         listenerConfiguration: HTTPListener.Configuration) {
        self.port = port
        self.authToken = authToken
        self.listenerConfiguration = listenerConfiguration
        self.router = Router()
        var continuation: AsyncStream<ServerEvent>.Continuation!
        self.eventStream = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
        BuiltinHandlers.registerAll(into: router)
        ExploreLogger.info(.server, "server initialized port=\(port) authTokenConfigured=\(authToken != nil)")
    }

    /// 注册一个 typed 协议命令对象。
    ///
    /// 适合把能力封装成独立 `Command` struct，便于复用、测试和被 `help` 自省。
    ///
    /// - Parameters:
    ///   - command: 具体命令对象。
    ///   - logCategory: 命令执行日志归属。
    public func register<C: Command>(_ command: C, logCategory: CommandLogCategory = .core) {
        ExploreLogger.info(.server, "server register command action=\(command.action) schemaFields=\(C.Input.inputSchema.fields.count)")
        router.register(command, logCategory: logCategory)
    }

    /// 注册一个 typed 闭包命令。
    ///
    /// 适合宿主 App 在启动时快速注入能力，例如需要 UIKit 的设备信息 handler。库本身不
    /// 依赖 UIKit；如果 handler 需要访问 UIKit API，应由宿主 App 在闭包内切换到
    /// `MainActor`。
    ///
    /// - Parameters:
    ///   - action: 命令名，也是请求 body 中 `action` 的匹配键。
    ///   - description: 命令说明，供 `help` 输出。
    ///   - input: 命令输入类型，负责 schema 暴露与 data 解析。
    ///   - logCategory: 命令执行日志归属。
    ///   - handler: 实际业务处理闭包，入参已经是 typed input。
    public func register<Input: CommandInput>(action: String,
                                              description: String = "",
                                              input: Input.Type,
                                              logCategory: CommandLogCategory = .core,
                                              _ handler: @escaping @Sendable (Input) async throws -> ExploreResult) {
        ExploreLogger.info(.server, "server register closure action=\(action) schemaFields=\(Input.inputSchema.fields.count)")
        router.register(action: action,
                        description: description,
                        input: input,
                        logCategory: logCategory,
                        handler)
    }

    /// 启动 TCP HTTP server。
    ///
    /// 该方法会等待 `NWListener` 进入 ready 状态后再返回；端口不可用时会抛出底层
    /// Network 错误。调用方应避免并发调用 `start()`/`stop()`，常见用法是在 App 主线程
    /// 按钮事件中串行触发。
    public func start() async throws {
        ExploreLogger.info(.server, "server start requested port=\(port)")
        if let stopping = stoppingListener.withLock({ value -> HTTPListener? in
            let pending = value
            value = nil
            return pending
        }) {
            await stopping.stopAndWait()
        }
        let l = try HTTPListener(port: port,
                                 router: router,
                                 configuration: listenerConfiguration) { [eventContinuation] event in
            eventContinuation.yield(event)
        }
        try await l.start()
        listener.withLock { $0 = l }
        ExploreLogger.info(.server, "server start completed port=\(port)")
    }

    /// 停止 TCP HTTP server。
    ///
    /// 方法是幂等的：如果当前没有 listener，调用也不会报错。
    public func stop() {
        ExploreLogger.info(.server, "server stop requested")
        let previous = listener.withLock { let prev = $0; $0 = nil; return prev }
        previous?.stop()
        if let previous { stoppingListener.withLock { $0 = previous } }
        ExploreLogger.info(.server, "server stop completed hadListener=\(previous != nil)")
    }

    /// 测试内部停止屏障：等待底层 listener 终态后返回。
    func stopAndWait() async {
        stop()
        if let stopping = stoppingListener.withLock({ value -> HTTPListener? in
            let pending = value
            value = nil
            return pending
        }) {
            await stopping.stopAndWait()
        }
    }

    /// 获取服务事件流。
    ///
    /// 返回当前服务器持有的事件流。事件主要用于单个调试 UI 或日志消费者，不参与协议语义；
    /// 如果未来需要多个订阅者都收到完整事件，应在上层增加广播分发。
    public func events() -> AsyncStream<ServerEvent> {
        eventStream
    }

    /// 测试辅助：不经网络直接路由，验证命令注册状态。
    func routerSnapshotRoute(_ request: ExploreRequest) async -> ExploreResult {
        ExploreLogger.debug(.server, "server snapshot route action=\(request.action)")
        return await router.route(request)
    }
}
