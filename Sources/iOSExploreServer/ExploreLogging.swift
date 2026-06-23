import Foundation
import os

/// iOSExploreServer 日志等级。
///
/// 等级值按严重程度递增，`ExploreLogging.setMinimumLevel(_:)` 用它过滤低优先级日志。
public enum ExploreLogLevel: Int, Sendable, Comparable {
    case debug = 0
    case info = 1
    case error = 2
    case fault = 3

    public static func < (lhs: ExploreLogLevel, rhs: ExploreLogLevel) -> Bool {
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
public struct ExploreLogRecord: Sendable, Equatable {
    public let level: ExploreLogLevel
    public let category: String
    public let message: String

    public init(level: ExploreLogLevel, category: String, message: String) {
        self.level = level
        self.category = category
        self.message = message
    }
}

/// `ExploreLogging` 的可变配置快照。
///
/// 用值类型 + `Mutex` 整体替换，避免开关/等级/sink 三个字段各自加锁。
private struct ExploreLoggingState: Sendable {
    /// 日志总开关。
    var isEnabled: Bool

    /// 最小输出等级。
    var minimumLevel: ExploreLogLevel

    /// 实际消费 record 的输出端，默认写 Apple Unified Logging，测试可替换。
    var sink: @Sendable (ExploreLogRecord) -> Void
}

/// 日志输出配置入口。
///
/// 默认关闭，避免组件被集成后主动产生大量系统日志。调试时调用
/// `ExploreLogging.setEnabled(true)` 即可把内部日志输出到 Apple Unified Logging。
public enum ExploreLogging {
    /// Unified Logging subsystem 名，所有日志归集于此。
    private static let defaultSubsystem = "iOSExploreServer"

    /// 全局配置状态，`Mutex` 保护读写。
    private static let state = Mutex(ExploreLoggingState(isEnabled: false,
                                                         minimumLevel: .debug,
                                                         sink: osLogSink))

    /// 当前日志总开关。
    public static var isEnabled: Bool {
        state.withLock { $0.isEnabled }
    }

    /// 当前最小输出等级。
    public static var minimumLevel: ExploreLogLevel {
        state.withLock { $0.minimumLevel }
    }

    /// 开启或关闭内部日志输出。
    public static func setEnabled(_ enabled: Bool) {
        state.withLock { $0.isEnabled = enabled }
    }

    /// 设置最小输出等级。低于该等级的日志会被丢弃。
    public static func setMinimumLevel(_ level: ExploreLogLevel) {
        state.withLock { $0.minimumLevel = level }
    }

    /// 派发一条日志到 sink。
    ///
    /// 在锁内只做等级过滤并取出 sink，真正写日志（`os_log`）放到锁外，避免临界区阻塞。
    /// 该方法是库内唯一落盘入口：`ExploreLogger` 与扩展入口 `emitExtension` 都汇聚于此，
    /// 保证开关、最小等级过滤和 sink 替换对所有日志来源统一生效。
    ///
    /// - Parameter record: 待派发的日志记录。
    static func emit(_ record: ExploreLogRecord) {
        let sink: (@Sendable (ExploreLogRecord) -> Void)? = state.withLock { state in
            guard state.isEnabled, record.level >= state.minimumLevel else { return nil }
            return state.sink
        }
        sink?(record)
    }

    /// 默认 sink：按 category 建 `OSLog`，调用 `os_log` 写入统一日志系统。
    private static func osLogSink(_ record: ExploreLogRecord) {
        let log = OSLog(subsystem: defaultSubsystem, category: record.category)
        os_log("%{public}@", log: log, type: record.level.osLogType, record.message)
    }

    /// 替换 sink，仅测试用：把日志接到可断言的回调上。
    static func setSinkForTesting(_ sink: @escaping @Sendable (ExploreLogRecord) -> Void) {
        state.withLock { $0.sink = sink }
    }

    /// 重置为默认状态，仅测试用，避免用例间相互污染。
    static func resetForTesting() {
        state.withLock {
            $0.isEnabled = false
            $0.minimumLevel = .debug
            $0.sink = osLogSink
        }
    }
}

/// 日志 category 枚举，对应库内各模块，用作 `OSLog` category 与排障过滤维度。
enum ExploreLogCategory: String, Sendable {
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
/// 包装 `ExploreLogging.emit`，按 category 自动归类，`message` 用 `@autoclosure`
/// 避免关闭日志时仍拼接字符串。
enum ExploreLogger {
    /// 记录一条 debug 日志。
    static func debug(_ category: ExploreLogCategory, _ message: @autoclosure () -> String) {
        log(.debug, category, message())
    }

    /// 记录一条 info 日志。
    static func info(_ category: ExploreLogCategory, _ message: @autoclosure () -> String) {
        log(.info, category, message())
    }

    /// 记录一条 error 日志。
    static func error(_ category: ExploreLogCategory, _ message: @autoclosure () -> String) {
        log(.error, category, message())
    }

    /// 记录一条 fault 日志（最严重，通常不可恢复）。
    static func fault(_ category: ExploreLogCategory, _ message: @autoclosure () -> String) {
        log(.fault, category, message())
    }

    /// 统一的落盘入口：组装 record 并交给 `ExploreLogging.emit`。
    private static func log(_ level: ExploreLogLevel,
                            _ category: ExploreLogCategory,
                            _ message: String) {
        ExploreLogging.emit(ExploreLogRecord(level: level,
                                             category: category.rawValue,
                                             message: message))
    }
}
