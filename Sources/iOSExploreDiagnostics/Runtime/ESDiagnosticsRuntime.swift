import Foundation
import iOSExploreServer

private struct ESDiagnosticsRuntimeState {
    var store: ESAppLogStore?
    var bridgeEnabled: Bool = false
    var observation: ESLogObservation?
    var configuration: ESDiagnosticsConfiguration = .default
#if DEBUG
    var nslogHookCapture: ESNSLogHookCapture?
    var stdioCapture: ESStdIOCapture?
    var unifiedLogCapture: ESUnifiedLogCapture?
    var pendingCaptureFlushOverride: (@Sendable () -> Void)?
#endif
}

/// 进程级 Diagnostics Runtime。
///
/// 日志 store、bridge 和 `ESLogger` observer 都是进程级资源，而不是某个
/// `ExploreServer` 实例的私有资源。`server.stop()` 只停止 HTTP listener，不会清空这里的
/// store。
final class ESDiagnosticsRuntime: Sendable {
    /// 共享 runtime。
    static let shared = ESDiagnosticsRuntime()

    private let state = Mutex(ESDiagnosticsRuntimeState())

    private init() {}

    /// 在指定 server 上注册 Diagnostics 命令并安装稳定日志来源。
    ///
    /// - Parameters:
    ///   - server: 要挂载 `app.logs.*` action 的 server。
    ///   - configuration: Diagnostics 配置。
    /// - Returns: 注册结果。
    @discardableResult
    func register(on server: ExploreServer,
                  configuration: ESDiagnosticsConfiguration) -> ESDiagnosticsRegistration {
#if DEBUG
        ESLogger.emitExtension(level: .info,
                               category: "diagnostics.runtime",
                               message: "diagnostics register started bufferCapacity=\(configuration.bufferCapacity) captureExploreLogs=\(configuration.captureExploreLogs) bridge=\(configuration.enableBridge) stdout=\(configuration.captureStdout) stderr=\(configuration.captureStderr) nslog=\(configuration.captureNSLog) oslog=\(configuration.captureOSLog)")
        let previousCaptures = state.withLock { state -> (ESNSLogHookCapture?, ESStdIOCapture?, ESUnifiedLogCapture?) in
            if let observation = state.observation {
                ESLogger.removeObserver(observation)
            }
            let captures = (state.nslogHookCapture, state.stdioCapture, state.unifiedLogCapture)
            state = ESDiagnosticsRuntimeState()
            return captures
        }
        previousCaptures.0?.stop()
        previousCaptures.1?.stop()
        previousCaptures.2?.stop()

        let store = ESAppLogStore(captureSessionID: UUID().uuidString,
                                  capacity: configuration.bufferCapacity,
                                  maximumEntryBytes: configuration.maximumEntryBytes,
                                  maximumMetadataEntries: configuration.maximumMetadataEntries,
                                  maximumMetadataKeyBytes: configuration.maximumMetadataKeyBytes,
                                  maximumMetadataValueBytes: configuration.maximumMetadataValueBytes,
                                  redactor: configuration.redaction)
        state.withLock { state in
            state.store = store
            state.bridgeEnabled = configuration.enableBridge
            state.configuration = configuration
            if configuration.captureExploreLogs {
                state.observation = ESLogger.addObserver { record in
                    store.append(source: .explore,
                                 level: ESAppLogLevel(record.level),
                                 category: record.category,
                                 message: record.message)
                }
            } else {
                state.observation = nil
            }
        }
        let nslogHookCapture = ESNSLogHookCapture(configuration: configuration,
                                                  store: store)
        let stdioCapture = ESStdIOCapture(configuration: configuration,
                                          store: store,
                                          captureNSLogFromStderr: configuration.captureNSLog,
                                          suppressNSLogStderrLines: false)
        let unifiedLogCapture = ESUnifiedLogCapture(configuration: configuration,
                                                    store: store)
        state.withLock { state in
            state.nslogHookCapture = nslogHookCapture
            state.stdioCapture = stdioCapture
            state.unifiedLogCapture = unifiedLogCapture
        }
        server.register(ESAppLogsMarkCommand(runtime: self))
        server.register(ESAppLogsReadCommand(runtime: self))
        ESLogger.emitExtension(level: .info,
                               category: "diagnostics.runtime",
                               message: "diagnostics register completed captureSessionID=\(store.mark().cursor.captureSessionID)")
        return .enabled(captureSessionID: store.mark().cursor.captureSessionID)
#else
        _ = server
        _ = configuration
        ESLogger.emitExtension(level: .info,
                               category: "diagnostics.runtime",
                               message: "diagnostics register disabled reason=non-debug-build")
        return .disabled(reason: "iOSExploreDiagnostics is disabled in non-Debug builds.")
#endif
    }

