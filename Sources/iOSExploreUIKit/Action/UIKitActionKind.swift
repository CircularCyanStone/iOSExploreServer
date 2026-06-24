import Foundation

/// UIKit 可执行动作的语义类型。
///
/// 该枚举是 Foundation-only 值类型，rawValue 与既有 executor 实际支持的行为一一对应：
/// - `tap` 对应 `UITapCommand` 对 `UIControl` 的 `touchUpInside` fallback 派发；
/// - 所有 `control.*` case 都对应 `UIControlSendActionCommand` 接受的 event 名；resolver
///   决定具体控件在当前状态下可以使用其中哪些值。
///
/// `UIKitActionKind` 描述 executor 真正能派发的动作，由 `UIKitActionCapabilityResolver`
/// 按真实 view/控件状态生成；命令响应中的 `availableActions` 即由本类型序列化，是 agent
/// 判断目标可执行性的唯一动作依据（`role` 仅作类型提示，不再派生动作建议）。
public enum UIKitActionKind: String, Sendable, Equatable {
    /// 点击语义。executor 对 `UIControl` 派发 `touchUpInside`。
    case tap
    /// UIControl 的 `touchUpInside` 事件，适用于按钮等触发型控件。
    case controlTouchUpInside = "control.touchUpInside"
    /// UIControl 的 `touchDown` 事件，适用于按下即触发的控件。
    case controlTouchDown = "control.touchDown"
    /// UIControl 的 `valueChanged` 事件，适用于 switch、slider、segmented control 等值型控件。
    case controlValueChanged = "control.valueChanged"
    /// 文本输入控件的编辑变化事件。
    case controlEditingChanged = "control.editingChanged"
    /// 文本输入控件开始编辑事件。
    case controlEditingDidBegin = "control.editingDidBegin"
    /// 文本输入控件结束编辑事件。
    case controlEditingDidEnd = "control.editingDidEnd"
}

/// 某个 UI 目标当前可执行的 UIKit 动作集合。
///
/// Foundation-only 值类型：由 `@MainActor` 的 `UIKitActionCapabilityResolver` 在 UIKit 隔离域
/// 内生成，随后可作为 `Sendable` 摘要跨边界传递（例如进入命令响应 JSON）。调用方不直接构造，
/// 应通过 resolver 获取，避免按 role 自行推断导致与 executor 实际支持范围脱节。
public struct UIKitActionAvailability: Sendable, Equatable {
    /// 当前目标可执行的动作，顺序即输出顺序。
    public let actions: [UIKitActionKind]

    /// 动作 rawValue 列表，用于序列化进命令响应 JSON。
    public var rawValues: [String] { actions.map(\.rawValue) }

    /// 创建动作可用性摘要。
    ///
    /// - Parameter actions: 当前目标可执行的动作。
    public init(actions: [UIKitActionKind]) {
        self.actions = actions
    }
}
