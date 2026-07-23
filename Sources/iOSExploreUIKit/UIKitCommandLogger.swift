import Foundation
import iOSExploreServer

/// UIKit 扩展命令的日志入口。
///
/// UIKit 命令通过本入口调用 core 的 public `ESLogger.emitExtension`，复用既有 sink、
/// 等级过滤与开关；core 的 `ESLogCategory` 仍保持 internal，扩展模块只传稳定的字符串分类。
///
/// category 默认使用 `"command"`，与 core 命令分发日志对齐，便于排障时按模块过滤；
/// 例外是 `UIKitCommandRegistrar` 使用 `"uikit.registrar"` 标记一次性注册事件。
enum UIKitCommandLogger {
    /// 记录一条 info 级别日志。
    ///
    /// - Parameters:
    ///   - category: 日志分类字符串（UIKit 模块统一传 `"command"`）。
    ///   - message: 日志正文，应为大小/摘要/错误码等非敏感信息，不要写完整 payload。
    static func info(_ category: String, _ message: String) {
        ESLogger.emitExtension(level: .info, category: category, message: message)
    }

    /// 记录一条 error 级别日志。
    ///
    /// - Parameters:
    ///   - category: 日志分类字符串（UIKit 模块统一传 `"command"`）。
    ///   - message: 日志正文，应为大小/摘要/错误码等非敏感信息，不要写完整 payload。
    static func error(_ category: String, _ message: String) {
        ESLogger.emitExtension(level: .error, category: category, message: message)
    }
}
