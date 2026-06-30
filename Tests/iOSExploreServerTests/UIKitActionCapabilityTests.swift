import Testing
@testable import iOSExploreUIKit

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Foundation-only 值类型测试（macOS 可编译）

@Test("静态节点不被声明为可 tap")
func staticNodeHasNoAvailableActions() {
    #expect(UIKitActionAvailability(actions: []).rawValues == [])
}

@Test("按钮声明 tap 与 touchUpInside")
func enabledButtonHasExecutableActions() {
    let result = UIKitActionAvailability(actions: [.tap, .controlTouchUpInside])
    #expect(result.rawValues == ["tap", "control.touchUpInside"])
}

@Test("UIKitActionKind rawValue 与 executor 事件名一致")
func actionKindRawValuesMatchExecutorEvents() {
    #expect(UIKitActionKind.tap.rawValue == "tap")
    #expect(UIKitActionKind.controlTouchUpInside.rawValue == "control.touchUpInside")
    #expect(UIKitActionKind.controlValueChanged.rawValue == "control.valueChanged")
}

@Test("UIKitActionAvailability 保留动作顺序且去重由调用方保证")
func availabilityPreservesActionOrder() {
    let single = UIKitActionAvailability(actions: [.controlValueChanged])
    #expect(single.rawValues == ["control.valueChanged"])
    #expect(single.actions == [.controlValueChanged])
}

#if canImport(UIKit)
@Test("文本输入框声明与 executor 一致的编辑动作及 input") @MainActor
func textFieldDeclaresEditingActions() {
    let textField = UITextField()
    let availability = UIKitActionCapabilityResolver.resolve(view: textField,
                                                               rootView: textField,
                                                               nearestControl: textField)
    // UITextField 既是 UIControl（保留 tap + control.editing* 编辑事件），又 conform UITextInput
    // → 追加 input。两条路径并列累加，覆盖 executor 后续的 ui.input 命令。
    #expect(availability.actions.contains(.tap))
    #expect(availability.actions.contains(.controlEditingChanged))
    #expect(availability.actions.contains(.controlEditingDidBegin))
    #expect(availability.actions.contains(.controlEditingDidEnd))
    #expect(availability.actions.contains(.input))
}

@Test("capability: input/scroll 声明 + UITextView 排除 scroll") @MainActor
func capabilityDeclarationsForInputAndScroll() {
    let root = UIView()
    let textField = UITextField(); root.addSubview(textField)
    let scrollView = UIScrollView(); root.addSubview(scrollView)
    let textView = UITextView(); root.addSubview(textView)
    let plain = UIView(); root.addSubview(plain)

    // UITextField（UIControl 子类）声明 input（UITextInput conform）。
    #expect(UIKitActionCapabilityResolver
            .resolve(view: textField, rootView: root, nearestControl: textField)
            .actions.contains(.input))
    // UIScrollView 声明 scroll。
    #expect(UIKitActionCapabilityResolver
            .resolve(view: scrollView, rootView: root, nearestControl: nil)
            .actions.contains(.scroll))
    // UITextView 虽是 UIScrollView 子类，但内部长文滚动留 v2——显式排除 scroll，避免误暴露。
    #expect(!UIKitActionCapabilityResolver
            .resolve(view: textView, rootView: root, nearestControl: nil)
            .actions.contains(.scroll))
    // UITextView conform UITextInput，仍声明 input（codex 第三轮补的正确性断言）。
    #expect(UIKitActionCapabilityResolver
            .resolve(view: textView, rootView: root, nearestControl: nil)
            .actions.contains(.input))
    // 既非 control、又非 UITextInput/UIScrollView 的普通 view 不声明任何动作。
    #expect(UIKitActionCapabilityResolver
            .resolve(view: plain, rootView: root, nearestControl: nil)
            .actions.isEmpty)
}

@Test("禁用控件不声明可执行动作") @MainActor
func disabledControlHasNoAvailableActions() {
    let button = UIButton(type: .system)
    button.isEnabled = false
    let availability = UIKitActionCapabilityResolver.resolve(view: button,
                                                               rootView: button,
                                                               nearestControl: button)
    #expect(availability.rawValues.isEmpty)
}

@Test("父容器不可见或不可交互时不声明可执行动作") @MainActor
func ancestorStateBlocksAvailableActions() {
    let root = UIView()
    let container = UIView()
    let button = UIButton(type: .system)
    root.addSubview(container)
    container.addSubview(button)

    for mutate in [
        { container.isHidden = true },
        { container.alpha = 0 },
        { container.isUserInteractionEnabled = false },
    ] {
        container.isHidden = false
        container.alpha = 1
        container.isUserInteractionEnabled = true
        mutate()
        let availability = UIKitActionCapabilityResolver.resolve(view: button,
                                                                   rootView: root,
                                                                   nearestControl: button)
        #expect(availability.actions.isEmpty)
    }
}

@Test("非 control 目标不因祖先 control 被声明可执行动作（与 executor view-tap 一致）") @MainActor
func nonControlTargetDoesNotInheritAncestorControlActions() {
    // 结构：root > button > container > leaf。leaf 非 control 且可交互，祖先是 UIControl。
    // collector 不应借用祖先 control 声明动作——否则 executor 按 path 派发时，nearestControl
    // 被限制在 leaf.superview 之内（找不到 control）会返回 unsupportedTarget，造成声明与派发分叉。
    let root = UIView()
    let button = UIButton(type: .system)
    let container = UIView()
    let leaf = UIView()
    root.addSubview(button)
    button.addSubview(container)
    container.addSubview(leaf)

    let availability = UIViewTargetsCollector.availableActions(for: leaf, rootView: root)
    #expect(availability.actions.isEmpty)
}
#endif
