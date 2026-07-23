import Foundation
import iOSExploreServer

/// Diagnostics 命令错误工厂。
///
/// Diagnostics 是 core 之外的扩展模块，不能直接使用 core internal 的 `ExploreServerError`。
/// 本类型集中保存 `app.logs.*` 的业务错误码、对外 message 和日志语义，避免命令实现里散写
/// envelope 文案。
struct ESDiagnosticsCommandError: Error, Sendable, Equatable {
    /// 可转换为 `ExploreResult` 的失败描述。
    let failure: ExploreCommandFailure

    /// 直接转换为命令失败结果。
    var result: ExploreResult { failure.result }

    /// Diagnostics Runtime 尚未安装。
    ///
    /// - Returns: `internal_error`，表示宿主未按预期调用 `registerDiagnosticsCommands()` 或
    ///   runtime 状态被测试重置。
    static func runtimeNotInstalled(action: String) -> ESDiagnosticsCommandError {
        ESDiagnosticsCommandError(failure: ExploreCommandFailure(
            code: .internalError,
            message: "Diagnostics Runtime is not installed",
            logMessage: "diagnostics runtime missing action=\(action)"))
    }

    /// 调用方传入的 cursor 属于旧 capture session。
    ///
    /// - Returns: `stale_cursor`，调用方应重新调用 `app.logs.mark` 建立新起点。
    static func staleCursor(action: String, currentSessionID: String?) -> ESDiagnosticsCommandError {
        ESDiagnosticsCommandError(failure: ExploreCommandFailure(
            code: .staleCursor,
            message: "The log capture session changed; call app.logs.mark to begin a new stream.",
            logMessage: "diagnostics stale cursor action=\(action) currentSessionID=\(currentSessionID ?? "unknown")"))
    }
}
