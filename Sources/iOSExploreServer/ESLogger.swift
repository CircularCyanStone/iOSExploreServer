import Foundation
import os

/// iOSExploreServer 日志等级。
///
/// 等级值按严重程度递增，`ESLogger.setMinimumLevel(_:)` 用它过滤低优先级日志。
public enum ESLogLevel: Int, Sendable, Comparable {
    case debug = 0
    case info = 1
    case error = 2
    case fault = 3

    public static func < (lhs: ESLogLevel, rhs: ESLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .error: return .error
        case .fault: return .fault
        }
    }
}

/// 单条日志记录。
public struct ESLogRecord: Sendable, Equatable {
    public let level: ESLogLevel
    public let category: String
    public let message: String

    public init(level: ESLogLevel, category: String, message: String) {
        self.level = level
        self.category = category
        self.message = message
    }
}

/// 日志 observer 注册令牌。
///
/// Diagnostics 模块用该令牌在进程级 runtime 中持有一条订阅；调用
/// `ESLogger.removeObserver(_:)` 可移除对应 observer。普通业务方通常不需要直接使用。
public struct ESLogObservation: Sendable, Equatable {
    fileprivate let id: UUID
}

/// `ESLogger` 的可变配置快照。
///
/// 用值类型 + `Mutex` 整体替换，避免开关/等级/sink/observer 各自加锁。输出 sink 与
/// observer 是两条独立路径：sink 受 `setEnabled` 和最小等级控制；observer 用于
/// Diagnostics store，不受 Unified Logging 输出开关影响。
private struct ESLoggerState: Sendable {
    /// 输出到 sink 的开关。
    var outputEnabled: Bool

    /// 输出到 sink 的最小等级。
    var outputMinimumLevel: ESLogLevel

    /// 实际消费 record 的输出端，默认写 Apple Unified Logging，测试可替换。
    var sink: @Sendable (ESLogRecord) -> Void

    /// 旁路 observer，供 Diagnostics 在不打开 Unified Logging 输出时仍能录入日志。
    var observers: [UUID: @Sendable (ESLogRecord) -> Void]
}

/// 日志输出配置入口。
///
/// 默认关闭，避免组件被集成后主动产生大量系统日志。调试时调用
/// `ESLogger.setEnabled(true)` 即可把内部日志输出到 Apple Unified Logging。
public enum ESLogger {
    /// Unified Logging subsystem 名，所有日志归集于此。
    private static let defaultSubsystem = "iOSExploreServer"

    /// 全局配置状态，`Mutex` 保护读写。
    private static let state = Mutex(ESLoggerState(outputEnabled: false,
                                                   outputMinimumLevel: .debug,
                                                   sink: osLogSink,
                                                   observers: [:]))

    /// 当前日志总开关。
    public static var isEnabled: Bool {
        state.withLock { $0.outputEnabled }
    }

    /// 当前最小输出等级。
    public static var minimumLevel: ESLogLevel {
        state.withLock { $0.outputMinimumLevel }
    }

    /// 开启或关闭内部日志输出。
    public static func setEnabled(_ enabled: Bool) {
        state.withLock { $0.outputEnabled = enabled }
    }

    /// 设置最小输出等级。低于该等级的日志会被丢弃。
    public static func setMinimumLevel(_ level: ESLogLevel) {
        state.withLock { $0.outputMinimumLevel = level }
    }

    /// 添加一条日志 observer。
    ///
    /// observer 在 `ESLogger` 锁外执行，不能阻塞日志状态读写。Diagnostics observer
    /// 应只做有界内存 append，不做 IO，也不能再写回 `ESLogger`，避免递归。
    ///
    /// - Parameter observer: 接收日志 record 的闭包。
    /// - Returns: 用于移除 observer 的令牌。
    public static func addObserver(_ observer: @escaping @Sendable (ESLogRecord) -> Void) -> ESLogObservation {
        let id = UUID()
        state.withLock { $0.observers[id] = observer }
        return ESLogObservation(id: id)
    }

    /// 移除一条日志 observer。
    ///
    /// - Parameter observation: `addObserver(_:)` 返回的令牌。
    public static func removeObserver(_ observation: ESLogObservation) {
        state.withLock { $0.observers.removeValue(forKey: observation.id) }
    }

