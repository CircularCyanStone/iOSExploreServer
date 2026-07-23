import Foundation

/// 日志增量读取 cursor。
///
/// `captureSessionID` 标识当前进程级 Diagnostics Runtime；`id` 是该 session 内单调递增的
/// 物理日志序号。两者一起使用，避免把 App 重启前后的日志误拼成连续序列。
struct ESAppLogCursor: Sendable, Codable, Equatable {
    /// 当前日志捕获 session 标识。
    let captureSessionID: String
    /// 同一 session 内单调递增的物理日志序号。
    let id: UInt64

    /// 创建日志 cursor。
    ///
    /// - Parameters:
    ///   - captureSessionID: 当前日志捕获 session 标识。
    ///   - id: 同一 session 内的物理日志序号。
    init(captureSessionID: String, id: UInt64) {
        self.captureSessionID = captureSessionID
        self.id = id
    }
}