    /// 写入宿主 bridge 日志。
    ///
    /// - Parameters:
    ///   - level: 日志等级。
    ///   - category: 宿主分类。
    ///   - message: 日志正文。
    ///   - metadata: 轻量上下文。
    func appendBridge(level: ESAppLogLevel,
                      category: String,
                      message: () -> String,
                      metadata: [String: String]?) {
        let snapshot = state.withLock { state -> (Bool, ESAppLogStore?) in
            (state.bridgeEnabled, state.store)
        }
        guard snapshot.0, let store = snapshot.1 else { return }
        store.append(source: .bridge, level: level, category: category, message: message(), metadata: metadata)
    }

    /// 当前 store 快照。
    ///
    /// - Returns: 已安装 store；未安装时为 nil。
    func currentStore() -> ESAppLogStore? {
        state.withLock { $0.store }
    }

    /// 读取日志前请求刷新需要主动轮询的捕获来源。
    ///
    /// stdout/stderr 由 fd read source 推送；NSLog 由 stderr 行识别与 fishhook 增强路径推送。
    /// os_log / Swift Logger 可能延迟落入 `OSLogStore`，因此在 `app.logs.read`
    /// 前发起一次后台拉取，降低 Agent 后续读到空结果的概率。
    /// 这里不能同步等待 `OSLogStore.getEntries`：真机日志量较大时该系统调用可能长时间不返回，
    /// 会阻塞 `app.logs.read` 响应并让 Agent 误判 MCP 服务不可用。
    func flushPendingCaptures() {
#if DEBUG
        let snapshot = state.withLock { state in
            (state.pendingCaptureFlushOverride, state.unifiedLogCapture)
        }
        if let override = snapshot.0 {
            ESLogger.emitExtension(level: .debug,
                                   category: "diagnostics.runtime",
                                   message: "pending capture flush requested mode=testOverride")
            DispatchQueue.global(qos: .utility).async(execute: override)
            return
        }
        snapshot.1?.requestFlush()
#endif
    }

#if DEBUG
    /// 测试辅助：替换 `app.logs.read` 前的 pending capture flush。
    ///
    /// 该 hook 用来复现系统日志刷新长时间不返回时，读取命令仍应立即响应的契约。
    /// `resetForTesting()` 会清掉 hook，避免污染其它测试。
    func setPendingCaptureFlushOverrideForTesting(_ override: (@Sendable () -> Void)?) {
        state.withLock { state in
            state.pendingCaptureFlushOverride = override
        }
    }
#endif