    /// 派发一条日志 record 到 `dispatch` 入口。
    ///
    /// - Parameter record: 待派发的日志记录。
    static func emit(_ record: ESLogRecord) {
        dispatch(record)
    }

    /// 按需构造并派发日志。
    ///
    /// 当存在 observer，或输出开启且等级通过最低门槛时，才会真正构造 `message`，
    /// 避免高频调试日志在所有出口都关闭时仍产生字符串拼接成本。
    static func emit(level: ESLogLevel, category: String, message: @autoclosure () -> String) {
        let shouldBuild = state.withLock { state in
            if state.observers.isEmpty == false { return true }
            return state.outputEnabled && level >= state.outputMinimumLevel
        }
        guard shouldBuild else { return }
        dispatch(ESLogRecord(level: level, category: category, message: message()))
    }

    /// 真正的落盘入口：在锁内做等级过滤并取出 observer/sink，再在锁外执行回调。
    ///
    /// 所有日志来源——`emit(_:)`（ESLogRecord 重载）、`emit(level:category:message:)`
    /// （autoclosure 重载）、`ESLogger` 各便捷方法、扩展模块 `emitExtension`——
    /// 最终都汇聚于此，保证开关、最小等级过滤和 sink 替换对全部来源统一生效。
    private static func dispatch(_ record: ESLogRecord) {
        let delivery: (observers: [@Sendable (ESLogRecord) -> Void], sink: (@Sendable (ESLogRecord) -> Void)?) = state.withLock { state in
            let observers = Array(state.observers.values)
            let sink: (@Sendable (ESLogRecord) -> Void)?
            if state.outputEnabled, record.level >= state.outputMinimumLevel {
                sink = state.sink
            } else {
                sink = nil
            }
            return (observers, sink)
        }
        for observer in delivery.observers {
            observer(record)
        }
        delivery.sink?(record)
    }

    /// 默认 sink：按 category 建 `OSLog`，调用 `os_log` 写入统一日志系统。
    private static func osLogSink(_ record: ESLogRecord) {
        let log = OSLog(subsystem: defaultSubsystem, category: record.category)
        os_log("%{public}@", log: log, type: record.level.osLogType, record.message)
    }

    /// 替换 sink，仅测试用：把日志接到可断言的回调上。
    static func setSinkForTesting(_ sink: @escaping @Sendable (ESLogRecord) -> Void) {
        state.withLock { $0.sink = sink }
    }

    /// 重置为默认状态，仅测试用，避免用例间相互污染。
    static func resetForTesting() {
        state.withLock {
            $0.outputEnabled = false
            $0.outputMinimumLevel = .debug
            $0.sink = osLogSink
            $0.observers.removeAll()
        }
    }
}

/// 日志 category 枚举，对应库内各模块，用作 `OSLog` category 与排障过滤维度。
enum ESLogCategory: String, Sendable {
    /// 门面 `ExploreServer` 与整体生命周期。
    case server
    /// 传输层 `HTTPListener` / `ClientSession`。
    case listener
    /// HTTP 解析与请求/响应收发。
    case http
    /// 命令分发 `Router`。
    case router
    /// 命令执行（handler 内）。
    case command
}

/// 模块内统一的日志便捷入口。
///
/// 包装 `ESLogger.emit`，按 category 自动归类，`message` 用 `@autoclosure`
/// 避免关闭日志时仍拼接字符串。
extension ESLogger {
    /// 记录一条 debug 日志。
    static func debug(_ category: ESLogCategory, _ message: @autoclosure () -> String) {
        log(.debug, category, message())
    }

    /// 记录一条 info 日志。
    static func info(_ category: ESLogCategory, _ message: @autoclosure () -> String) {
        log(.info, category, message())
    }

    /// 记录一条 error 日志。
    static func error(_ category: ESLogCategory, _ message: @autoclosure () -> String) {
        log(.error, category, message())
    }

    /// 记录一条 fault 日志（最严重，通常不可恢复）。
    static func fault(_ category: ESLogCategory, _ message: @autoclosure () -> String) {
        log(.fault, category, message())
    }

    /// 组装 record 并委托 `ESLogger.emit(level:category:message:)` 派发。
    private static func log(_ level: ESLogLevel,
                            _ category: ESLogCategory,
                            _ message: @autoclosure () -> String) {
        ESLogger.emit(level: level, category: category.rawValue, message: message())
    }
}
