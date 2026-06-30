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
/// - `input` 对 conform `UITextInput` 的 view 声明（覆盖 `UITextField`/`UITextView`/
///   `UISearchTextField`），为 `ui.input` 类命令预留可输入声明；
/// - `scroll` 对 `UIScrollView` 系声明，但显式排除 `UITextView`（其本身是 scroll view 子类，
///   内部长文滚动留待后续版本，避免误暴露）；
/// - disabled `UIControl` 一律返回空集合，executor 同样拒绝派发，避免 discovery 与执行分叉。
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
    /// `input`/`scroll` 只看 view 本身的协议 conform（不看 nearestControl）：输入与滚动描述的是
    /// 该叶子目标自身的可操作语义，不应借祖先 control 派生。
    ///
    /// - Parameters:
    ///   - view: 被采集/点击的真实 view。
    ///   - rootView: 当前 UIKit 查询上下文的根 view；目标到该根之间任一节点不可交互即拒绝。
    ///   - nearestControl: 调用方预先解析的最近 `UIControl`（可由 `UIKitLocatorResolver.nearestControl`
    ///     得到）；若 view 自身即控件，传它本身即可。`nil` 表示无关联控件。
    ///   - isEnabled: 控件当前是否可用。非控件或未知时传 `nil`。
    /// - Returns: 该目标当前可执行的动作集合。disabled 控件返回空集合（`input`/`scroll`
    ///   不会绕过 disabled 空集规则——disabled `UIControl` 整体拒绝声明任何动作）。
    static func resolve(view: UIView,
                        rootView: UIView,
                        nearestControl: UIControl?) -> UIKitActionAvailability {
        guard isInteractable(view: view, through: rootView) else {
            return UIKitActionAvailability(actions: [])
        }
        let control = (view as? UIControl) ?? nearestControl

        // disabled 控件语义上不可执行：UITapCommand 的 touchUpInside fallback 与
        // UIControlSendActionCommand 都不应在 disabled 状态下被声明为可用动作。
        // disabled 规则作用于整棵声明树——disabled 控件不声明 input/scroll 等任何动作，
        // 避免 discovery 与 executor 在 disabled 状态下出现“可声明但不可派发”的分叉。
        if let control, !control.isEnabled {
            return UIKitActionAvailability(actions: [])
        }

        // 三条声明路径并列累加（用 Set 去重，再按 UIKitActionKind 声明顺序稳定排序输出）：
        // 1. UIControl 路径：tap + control.*（仅当命中可用 control）；
        // 2. UITextInput 路径：input（UITextField/UITextView/UISearchTextField 等）；
        // 3. UIScrollView 路径：scroll（UIScrollView/UICollectionView/UITableView），UITextView 显式排除。
        var collected = Set<UIKitActionKind>()
        if let control {
            collected.formUnion(controlActions(for: control))
        }
        if view is UITextInput {
            collected.insert(.input)
        }
        if view is UIScrollView, !(view is UITextView) {
            collected.insert(.scroll)
        }
        return UIKitActionAvailability(actions: ordered(collected))
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

    /// 按控件真实类型选择 executor 能派发的 control 事件。
    ///
    /// - `UITextField` 声明编辑开始、变化和结束事件（input 由 `UITextInput` 路径补充）；
    /// - 值型控件（`UISwitch`/`UISlider`/`UISegmentedControl`）声明 `valueChanged`；
    /// - 其余 `UIControl`（如 `UIButton`）声明按下和抬起事件。
    private static func controlActions(for control: UIControl) -> [UIKitActionKind] {
        if control is UITextField {
            return [.tap, .controlEditingChanged, .controlEditingDidBegin, .controlEditingDidEnd]
        }
        if control is UISwitch || control is UISlider || control is UISegmentedControl {
            return [.tap, .controlValueChanged]
        }
        return [.tap, .controlTouchDown, .controlTouchUpInside]
    }

    /// 将动作集合按 `UIKitActionKind` 声明顺序稳定排序后输出。
    ///
    /// 用 Set 去重后输出顺序仍需确定（避免测试与 JSON 序列化抖动），按 case 声明顺序过滤即可。
    private static func ordered(_ actions: Set<UIKitActionKind>) -> [UIKitActionKind] {
        let declarationOrder: [UIKitActionKind] = [
            .tap,
            .controlTouchUpInside,
            .controlTouchDown,
            .controlValueChanged,
            .controlEditingChanged,
            .controlEditingDidBegin,
            .controlEditingDidEnd,
            .input,
            .scroll,
        ]
        return declarationOrder.filter { actions.contains($0) }
    }
}
#endif
