import Foundation

/// 进程日志来源。
///
/// 每个来源代表 iOSExplore 已实际捕获并写入内存 store 的一条路径；不表示系统里所有
/// 同名日志都能被读取。
enum ESAppLogSource: String, Sendable, Codable, Equatable, CaseIterable {
    /// iOSExplore core / 扩展模块通过 `ESLogger` 产生的日志。
    case explore
    /// 宿主 App 主动通过 `ESAppLogger` 写入的业务日志。
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
