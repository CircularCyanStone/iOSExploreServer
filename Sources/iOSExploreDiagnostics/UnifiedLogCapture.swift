import Foundation
import iOSExploreServer

#if DEBUG
@preconcurrency import OSLog

/// Apple Unified Logging 当前进程捕获器。
///
/// 该类型只在 Debug Diagnostics runtime 中安装。它通过 `OSLogStore(scope:
/// .currentProcessIdentifier)` 周期性读取当前进程新增 entry，并写入统一 `AppLogStore`。
/// 如果系统版本或沙箱不允许读取，状态返回 `unavailable`，避免让 Agent 误以为日志不存在。
final class UnifiedLogCapture: @unchecked Sendable {
    private let stopHandler: (@Sendable () -> Void)?
    private let flushHandler: (@Sendable () -> Void)?
    private let nslogCaptureStatus: StdIOCaptureStatus
    private let oslogCaptureStatus: StdIOCaptureStatus

    /// 根据配置安装 unified logging 捕获。
    ///
    /// - Parameters:
    ///   - configuration: Diagnostics 注册配置。
    ///   - store: 捕获到的日志写入的统一 store。
    init(configuration: DiagnosticsConfiguration, store: AppLogStore) {
        guard configuration.captureNSLog || configuration.captureOSLog else {
            stopHandler = nil
            flushHandler = nil
            nslogCaptureStatus = .notCaptured(reason: "NSLog capture is disabled")
            oslogCaptureStatus = .notCaptured(reason: "os_log capture is disabled")
            return
        }

        if #available(iOS 15.0, macOS 12.0, *) {
            do {
                let capture = try UnifiedLogPollingCapture(store: store,
                                                           captureNSLog: configuration.captureNSLog,
                                                           captureOSLog: configuration.captureOSLog)
                stopHandler = { capture.stop() }
                flushHandler = { capture.requestDrain() }
                nslogCaptureStatus = configuration.captureNSLog
                    ? .enabled
                    : .notCaptured(reason: "NSLog capture is disabled")
                oslogCaptureStatus = configuration.captureOSLog
                    ? .enabled
                    : .notCaptured(reason: "os_log capture is disabled")
                capture.start()
                ExploreLogging.emitExtension(level: .info,
                                             category: "diagnostics.oslog",
                                             message: "unified log capture enabled nslog=\(configuration.captureNSLog) oslog=\(configuration.captureOSLog)")
            } catch {
                stopHandler = nil
                flushHandler = nil
                nslogCaptureStatus = configuration.captureNSLog
                    ? .unavailable(reason: "OSLogStore unavailable: \(error)")
                    : .notCaptured(reason: "NSLog capture is disabled")
                oslogCaptureStatus = configuration.captureOSLog
                    ? .unavailable(reason: "OSLogStore unavailable: \(error)")
                    : .notCaptured(reason: "os_log capture is disabled")
                ExploreLogging.emitExtension(level: .error,
                                             category: "diagnostics.oslog",
                                             message: "unified log capture unavailable error=\(error)")
            }
        } else {
            stopHandler = nil
            flushHandler = nil
            nslogCaptureStatus = configuration.captureNSLog
                ? .unavailable(reason: "OSLogStore requires iOS 15 or macOS 12")
                : .notCaptured(reason: "NSLog capture is disabled")
            oslogCaptureStatus = configuration.captureOSLog
                ? .unavailable(reason: "OSLogStore requires iOS 15 or macOS 12")
                : .notCaptured(reason: "os_log capture is disabled")
            ExploreLogging.emitExtension(level: .error,
                                         category: "diagnostics.oslog",
                                         message: "unified log capture unavailable reason=unsupported-os")
        }
    }

    /// 当前 unified logging 路径上的 NSLog 捕获状态。
    var nslogStatus: StdIOCaptureStatus { nslogCaptureStatus }

    /// 当前 unified logging 捕获状态。
    var oslogStatus: StdIOCaptureStatus { oslogCaptureStatus }

    /// 停止轮询并释放 timer。
    func stop() {
        stopHandler?()
    }

    /// 请求后台读取一次当前进程 unified logging。
    ///
    /// `OSLogStore.getEntries` 在真机日志量较大时可能耗时明显，调用方不能同步等待它完成。
    /// 该方法只把 drain 投递到 unified log 捕获自己的串行队列，保证 `app.logs.read` 能及时返回。
    func requestFlush() {
        flushHandler?()
    }
}

