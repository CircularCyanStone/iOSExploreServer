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
@Test("文本输入框声明与 executor 一致的编辑动作") @MainActor
func textFieldDeclaresEditingActions() {
    let textField = UITextField()
    let availability = UIKitActionCapabilityResolver.resolve(view: textField,
                                                               rootView: textField,
                                                               nearestControl: textField)
    #expect(availability.rawValues == [
        "tap",
        "control.editingChanged",
        "control.editingDidBegin",
        "control.editingDidEnd",
    ])
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
#endif
