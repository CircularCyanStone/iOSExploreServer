import Foundation

/// 日志读取中的缺口说明。
///
/// 当前只建模 ring buffer 覆盖：调用方请求的 cursor 太旧，部分日志已经被有界 store 驱逐。
enum ESAppLogGap: Sendable, Equatable {
    /// 请求 cursor 之后、当前最旧 entry 之前的日志已被覆盖。
    case bufferOverrun(requestedAfterID: UInt64, oldestAvailableID: UInt64, lostRange: ClosedRange<UInt64>)
}
