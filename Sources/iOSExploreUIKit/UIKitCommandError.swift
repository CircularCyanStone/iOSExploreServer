import Foundation
import iOSExploreServer

/// UIKit 扩展命令失败的统一描述。
///
/// 包装 core 的 `ExploreCommandFailure`，集中 UIKit 命令的错误码、对外 message 和内部
/// logMessage 三段。所有 UIKit handler 失败出口都应通过本类型的工厂构造，避免在调用点
/// 散写 `code`/`message`/`logMessage`，也避免依赖 core 的 `ExploreServerError`
/// （该类型对扩展模块不可见）。
///
/// 错误码语义与既有行为保持一致：定位/命中类失败用 `.invalidData`，UIKit 上下文不可用
/// 用 `.internalError`。
struct UIKitCommandError: Error, Sendable, Equatable {
    /// 被包装的扩展失败描述。
    let failure: ExploreCommandFailure

    /// 转为命令结果，供 handler 直接返回。
    var result: ExploreResult { failure.result }

    /// 创建一条 UIKit 命令失败描述。
    ///
    /// - Parameters:
    ///   - code: 业务失败码。
    ///   - message: 对外失败说明，进入 envelope。
    ///   - logMessage: 仅用于日志的内部说明，不进 envelope。
    init(code: ExploreError, message: String, logMessage: String) {
        self.failure = ExploreCommandFailure(code: code, message: message, logMessage: logMessage)
    }

    /// locator 陈旧（snapshot 已过期），需重新查询后重试。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名，用于日志关联。
    ///   - snapshotID: 过期的 snapshot 标识摘要。
    /// - Returns: `invalid_data` 失败描述。
    static func staleLocator(action: String, snapshotID: String) -> UIKitCommandError {
        UIKitCommandError(code: .invalidData,
                          message: "locator is stale; re-query",
                          logMessage: "uikit locator stale action=\(action) snapshot=\(snapshotID)")
    }

    /// UIKit 层级采集所需的窗口、控制器或根 view 不可用。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - reason: 上下文不可用的具体原因（如 active window not found）。
    /// - Returns: `internal_error` 失败描述。
    static func hierarchyUnavailable(action: String, reason: String) -> UIKitCommandError {
        UIKitCommandError(code: .internalError,
                          message: "UI hierarchy unavailable: \(reason)",
                          logMessage: "ui hierarchy unavailable action=\(action) reason=\(reason)")
    }

    /// ui.tap 按 view 定位时目标未找到。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - targetDescription: 目标摘要（identifier/path），不含大块 payload。
    /// - Returns: `invalid_data` 失败描述。
    static func targetNotFound(action: String, targetDescription: String) -> UIKitCommandError {
        UIKitCommandError(code: .invalidData,
                          message: "tap target not found",
                          logMessage: "ui tap target not found action=\(action) target=\(targetDescription)")
    }

    /// ui.tap 目标匹配到多个 view，可能误触发。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - targetDescription: 目标摘要。
    ///   - count: 匹配到的 view 数量。
    /// - Returns: `invalid_data` 失败描述。
    static func targetAmbiguous(action: String, targetDescription: String, count: Int) -> UIKitCommandError {
        UIKitCommandError(code: .invalidData,
                          message: "tap target is ambiguous",
                          logMessage: "ui tap target ambiguous action=\(action) target=\(targetDescription) count=\(count)")
    }

    /// ui.tap 的目标点没有命中任何 view。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - targetDescription: 目标摘要。
    ///   - x: window 坐标 x。
    ///   - y: window 坐标 y。
    /// - Returns: `invalid_data` 失败描述。
    static func hitTestFailed(action: String, targetDescription: String, x: Double, y: Double) -> UIKitCommandError {
        UIKitCommandError(code: .invalidData,
                          message: "tap point did not hit any view",
                          logMessage: "ui tap hit test failed action=\(action) target=\(targetDescription) x=\(x) y=\(y)")
    }

    /// ui.tap 按 view 定位时，中心点被其他 view 命中。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - targetDescription: 目标摘要。
    ///   - hitType: 实际命中 view 的类型名。
    /// - Returns: `invalid_data` 失败描述。
    static func hitMismatch(action: String, targetDescription: String, hitType: String) -> UIKitCommandError {
        UIKitCommandError(code: .invalidData,
                          message: "tap point hit a different view",
                          logMessage: "ui tap hit mismatch action=\(action) target=\(targetDescription) hitType=\(hitType)")
    }

    /// ui.tap 找到了 view，但第一版无法派发非 UIControl 的真实 tap。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - targetDescription: 目标摘要。
    ///   - type: 目标 view 的类型名。
    /// - Returns: `invalid_data` 失败描述。
    static func unsupportedTarget(action: String, targetDescription: String, type: String) -> UIKitCommandError {
        UIKitCommandError(code: .invalidData,
                          message: "tap dispatch is only supported for UIControl in this version",
                          logMessage: "ui tap unsupported target action=\(action) target=\(targetDescription) type=\(type)")
    }

    /// 已定位的控件不支持请求动作，或控件当前不可用。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - targetDescription: 目标路径或定位摘要。
    ///   - requestedAction: 调用方请求的动作或事件名。
    /// - Returns: `invalid_data` 失败描述，避免在能力表为空时仍派发事件。
    static func unsupportedAction(action: String,
                                  targetDescription: String,
                                  requestedAction: String) -> UIKitCommandError {
        UIKitCommandError(code: .invalidData,
                          message: "requested action is not supported for target",
                          logMessage: "ui action unsupported action=\(action) target=\(targetDescription) requestedAction=\(requestedAction)")
    }

    /// UIControl sendAction 目标没有找到。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - targetDescription: 目标摘要。
    /// - Returns: `invalid_data` 失败描述。
    static func controlTargetNotFound(action: String, targetDescription: String) -> UIKitCommandError {
        UIKitCommandError(code: .invalidData,
                          message: "UIControl target not found",
                          logMessage: "ui control target not found action=\(action) target=\(targetDescription)")
    }

    /// UIControl sendAction 目标匹配到多个视图，可能误触发。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - targetDescription: 目标摘要。
    ///   - count: 匹配到的 view 数量。
    /// - Returns: `invalid_data` 失败描述。
    static func controlTargetAmbiguous(action: String, targetDescription: String, count: Int) -> UIKitCommandError {
        UIKitCommandError(code: .invalidData,
                          message: "UIControl target is ambiguous",
                          logMessage: "ui control target ambiguous action=\(action) target=\(targetDescription) count=\(count)")
    }

    /// UIControl sendAction 目标存在但不是 UIControl。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - targetDescription: 目标摘要。
    ///   - type: 目标 view 的类型名。
    /// - Returns: `invalid_data` 失败描述。
    static func controlTargetNotControl(action: String, targetDescription: String, type: String) -> UIKitCommandError {
        UIKitCommandError(code: .invalidData,
                          message: "target view is not UIControl",
                          logMessage: "ui control target not control action=\(action) target=\(targetDescription) type=\(type)")
    }

    /// 命令参数校验失败（必填缺失 / 类型不符），与 core `invalidData` 对齐。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - message: 对外失败说明。
    /// - Returns: `invalid_data` 失败描述。
    static func invalidData(action: String, message: String) -> UIKitCommandError {
        UIKitCommandError(code: .invalidData,
                          message: message,
                          logMessage: "invalid data action=\(action) message=\(message)")
    }
}
