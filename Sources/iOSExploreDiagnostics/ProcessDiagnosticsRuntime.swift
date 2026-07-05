import Foundation
import iOSExploreServer

private struct ProcessDiagnosticsRuntimeState {
    var store: AppLogStore?
    var bridgeEnabled: Bool = false
    var observation: ExploreLogObservation?
    var configuration: DiagnosticsConfiguration = .default
#if DEBUG
    var stdioCapture: StdIOCapture?
    var unifiedLogCapture: UnifiedLogCapture?
#endif
}

/// 进程级 Diagnostics Runtime。
///
/// 日志 store、bridge 和 `ExploreLogging` observer 都是进程级资源，而不是某个
/// `ExploreServer` 实例的私有资源。`server.stop()` 只停止 HTTP listener，不会清空这里的
/// store。
public final class ProcessDiagnosticsRuntime: Sendable {
    /// 共享 runtime。
    public static let shared = ProcessDiagnosticsRuntime()

    private let state = Mutex(ProcessDiagnosticsRuntimeState())

    private init() {}

    /// 在指定 server 上注册 Diagnostics 命令并安装稳定日志来源。
    ///
    /// - Parameters:
    ///   - server: 要挂载 `app.logs.*` action 的 server。
    ///   - configuration: Diagnostics 配置。
    /// - Returns: 注册结果。
    @discardableResult
    func register(on server: ExploreServer,
                  configuration: DiagnosticsConfiguration) -> DiagnosticsRegistration {
#if DEBUG
        ExploreLogging.emitExtension(level: .info,
                                     category: "diagnostics.runtime",
                                     message: "diagnostics register started bufferCapacity=\(configuration.bufferCapacity) captureExploreLogs=\(configuration.captureExploreLogs) bridge=\(configuration.enableBridge) stdout=\(configuration.captureStdout) stderr=\(configuration.captureStderr) nslog=\(configuration.captureNSLog) oslog=\(configuration.captureOSLog)")
        let previousCaptures = state.withLock { state -> (StdIOCapture?, UnifiedLogCapture?) in
            if let observation = state.observation {
                ExploreLogging.removeObserver(observation)
            }
            let captures = (state.stdioCapture, state.unifiedLogCapture)
            state = ProcessDiagnosticsRuntimeState()
            return captures
        }
        previousCaptures.0?.stop()
        previousCaptures.1?.stop()

        let store = AppLogStore(captureSessionID: UUID().uuidString,
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
                state.observation = ExploreLogging.addObserver { record in
                    store.append(source: .explore,
                                 level: AppLogLevel(record.level),
                                 category: record.category,
                                 message: record.message)
                }
            } else {
                state.observation = nil
            }
        }
        let stdioCapture = StdIOCapture(configuration: configuration, store: store)
        let unifiedLogCapture = UnifiedLogCapture(configuration: configuration, store: store)
        state.withLock { state in
            state.stdioCapture = stdioCapture
            state.unifiedLogCapture = unifiedLogCapture
        }
        server.register(AppLogsMarkCommand(runtime: self))
        server.register(AppLogsReadCommand(runtime: self))
        ExploreLogging.emitExtension(level: .info,
                                     category: "diagnostics.runtime",
                                     message: "diagnostics register completed captureSessionID=\(store.mark().cursor.captureSessionID)")
        return .enabled(captureSessionID: store.mark().cursor.captureSessionID)
#else
        _ = server
        _ = configuration
        ExploreLogging.emitExtension(level: .info,
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
    func appendBridge(level: AppLogLevel,
                      category: String,
                      message: () -> String,
                      metadata: [String: String]?) {
        let snapshot = state.withLock { state -> (Bool, AppLogStore?) in
            (state.bridgeEnabled, state.store)
        }
        guard snapshot.0, let store = snapshot.1 else { return }
        store.append(source: .bridge, level: level, category: category, message: message(), metadata: metadata)
    }

    /// 当前 store 快照。
    ///
    /// - Returns: 已安装 store；未安装时为 nil。
    func currentStore() -> AppLogStore? {
        state.withLock { $0.store }
    }

    /// 读取日志前刷新需要主动轮询的捕获来源。
    ///
    /// stdout/stderr/NSLog 由 fd read source 推送；Apple Unified Logging 可能延迟落入
    /// `OSLogStore`，因此在 `app.logs.read` 前主动拉取一次，降低 Agent 读到空结果的概率。
    func flushPendingCaptures() {
#if DEBUG
        let unifiedLogCapture = state.withLock { $0.unifiedLogCapture }
        unifiedLogCapture?.flush()
#endif
    }

    /// 当前各日志来源捕获状态。
    ///
    /// - Returns: 可直接放入 `app.logs.mark/read` 响应的 JSON object。
    func captureStatusJSON() -> JSON {
#if DEBUG
        let snapshot = state.withLock { state in
            (state.store != nil, state.bridgeEnabled, state.configuration, state.stdioCapture, state.unifiedLogCapture)
        }
        let installed = snapshot.0
        let bridgeEnabled = snapshot.1
        let configuration = snapshot.2
        let stdioCapture = snapshot.3
        let unifiedLogCapture = snapshot.4
        let nslogCaptureStatus = combinedNSLogStatus(stdioStatus: stdioCapture?.nslog,
                                                     unifiedStatus: unifiedLogCapture?.nslogStatus)
        let oslogCaptureStatus = unifiedLogCapture?.oslogStatus
#else
        let snapshot = state.withLock { state in
            (state.store != nil, state.bridgeEnabled, state.configuration)
        }
        let installed = snapshot.0
        let bridgeEnabled = snapshot.1
        let configuration = snapshot.2
        let nslogCaptureStatus: StdIOCaptureStatus? = .notCaptured(reason: "NSLog capture is disabled in non-Debug builds")
        let oslogCaptureStatus: StdIOCaptureStatus? = .notCaptured(reason: "os_log capture is disabled in non-Debug builds")
#endif
        var capture: JSON = [
            "explore": .object(status(state: installed && configuration.captureExploreLogs ? "enabled" : "notCaptured",
                                      reason: installed ? nil : "Diagnostics Runtime is not installed")),
            "bridge": .object(status(state: installed && bridgeEnabled ? "enabled" : "notCaptured",
                                     reason: bridgeEnabled ? nil : "ExploreAppLog bridge is disabled")),
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
        let previousCaptures = state.withLock { state -> (StdIOCapture?, UnifiedLogCapture?) in
            if let observation = state.observation {
                ExploreLogging.removeObserver(observation)
            }
            let captures = (state.stdioCapture, state.unifiedLogCapture)
            state = ProcessDiagnosticsRuntimeState()
            return captures
        }
        previousCaptures.0?.stop()
        previousCaptures.1?.stop()
#else
        state.withLock { state in
            if let observation = state.observation {
                ExploreLogging.removeObserver(observation)
            }
            state = ProcessDiagnosticsRuntimeState()
        }
#endif
    }

    private func streamStatus(enabled: Bool,
                              installed: Bool,
                              status captureStatus: StdIOCaptureStatus?,
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
    private func combinedNSLogStatus(stdioStatus: StdIOCaptureStatus?,
                                     unifiedStatus: StdIOCaptureStatus?) -> StdIOCaptureStatus? {
        if stdioStatus?.state == "enabled" || unifiedStatus?.state == "enabled" {
            return .enabled
        }
        return unifiedStatus ?? stdioStatus
    }
#endif
}

private extension AppLogLevel {
    init(_ level: ExploreLogLevel) {
        switch level {
        case .debug: self = .debug
        case .info: self = .info
        case .error: self = .error
        case .fault: self = .fault
        }
    }
}
