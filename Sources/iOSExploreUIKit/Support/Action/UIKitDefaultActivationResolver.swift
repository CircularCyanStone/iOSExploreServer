#if canImport(UIKit)
import UIKit

/// `ui.tap` 默认激活路由名。
///
/// `rawValue` 同时出现在 capability 的 `availableActions`（决定是否声明 `tap`）、executor 的
/// 响应 `activationRoute` 字段（说明实际走了哪条 adapter）以及 `semanticDigest`（语义摘要
/// 纳入路由，路由变化即视为语义变化）。collector 与 executor 共用，保证"声明可 tap"与
/// "实际默认激活路由"两侧不可分叉。
@MainActor
enum UIKitDefaultActivationRoute: String, Sendable {
    /// `UIButton` 及其子类：`sendActions(for: .touchUpInside)`。
    case controlTouchUpInside = "control.touchUpInside"
    /// `UISwitch`：`setOn(!isOn)` 后 `sendActions(for: .valueChanged)`。
    case switchToggle = "switch.toggle"
    /// `UITextField` / `UISearchTextField` / `UITextView`：`becomeFirstResponder()`（聚焦语义）。
    case inputFocus = "input.focus"
}

/// `ui.tap` 默认激活路由的唯一判定器。
///
/// collector（`availableActions` 是否含 `tap`）与 executor（按 route 派发）共用本类型，
/// 保证"声明可 tap"与"实际默认激活路由"走同一份规则，不再出现 collector 宣告 tap、executor
/// 却做不同事情的分叉，也不再借祖先 UIControl 派生 tap。
///
/// V1 只自动支持三类确定 adapter：
/// - `UIButton` / `UIButton` 子类 → `controlTouchUpInside`；
/// - `UISwitch` → `switchToggle`（翻转 + valueChanged，而非 touchUpInside）；
/// - `UITextField` / `UISearchTextField` / `UITextView` → `inputFocus`（聚焦）。
///
/// `UISlider` / `UISegmentedControl` / 未知自定义 `UIControl` / 普通 `UIView` 均返回 `nil`
/// （executor 抛 `unsupported_target`，宁可漏声明也不误激活）。后续若要支持自定义
/// button-like control，必须另开显式 adapter，不在本轮夹带。
@MainActor
enum UIKitDefaultActivationResolver {
    /// 返回 target 的默认激活路由；无确定公开 adapter 时返回 `nil`。
    ///
    /// - Parameter view: canonical target 真实 view。
    static func route(for view: UIView) -> UIKitDefaultActivationRoute? {
        if view is UIButton { return .controlTouchUpInside }
        if view is UISwitch { return .switchToggle }
        if view is UITextField || view is UISearchTextField || view is UITextView {
            return .inputFocus
        }
        return nil
    }
}
#endif
