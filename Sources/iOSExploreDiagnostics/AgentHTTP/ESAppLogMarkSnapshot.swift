import Foundation

/// `app.logs.mark` 的 store 快照。
struct ESAppLogMarkSnapshot: Sendable, Equatable {
    /// 此刻最新 cursor。
    let cursor: ESAppLogCursor
    /// 当前 store 仍保留的最旧物理 id。
    let oldestAvailableID: UInt64?
    /// 当前 store 已分配的最大物理 id。
    let latestAvailableID: UInt64
}
