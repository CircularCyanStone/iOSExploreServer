import Dispatch
import Foundation
import Network

/// 单个短连接客户端会话。
///
/// 当前会话仍是一请求一响应：读完整 HTTP 请求、路由、发送响应、关闭连接。把这些状态从
/// `HTTPListener` 收拢到独立对象，是为了统一连接关闭、超时、日志关联和后续鉴权/订阅扩展点。
final class ClientSession: Sendable {
    /// 单连接运行参数。
    ///
    /// 由 `HTTPListener` 在 accept 时构造，集中存放解析上限、各类超时和单次读上限，
    /// 避免这些数字散落在会话各处。
    struct Configuration: Sendable, Equatable {
        /// HTTP 请求解析上限（header/body/request 总长）。
        let parseLimits: HTTPParseLimits

        /// 读完整 HTTP 请求的超时（纳秒）。超时触发 `readTimeout` 并关闭连接。
        let readTimeoutNanoseconds: UInt64

        /// 执行单条命令的超时（纳秒）。超时触发 `commandTimeout`，仍以 200 + envelope 返回。
        let commandTimeoutNanoseconds: UInt64

        /// 单次 `NWConnection.receive` 拉取的最大字节数。
        let receiveMaximumLength: Int

        /// 响应 body 软上限（字节）。超过此值的响应会被替换为 `responseTooLarge` envelope，
        /// 避免单条命令（如截图，可能数 MB）回写过大的产物压垮 USB 传输或对端缓冲。
        let maxResponseBodyBytes: Int

        /// 创建单连接配置。
        ///
        /// - Parameters:
        ///   - parseLimits: HTTP 解析上限。
        ///   - readTimeoutNanoseconds: 读请求超时，默认 10s。
        ///   - commandTimeoutNanoseconds: 命令执行超时，默认 10s。
        ///   - receiveMaximumLength: 单次读上限，默认 64KB。
        ///   - maxResponseBodyBytes: 响应 body 软上限，默认 6MB。
        init(parseLimits: HTTPParseLimits = HTTPParseLimits(),
             readTimeoutNanoseconds: UInt64 = 10_000_000_000,
             commandTimeoutNanoseconds: UInt64 = 10_000_000_000,
             receiveMaximumLength: Int = 64 * 1024,
             maxResponseBodyBytes: Int = 6 * 1024 * 1024) {
            self.parseLimits = parseLimits
            self.readTimeoutNanoseconds = readTimeoutNanoseconds
            self.commandTimeoutNanoseconds = commandTimeoutNanoseconds
            self.receiveMaximumLength = receiveMaximumLength
            self.maxResponseBodyBytes = maxResponseBodyBytes
        }
    }

    /// 会话内部可变状态。
    ///
    /// 通过 `Mutex` 保护，临界区内只做同步的 buffer 拼接与关闭标记。
    private struct State: Sendable {
        /// 已收到尚未解析完成的请求字节累积区。
        var buffer = Data()

        /// 是否已关闭，用于保证 `close` 只真正执行一次。
        var isClosed = false
    }

    /// 会话内部错误。
    ///
    /// 把"连接关闭""已转换的服务端错误""底层接收失败"统一成一个错误类型，
    /// 让 `run` 的 catch 分支能与日志/响应一一对应。
    private enum SessionError: Error {
        /// 连接已关闭（对端断开或主动取消），无需再发响应。
        case closed

        /// 已经是 `ExploreServerError`，需要转成 HTTP 错误响应。
        case server(ExploreServerError)

        /// `NWConnection.receive` 报错，仅记录后关闭。
        case receiveFailed(String)
    }

    /// 会话唯一标识，贯穿所有日志用于关联同一连接的事件。
    let sessionID: String

    /// 底层 Network 连接。
    private let connection: NWConnection

    /// 命令分发器，`process` 阶段把请求交给它路由。
    private let router: Router

    /// 会话运行参数。
    private let configuration: Configuration

    /// 连接与回调派发的串行队列（由 `HTTPListener` 提供）。
    private let networkQueue: DispatchQueue

    /// 会话级事件回调（请求收到 / 已响应），由 `HTTPListener` 汇总用于统计与日志。
    private let onEvent: @Sendable (ServerEvent) -> Void

