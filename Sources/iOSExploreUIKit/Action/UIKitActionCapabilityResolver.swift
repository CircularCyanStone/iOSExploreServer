#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// UIKit 动作能力的唯一解析器。
///
/// collector（`ui.viewTargets` 输出 `availableActions`）与 executor（Task 5 的
/// `UIKitActionExecutor` 决定 tap/control 派发）共用本类型，确保“声明可执行”与“实际可派发”
/// 走同一份规则，避免静态节点被标成可 tap，或给 disabled 控件虚假动作。
///
/// 规则与既有命令的实际行为严格对齐：
/// - `UITapCommand` 仅对 `UIControl` 派发 `touchUpInside` fallback（非 UIControl 返回
///   `unsupportedTarget`）；因此 `tap` 要求命中点能解析到一个**已启用**的 `UIControl`。
/// - `UIControlSendActionCommand` 对 `UIControl` 调用 `sendActions(for:)`，事件名取
///   `touchUpInside`（按钮等触发型）或 `valueChanged`（switch/slider/segmented 等值型）。
///   disabled 控件虽然能被 `sendActions` 调用，但语义上不可执行，故一律不声明可用动作。
///
/// 该类型是 `@MainActor`，只能在 UIKit 隔离域调用；跨边界只传 `UIKitActionAvailability`
/// 这个 Sendable 值类型。
@MainActor
enum UIKitActionCapabilityResolver {
    /// 解析单个 view 的可执行动作。
    ///
    /// 当 view 本身不是 `UIControl` 时，沿用 `UITapCommand` 的 nearest-control 策略：向上
    /// 查找最近的 `UIControl`（例如按钮内的 label），但不再越过本 view 的父级——因为
    /// `ui.viewTargets` 返回的是叶子目标，能力应描述该叶子点上去能触发的控件。
    ///
    /// - Parameters:
    ///   - view: 被采集/点击的真实 view。
    ///   - nearestControl: 调用方预先解析的最近 `UIControl`（可由 `UIKitLocatorResolver.nearestControl`
    ///     得到）；若 view 自身即控件，传它本身即可。`nil` 表示无关联控件。
    ///   - isEnabled: 控件当前是否可用。非控件或未知时传 `nil`。
    /// - Returns: 该目标当前可执行的动作集合。无控件或 disabled 时返回空集合。
    static func resolve(view: UIView,
                        nearestControl: UIControl?,
                        isEnabled: Bool?) -> UIKitActionAvailability {
        let control = (view as? UIControl) ?? nearestControl
        guard let control else { return UIKitActionAvailability(actions: []) }

        // disabled 控件语义上不可执行：UITapCommand 的 touchUpInside fallback 与
        // UIControlSendActionCommand 都不应在 disabled 状态下被声明为可用动作。
        let enabled = isEnabled ?? control.isEnabled
        guard enabled else { return UIKitActionAvailability(actions: []) }

        return UIKitActionAvailability(actions: actions(for: control))
    }

    /// 按控件真实类型选择 executor 能派发的事件。
    ///
    /// - 值型控件（`UISwitch`/`UISlider`/`UISegmentedControl`）以 `valueChanged` 为主事件，
    ///   对应 `UIControlSendActionCommand` 对这类控件的自然用法；同时保留 `tap`，因为
    ///   `UITapCommand` 对它们也会派发 `touchUpInside` fallback。
    /// - 其余 `UIControl`（如 `UIButton`）以 `tap` + `control.touchUpInside` 表达按钮语义。
    private static func actions(for control: UIControl) -> [UIKitActionKind] {
        if control is UISwitch || control is UISlider || control is UISegmentedControl {
            return [.tap, .controlValueChanged]
        }
        return [.tap, .controlTouchUpInside]
    }
}
#endif
