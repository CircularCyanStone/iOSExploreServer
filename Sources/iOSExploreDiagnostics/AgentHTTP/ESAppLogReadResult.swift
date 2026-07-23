import Foundation

/// `app.logs.read` 的 store 读取结果。
struct ESAppLogReadResult: Sendable, Equatable {
    /// 命中筛选条件并返回给调用方的日志。
    let entries: [ESAppLogEntry]
    /// 下一次读取应传入的 cursor；它指向最后扫描到的物理 id，不一定是最后返回 entry 的 id。
    let nextCursor: ESAppLogCursor
    /// 本次读取固定的最新物理 id 快照。
    let capturedThrough: ESAppLogCursor
    /// 是否还有未扫描的日志可继续分页读取。
    let hasMore: Bool
    /// 如果请求 cursor 太旧，这里说明被覆盖的 id 范围。
    let gap: ESAppLogGap?
    /// 当前 store 仍保留的最旧物理 id。
    let oldestAvailableID: UInt64?
    /// cursor session 不匹配时，返回当前 session id；正常读取时为 nil。
    let staleCursorCurrentSessionID: String?
}
