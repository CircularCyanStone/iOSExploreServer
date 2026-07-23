import Foundation

/// 进程日志等级。
///
/// `.unknown` 表示无法可靠推断等级的来源，用于 OSLog 未定义等级 entry（如
/// `OSLogEntryLog.Type.undefined` 与 `@unknown default`），或后续未识别的纯文本来源。
/// 当前 stdout 固定为 `.info`，stderr 固定为 `.error`。
public enum ESAppLogLevel: String, Sendable, Codable, Equatable, Comparable, CaseIterable {
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

    public static func < (lhs: ESAppLogLevel, rhs: ESAppLogLevel) -> Bool {
        lhs.order < rhs.order
    }
}
