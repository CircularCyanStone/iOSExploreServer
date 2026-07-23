import Foundation
import iOSExploreServer

#if DEBUG
@preconcurrency import OSLog

/// Apple Unified Logging 当前进程捕获器。
///
/// 该类型只在 Debug Diagnostics runtime 中安装。它通过 `OSLogStore(scope:
/// .currentProcessIdentifier)` 周期性读取当前进程新增 os_log / Swift Logger entry，并写入
/// 统一 `ESAppLogStore`。
/// 如果系统版本或沙箱不允许读取，状态返回 `unavailable`，避免让 Agent 误以为日志不存在。
final class ESUnifiedLogCapture: @unchecked Sendable {
    private let stopHandler: (@Sendable () -> Void)?
    private let flushHandler: (@Sendable () -> Void)?
    private let oslogCaptureStatus: ESLogCaptureStatus

    /// 根据配置安装 os_log / Swift Logger 捕获。
    ///
    /// - Parameters:
    ///   - configuration: Diagnostics 注册配置。
    ///   - store: 捕获到的日志写入的统一 store。
    init(configuration: ESDiagnosticsConfiguration, store: ESAppLogStore) {
        guard configuration.captureOSLog else {
            stopHandler = nil
            flushHandler = nil
            oslogCaptureStatus = .notCaptured(reason: "os_log capture is disabled")
            return
        }

        if #available(iOS 15.0, macOS 12.0, *) {
            do {
                let capture = try ESUnifiedLogPollingCapture(store: store)
                stopHandler = { capture.stop() }
                flushHandler = { capture.requestDrain() }
                oslogCaptureStatus = .enabled
                capture.start()
                ESLogger.emitExtension(level: .info,
                                       category: "diagnostics.oslog",
                                       message: "os_log capture enabled")
            } catch {
                stopHandler = nil
                flushHandler = nil
                oslogCaptureStatus = .unavailable(reason: "OSLogStore unavailable: \(error)")
                ESLogger.emitExtension(level: .error,
                                       category: "diagnostics.oslog",
                                       message: "os_log capture unavailable error=\(error)")
            }
        } else {
            stopHandler = nil
            flushHandler = nil
            oslogCaptureStatus = .unavailable(reason: "OSLogStore requires iOS 15 or macOS 12")
            ESLogger.emitExtension(level: .error,
                                   category: "diagnostics.oslog",
                                   message: "os_log capture unavailable reason=unsupported-os")
        }
    }

    /// 当前 os_log / Swift Logger 捕获状态。
    var oslogStatus: ESLogCaptureStatus { oslogCaptureStatus }

    /// 停止轮询并释放 timer。
    func stop() {
        stopHandler?()
    }

    /// 请求后台读取一次当前进程 Apple Unified Logging。
    ///
    /// `OSLogStore.getEntries` 在真机日志量较大时可能耗时明显，调用方不能同步等待它完成。
    /// 该方法只把 drain 投递到 unified log 捕获自己的串行队列，保证 `app.logs.read` 能及时返回。
    func requestFlush() {
        flushHandler?()
    }
}

@available(iOS 15.0, macOS 12.0, *)
private final class ESUnifiedLogPollingCapture: @unchecked Sendable {
    private static let rescanOverlap: TimeInterval = 30
    private let osStore: OSLogStore
    private let appStore: ESAppLogStore
    private let queue: DispatchQueue
    private let timer: DispatchSourceTimer
    private let cancelSemaphore: DispatchSemaphore
    private let state: Mutex<ESUnifiedLogPollingState>

    init(store: ESAppLogStore) throws {
        self.osStore = try OSLogStore(scope: .currentProcessIdentifier)
        self.appStore = store
        let queue = DispatchQueue(label: "com.coo.iOSExploreDiagnostics.oslog")
        self.queue = queue
        self.timer = DispatchSource.makeTimerSource(queue: queue)
        self.cancelSemaphore = DispatchSemaphore(value: 0)
        self.state = Mutex(ESUnifiedLogPollingState(stopped: false,
                                                  scanStartDate: Date(timeIntervalSinceNow: -2),
                                                  seenKeys: [],
                                                  seenOrder: []))
    }

