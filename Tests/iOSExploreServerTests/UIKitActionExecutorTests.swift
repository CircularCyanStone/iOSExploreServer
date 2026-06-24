#if canImport(UIKit)
import UIKit
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

/// `UIKitActionExecutor` 全派发路径的运行时测试。
///
/// 通过 `UIKitTestHost` 注入可控 view 树，真实驱动 executor 的 locate / hit-test /
/// capability / sendActions / 陈旧校验，补齐此前零运行时覆盖的执行核心——这正是问题 #1 这类
/// "零件都对、组装分叉"bug 能潜伏的盲区。
///
/// 注意：logic test 下 `UIControl.sendActions` 不派发 target-action（无 app runloop），故这些
/// 测试验证的是 executor 自身逻辑（走到 sendActions、命中正确 control、返回正确 JSON 或
/// 抛出对应错误码），而非 UIKit 的派发效果。
///
/// executor 已 throw 化：成功路径返回纯 `JSON`，失败路径 `throw UIKitCommandError`，故成功
/// 测试用 `try` 直取 JSON，失败测试用 do/catch 断言 `error.failure.code`。

@Test("executor 按 path tap 可交互 UIControl 走 controlActionFallback") @MainActor
func executorTapsUIControlByPath() throws {
    let context = UIKitTestHost.context { root in
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 100, y: 100, width: 120, height: 60)
        root.addSubview(button)
    }

    let data = try UIKitActionExecutor.execute(.tap(locator: .path([0]), snapshotID: nil),
                                               context: context)

    #expect(data["tapped"]?.boolValue == true)
    #expect(data["dispatchMode"]?.stringValue == "controlActionFallback")
    #expect(data["event"]?.stringValue == "touchUpInside")
    #expect(data["controlType"]?.stringValue == "UIButton")
    #expect(data["controlPath"]?.stringValue == "root/0")
}

@Test("executor tap 按 accessibilityIdentifier 命中 UIControl") @MainActor
func executorTapsUIControlByIdentifier() throws {
    let context = UIKitTestHost.context { root in
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 100, y: 100, width: 120, height: 60)
        button.accessibilityIdentifier = "submit"
        root.addSubview(button)
    }

    let data = try UIKitActionExecutor.execute(.tap(locator: .accessibilityIdentifier("submit"), snapshotID: nil),
                                               context: context)

    #expect(data["controlType"]?.stringValue == "UIButton")
}

@Test("executor tap 非 control 可交互 view 抛 invalid_data") @MainActor
func executorTapNonControlReturnsInvalidData() {
    let context = UIKitTestHost.context { root in
        let view = UIView()
        view.frame = CGRect(x: 100, y: 100, width: 120, height: 60)
        view.isUserInteractionEnabled = true
        root.addSubview(view)
    }

    do {
        _ = try UIKitActionExecutor.execute(.tap(locator: .path([0]), snapshotID: nil),
                                            context: context)
        Issue.record("expected failure, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .invalidData)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("executor tap window 坐标命中 UIControl") @MainActor
func executorTapWindowPointHitsControl() throws {
    let context = UIKitTestHost.context { root in
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 100, y: 100, width: 120, height: 60)
        root.addSubview(button)
    }

    // button 中心在 window 坐标 (160, 130)
    let data = try UIKitActionExecutor.execute(.tap(locator: .windowPoint(x: 160, y: 130), snapshotID: nil),
                                               context: context)

    #expect(data["controlType"]?.stringValue == "UIButton")
    #expect(data["dispatchMode"]?.stringValue == "controlActionFallback")
}

@Test("executor control.sendAction 对 UIControl 返回 sent") @MainActor
func executorControlSendActionOnUIControl() throws {
    let context = UIKitTestHost.context { root in
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 100, y: 100, width: 120, height: 60)
        root.addSubview(button)
    }

    let data = try UIKitActionExecutor.execute(.controlEvent(locator: .path([0]),
                                                              event: .touchUpInside,
                                                              snapshotID: nil),
                                               context: context)

    #expect(data["sent"]?.boolValue == true)
    #expect(data["event"]?.stringValue == "touchUpInside")
    #expect(data["type"]?.stringValue == "UIButton")
}

@Test("executor control.sendAction 非 UIControl 抛 invalid_data") @MainActor
func executorControlSendActionNonControlReturnsInvalidData() {
    let context = UIKitTestHost.context { root in
        let view = UIView()
        view.frame = CGRect(x: 100, y: 100, width: 120, height: 60)
        root.addSubview(view)
    }

    do {
        _ = try UIKitActionExecutor.execute(.controlEvent(locator: .path([0]),
                                                           event: .touchUpInside,
                                                           snapshotID: nil),
                                            context: context)
        Issue.record("expected failure, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .invalidData)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("executor control.sendAction 不支持的事件抛 invalid_data") @MainActor
func executorControlSendActionUnsupportedEventReturnsInvalidData() {
    let context = UIKitTestHost.context { root in
        let toggle = UISwitch()
        toggle.frame = CGRect(x: 100, y: 100, width: 51, height: 31)
        root.addSubview(toggle)
    }

    // UISwitch 只声明 valueChanged，touchUpInside 不在其 availableActions
    do {
        _ = try UIKitActionExecutor.execute(.controlEvent(locator: .path([0]),
                                                           event: .touchUpInside,
                                                           snapshotID: nil),
                                            context: context)
        Issue.record("expected failure, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .invalidData)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("executor path tap 携带陈旧 snapshotID 抛 invalid_data") @MainActor
func executorTapStaleSnapshotReturnsInvalidData() {
    let context = UIKitTestHost.context { root in
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 100, y: 100, width: 120, height: 60)
        root.addSubview(button)
    }

    let data = UIViewTargetsCollector.collect(query: .default, context: context)
    guard let snapshotID = data["snapshotID"]?.stringValue else {
        Issue.record("collect should produce snapshotID")
        return
    }

    // 改变 button 的 enabled 状态使指纹陈旧（isEnabled 进入指纹）
    (context.rootView.subviews.first as? UIButton)?.isEnabled = false

    do {
        _ = try UIKitActionExecutor.execute(.tap(locator: .path([0]), snapshotID: snapshotID),
                                            context: context)
        Issue.record("expected failure, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .invalidData)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}
#endif
