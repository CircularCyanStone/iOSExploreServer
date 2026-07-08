#if canImport(UIKit)
import UIKit
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

/// `UIKitActionExecutor` 全派发路径的运行时测试（Task 7 重构后）。
///
/// 通过 `UIKitTestHost` 注入可控 view 树，先 `UIViewTargetsCollector.collect` 签发
/// `viewSnapshotID`，再驱动 executor 的 locate / freshness / 默认激活路由 / sendActions，
/// 覆盖重构后的语义：tap 按 `UIKitDefaultActivationResolver` 路由派发（button/switch/input），
/// 无路由目标（slider/segmented）抛 unsupported_target，child label path 不激活父 button，
/// identifier 与 path 都走同一 freshness 校验。
///
/// 注意：logic test 下 `UIControl.sendActions` 不派发 target-action（无 app runloop），故这些
/// 测试验证的是 executor 自身逻辑（走到 sendActions、命中正确 route、返回正确 JSON 或抛出
/// 对应错误码），而非 UIKit 的派发效果。
///
/// executor 已 throw 化：成功路径返回纯 `JSON`，失败路径 `throw UIKitCommandError`，故成功
/// 测试用 `try` 直取 JSON，失败测试用 do/catch 断言 `error.failure.code`。

/// 取一次 `ui.inspect` 签发的 viewSnapshotID，供交互命令携带做 freshness 校验。
@MainActor
private func testViewSnapshotID(context: UIKitContextProvider.Context) -> String {
    let data = UIViewTargetsCollector.collect(query: .default, context: context)
    guard let id = data["viewSnapshotID"]?.stringValue else {
        Issue.record("collect should produce viewSnapshotID")
        return ""
    }
    return id
}

@Test("executor tap UIButton 走 control.touchUpInside 默认激活") @MainActor
func tapButtonActivatesTouchUpInsideRoute() throws {
    let context = UIKitTestHost.context { root in
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 100, y: 100, width: 120, height: 60)
        root.addSubview(button)
    }
    let viewSnapshotID = testViewSnapshotID(context: context)

    let data = try UIKitActionExecutor.execute(.tap(locator: .path([0]), viewSnapshotID: viewSnapshotID),
                                               context: context)

    #expect(data["activated"]?.boolValue == true)
    #expect(data["activationRoute"]?.stringValue == "control.touchUpInside")
    #expect(data["type"]?.stringValue == "UIButton")
    #expect(data["event"]?.stringValue == "touchUpInside")
    #expect(data["path"]?.stringValue == "root/0")
}

@Test("executor tap UISwitch 翻转并派发 valueChanged") @MainActor
func tapSwitchTogglesAndSendsValueChanged() throws {
    let context = UIKitTestHost.context { root in
        let toggle = UISwitch()
        toggle.frame = CGRect(x: 100, y: 100, width: 51, height: 31)
        toggle.isOn = false
        root.addSubview(toggle)
    }
    let viewSnapshotID = testViewSnapshotID(context: context)

    let data = try UIKitActionExecutor.execute(.tap(locator: .path([0]), viewSnapshotID: viewSnapshotID),
                                               context: context)

    #expect(data["activated"]?.boolValue == true)
    #expect(data["activationRoute"]?.stringValue == "switch.toggle")
    #expect(data["event"]?.stringValue == "valueChanged")
    #expect(data["previousValue"]?.boolValue == false)
    #expect(data["currentValue"]?.boolValue == true)
}

@Test("executor tap UITextField 走 input.focus 聚焦") @MainActor
func tapTextFieldFocusesFirstResponder() throws {
    let context = UIKitTestHost.context { root in
        let field = UITextField()
        field.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        root.addSubview(field)
    }
    let viewSnapshotID = testViewSnapshotID(context: context)

    let data = try UIKitActionExecutor.execute(.tap(locator: .path([0]), viewSnapshotID: viewSnapshotID),
                                               context: context)

    #expect(data["activated"]?.boolValue == true)
    #expect(data["activationRoute"]?.stringValue == "input.focus")
    #expect(data["isFirstResponder"]?.boolValue == true)
}

