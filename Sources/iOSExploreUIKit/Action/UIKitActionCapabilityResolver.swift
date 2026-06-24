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
/// 规则由 collector 与 executor 同时调用：
/// - `tap` 仅在命中可用 `UIControl` 时可执行；
/// - `control.*` 按真实控件类型选择自然事件；
/// - disabled 控件一律返回空集合，executor 同样拒绝派发，避免 discovery 与执行分叉。
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
    ///   - rootView: 当前 UIKit 查询上下文的根 view；目标到该根之间任一节点不可交互即拒绝。
    ///   - nearestControl: 调用方预先解析的最近 `UIControl`（可由 `UIKitLocatorResolver.nearestControl`
    ///     得到）；若 view 自身即控件，传它本身即可。`nil` 表示无关联控件。
    ///   - isEnabled: 控件当前是否可用。非控件或未知时传 `nil`。
    /// - Returns: 该目标当前可执行的动作集合。无控件或 disabled 时返回空集合。
    static func resolve(view: UIView,
                        rootView: UIView,
                        nearestControl: UIControl?) -> UIKitActionAvailability {
        guard isInteractable(view: view, through: rootView) else {
            return UIKitActionAvailability(actions: [])
        }
        let control = (view as? UIControl) ?? nearestControl
        guard let control else { return UIKitActionAvailability(actions: []) }

        // disabled 控件语义上不可执行：UITapCommand 的 touchUpInside fallback 与
        // UIControlSendActionCommand 都不应在 disabled 状态下被声明为可用动作。
        guard control.isEnabled else { return UIKitActionAvailability(actions: []) }

        return UIKitActionAvailability(actions: actions(for: control))
    }

    /// 检查 target 到上下文 root 的 UIKit 命中前提。
    private static func isInteractable(view: UIView, through rootView: UIView) -> Bool {
        var current: UIView? = view
        while let node = current {
            guard !node.isHidden, node.alpha > 0.01, node.isUserInteractionEnabled else { return false }
            if node === rootView { return true }
            current = node.superview
        }
        return false
    }

    /// 将命令事件映射为 capability 中的动作值。
    ///
    /// - Parameter event: `ui.control.sendAction` 请求的事件。
    /// - Returns: 与响应 `availableActions` 使用相同 rawValue 的动作类型。
    static func actionKind(for event: UIControlSendActionEvent) -> UIKitActionKind {
        switch event {
        case .touchDown: return .controlTouchDown
        case .touchUpInside: return .controlTouchUpInside
        case .valueChanged: return .controlValueChanged
        case .editingChanged: return .controlEditingChanged
        case .editingDidBegin: return .controlEditingDidBegin
        case .editingDidEnd: return .controlEditingDidEnd
        }
    }

    /// 按控件真实类型选择 executor 能派发的事件。
    ///
    /// - `UITextField` 声明编辑开始、变化和结束事件；
    /// - 值型控件（`UISwitch`/`UISlider`/`UISegmentedControl`）声明 `valueChanged`；
    /// - 其余 `UIControl`（如 `UIButton`）声明按下和抬起事件。
    private static func actions(for control: UIControl) -> [UIKitActionKind] {
        if control is UITextField {
            return [.tap, .controlEditingChanged, .controlEditingDidBegin, .controlEditingDidEnd]
        }
        if control is UISwitch || control is UISlider || control is UISegmentedControl {
            return [.tap, .controlValueChanged]
        }
        return [.tap, .controlTouchDown, .controlTouchUpInside]
    }
}
#endif
