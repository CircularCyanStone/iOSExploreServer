import Foundation

/// UIKit 底层定位文法解析失败的统一错误。
///
/// 命令输入主路径已经迁移到 core 的 `CommandInputParseError`。本类型只保留给
/// `UIKitViewLookupTarget`、`UIKitLocator` 这类底层 Foundation-only 文法解析 helper，
/// 调用方在命令 input 层应把它转换为 `CommandInputParseError`，避免旧 query parser
/// 继续成为命令入口。
///
/// 该类型保持 Foundation-only、`Sendable`，不携带 UIKit 类型，可在 macOS
/// `swift test` 中覆盖解析失败的断言。
public struct QueryParseError: Error, Sendable, Equatable {
    /// 可转换为 `invalid_data` envelope 的失败说明。
    public let message: String

    /// 创建一条定位文法解析错误。
    ///
    /// - Parameter message: 失败说明文案，由调用方转换成命令输入解析错误。
    public init(_ message: String) { self.message = message }
}
