import Testing
@testable import iOSExploreUIKit

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