@Test("executor tap UISlider 无默认激活路由返回 unsupported_target") @MainActor
func tapSliderReturnsUnsupportedTarget() {
    let context = UIKitTestHost.context { root in
        let slider = UISlider()
        slider.frame = CGRect(x: 100, y: 100, width: 200, height: 30)
        root.addSubview(slider)
    }
    let viewSnapshotID = testViewSnapshotID(context: context)

    do {
        _ = try UIKitActionExecutor.execute(.tap(locator: .path([0]), viewSnapshotID: viewSnapshotID),
                                            context: context)
        Issue.record("expected unsupported_target, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .unsupportedTarget)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("executor tap UISegmentedControl 无默认激活路由返回 unsupported_target") @MainActor
func tapSegmentedControlReturnsUnsupportedTarget() {
    let context = UIKitTestHost.context { root in
        let segmented = UISegmentedControl(items: ["一", "二"])
        segmented.frame = CGRect(x: 100, y: 100, width: 200, height: 30)
        root.addSubview(segmented)
    }
    let viewSnapshotID = testViewSnapshotID(context: context)

    do {
        _ = try UIKitActionExecutor.execute(.tap(locator: .path([0]), viewSnapshotID: viewSnapshotID),
                                            context: context)
        Issue.record("expected unsupported_target, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .unsupportedTarget)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("executor tap 未签发 path(普通 UIView 非 canonical) 返回 not_actionable") @MainActor
func tapUnsignedPathReturnsNotActionable() {
    let context = UIKitTestHost.context { root in
        let view = UIView()
        view.frame = CGRect(x: 100, y: 100, width: 120, height: 60)
        view.isUserInteractionEnabled = true
        root.addSubview(view)
    }
    let viewSnapshotID = testViewSnapshotID(context: context)
    // 普通 UIView 非 canonical，collect 不为其签发指纹 → isPathSigned 返回 false → not_actionable。
    // 区分语义：stale_locator 表示"快照陈旧需重新 inspect 再观察"（如 id 过期、context 变化、
    // 指纹漂移）；not_actionable 表示"该 path 本就不是可操作目标（availableActions 为空）"，
    // 调用方应换目标而非重新观察。这是 Task 7 在 freshness 校验前前置 isPathSigned 的目的。

    do {
        _ = try UIKitActionExecutor.execute(.tap(locator: .path([0]), viewSnapshotID: viewSnapshotID),
                                            context: context)
        Issue.record("expected not_actionable, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .notActionable)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("executor tap 按钮 internal label(minimal) path 返回 not_actionable 且不激活父 button") @MainActor
func tapChildLabelPathReturnsNotActionable() {
    let context = UIKitTestHost.context { root in
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 100, y: 100, width: 120, height: 60)
        button.setTitle("提交", for: .normal)
        root.addSubview(button)
    }
    let viewSnapshotID = testViewSnapshotID(context: context)
    // collect 只签 canonical target（button root/0）；内部 label/image 在 root/0/0 等子节点是
    // minimal（未签发指纹）→ isPathSigned 返回 false → not_actionable。
    // 关键：绝不沿祖先 fallback 激活父 button——返回 not_actionable 而非激活父节点，
    // 因为 minimal 节点的 availableActions 为空，本就不是有效操作目标（语义比原 stale_locator
    // 更准确：调用方应换目标而非重新 inspect）。

    do {
        _ = try UIKitActionExecutor.execute(.tap(locator: .path([0, 0]), viewSnapshotID: viewSnapshotID),
                                            context: context)
        Issue.record("expected not_actionable, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .notActionable)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("executor control.sendAction minimal 节点(label 未签发) 返回 not_actionable") @MainActor
func sendActionMinimalNodeReturnsNotActionable() {
    let context = UIKitTestHost.context { root in
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 100, y: 100, width: 120, height: 60)
        button.setTitle("提交", for: .normal)
        root.addSubview(button)
    }
    let viewSnapshotID = testViewSnapshotID(context: context)
    // root/0/0 是 button 内部 label（minimal，未签发指纹）→ isPathSigned 返回 false → not_actionable。
    // 验证 isPathSigned 前置在 validateViewSnapshot 共用入口，覆盖 tap 与 control.sendAction 两条路径，
    // 而非只在 tap 分支生效。

    do {
        _ = try UIKitActionExecutor.execute(.controlEvent(locator: .path([0, 0]),
                                                           event: .touchUpInside,
                                                           viewSnapshotID: viewSnapshotID),
                                            context: context)
        Issue.record("expected not_actionable, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .notActionable)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("executor tap unknown viewSnapshotID 返回 stale_locator(非 not_actionable)") @MainActor
func tapUnknownViewSnapshotReturnsStaleLocator() {
    let context = UIKitTestHost.context { root in
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 100, y: 100, width: 120, height: 60)
        root.addSubview(button)
    }
    // isPathSigned 三态：unknown id（store 中无此 entry）→ 返回 true，交 isStale 裁决；
    // isStale 对 unknown id 返回 true → stale_locator。
    // 这保证 not_actionable 只在"id 有效但 path 确实未签发"时抛出，绝不把"传错 id / 过期 id"
    // 误判成 not_actionable——后者应引导调用方重新 inspect，而非放弃目标。

    do {
        _ = try UIKitActionExecutor.execute(.tap(locator: .path([0]), viewSnapshotID: "nonexistent-snapshot-id"),
                                            context: context)
        Issue.record("expected stale_locator, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .staleLocator)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("executor tap accessibilityIdentifier 携带 viewSnapshotID 走 freshness") @MainActor
func tapIdentifierRequiresFreshViewSnapshot() throws {
    let context = UIKitTestHost.context { root in
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = "submit"
        button.frame = CGRect(x: 100, y: 100, width: 120, height: 60)
        root.addSubview(button)
    }
    let viewSnapshotID = testViewSnapshotID(context: context)

    let data = try UIKitActionExecutor.execute(.tap(locator: .accessibilityIdentifier("submit"),
                                                    viewSnapshotID: viewSnapshotID),
                                               context: context)
    #expect(data["activationRoute"]?.stringValue == "control.touchUpInside")
}

@Test("executor tap 携带陈旧 viewSnapshotID(语义变化) 抛 stale_locator") @MainActor
func tapStaleViewSnapshotReturnsStaleLocator() {
    let context = UIKitTestHost.context { root in
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 100, y: 100, width: 120, height: 60)
        root.addSubview(button)
    }
    let viewSnapshotID = testViewSnapshotID(context: context)

    // 改按钮标题使 semanticDigest 变化（标题进 semanticDigest），即使 path/类型不变也判陈旧。
    (context.rootView.subviews.first as? UIButton)?.setTitle("删除", for: .normal)

    do {
        _ = try UIKitActionExecutor.execute(.tap(locator: .path([0]), viewSnapshotID: viewSnapshotID),
                                            context: context)
        Issue.record("expected stale_locator, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .staleLocator)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("executor control.sendAction 对 UIControl 返回 sent") @MainActor
func sendActionOnUIControlReturnsSent() throws {
    let context = UIKitTestHost.context { root in
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 100, y: 100, width: 120, height: 60)
        root.addSubview(button)
    }
    let viewSnapshotID = testViewSnapshotID(context: context)

    let data = try UIKitActionExecutor.execute(.controlEvent(locator: .path([0]),
                                                              event: .touchUpInside,
                                                              viewSnapshotID: viewSnapshotID),
                                               context: context)
    #expect(data["sent"]?.boolValue == true)
    #expect(data["event"]?.stringValue == "touchUpInside")
    #expect(data["type"]?.stringValue == "UIButton")
}

@Test("executor control.sendAction valueChanged 可设置 UISlider value") @MainActor
func sendActionSetsSliderValueBeforeValueChanged() throws {
    let context = UIKitTestHost.context { root in
        let slider = UISlider()
        slider.frame = CGRect(x: 100, y: 100, width: 200, height: 30)
        slider.value = 0.1
        root.addSubview(slider)
    }
    let viewSnapshotID = testViewSnapshotID(context: context)

    let data = try UIKitActionExecutor.execute(.controlEvent(locator: .path([0]),
                                                             event: .valueChanged,
                                                             value: .double(0.85),
                                                             viewSnapshotID: viewSnapshotID),
                                               context: context)

    let slider = try #require(context.rootView.subviews.first as? UISlider)
    #expect(data["sent"]?.boolValue == true)
    #expect(slider.value == Float(0.85))
}

@Test("executor control.sendAction valueChanged 可设置 UISegmentedControl selectedSegmentIndex") @MainActor
func sendActionSetsSegmentedControlSelectedIndexBeforeValueChanged() throws {
    let context = UIKitTestHost.context { root in
        let segmented = UISegmentedControl(items: ["一", "二", "三"])
        segmented.frame = CGRect(x: 100, y: 100, width: 240, height: 30)
        segmented.selectedSegmentIndex = 0
        root.addSubview(segmented)
    }
    let viewSnapshotID = testViewSnapshotID(context: context)

    let data = try UIKitActionExecutor.execute(.controlEvent(locator: .path([0]),
                                                             event: .valueChanged,
                                                             value: .double(2),
                                                             viewSnapshotID: viewSnapshotID),
                                               context: context)

    let segmented = try #require(context.rootView.subviews.first as? UISegmentedControl)
    #expect(data["sent"]?.boolValue == true)
    #expect(segmented.selectedSegmentIndex == 2)
}

@Test("executor control.sendAction valueChanged 可设置 UIStepper value") @MainActor
func sendActionSetsStepperValueBeforeValueChanged() throws {
    let context = UIKitTestHost.context { root in
        let stepper = UIStepper()
        stepper.frame = CGRect(x: 100, y: 100, width: 100, height: 32)
        stepper.minimumValue = 0
        stepper.maximumValue = 10
        stepper.value = 1
        root.addSubview(stepper)
    }
    let viewSnapshotID = testViewSnapshotID(context: context)

    let data = try UIKitActionExecutor.execute(.controlEvent(locator: .path([0]),
                                                             event: .valueChanged,
                                                             value: .double(4),
                                                             viewSnapshotID: viewSnapshotID),
                                               context: context)

    let stepper = try #require(context.rootView.subviews.first as? UIStepper)
    #expect(data["sent"]?.boolValue == true)
    #expect(stepper.value == 4)
}

@Test("executor control.sendAction valueChanged 可用 bool 设置 UISwitch isOn") @MainActor
func sendActionSetsSwitchValueFromBoolBeforeValueChanged() throws {
    let context = UIKitTestHost.context { root in
        let toggle = UISwitch()
        toggle.frame = CGRect(x: 100, y: 100, width: 51, height: 31)
        toggle.isOn = false
        root.addSubview(toggle)
    }
    let viewSnapshotID = testViewSnapshotID(context: context)

    let data = try UIKitActionExecutor.execute(.controlEvent(locator: .path([0]),
                                                             event: .valueChanged,
                                                             value: .bool(true),
                                                             viewSnapshotID: viewSnapshotID),
                                               context: context)

    let toggle = try #require(context.rootView.subviews.first as? UISwitch)
    #expect(data["sent"]?.boolValue == true)
    #expect(toggle.isOn == true)
}

@Test("executor control.sendAction valueChanged 可用 0 或 1 设置 UISwitch isOn") @MainActor
func sendActionSetsSwitchValueFromNumberBeforeValueChanged() throws {
    let context = UIKitTestHost.context { root in
        let toggle = UISwitch()
        toggle.frame = CGRect(x: 100, y: 100, width: 51, height: 31)
        toggle.isOn = true
        root.addSubview(toggle)
    }
    let viewSnapshotID = testViewSnapshotID(context: context)

    let data = try UIKitActionExecutor.execute(.controlEvent(locator: .path([0]),
                                                             event: .valueChanged,
                                                             value: .double(0),
                                                             viewSnapshotID: viewSnapshotID),
                                               context: context)

    let toggle = try #require(context.rootView.subviews.first as? UISwitch)
    #expect(data["sent"]?.boolValue == true)
    #expect(toggle.isOn == false)
}

@Test("executor control.sendAction 非 UIControl(canonical scrollView) 抛 invalid_data") @MainActor
func sendActionNonControlReturnsInvalidData() {
    let context = UIKitTestHost.context { root in
        let scrollView = UIScrollView()
        scrollView.frame = CGRect(x: 100, y: 100, width: 200, height: 200)
        root.addSubview(scrollView)
    }
    let viewSnapshotID = testViewSnapshotID(context: context)
    // scrollView 是 canonical（freshness 通过），但非 UIControl → controlTargetNotControl。

    do {
        _ = try UIKitActionExecutor.execute(.controlEvent(locator: .path([0]),
                                                           event: .touchUpInside,
                                                           viewSnapshotID: viewSnapshotID),
                                            context: context)
        Issue.record("expected failure, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .invalidData)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("executor control.sendAction UISwitch 不支持的 touchUpInside 抛 invalid_data") @MainActor
func sendActionUnsupportedEventReturnsInvalidData() {
    let context = UIKitTestHost.context { root in
        let toggle = UISwitch()
        toggle.frame = CGRect(x: 100, y: 100, width: 51, height: 31)
        root.addSubview(toggle)
    }
    let viewSnapshotID = testViewSnapshotID(context: context)
    // UISwitch 只声明 valueChanged，touchUpInside 不在其 availableActions。

    do {
        _ = try UIKitActionExecutor.execute(.controlEvent(locator: .path([0]),
                                                           event: .touchUpInside,
                                                           viewSnapshotID: viewSnapshotID),
                                            context: context)
        Issue.record("expected failure, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .invalidData)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}
#endif
