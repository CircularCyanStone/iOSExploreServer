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
    ///   - data: 可选的结构化 data，随 envelope 顶层 `data` 返回。
    init(code: ExploreError, message: String, logMessage: String, data: JSON? = nil) {
        self.failure = ExploreCommandFailure(code: code, message: message, logMessage: logMessage, data: data)
    }

    /// locator 陈旧（viewSnapshot 已过期、目标未被签发，或指纹 / 语义变化），需重新观察后重试。
    ///
    /// 提示调用方重新调用 `ui.inspect` 拿到新 `viewSnapshotID` 再下发交互。viewSnapshotID
    /// 只由 `ui.inspect` 签发（不再来自 `ui.screenshot`）。
    ///
    /// message 额外提醒：snapshot 指纹不含 UILabel/UITextField/UITextView 的展示文本，
    /// 异步文本变化（如 "加载中"→"已完成"）不会触发 stale。若 agent 的决策依赖当前展示文本，
    /// 应主动重新 inspect 而非依赖 stale 校验拦截。见 F-24。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名，用于日志关联。
    ///   - viewSnapshotID: 过期的 viewSnapshot 标识摘要。
    /// - Returns: `stale_locator` 失败描述。
    static func staleLocator(action: String, viewSnapshotID: String) -> UIKitCommandError {
        UIKitCommandError(code: .staleLocator,
                          message: "view snapshot expired (TTL \(Int(UIKitSnapshotStore.ttlSeconds))s) or target changed; call ui.inspect first, then retry with the new viewSnapshotID. Note: snapshots do not track label/text content changes — if your decision depends on displayed text, re-inspect before acting",
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
                          message: "tap target not found — the page view tree may have changed; call ui.inspect first, then retry with a fresh target",
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

    /// 目标没有可触发的路由：`ui.tap` 找到了 view 但默认激活路由与 adapter 均不可达，
    /// 或 `ui.swipe`/`ui.longPress` 在目标上未找到匹配的手势识别器。
    ///
    /// 这是一个被多个命令复用的失败出口，对外 message 通过 `message` 参数按命令定制：
    /// - **ui.tap**（默认值）：说明默认激活仅覆盖 UIButton / UISwitch / 文本输入，cell selection /
    ///   手势 adapter 均未命中。典型如 UISlider / UISegmentedControl / 普通 UIView / 无 gesture 的
    ///   纯装饰 view / Release 构建下 ivar 不可读。区别于 `unsupportedAction`（控件存在但请求的事件
    ///   不支持）：这里是目标类型本身无任何可用 tap 路由。
    /// - **ui.swipe**：调用方传 "no matching swipe gesture recognizer found on target"，
    ///   说明策略 1/2/3（scrollView swipe actions / UISwipeGestureRecognizer / UIPanGestureRecognizer）
    ///   均未命中或不可达。
    /// - **ui.longPress**：调用方传 "no UILongPressGestureRecognizer found on target"。
    ///
    /// tap 的现有调用方不传 `message`（走默认值），保持文案与历史行为不变。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - targetDescription: 目标摘要。
    ///   - type: 目标 view 的类型名。
    ///   - message: 对外失败说明，进入 envelope；缺省为 tap 专用文案。
    /// - Returns: `unsupported_target` 失败描述。
    static func unsupportedTarget(action: String,
                                  targetDescription: String,
                                  type: String,
                                  message: String = "target has no default activation route (UIButton / UISwitch / text input only)") -> UIKitCommandError {
        UIKitCommandError(code: .unsupportedTarget,
                          message: message,
                          logMessage: "uikit unsupported target action=\(action) target=\(targetDescription) type=\(type)")
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

    /// 节点 `availableActions` 为空，是 `ui.inspect` 标注的 minimal 结构节点，不支持任何动作。
    ///
    /// 区别于 `unsupportedTarget`（目标类型有默认 tap 路由但不在 UIButton/UISwitch/文本输入白名单内）
    /// 与 `unsupportedAction`（控件存在、有能力表，但请求的事件不在表里）：这里是 inspect 阶段就
    /// 判定该节点无任何可用动作（容器/装饰 view），message 引导调用方回到 `ui.inspect` 结果里挑
    /// `availableActions` 非空的目标再操作。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名，用于日志关联。
    ///   - path: 目标 path（如 `"root/5/0"`），进入 message 帮助调用方定位。
    /// - Returns: `not_actionable` 失败描述。
    static func notActionable(action: String, path: String) -> UIKitCommandError {
        UIKitCommandError(code: .notActionable,
                          message: "节点 \(path) 不可操作（availableActions 为空）。请在 ui.inspect 结果里找 availableActions 非空的目标再操作。",
                          logMessage: "uikit not_actionable action=\(action) path=\(path)")
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
    ///   - attempts: 轮询尝试次数（可选，提供时入 data）。
    /// - Returns: `wait_timeout` 失败描述，`elapsedMs`/`attempts` 入 data。
    static func waitTimeout(action: String, mode: String, elapsedMs: Int, attempts: Int? = nil) -> UIKitCommandError {
        var data: JSON = [
            "elapsedMs": .double(Double(elapsedMs))
        ]
        if let attempts {
            data["attempts"] = .double(Double(attempts))
        }
        return UIKitCommandError(code: .waitTimeout,
                                 message: "wait timed out mode=\(mode)",
                                 logMessage: "ui wait timeout action=\(action) mode=\(mode) elapsedMs=\(elapsedMs) attempts=\(attempts.map(String.init) ?? "?")",
                                 data: data)
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

    /// 导航栏按钮选择器参数不足或组合无效。
    ///
    /// `ui.navigation.tapBarButton` 必须提供 `(placement + index)` 或 `accessibilityIdentifier`
    /// 之一才能定位按钮；单独提供 `placement` 无法确定具体按钮。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - reason: 选择器无效的具体原因。
    /// - Returns: `invalid_data` 失败描述。
    static func invalidNavigationBarSelector(action: String, reason: String) -> UIKitCommandError {
        UIKitCommandError(code: .invalidData,
                          message: "invalid navigation bar button selector: \(reason)",
                          logMessage: "ui navigation bar invalid selector action=\(action) reason=\(reason)")
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
    /// - Parameter action: 触发失败的 action 名。
    /// - Returns: `alert_button_required` 失败描述。
    static func alertButtonRequired(action: String) -> UIKitCommandError {
        UIKitCommandError(code: .alertButtonRequired,
                          message: "alert has multiple buttons; specify buttonTitle, buttonIndex, or role",
                          logMessage: "ui alert button required action=\(action)")
    }

    /// alert 按钮已选中，但无法取到或执行对应的 `UIAlertAction` handler。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - reason: runtime 层返回的失败原因摘要。
    /// - Returns: `alert_button_trigger_failed` 失败描述。
    static func alertButtonTriggerFailed(action: String, reason: String) -> UIKitCommandError {
        UIKitCommandError(code: .alertButtonTriggerFailed,
                          message: "alert button handler could not be triggered",
                          logMessage: "ui alert button trigger failed action=\(action) reason=\(reason)")
    }

    /// 非 Debug 构建：`ui.alert.respond` 的 `dryRun=false` 触发路径被 `#if DEBUG` 隔离，不可用。
    ///
    /// 区别于 `alertButtonRequired`（多按钮需指定选择器，补参数可解决）：这里是构建配置硬限制，
    /// 调用方应改用 `dryRun=true` 查询，触发交宿主自定义 action 或人工。
    ///
    /// - Parameter action: 触发失败的 action 名。
    /// - Returns: `alert_release_unsupported` 失败描述。
    static func alertRespondDisabledInRelease(action: String) -> UIKitCommandError {
        UIKitCommandError(code: .alertReleaseUnsupported,
                          message: "alert trigger is disabled in Release builds; use dryRun=true to query",
                          logMessage: "ui alert respond disabled in release action=\(action)")
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
    /// 但 `UITextView` 是 `UIScrollView` 子类且其内部长文滚动语义不同——`UIScrollResolver`
    /// 在解析可滚动容器时显式排除它，命中本错误。当定位字段缺省且回退扫描 keyWindow 也无
    /// scrollView 时同样命中。
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

    /// 滚动容器存在但不可滚动（`isScrollEnabled=false` 或 `window=nil`）。
    ///
    /// 区别于 `scrollContainerUnavailable`（`UIScrollResolver` 没找到 UIScrollView，
    /// message 为 "no UIScrollView ancestor"，调用方应重新 `ui.inspect` 找正确 path）：
    /// 这里容器已经定位成功，但因禁用滚动或脱离 window 而无法执行 `scrollRectToVisible`。
    /// 调用方看到本错误应区分两种处置——若 `isScrollEnabled=false` 是 UI 设计（如 SPMExample
    /// 的 `menuTableView`），不应反复重试 `ui.scrollToElement`，应改 `ui.scroll` 或换路径；
    /// 若 `window=nil` 是临时脱离，可重 `ui.inspect` 后再试。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名，用于日志关联。
    ///   - target: 目标定位摘要（identifier/path），不含大块 payload。
    /// - Returns: `container_not_scrollable` 失败描述。
    static func scrollContainerNotScrollable(action: String, target: String) -> UIKitCommandError {
        UIKitCommandError(code: .containerNotScrollable,
                          message: "scroll container exists but is not scrollable (isScrollEnabled=false or window=nil)",
                          logMessage: "ui scroll container not scrollable action=\(action) target=\(target)")
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
    /// 当目标为 UITextField（单行控件）且 `finalLen < expectedLen` 时，message 会追加换行符提示：
    /// UITextField 的 return 键触发 action 而非插入换行，含 `\n` 的文本会被 UIKit 静默截断，
    /// 这不是库的主动拒绝而是 UIKit 固有行为。agent 可据此切换到 UITextView 完成多行输入。
    ///
    /// - Parameters:
    ///   - action: 触发失败的 action 名。
    ///   - expectedLen: 期望文本长度。
    ///   - finalLen: 实际文本长度。
    ///   - secure: 目标是否为密码输入（`isSecureTextEntry`），决定是否对响应脱敏。
    ///   - singleLineField: 目标是否为 UITextField（单行控件）；为 true 且 finalLen<expectedLen
    ///     时追加换行符拒绝提示。默认 false，保持已有调用方的行为不变。
    /// - Returns: `input_rejected` 失败描述；**日志与 message 都不回原文**，只回长度与 secure 标记。
    static func inputRejected(action: String, expectedLen: Int, finalLen: Int, secure: Bool, singleLineField: Bool = false) -> UIKitCommandError {
        var message = "text input was rejected or altered by delegate"
        // UITextField（单行控件）的 return 键触发 action 而非插入换行，含 \n / 控制字符的
        // 输入会被 UIKit 静默截断（finalLen < expectedLen）。这不是库的主动拒绝，告知 agent
        // 改用 UITextView 即可完成多行输入。见 F-23 / F-04。
        if singleLineField && finalLen < expectedLen {
            message += "; newline or control characters may be rejected by UITextField — use UITextView for multiline input"
        }
        return UIKitCommandError(code: .inputRejected,
                          message: message,
                          logMessage: "ui input rejected action=\(action) expectedLen=\(expectedLen) finalLen=\(finalLen) secure=\(secure) singleLineField=\(singleLineField)")
    }
}