    /// 会话关闭回调，参数为 `sessionID`，通知 `HTTPListener` 从 session map 移除。
    private let onClose: @Sendable (String) -> Void

    /// 可变状态（buffer + 关闭标记），`Mutex` 保护。
    private let state = Mutex(State())

    /// 创建一个客户端会话。
    ///
    /// 会话对象由 `HTTPListener` 在 accept 新连接时创建，随后调用 `start()` 进入生命周期。
    ///
    /// - Parameters:
    ///   - sessionID: 会话唯一标识。
    ///   - connection: 底层 NWConnection。
    ///   - router: 命令分发器。
    ///   - configuration: 运行参数。
    ///   - networkQueue: 回调派发队列。
    ///   - onEvent: 请求/响应事件回调。
    ///   - onClose: 关闭通知回调。
    init(sessionID: String,
         connection: NWConnection,
         router: Router,
         configuration: Configuration,
         networkQueue: DispatchQueue,
         onEvent: @escaping @Sendable (ServerEvent) -> Void,
         onClose: @escaping @Sendable (String) -> Void) {
        self.sessionID = sessionID
        self.connection = connection
        self.router = router
        self.configuration = configuration
        self.networkQueue = networkQueue
        self.onEvent = onEvent
        self.onClose = onClose
    }

    /// 启动会话：记录 accepted 日志、订阅连接状态、在 networkQueue 上启动连接并开跑读循环。
    func start() {
        ExploreLogger.info(.listener, "session accepted id=\(sessionID)")
        connection.stateUpdateHandler = { [weak self] state in
            self?.handleConnectionState(state)
        }
        connection.start(queue: networkQueue)
        Task { [self] in
            await run()
        }
    }

    /// 关闭会话。
    ///
    /// 用 `isClosed` 标记保证幂等：只有第一次调用真正执行取消连接与 `onClose` 通知，
    /// 避免重复日志和重复移除。所有结束路径（超时、错误、正常响应、对端断开）都应收敛到这里。
    ///
    /// - Parameter reason: 关闭原因，写入日志便于排障。
    func close(reason: String) {
        let shouldClose = state.withLock { state -> Bool in
            if state.isClosed { return false }
            state.isClosed = true
            return true
        }
        guard shouldClose else { return }
        ExploreLogger.info(.listener, "session closed id=\(sessionID) reason=\(reason)")
        connection.stateUpdateHandler = nil
        connection.cancel()
        onClose(sessionID)
    }

    /// 处理 `NWConnection` 状态转移。
    ///
    /// 只关心与生命周期相关的状态：ready 仅记录，failed/cancelled 收敛到 `close`。
    /// - Parameter connectionState: 最新连接状态。
    private func handleConnectionState(_ connectionState: NWConnection.State) {
        switch connectionState {
        case .ready:
            ExploreLogger.debug(.listener, "session ready id=\(sessionID)")
        case .waiting(let error):
            ExploreLogger.error(.listener, "session waiting id=\(sessionID) error=\(error)")
        case .failed(let error):
            ExploreLogger.error(.listener, "session failed id=\(sessionID) error=\(error)")
            close(reason: "connection_failed")
        case .cancelled:
            close(reason: "connection_cancelled")
        default:
            break
        }
    }

    /// 会话主流程：在 `readTimeout` 内读完整 HTTP 请求，再交给 `process` 路由并回写响应。
    ///
    /// 错误收敛为两类：`server` 错误（如读超时）先发对应 HTTP 错误响应再关闭；连接关闭、
    /// 接收失败等不发送响应直接关闭。命令执行阶段在 `process` 内部用 `commandTimeout` 单独包裹。
    private func run() async {
        do {
            let request = try await withTimeout(nanoseconds: configuration.readTimeoutNanoseconds,
                                                timeoutError: .readTimeout()) { [self] in
                try await readRequest()
            }
            await process(request: request)
        } catch SessionError.server(let error) {
            ExploreLogger.error(.listener, "session error id=\(sessionID) category=\(error.category.rawValue) message=\(error.logMessage)")
            await send(HTTPParser.errorResponse(for: error), action: nil, closeReason: "read_timeout")
        } catch SessionError.closed {
            close(reason: "connection_closed")
        } catch {
            ExploreLogger.error(.listener, "session error id=\(sessionID) error=\(error)")
            close(reason: "receive_error")
        }
    }

