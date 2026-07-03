import Foundation
import iOSExploreServer

/// UIKit 扩展命令失败的统一描述。
///
/// 包装 core 的 `ExploreCommandFailure`，集中 UIKit 命令的错误码、对外 message 和内部
/// logMessage 三段。所有 UIKit handler 失败出口都应通过本类型的工厂构造，避免在调用点
/// 散写 `code`/`message`/`logMessage`，也避免依赖 core 的 `ExploreServerError`
/// （该类型对扩展模块不可见）。
///
/// 错误码语义集中在这里：schema/能力类失败用 `.invalidData`，目标缺失用 `.targetNotFound`，
/// UIKit 上下文不可用用 `.internalError`。
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

    /// locator 陈旧（viewSnapshot 已过期、目标未被签发，或指纹 / 语义变化），需重新观察后重试。
    ///
    /// 提示调用方重新调用 `ui.viewTargets` 拿到新 `viewSnapshotID` 再下发交互。viewSnapshotID
    /// 只由 `ui.viewTargets` 签发（不再来自 `ui.screenshot`）。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名，用于日志关联。
    ///   - viewSnapshotID: 过期的 viewSnapshot 标识摘要。
    /// - Returns: `stale_locator` 失败描述。
    static func staleLocator(action: String, viewSnapshotID: String) -> UIKitCommandError {
        UIKitCommandError(code: .staleLocator,
                          message: "view snapshot expired or target changed; call ui.viewTargets first, then retry with the new viewSnapshotID",
                          logMessage: "uikit locator stale action=\(action) viewSnapshot=\(viewSnapshotID)")
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
    /// - Returns: `target_not_found` 失败描述。
    static func targetNotFound(action: String, targetDescription: String) -> UIKitCommandError {
        UIKitCommandError(code: .targetNotFound,
                          message: "tap target not found",
                          logMessage: "ui tap target not found action=\(action) target=\(targetDescription)")
    }

    /// 目标在当前 UI 树或滚动搜索后仍未找到。
    ///
    /// 供新增命令复用自定义 message/logMessage，同时保持目标缺失统一映射到 `target_not_found`。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - message: 对外失败说明，进入 envelope。
    ///   - logMessage: 仅用于日志的内部说明，不进 envelope。
    /// - Returns: `target_not_found` 失败描述。
    static func targetNotFound(action: String, message: String, logMessage: String) -> UIKitCommandError {
        UIKitCommandError(code: .targetNotFound,
                          message: message,
                          logMessage: logMessage)
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
    /// - Returns: `target_not_found` 失败描述。
    static func controlTargetNotFound(action: String, targetDescription: String) -> UIKitCommandError {
        UIKitCommandError(code: .targetNotFound,
                          message: "UIControl target not found",
                          logMessage: "ui control target not found action=\(action) target=\(targetDescription)")
    }

    /// `ui.wait` 的业务等待条件在输入 deadline 内未满足。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - mode: 等待模式摘要。
    ///   - elapsedMs: 已等待毫秒数。
    /// - Returns: `wait_timeout` 失败描述。
    static func waitTimeout(action: String, mode: String, elapsedMs: Int) -> UIKitCommandError {
        UIKitCommandError(code: .waitTimeout,
                          message: "wait timed out mode=\(mode) elapsedMs=\(elapsedMs)",
                          logMessage: "ui wait timeout action=\(action) mode=\(mode) elapsedMs=\(elapsedMs)")
    }

    /// 当前页面没有可返回的导航路径。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - top: 当前顶部控制器类型摘要。
    /// - Returns: `navigation_back_unavailable` 失败描述。
    static func navigationBackUnavailable(action: String, top: String) -> UIKitCommandError {
        UIKitCommandError(code: .navigationBackUnavailable,
                          message: "navigation back unavailable",
                          logMessage: "ui navigation back unavailable action=\(action) top=\(top)")
    }

    /// 当前顶部控制器不在导航控制器中，无法读取或触发导航栏按钮。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - top: 当前顶部控制器类型摘要。
    /// - Returns: `navigation_bar_unavailable` 失败描述。
    static func navigationBarUnavailable(action: String, top: String) -> UIKitCommandError {
        UIKitCommandError(code: .navigationBarUnavailable,
                          message: "navigation bar unavailable",
                          logMessage: "ui navigation bar unavailable action=\(action) top=\(top)")
    }

    /// 指定侧和下标没有对应导航栏按钮。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - selector: 调用方选择器摘要。
    /// - Returns: `navigation_bar_item_not_found` 失败描述。
    static func navigationBarItemNotFound(action: String, selector: String) -> UIKitCommandError {
        UIKitCommandError(code: .navigationBarItemNotFound,
                          message: "navigation bar item not found",
                          logMessage: "ui navigation bar item not found action=\(action) selector=\(selector)")
    }

    /// 导航栏按钮存在，但标题或 identifier 与调用方观察时不一致。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - selector: 调用方选择器摘要。
    /// - Returns: `navigation_bar_item_mismatch` 失败描述。
    static func navigationBarItemMismatch(action: String, selector: String) -> UIKitCommandError {
        UIKitCommandError(code: .navigationBarItemMismatch,
                          message: "navigation bar item changed since observation",
                          logMessage: "ui navigation bar item mismatch action=\(action) selector=\(selector)")
    }

    /// 导航栏按钮存在，但当前 disabled。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - selector: 调用方选择器摘要。
    /// - Returns: `navigation_bar_item_disabled` 失败描述。
    static func navigationBarItemDisabled(action: String, selector: String) -> UIKitCommandError {
        UIKitCommandError(code: .navigationBarItemDisabled,
                          message: "navigation bar item disabled",
                          logMessage: "ui navigation bar item disabled action=\(action) selector=\(selector)")
    }

    /// 导航栏按钮存在，但没有 target-action 或可触发的 UIControl customView。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - selector: 调用方选择器摘要。
    /// - Returns: `navigation_bar_item_unsupported` 失败描述。
    static func navigationBarItemUnsupported(action: String, selector: String) -> UIKitCommandError {
        UIKitCommandError(code: .navigationBarItemUnsupported,
                          message: "navigation bar item has no supported action",
                          logMessage: "ui navigation bar item unsupported action=\(action) selector=\(selector)")
    }

    /// 当前没有可处理的 `UIAlertController`。
    ///
    /// - Parameter action: 触发失败的 action 名。
    /// - Returns: `alert_unavailable` 失败描述。
    static func alertUnavailable(action: String) -> UIKitCommandError {
        UIKitCommandError(code: .alertUnavailable,
                          message: "alert unavailable",
                          logMessage: "ui alert unavailable action=\(action)")
    }

    /// 指定的 alert 按钮不存在。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - selector: 调用方提供的按钮选择条件摘要。
    /// - Returns: `alert_button_not_found` 失败描述。
    static func alertButtonNotFound(action: String, selector: String) -> UIKitCommandError {
        UIKitCommandError(code: .alertButtonNotFound,
                          message: "alert button not found",
                          logMessage: "ui alert button not found action=\(action) selector=\(selector)")
    }

    /// 当前 alert 不能安全默认选择按钮，需要调用方明确指定。
    ///
    /// 同时是「点击未实现」的统一出口：当前版本 `ui.alert.respond` 仅查询，`dryRun=false` 一律命中
    /// 此错误。message 明确告知 agent 本命令不能关闭 alert，需宿主注册自定义 handler 或等待后续版本。
    ///
    /// - Parameter action: 触发失败的 action 名。
    /// - Returns: `alert_button_required` 失败描述。
    static func alertButtonRequired(action: String) -> UIKitCommandError {
        UIKitCommandError(code: .alertButtonRequired,
                          message: "ui.alert.respond is query-only in this version; it cannot dismiss the alert. Use dryRun=true to list buttons/textFields, then close the alert via a host-registered handler or a later version",
                          logMessage: "ui alert button required action=\(action)")
    }

    /// 键盘或 first responder 收起失败。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - strategy: 使用的收起策略。
    /// - Returns: `keyboard_dismiss_failed` 失败描述。
    static func keyboardDismissFailed(action: String, strategy: String) -> UIKitCommandError {
        UIKitCommandError(code: .keyboardDismissFailed,
                          message: "keyboard dismiss failed",
                          logMessage: "ui keyboard dismiss failed action=\(action) strategy=\(strategy)")
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

    /// `ui.scroll` 在目标（或其祖先链）及 keyWindow 最前 view 中都找不到可滚动容器。
    ///
    /// 仅 `UIScrollView` 系（含 `UICollectionView`/`UITableView`/`UITextView`）可滚动，
    /// 但 `UITextView` 是 `UIScrollView` 子类且其内部长文滚动语义不同——executor 显式排除
    /// 它，命中本错误。当定位字段缺省且回退扫描 keyWindow 也无 scrollView 时同样命中。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名，用于日志关联。
    ///   - target: 目标定位摘要（identifier/path 或 "keyWindow"），不含大块 payload。
    /// - Returns: `scroll_container_unavailable` 失败描述。
    static func scrollContainerUnavailable(action: String, target: String) -> UIKitCommandError {
        UIKitCommandError(code: .scrollContainerUnavailable,
                          message: "no UIScrollView ancestor (UITextView excluded)",
                          logMessage: "ui scroll container unavailable action=\(action) target=\(target)")
    }

    /// 截图渲染失败（`drawHierarchy` 返回 false、cgImage 丢失、PNG 编码失败等）。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名，用于日志关联。
    ///   - reason: 渲染失败的具体原因摘要（如 "drawHierarchy returned false"），不含图像内容。
    /// - Returns: `rendering_failed` 失败描述。
    static func renderingFailed(action: String, reason: String) -> UIKitCommandError {
        UIKitCommandError(code: .renderingFailed,
                          message: "screenshot rendering failed: \(reason)",
                          logMessage: "ui screenshot rendering failed action=\(action) reason=\(reason)")
    }

    /// 截图时顶部控制器正处于过渡态（push/present/modal 动画中），当前帧不可靠。
    ///
    /// - Parameter action: 触发失败的 action 名。
    /// - Returns: `transition_in_progress` 失败描述，提示调用方稍后重试。
    static func transitionInProgress(action: String) -> UIKitCommandError {
        UIKitCommandError(code: .transitionInProgress,
                          message: "view controller transition in progress; retry",
                          logMessage: "ui screenshot transition in progress action=\(action)")
    }

    /// `ui.input` 的目标不是受支持的文本输入控件。
    ///
    /// 仅 `UITextField` / `UITextView` / `UISearchTextField` 三类走 `UITextInput.insertText`
    /// 注入路径；其它类型（如 `UILabel`）命中本错误。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名，用于日志关联。
    ///   - type: 实际命中的 view 运行时类型名（`String(describing: type(of:))`），便于排障。
    /// - Returns: `unsupported_text_input_type` 失败描述。
    static func unsupportedTextInputType(action: String, type: String) -> UIKitCommandError {
        UIKitCommandError(code: .unsupportedTextInputType,
                          message: "target is not a supported text input",
                          logMessage: "ui input unsupported type action=\(action) type=\(type)")
    }

    /// `ui.input` 让目标成为 first responder 失败，无法进入编辑/焦点状态。
    ///
    /// `becomeFirstResponder()` 返回 false，或调用后 `isFirstResponder` / `selectedTextRange`
    /// 仍不可用时命中本错误。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - target: 目标定位摘要（identifier/path），不含大块 payload。
    /// - Returns: `become_first_responder_failed` 失败描述。
    static func becomeFirstResponderFailed(action: String, target: String) -> UIKitCommandError {
        UIKitCommandError(code: .becomeFirstResponderFailed,
                          message: "failed to become first responder",
                          logMessage: "ui input becomeFirstResponder failed action=\(action) target=\(target)")
    }

    /// `ui.input` 注入的文本被委托拒绝或被输入代理改写。
    ///
    /// 通过比对注入后期望文本与实际 `text` 不一致判定：replace 模式期望等于 `input.text`，
    /// append 模式期望等于 `旧文本 + input.text`。差异通常源于 `textField(_:shouldChangeCharactersIn:)`
    /// 返回 false、输入过滤（如数字键盘删掉非数字字符）、或 formatter 改写。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - expectedLen: 期望文本长度。
    ///   - finalLen: 实际文本长度。
    ///   - secure: 目标是否为密码输入（`isSecureTextEntry`），决定是否对响应脱敏。
    /// - Returns: `input_rejected` 失败描述；**日志与 message 都不回原文**，只回长度与 secure 标记。
    static func inputRejected(action: String, expectedLen: Int, finalLen: Int, secure: Bool) -> UIKitCommandError {
        UIKitCommandError(code: .inputRejected,
                          message: "text input was rejected or altered by delegate",
                          logMessage: "ui input rejected action=\(action) expectedLen=\(expectedLen) finalLen=\(finalLen) secure=\(secure)")
    }
}
