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

/// 取一次 `ui.viewTargets` 签发的 viewSnapshotID，供交互命令携带做 freshness 校验。
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
        #expect(error.failure.code == .invalidData)
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
        #expect(error.failure.code == .invalidData)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("executor tap 普通 UIView(非 canonical) 抛 stale_locator") @MainActor
func tapPlainViewReturnsStaleLocator() {
    let context = UIKitTestHost.context { root in
        let view = UIView()
        view.frame = CGRect(x: 100, y: 100, width: 120, height: 60)
        view.isUserInteractionEnabled = true
        root.addSubview(view)
    }
    let viewSnapshotID = testViewSnapshotID(context: context)
    // 普通 UIView 非 canonical，未被签发 → freshness 校验 path missing → stale_locator。

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

@Test("executor tap 按钮 internal label path 不激活父 button") @MainActor
func tapChildLabelPathDoesNotActivateParentButton() {
    let context = UIKitTestHost.context { root in
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 100, y: 100, width: 120, height: 60)
        button.setTitle("提交", for: .normal)
        root.addSubview(button)
    }
    let viewSnapshotID = testViewSnapshotID(context: context)
    // collect 只签 canonical target（button root/0）；内部 label/image 在 root/0/0 等子节点
    // 未被签发 → tap 子 path 应 stale_locator，绝不沿祖先 fallback 激活父 button。

    do {
        _ = try UIKitActionExecutor.execute(.tap(locator: .path([0, 0]), viewSnapshotID: viewSnapshotID),
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