    /// 循环读取字节直到解析出完整 HTTP 请求。
    ///
    /// 每收到一段就追加进 buffer 并尝试解析：complete 返回请求，incomplete 继续读，
    /// invalid 直接回错误响应并关闭连接。buffer 访问全部在 `Mutex` 临界区内完成。
    /// - Returns: 解析成功的 HTTP 请求。
    private func readRequest() async throws -> HTTPRequest {
        while true {
            let chunk = try await receive()
            let parseResult = state.withLock { state -> HTTPParseResult in
                state.buffer.append(chunk)
                ExploreLogger.debug(.listener, "session received id=\(sessionID) chunkBytes=\(chunk.count) totalBytes=\(state.buffer.count)")
                return HTTPParser.parseRequestResult(from: state.buffer,
                                                     limits: configuration.parseLimits)
            }
            switch parseResult {
            case .complete(let request, _):
                return request
            case .incomplete:
                continue
            case .invalid(let error):
                ExploreLogger.error(.http, "http parse failed session=\(sessionID) category=\(error.category.rawValue) message=\(error.logMessage)")
                await send(HTTPParser.errorResponse(for: error), action: nil, closeReason: "bad_request")
                throw SessionError.closed
            }
        }
    }

    /// 从连接拉取一段字节。
    /// - Returns: 收到的非空数据。
    /// - Throws: 连接关闭抛 `closed`，底层错误或空读抛 `receiveFailed`。
    private func receive() async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1,
                               maximumLength: configuration.receiveMaximumLength) { data, _, isComplete, error in
                if let error {
                    ExploreLogger.error(.listener, "session receive error id=\(self.sessionID) error=\(error)")
                    cont.resume(throwing: SessionError.receiveFailed(error.localizedDescription))
                    return
                }
                if let data, !data.isEmpty {
                    cont.resume(returning: data)
                    return
                }
                if isComplete {
                    cont.resume(throwing: SessionError.closed)
                    return
                }
                cont.resume(throwing: SessionError.receiveFailed("empty receive"))
            }
        }
    }

    /// 处理一条已解析的 HTTP 请求：校验端点与 body、路由命令、回写响应。
    ///
    /// 通信层失败（方法/路径/body 非法）用 HTTP 400；命令执行失败统一用 200 +
    /// 顶层失败 `code/message`，二者在此显式区分。命令执行受 `commandTimeout` 保护。
    /// - Parameter request: 已解析的 HTTP 请求。
    private func process(request: HTTPRequest) async {
        guard request.method == "POST", request.path == "/" else {
            let error = ExploreServerError.invalidMethod(method: request.method, path: request.path)
            ExploreLogger.error(.http, "http rejected session=\(sessionID) message=\(error.logMessage)")
            await send(HTTPParser.errorResponse(for: error), action: nil, closeReason: "bad_request")
            onEvent(.responded(status: 400, ok: false))
            return
        }

        let exploreReq: ExploreRequest
        switch HTTPParser.exploreRequest(from: request.body) {
        case .success(let req):
            exploreReq = req
        case .failure(let error):
            ExploreLogger.error(.http, "http rejected session=\(sessionID) message=\(error.logMessage)")
            await send(HTTPParser.errorResponse(for: error), action: nil, closeReason: "bad_request")
            onEvent(.responded(status: 400, ok: false))
            return
        }

        ExploreLogger.info(.http, "http received session=\(sessionID) method=\(request.method) path=\(request.path) action=\(exploreReq.action) bodyBytes=\(request.body.count)")
        onEvent(.received(method: request.method, path: request.path, action: exploreReq.action))

        let result: ExploreResult
        do {
            // 两步查表：超时上限须在 withTimeout 包裹 route 之前确定，而命令自声明
            // timeout 只有锁内取到 AnyCommand 后才读到，故先查 router.commandTimeout，
            // 缺省时回退全局 commandTimeoutNanoseconds。
            let timeoutNanos = router.commandTimeout(for: exploreReq.action)
                ?? configuration.commandTimeoutNanoseconds
            result = try await withTimeout(nanoseconds: timeoutNanos,
                                           timeoutError: .commandTimeout(action: exploreReq.action)) { [router] in
                await router.route(exploreReq)
            }
        } catch SessionError.server(let error) {
            ExploreLogger.error(.router, "router route failed session=\(sessionID) category=\(error.category.rawValue) message=\(error.logMessage)")
            result = .failure(code: error.code, message: error.message)
        } catch {
            let serverError = ExploreServerError.handlerThrown(action: exploreReq.action, error: error)
            ExploreLogger.error(.router, "router route failed session=\(sessionID) category=\(serverError.category.rawValue) message=\(serverError.logMessage)")
            result = .failure(code: serverError.code, message: serverError.message)
        }

        await send(HTTPParser.response(for: result), action: exploreReq.action, closeReason: "response_sent")
        let ok: Bool
        if case .success = result { ok = true } else { ok = false }
        onEvent(.responded(status: 200, ok: ok))
        ExploreLogger.info(.http, "http responded session=\(sessionID) status=200 ok=\(ok) action=\(exploreReq.action)")
    }

    /// 发送 HTTP 响应并随后关闭连接。
    ///
    /// 响应 body 超过 `maxResponseBodyBytes` 时改发 `responseTooLarge` envelope
    /// （HTTP 200 + `response_too_large`），此时 closeReason 会被改写为
    /// `"response_too_large"`。发送错误只记录（对端可能已断开），无论成功与否都按
    /// `closeReason` 收敛到 `close`。
    /// - Parameters:
    ///   - response: 待发送的 HTTP 响应。
    ///   - action: 触发该响应的命令名；早于命令解析的通信层失败传 `nil`，业务响应传
    ///     `exploreReq.action`，仅用于日志关联与错误 envelope 上下文。
    ///   - closeReason: 发送完成后的关闭原因，写入日志。
    private func send(_ response: HTTPResponse, action: String?, closeReason: String) async {
        if response.body.count > configuration.maxResponseBodyBytes {
            let resolvedAction = action ?? "unknown"
            let error = ExploreServerError.responseTooLarge(action: resolvedAction,
                                                            bytes: response.body.count,
                                                            limit: configuration.maxResponseBodyBytes)
            ExploreLogger.error(.listener, "session response too large id=\(sessionID) action=\(action ?? "?") bytes=\(response.body.count) limit=\(configuration.maxResponseBodyBytes)")
            await send(HTTPParser.errorResponse(for: error), action: action, closeReason: "response_too_large")
            return
        }
        ExploreLogger.debug(.http, "http send session=\(sessionID) status=\(response.status) bodyBytes=\(response.body.count)")
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            connection.send(content: response.serialized(), completion: .contentProcessed { error in
                if let error {
                    ExploreLogger.error(.http, "http send error session=\(self.sessionID) error=\(error)")
                }
                cont.resume()
            })
        }
        close(reason: closeReason)
    }

    /// 给异步操作套一个超时外壳。
    ///
    /// 用 `didResume` 标志保证 continuation 只被恢复一次：操作先完成就回值，
    /// 超时先到就取消操作并抛 `timeoutError`。`operation` 在锁外 await，符合锁内禁 await 约束。
    /// - Parameters:
    ///   - nanoseconds: 超时时长。
    ///   - timeoutError: 超时抛出的服务端错误。
    ///   - operation: 被包裹的异步工作。
    /// - Returns: 操作的返回值。
    /// - Throws: 操作自身抛出的错误，或超时抛出的 `timeoutError`。
    private func withTimeout<T: Sendable>(nanoseconds: UInt64,
                                timeoutError: ExploreServerError,
                                operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
            let didResume = Mutex(false)
            let operationTask = Task {
                do {
                    let value = try await operation()
                    
                    if didResume.withLock({ value in
                        if value { return false }
                        value = true
                        return true
                    }) {
                        cont.resume(returning: value)
                    }
                } catch {
                    if didResume.withLock({ value in
                        if value { return false }
                        value = true
                        return true
                    }) {
                        cont.resume(throwing: error)
                    }
                }
            }
            Task {
                try await Task.sleep(nanoseconds: nanoseconds)
                if didResume.withLock({ value in
                    if value { return false }
                    value = true
                    return true
                }) {
                    operationTask.cancel()
                    cont.resume(throwing: SessionError.server(timeoutError))
                }
            }
        }
    }
}
