import Foundation
import iOSExploreServer

/// UIKit 扩展命令的日志入口。
///
/// core 内部统一走 `ExploreLogger` + `ExploreLogCategory`，但两者刻意保持 `internal`，
/// 不向扩展模块暴露。UIKit 命令通过本入口调用 core 的 public 缝
/// `ExploreLogging.emitExtension`，复用既有 sink、等级过滤与开关，保证日志口径一致。
///
/// category 默认使用 `"command"`，与 core 命令分发日志对齐，便于排障时按模块过滤；
/// 例外是 `UIKitCommandRegistrar` 使用 `"uikit.registrar"` 标记一次性注册事件。
enum UIKitCommandLogging {
    /// 记录一条 info 级别日志。
    ///
    /// - Parameters:
    ///   - category: 日志分类字符串（UIKit 模块统一传 `"command"`）。
    ///   - message: 日志正文，应为大小/摘要/错误码等非敏感信息，不要写完整 payload。
    static func info(_ category: String, _ message: String) {
        ExploreLogging.emitExtension(level: .info, category: category, message: message)
    }

    /// 记录一条 error 级别日志。
    ///
    /// - Parameters:
    ///   - category: 日志分类字符串（UIKit 模块统一传 `"command"`）。
    ///   - message: 日志正文，应为大小/摘要/错误码等非敏感信息，不要写完整 payload。
    static func error(_ category: String, _ message: String) {
        ExploreLogging.emitExtension(level: .error, category: category, message: message)
    }
}
