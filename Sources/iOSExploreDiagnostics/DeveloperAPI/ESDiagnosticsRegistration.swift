import Foundation

/// Diagnostics 注册结果。
///
/// 该值让宿主能知道日志能力是否实际启用，以及当前 capture session 是哪一个。
public struct ESDiagnosticsRegistration: Sendable, Equatable {
    /// 是否启用 Diagnostics Runtime。
    public let enabled: Bool
    /// 当前 capture session id；未启用时为 nil。
    public let captureSessionID: String?
    /// 未启用或降级原因。
    public let reason: String?

    /// 创建启用结果。
    ///
    /// - Parameter captureSessionID: 当前 capture session id。
    public static func enabled(captureSessionID: String) -> ESDiagnosticsRegistration {
        ESDiagnosticsRegistration(enabled: true, captureSessionID: captureSessionID, reason: nil)
    }

    /// 创建禁用结果。
    ///
    /// - Parameter reason: 禁用原因。
    public static func disabled(reason: String) -> ESDiagnosticsRegistration {
        ESDiagnosticsRegistration(enabled: false, captureSessionID: nil, reason: reason)
    }
}
