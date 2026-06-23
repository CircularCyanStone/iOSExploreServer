import Testing
@testable import iOSExploreUIKit

// MARK: - Foundation-only 值类型测试（macOS 可编译）

/// `UIKitActionPlan` 是值类型，描述 tap/control 两种动作语义。它在 macOS 测试覆盖构造与
/// 字段保留；`@MainActor` 的 `UIKitActionExecutor` 只能在 iOS framework 测试覆盖运行时行为
/// （Task 7）。这两个测试对应 brief Task 5 Step 1。

@Test("ActionPlan 保留 tap 的坐标定位")
func tapActionPlanPreservesWindowPoint() {
    let plan = UIKitActionPlan.tap(locator: .windowPoint(x: 20, y: 30))
    guard case .tap(let locator) = plan else { Issue.record("expected tap plan"); return }
    #expect(locator == .windowPoint(x: 20, y: 30))
}

@Test("ActionPlan 保留 control event")
func controlActionPlanPreservesEvent() {
    let plan = UIKitActionPlan.controlEvent(locator: .path([0]), event: .touchUpInside)
    guard case .controlEvent(_, let event) = plan else { Issue.record("expected control plan"); return }
    #expect(event == .touchUpInside)
}

@Test("ActionPlan tap 保留 accessibilityIdentifier 定位")
func tapActionPlanPreservesIdentifier() {
    let plan = UIKitActionPlan.tap(locator: .accessibilityIdentifier("mine.header.avatar"))
    guard case .tap(let locator) = plan else { Issue.record("expected tap plan"); return }
    #expect(locator == .accessibilityIdentifier("mine.header.avatar"))
}

@Test("ActionPlan controlEvent 保留 locator 与事件")
func controlActionPlanPreservesLocatorAndEvent() {
    let plan = UIKitActionPlan.controlEvent(locator: .accessibilityIdentifier("switch"),
                                            event: .valueChanged)
    guard case .controlEvent(let locator, let event) = plan else {
        Issue.record("expected control plan")
        return
    }
    #expect(locator == .accessibilityIdentifier("switch"))
    #expect(event == .valueChanged)
}

@Test("ActionPlan 两种变体互不相等")
func actionPlanTapAndControlEventAreDistinct() {
    let tap = UIKitActionPlan.tap(locator: .path([0]))
    let control = UIKitActionPlan.controlEvent(locator: .path([0]), event: .touchUpInside)
    #expect(tap != control)
}