@available(iOS 15.0, macOS 12.0, *)
private final class UnifiedLogPollingCapture: @unchecked Sendable {
    private static let rescanOverlap: TimeInterval = 30
    private let osStore: OSLogStore
    private let appStore: AppLogStore
    private let captureNSLog: Bool
    private let captureOSLog: Bool
    private let queue: DispatchQueue
    private let timer: DispatchSourceTimer
    private let cancelSemaphore: DispatchSemaphore
    private let state: Mutex<UnifiedLogPollingState>

    init(store: AppLogStore, captureNSLog: Bool, captureOSLog: Bool) throws {
        self.osStore = try OSLogStore(scope: .currentProcessIdentifier)
        self.appStore = store
        self.captureNSLog = captureNSLog
        self.captureOSLog = captureOSLog
        let queue = DispatchQueue(label: "com.coo.iOSExploreDiagnostics.oslog")
        self.queue = queue
        self.timer = DispatchSource.makeTimerSource(queue: queue)
        self.cancelSemaphore = DispatchSemaphore(value: 0)
        self.state = Mutex(UnifiedLogPollingState(stopped: false,
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
            ExploreLogging.emitExtension(level: .error,
                                         category: "diagnostics.oslog",
                                         message: "unified log capture cancel timed out")
        }
        ExploreLogging.emitExtension(level: .info,
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
            ExploreLogging.emitExtension(level: .error,
                                         category: "diagnostics.oslog",
                                         message: "os_log capture read failed error=\(error)")
        }
    }

    private func append(_ entry: OSLogEntryLog) {
        let isNSLog = Self.looksLikeNSLogEntry(entry)
        if captureNSLog, isNSLog || captureOSLog == false {
            appStore.append(source: .nslog,
                            level: .info,
                            category: "nslog",
                            message: entry.composedMessage,
                            metadata: [
                                "subsystem": entry.subsystem,
                                "category": entry.category,
                                "capturePath": "unifiedLog",
                            ])
        }
        if captureOSLog, isNSLog == false {
            // 跳过 Apple 系统框架（subsystem 以 "com.apple." 开头）的 unified log entry。
            // OSLogStore(scope: .currentProcessIdentifier) 会读到当前进程内 Foundation、
            // UIKit、CFNetwork 等系统框架产生的 entry，对调试宿主 App 自身行为没有价值。
            // 宿主自己写的 os_log / Swift Logger 使用的 subsystem 不会以 "com.apple." 开头。
            guard Self.isAppleSystemSubsystem(entry.subsystem) == false else { return }
            appStore.append(source: .oslog,
                            level: AppLogLevel(entry.level),
                            category: entry.category,
                            message: entry.composedMessage,
                            metadata: [
                                "subsystem": entry.subsystem,
                                "category": entry.category,
                            ])
        }
    }

    /// 判断 entry 是否属于 Apple 系统框架。
    ///
    /// 系统框架（Foundation、UIKit、CFNetwork、CoreText 等）的 subsystem 一律以
    /// `com.apple.` 开头。空 subsystem 不视为系统框架（部分宿主代码会以空字符串写日志）。
    private static func isAppleSystemSubsystem(_ subsystem: String) -> Bool {
        subsystem.lowercased().hasPrefix("com.apple.")
    }

    private static func entryKey(_ entry: OSLogEntryLog) -> String {
        "\(entry.date.timeIntervalSince1970)|\(entry.subsystem)|\(entry.category)|\(entry.composedMessage)"
    }

    private static func looksLikeNSLogEntry(_ entry: OSLogEntryLog) -> Bool {
        let subsystem = entry.subsystem.lowercased()
        let category = entry.category.lowercased()
        return subsystem.contains("foundation") && category.contains("nslog")
            || subsystem.contains("nslog")
            || category.contains("nslog")
    }
}

@available(iOS 15.0, macOS 12.0, *)
private struct UnifiedLogPollingState {
    var stopped: Bool
    var scanStartDate: Date
    var seenKeys: Set<String>
    var seenOrder: [String]
}

@available(iOS 15.0, macOS 12.0, *)
private extension AppLogLevel {
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
