import Testing
@testable import iOSExploreServer
@testable import iOSExploreUIKit

// MARK: - Foundation-only 值类型测试（macOS 可编译）

/// `UIKitActionPlan` 是值类型，描述 tap/control 两种动作语义。它在 macOS 测试覆盖构造与
/// 字段保留（`viewSnapshotID` 必填）；`@MainActor` 的 `UIKitActionExecutor` 只能在 iOS
/// framework 测试覆盖运行时行为（Task 7）。

@Test("ActionPlan 保留 tap 的 path 定位与 viewSnapshotID")
func tapActionPlanPreservesPathAndSnapshot() {
    let plan = UIKitActionPlan.tap(locator: .path([0]), viewSnapshotID: "view_snapshot_test")
    guard case .tap(let locator, let viewSnapshotID) = plan else {
        Issue.record("expected tap plan")
        return
    }
    #expect(locator == .path([0]))
    #expect(viewSnapshotID == "view_snapshot_test")
}

@Test("ActionPlan 保留 tap 的 accessibilityIdentifier 定位")
func tapActionPlanPreservesIdentifier() {
    let plan = UIKitActionPlan.tap(locator: .accessibilityIdentifier("mine.header.avatar"),
                                   viewSnapshotID: "view_snapshot_test")
    guard case .tap(let locator, _) = plan else { Issue.record("expected tap plan"); return }
    #expect(locator == .accessibilityIdentifier("mine.header.avatar"))
}

@Test("ActionPlan 保留 controlEvent 的 locator 与事件")
func controlActionPlanPreservesLocatorAndEvent() {
    let plan = UIKitActionPlan.controlEvent(locator: .accessibilityIdentifier("switch"),
                                            event: .valueChanged,
                                            value: .double(1),
                                            viewSnapshotID: "view_snapshot_test")
    guard case .controlEvent(let locator, let event, let value, let viewSnapshotID) = plan else {
        Issue.record("expected control plan")
        return
    }
    #expect(locator == .accessibilityIdentifier("switch"))
    #expect(event == .valueChanged)
    #expect(value == .double(1))
    #expect(viewSnapshotID == "view_snapshot_test")
}

@Test("ActionPlan 两种变体互不相等")
func actionPlanTapAndControlEventAreDistinct() {
    let tap = UIKitActionPlan.tap(locator: .path([0]), viewSnapshotID: "view_snapshot_test")
    let control = UIKitActionPlan.controlEvent(locator: .path([0]),
                                               event: .touchUpInside,
                                               viewSnapshotID: "view_snapshot_test")
    #expect(tap != control)
}
