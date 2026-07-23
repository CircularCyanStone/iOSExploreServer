import Foundation

/// 一条已进入 Diagnostics store 的日志。
///
/// entry 写入前已经完成脱敏和截断；store 不保留未脱敏原文。
struct ESAppLogEntry: Sendable, Codable, Equatable {
    /// store 分配的物理日志序号。
    let id: UInt64
    /// entry 写入 store 的时间。
    let timestamp: Date
    /// 日志来源。
    let source: ESAppLogSource
    /// 日志等级。
    let level: ESAppLogLevel
    /// 来源内分类，如 `router`、`command`、`auth`。
    let category: String?
    /// 已脱敏、可能已截断的日志正文。
    let message: String
    /// `message` 是否因单条大小上限被截断。
    let messageTruncated: Bool
    /// 已脱敏的轻量结构化上下文，仅允许 string:string。
    let metadata: [String: String]?
}