    func start() {
        timer.setEventHandler { [weak self] in
            self?.drain()
        }
        timer.setCancelHandler { [weak self] in
            self?.cancelSemaphore.signal()
        }
        timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))
        timer.resume()
    }

    func stop() {
        let shouldStop = state.withLock { state -> Bool in
            if state.stopped { return false }
            state.stopped = true
            return true
        }
        guard shouldStop else { return }
        timer.cancel()
        if cancelSemaphore.wait(timeout: .now() + .seconds(2)) == .timedOut {
            ESLogger.emitExtension(level: .error,
                                   category: "diagnostics.oslog",
                                   message: "os_log capture cancel timed out")
        }
        ESLogger.emitExtension(level: .info,
                               category: "diagnostics.oslog",
                               message: "os_log capture stopped")
    }

    func requestDrain() {
        queue.async { [weak self] in
            self?.drain()
        }
    }

    func drain() {
        let isStopped = state.withLock { $0.stopped }
        guard isStopped == false else { return }
        let startDate = state.withLock { $0.scanStartDate }
        let startPosition = osStore.position(date: startDate)
        do {
            let entries = try osStore.getEntries(at: startPosition)
            var latestDate: Date?
            for entry in entries {
                latestDate = entry.date
                guard let logEntry = entry as? OSLogEntryLog else { continue }
                let key = Self.entryKey(logEntry)
                let shouldAppend = state.withLock { state -> Bool in
                    if state.seenKeys.contains(key) {
                        return false
                    }
                    state.seenKeys.insert(key)
                    state.seenOrder.append(key)
                    while state.seenOrder.count > 8_192 {
                        let removed = state.seenOrder.removeFirst()
                        state.seenKeys.remove(removed)
                    }
                    return true
                }
                if shouldAppend {
                    append(logEntry)
                }
            }
            if let latestDate {
                let nextStart = latestDate.addingTimeInterval(-Self.rescanOverlap)
                state.withLock { state in
                    if nextStart > state.scanStartDate {
                        state.scanStartDate = nextStart
                    }
                }
            }
        } catch {
            ESLogger.emitExtension(level: .error,
                                   category: "diagnostics.oslog",
                                   message: "os_log capture read failed error=\(error)")
        }
    }

    private func append(_ entry: OSLogEntryLog) {
        // OSLogStore(scope: .currentProcessIdentifier) 会读到当前进程内 Foundation、
        // UIKit、CFNetwork 等系统框架产生的 entry；Diagnostics 只把宿主主动写入的
        // os_log / Swift Logger 记录作为 `source=oslog` 暴露给 Agent。
        guard Self.isAppleSystemSubsystem(entry.subsystem) == false,
              Self.isExploreSubsystem(entry.subsystem) == false,
              Self.isRedactedPlaceholder(entry) == false,
              Self.isLikelyNSLogEntry(entry) == false else { return }
        appStore.append(source: .oslog,
                        level: ESAppLogLevel(entry.level),
                        category: entry.category,
                        message: entry.composedMessage,
                        metadata: [
                            "subsystem": entry.subsystem,
                            "category": entry.category,
                        ])
    }

    /// 判断 entry 是否属于 Apple 系统框架。
    ///
    /// 系统框架（Foundation、UIKit、CFNetwork、CoreText 等）的 subsystem 一律以
    /// `com.apple.` 开头。空 subsystem 不视为系统框架（部分宿主代码会以空字符串写日志）。
    private static func isAppleSystemSubsystem(_ subsystem: String) -> Bool {
        subsystem.lowercased().hasPrefix("com.apple.")
    }

    /// 判断 entry 是否属于 iOSExploreServer 自己的日志系统。
    private static func isExploreSubsystem(_ subsystem: String) -> Bool {
        subsystem == "iOSExploreServer"
    }

    /// 过滤掉 OSLogStore 里只剩 `<private>` 的占位记录。
    ///
    /// 这类 entry 没有可读业务信息，常见于系统把原始文本做了隐私脱敏后写回 store 的场景。
    /// 对 agent 来说它既不能帮助排障，也会制造重复噪音。
    private static func isRedactedPlaceholder(_ entry: OSLogEntryLog) -> Bool {
        entry.composedMessage == "<private>" && entry.subsystem.isEmpty && entry.category.isEmpty
    }

    private static func entryKey(_ entry: OSLogEntryLog) -> String {
        "\(entry.date.timeIntervalSince1970)|\(entry.subsystem)|\(entry.category)|\(entry.composedMessage)"
    }

    /// 保守排除 Foundation NSLog 记录，避免 os_log 捕获路径伪装成 NSLog fallback。
    private static func isLikelyNSLogEntry(_ entry: OSLogEntryLog) -> Bool {
        let subsystem = entry.subsystem.lowercased()
        let category = entry.category.lowercased()
        return subsystem.contains("foundation") && category.contains("nslog")
            || subsystem.contains("nslog")
            || category.contains("nslog")
    }
}

@available(iOS 15.0, macOS 12.0, *)
private struct ESUnifiedLogPollingState {
    var stopped: Bool
    var scanStartDate: Date
    var seenKeys: Set<String>
    var seenOrder: [String]
}

@available(iOS 15.0, macOS 12.0, *)
private extension ESAppLogLevel {
    init(_ level: OSLogEntryLog.Level) {
        switch level {
        case .debug:
            self = .debug
        case .info, .notice:
            self = .info
        case .error:
            self = .error
        case .fault:
            self = .fault
        case .undefined:
            self = .unknown
        @unknown default:
            self = .unknown
        }
    }
}
#endif
