#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// UIKit 动作能力的唯一解析器。
///
/// collector（`ui.inspect` 输出 `availableActions`）与 executor（`UIKitActionExecutor`
/// 决定 tap / control 派发）共用本类型，确保"声明可执行"与"实际可派发"走同一份规则。
///
/// 重构后的规则：
/// - `tap` 仅在目标存在默认激活路由（`UIKitDefaultActivationResolver`）时声明——即
///   `UIButton`/`UISwitch`/文本输入。`UISlider`/`UISegmentedControl`/未知自定义 `UIControl`
///   不声明 `tap`（tap 语义不明确），但仍可暴露精确 `control.*` 事件；
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
    /// 不再借祖先 `UIControl` 派生动作：canonical target 的能力描述该 target 自身可触发的
    /// 动作。`tap` 由默认激活路由决定，`control.*`/`input`/`scroll` 按真实类型与状态生成。
    ///
    /// - Parameters:
    ///   - view: 被采集/点击的真实 view。
    ///   - rootView: 当前 UIKit 查询上下文的根 view；目标到该根之间任一节点不可交互即拒绝。
    /// - Returns: 该目标当前可执行的动作集合。disabled 控件返回空集合。
    static func resolve(view: UIView, rootView: UIView) -> UIKitActionAvailability {
        guard isInteractable(view: view, through: rootView) else {
            return UIKitActionAvailability(actions: [])
        }

        // disabled 控件语义上不可执行：tap 默认激活与 control.sendAction 都不应在 disabled
        // 状态下被声明为可用动作。disabled 规则作用于整棵声明树——disabled 控件不声明
        // input/scroll 等任何动作，避免 discovery 与 executor 在 disabled 状态下出现
        // "可声明但不可派发"的分叉。
        if let control = view as? UIControl, !control.isEnabled {
            return UIKitActionAvailability(actions: [])
        }

        // 三条声明路径并列累加（用 Set 去重，再按 UIKitActionKind 声明顺序稳定排序输出）：
        // 1. 默认激活路由：UIButton/UISwitch/文本输入 → tap；
        // 2. UIControl 路径：精确 control.* 事件（不含 tap，tap 已由路由决定）；
        // 3. UITextInput 路径：input；
        // 4. UIScrollView 路径：scroll（UITextView 显式排除）。
        var collected = Set<UIKitActionKind>()
        if UIKitDefaultActivationResolver.route(for: view) != nil {
            collected.insert(.tap)
        }
        // cell 子树：cellSelection adapter（executeTap 的 cellSelection 分支）能为其派发
        // didSelectRow/Item，故声明 tap 让 agent 直接知道此 view 可点。与 hasGestureRecognizers
        // 推断双保险：即使该子 view 未挂私有 gesture，只要它在 cell 子树内就声明 tap；
        // executeTap 走 cellSelection 仍可达。
        if view.explore_cellAncestor != nil {
            collected.insert(.tap)
        }
        if let control = view as? UIControl {
            collected.formUnion(controlActions(for: control))
        }
        if view is UITextInput {
            collected.insert(.input)
        }
        if view is UIScrollView, !(view is UITextView) {
            // isScrollEnabled=false 时不声明 scroll 能力，避免 discovery（availableActions=['scroll']）
            // 与 executor（scroll to element/scroll 被 isScrollEnabled=false 拒绝）的分叉。
            // SPMExample 的 menuTableView 设了 isScrollEnabled=false 触发过此问题。
            if let scrollView = view as? UIScrollView, !scrollView.isScrollEnabled {
                // scroll disabled → 不声明 scroll
            } else {
                collected.insert(.scroll)
            }
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

    /// 按控件真实类型选择 executor 能派发的精确 control 事件（不含 tap）。
    ///
    /// - `UITextField` 声明编辑开始、变化和结束事件（input 由 `UITextInput` 路径补充，
    ///   tap 由默认激活路由补充）；
    /// - 值型控件（`UISwitch`/`UISlider`/`UISegmentedControl`/`UIStepper`）声明 `valueChanged`
    ///   （其中 UISwitch 的 tap 由路由 switchToggle 声明，slider/segmented 无 tap）；
    /// - 其余 `UIControl`（如 `UIButton`、未知自定义 control）声明按下和抬起事件
    ///   （UIButton 的 tap 由路由 controlTouchUpInside 声明，自定义 control 无 tap）。
    private static func controlActions(for control: UIControl) -> [UIKitActionKind] {
        if control is UITextField {
            return [.controlEditingChanged, .controlEditingDidBegin, .controlEditingDidEnd]
        }
        if control is UISwitch || control is UISlider || control is UISegmentedControl || control is UIStepper {
            return [.controlValueChanged]
        }
        return [.controlTouchDown, .controlTouchUpInside]
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
