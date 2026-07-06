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
@Test("UIButton 声明 tap 与 touchDown/touchUpInside") @MainActor
func buttonDeclaresTapAndTouchEvents() {
    let button = UIButton(type: .system)
    let availability = UIKitActionCapabilityResolver.resolve(view: button, rootView: button)
    #expect(availability.actions.contains(.tap))
    #expect(availability.actions.contains(.controlTouchDown))
    #expect(availability.actions.contains(.controlTouchUpInside))
}

@Test("UISwitch 声明 tap 与 valueChanged") @MainActor
func switchDeclaresTapAndValueChanged() {
    let toggle = UISwitch()
    let availability = UIKitActionCapabilityResolver.resolve(view: toggle, rootView: toggle)
    #expect(availability.actions.contains(.tap))
    #expect(availability.actions.contains(.controlValueChanged))
}

@Test("UISlider 不声明 tap，仅 valueChanged") @MainActor
func sliderDoesNotDeclareTap() {
    let slider = UISlider()
    let availability = UIKitActionCapabilityResolver.resolve(view: slider, rootView: slider)
    #expect(!availability.actions.contains(.tap))
    #expect(availability.actions.contains(.controlValueChanged))
}

@Test("UISegmentedControl 不声明 tap，仅 valueChanged") @MainActor
func segmentedControlDoesNotDeclareTap() {
    let segmented = UISegmentedControl(items: ["一", "二"])
    let availability = UIKitActionCapabilityResolver.resolve(view: segmented, rootView: segmented)
    #expect(!availability.actions.contains(.tap))
    #expect(availability.actions.contains(.controlValueChanged))
}

@Test("UIStepper 不声明 tap，仅 valueChanged") @MainActor
func stepperDoesNotDeclareTap() {
    let stepper = UIStepper()
    let availability = UIKitActionCapabilityResolver.resolve(view: stepper, rootView: stepper)
    #expect(!availability.actions.contains(.tap))
    #expect(availability.actions.contains(.controlValueChanged))
}

@Test("未知自定义 UIControl 不声明 tap，仅 touchDown/touchUpInside") @MainActor
func unknownCustomControlDoesNotDeclareTap() {
    final class CustomControl: UIControl {}
    let control = CustomControl()
    let availability = UIKitActionCapabilityResolver.resolve(view: control, rootView: control)
    #expect(!availability.actions.contains(.tap))
    #expect(availability.actions.contains(.controlTouchDown))
    #expect(availability.actions.contains(.controlTouchUpInside))
}

@Test("UITextField 声明 tap/input 与编辑事件") @MainActor
func textFieldDeclaresTapInputAndEditingEvents() {
    let textField = UITextField()
    let availability = UIKitActionCapabilityResolver.resolve(view: textField, rootView: textField)
    // UITextField 既是 UIControl（默认激活路由 inputFocus → tap + control.editing*），又 conform
    // UITextInput → 追加 input。覆盖 executor 后续的 ui.tap(聚焦) 与 ui.input 命令。
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
            .resolve(view: textField, rootView: root)
            .actions.contains(.input))
    // UIScrollView 声明 scroll。
    #expect(UIKitActionCapabilityResolver
            .resolve(view: scrollView, rootView: root)
            .actions.contains(.scroll))
    // UITextView 虽是 UIScrollView 子类，但内部长文滚动留 v2——显式排除 scroll，避免误暴露。
    #expect(!UIKitActionCapabilityResolver
            .resolve(view: textView, rootView: root)
            .actions.contains(.scroll))
    // UITextView conform UITextInput，仍声明 input。
    #expect(UIKitActionCapabilityResolver
            .resolve(view: textView, rootView: root)
            .actions.contains(.input))
    // 既非 control、又非 UITextInput/UIScrollView 的普通 view 不声明任何动作。
    #expect(UIKitActionCapabilityResolver
            .resolve(view: plain, rootView: root)
            .actions.isEmpty)
}

@Test("禁用控件不声明可执行动作") @MainActor
func disabledControlHasNoAvailableActions() {
    let button = UIButton(type: .system)
    button.isEnabled = false
    let availability = UIKitActionCapabilityResolver.resolve(view: button, rootView: button)
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
        let availability = UIKitActionCapabilityResolver.resolve(view: button, rootView: root)
        #expect(availability.actions.isEmpty)
    }
}

@Test("非 control 目标不声明动作（canonical-only，不借祖先 control）") @MainActor
func nonControlTargetDoesNotInheritAncestorControlActions() {
    // 结构：root > button > container > leaf。leaf 非 control 非 scrollView，canonical-only 规则下
    // 不声明任何动作，更不会借祖先 button control 派生 tap（resolver 已无 nearestControl 借用路径）。
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
