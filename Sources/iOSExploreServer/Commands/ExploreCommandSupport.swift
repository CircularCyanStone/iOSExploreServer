import Foundation

/// 扩展模块（如未来拆分出去的 `iOSExploreUIKit`）产生命令失败时的统一描述。
///
/// core 库本身不依赖 UIKit，但需要给上层 UIKit 扩展暴露一个最小的失败构造缝：扩展
/// handler 失败时不应在调用点散写错误码、消息和日志，而应集中由本结构表达。本结构只
/// 持有错误码、对外消息和内部日志消息三段，分别对应 envelope 顶层 `code/message`
/// 与排障日志。
///
/// 该类型为 `Sendable` 值类型，可安全跨并发边界传递；`Equatable` 便于测试精确断言。
public struct ExploreCommandFailure: Sendable, Equatable {
    /// 业务失败码，序列化进响应 envelope 的顶层 `code`。
    public let code: ExploreError

    /// 对外暴露的失败说明，序列化进响应 envelope 的顶层 `message`。
    public let message: String

    /// 仅用于日志的详细说明，不会进入响应 envelope。
    ///
    /// 扩展 handler 的内部排障信息（定位失败的元素、截图尺寸、手势坐标摘要等）写在这里，
    /// 由调用方决定是否调用 `ESLogger.emitExtension` 输出。
    public let logMessage: String

    /// 可选的结构化 data，随 envelope 顶层 `data` 返回。
    ///
    /// 用于业务失败需要给调用方返回额外结构化字段时（如超时时的 `elapsedMs`/`attempts`），
    /// 默认为 `nil`（envelope 无 `data` 字段）。
    public let data: JSON?

    /// 创建一条扩展命令失败描述。
    ///
    /// - Parameters:
    ///   - code: 业务失败码，对应 envelope 顶层 `code`。
    ///   - message: 对外失败说明，对应 envelope 顶层 `message`。
    ///   - logMessage: 仅用于日志的内部说明，不进响应。
    ///   - data: 可选的结构化 data，随 envelope 顶层 `data` 返回。
    public init(code: ExploreError, message: String, logMessage: String, data: JSON? = nil) {
        self.code = code
        self.message = message
        self.logMessage = logMessage
        self.data = data
    }

    /// 转换为命令失败结果，由扩展 handler `return failure.result` 收敛进响应 envelope。
    ///
    /// 该类型不实现 `Error`，handler 不能 `throw` 它；只能通过 `return` 把扩展失败转为
    /// `ExploreResult.failure`，由 `AnyCommand` 走业务失败 envelope 路径输出。
    public var result: ExploreResult {
        if let data {
            return .failure(code: code, message: message, data: data)
        } else {
            return .failure(code: code, message: message)
        }
    }
}

/// 为扩展模块（UIKit 等）提供的日志入口。
///
/// core 内部统一走 `ESLogger` + `ESLogCategory`，但这两个类型刻意保持
/// `internal`，不向扩展暴露库内部分类枚举。扩展模块用本扩展的 `emitExtension` 指定
/// 自有 category 字符串（如 `"uikit.action"`），记录会进入同一套 sink 与等级过滤，
/// 保证日志口径一致、便于排障。
public extension ESLogger {
    /// 派发一条扩展模块日志到既有 sink。
    ///
    /// 内部直接调用 `ESLogger.emit(_:)`，复用其开关、最小等级过滤和 sink 配置，
    /// 不引入新的输出通道。
    ///
    /// - Parameters:
    ///   - level: 日志等级。
    ///   - category: 扩展模块自定义分类字符串，建议以模块名为前缀（如 `"uikit.action"`）。
    ///   - message: 日志正文，应为大小/摘要/错误码等非敏感信息，不要写完整 payload。
    static func emitExtension(level: ESLogLevel, category: String, message: String) {
        emit(ESLogRecord(level: level, category: category, message: message))
    }
}
