import Foundation

/// UIKit 命令参数解析失败的统一错误。
///
/// `iOSExploreUIKit` 所有 typed query 的 `parse` 用普通 `throws` 抛出本类型，
/// 取代此前每个命令各自定义的 `success(T)/failure(String)` result 枚举。
/// 命令 handler 统一把本错误转成 `UIKitCommandError.invalidData`，错误文案
/// 直接进入 `invalid_data` envelope。
///
/// 该类型保持 Foundation-only、`Sendable`，不携带 UIKit 类型，可在 macOS
/// `swift test` 中覆盖解析失败的断言。
public struct QueryParseError: Error, Sendable, Equatable {
    /// 可直接对外返回的失败说明，进入 `invalid_data` envelope。
    public let message: String

    /// 创建一条参数解析错误。
    ///
    /// - Parameter message: 失败说明文案，会原样进入 envelope 的 `error.message`。
    public init(_ message: String) { self.message = message }
}
