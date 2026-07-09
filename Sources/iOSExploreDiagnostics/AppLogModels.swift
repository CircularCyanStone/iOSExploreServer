import Foundation

/// 进程日志来源。
///
/// 每个来源代表 iOSExplore 已实际捕获并写入内存 store 的一条路径；不表示系统里所有
/// 同名日志都能被读取。
public enum AppLogSource: String, Sendable, Codable, Equatable, CaseIterable {
    /// iOSExplore core / 扩展模块通过 `ExploreLogging` 产生的日志。
    case explore
    /// 宿主 App 主动通过 `ExploreAppLog` 写入的业务日志。
    case bridge
    /// 进程 stdout fd 捕获到的逐行文本。
    case stdout
    /// 进程 stderr fd 捕获到的逐行文本。
    case stderr
    /// `NSLog` 输出识别后的捕获来源。
    case nslog
    /// Apple Unified Logging 捕获来源，覆盖可读取到的 `os_log` 与 Swift `Logger` entry。
    case oslog
}

/// 进程日志等级。
///
/// `.unknown` 表示无法可靠推断等级的来源，用于 OSLog 未定义等级 entry（如
/// `OSLogEntryLog.Type.undefined` 与 `@unknown default`），或后续未识别的纯文本来源。
/// 当前 stdout 固定为 `.info`，stderr 固定为 `.error`。
public enum AppLogLevel: String, Sendable, Codable, Equatable, Comparable, CaseIterable {
    case debug
    case info
    case error
    case fault
    case unknown

    private var order: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .error: return 2
        case .fault: return 3
        case .unknown: return -1
        }
    }

    public static func < (lhs: AppLogLevel, rhs: AppLogLevel) -> Bool {
        lhs.order < rhs.order
    }
}

/// 日志增量读取 cursor。
///
/// `captureSessionID` 标识当前进程级 Diagnostics Runtime；`id` 是该 session 内单调递增的
/// 物理日志序号。两者一起使用，避免把 App 重启前后的日志误拼成连续序列。
public struct AppLogCursor: Sendable, Codable, Equatable {
    /// 当前日志捕获 session 标识。
    public let captureSessionID: String
    /// 同一 session 内单调递增的物理日志序号。
    public let id: UInt64

    /// 创建日志 cursor。
    ///
    /// - Parameters:
    ///   - captureSessionID: 当前日志捕获 session 标识。
    ///   - id: 同一 session 内的物理日志序号。
    public init(captureSessionID: String, id: UInt64) {
        self.captureSessionID = captureSessionID
        self.id = id
    }
}

/// 一条已进入 Diagnostics store 的日志。
///
/// entry 写入前已经完成脱敏和截断；store 不保留未脱敏原文。
public struct AppLogEntry: Sendable, Codable, Equatable {
    /// store 分配的物理日志序号。
    public let id: UInt64
    /// entry 写入 store 的时间。
    public let timestamp: Date
    /// 日志来源。
    public let source: AppLogSource
    /// 日志等级。
    public let level: AppLogLevel
    /// 来源内分类，如 `router`、`command`、`auth`。
    public let category: String?
    /// 已脱敏、可能已截断的日志正文。
    public let message: String
    /// `message` 是否因单条大小上限被截断。
    public let messageTruncated: Bool
    /// 已脱敏的轻量结构化上下文，仅允许 string:string。
    public let metadata: [String: String]?
}

/// 日志读取中的缺口说明。
///
/// 当前只建模 ring buffer 覆盖：调用方请求的 cursor 太旧，部分日志已经被有界 store 驱逐。
public enum AppLogGap: Sendable, Equatable {
    /// 请求 cursor 之后、当前最旧 entry 之前的日志已被覆盖。
    case bufferOverrun(requestedAfterID: UInt64, oldestAvailableID: UInt64, lostRange: ClosedRange<UInt64>)
}

/// `app.logs.mark` 的 store 快照。
public struct AppLogMarkSnapshot: Sendable, Equatable {
    /// 此刻最新 cursor。
    public let cursor: AppLogCursor
    /// 当前 store 仍保留的最旧物理 id。
    public let oldestAvailableID: UInt64?
    /// 当前 store 已分配的最大物理 id。
    public let latestAvailableID: UInt64
}

/// `app.logs.read` 的 store 读取结果。
public struct AppLogReadResult: Sendable, Equatable {
    /// 命中筛选条件并返回给调用方的日志。
    public let entries: [AppLogEntry]
    /// 下一次读取应传入的 cursor；它指向最后扫描到的物理 id，不一定是最后返回 entry 的 id。
    public let nextCursor: AppLogCursor
    /// 本次读取固定的最新物理 id 快照。
    public let capturedThrough: AppLogCursor
    /// 是否还有未扫描的日志可继续分页读取。
    public let hasMore: Bool
    /// 如果请求 cursor 太旧，这里说明被覆盖的 id 范围。
    public let gap: AppLogGap?
    /// 当前 store 仍保留的最旧物理 id。
    public let oldestAvailableID: UInt64?
    /// cursor session 不匹配时，返回当前 session id；正常读取时为 nil。
    public let staleCursorCurrentSessionID: String?
}