    /// 当前各日志来源捕获状态。
    ///
    /// - Returns: 可直接放入 `app.logs.mark/read` 响应的 JSON object。
    func captureStatusJSON() -> JSON {
#if DEBUG
        let snapshot = state.withLock { state in
            (state.store != nil, state.bridgeEnabled, state.configuration, state.nslogHookCapture, state.stdioCapture, state.unifiedLogCapture)
        }
        let installed = snapshot.0
        let bridgeEnabled = snapshot.1
        let configuration = snapshot.2
        let nslogHookCapture = snapshot.3
        let stdioCapture = snapshot.4
        let unifiedLogCapture = snapshot.5
        let nslogCaptureStatus = combinedNSLogStatus(hookStatus: nslogHookCapture?.status,
                                                     stdioStatus: stdioCapture?.nslog)
        let oslogCaptureStatus = unifiedLogCapture?.oslogStatus
#else
        let snapshot = state.withLock { state in
            (state.store != nil, state.bridgeEnabled, state.configuration)
        }
        let installed = snapshot.0
        let bridgeEnabled = snapshot.1
        let configuration = snapshot.2
        let nslogCaptureStatus: ESLogCaptureStatus? = .notCaptured(reason: "NSLog capture is disabled in non-Debug builds")
        let oslogCaptureStatus: ESLogCaptureStatus? = .notCaptured(reason: "os_log capture is disabled in non-Debug builds")
#endif
        var capture: JSON = [
            "explore": .object(status(state: installed && configuration.captureExploreLogs ? "enabled" : "notCaptured",
                                      reason: installed ? nil : "Diagnostics Runtime is not installed")),
            "bridge": .object(status(state: installed && bridgeEnabled ? "enabled" : "notCaptured",
                                     reason: bridgeEnabled ? nil : "ESAppLogger bridge is disabled")),
            "nslog": .object(streamStatus(enabled: configuration.captureNSLog,
                                          installed: installed,
                                          status: nslogCaptureStatus,
                                          name: "NSLog")),
            "oslog": .object(streamStatus(enabled: configuration.captureOSLog,
                                          installed: installed,
                                          status: oslogCaptureStatus,
                                          name: "os_log")),
        ]
#if DEBUG
        capture["stdout"] = .object(streamStatus(enabled: configuration.captureStdout,
                                                 installed: installed,
                                                 status: stdioCapture?.stdout,
                                                 name: "stdout"))
        capture["stderr"] = .object(streamStatus(enabled: configuration.captureStderr,
                                                 installed: installed,
                                                 status: stdioCapture?.stderr,
                                                 name: "stderr"))
#else
        capture["stdout"] = .object(streamStatus(enabled: configuration.captureStdout,
                                                 installed: installed,
                                                 status: .notCaptured(reason: "stdout capture is disabled in non-Debug builds"),
                                                 name: "stdout"))
        capture["stderr"] = .object(streamStatus(enabled: configuration.captureStderr,
                                                 installed: installed,
                                                 status: .notCaptured(reason: "stderr capture is disabled in non-Debug builds"),
                                                 name: "stderr"))
#endif
        return capture
    }

    /// 测试辅助：清空 runtime 并移除 observer。
    func resetForTesting() {
#if DEBUG
        let previousCaptures = state.withLock { state -> (ESNSLogHookCapture?, ESStdIOCapture?, ESUnifiedLogCapture?) in
            if let observation = state.observation {
                ESLogger.removeObserver(observation)
            }
            let captures = (state.nslogHookCapture, state.stdioCapture, state.unifiedLogCapture)
            state = ESDiagnosticsRuntimeState()
            return captures
        }
        previousCaptures.0?.stop()
        previousCaptures.1?.stop()
        previousCaptures.2?.stop()
#else
        state.withLock { state in
            if let observation = state.observation {
                ESLogger.removeObserver(observation)
            }
            state = ESDiagnosticsRuntimeState()
        }
#endif
    }

    private func streamStatus(enabled: Bool,
                              installed: Bool,
                              status captureStatus: ESLogCaptureStatus?,
                              name: String) -> JSON {
        guard enabled else {
            return status(state: "notCaptured", reason: "\(name) capture is disabled")
        }
        guard installed else {
            return status(state: "unavailable", reason: "Diagnostics Runtime is not installed")
        }
        guard let captureStatus else {
            return status(state: "unavailable", reason: "\(name) capture was not installed")
        }
        return status(state: captureStatus.state, reason: captureStatus.reason)
    }

    private func status(state: String, reason: String?) -> JSON {
        var json: JSON = ["state": .string(state)]
        if let reason {
            json["reason"] = .string(reason)
        }
        return json
    }

#if DEBUG
    private func combinedNSLogStatus(hookStatus: ESLogCaptureStatus?,
                                     stdioStatus: ESLogCaptureStatus?) -> ESLogCaptureStatus? {
        if hookStatus?.state == "enabled"
            || stdioStatus?.state == "enabled" {
            return .enabled
        }
        return hookStatus ?? stdioStatus
    }
#endif
}

private extension ESAppLogLevel {
    init(_ level: ESLogLevel) {
        switch level {
        case .debug: self = .debug
        case .info: self = .info
        case .error: self = .error
        case .fault: self = .fault
        }
    }
}
