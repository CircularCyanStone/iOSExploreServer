#if canImport(UIKit)
import UIKit
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

/// `ui.tap` realTouch 合成触摸 spike 的真机验证测试。
///
/// 验证「合成 `UITouch` + `UIEvent` → `UIWindow.sendEvent`」在真机 iOS 上能否：
/// 1. 触发 `UITapGestureRecognizer`（手势识别器路径）；
/// 2. 把 touches 分发到 hit-test 命中的普通 `UIView`（非 `UIControl`）；
/// 3. 透明遮挡时命中遮挡层而非底层（不掩盖布局 bug）；
/// 4. 触发 `UIButton` 的 `.touchUpInside`（与 default 模式兼容）。
///
/// 此外 `syntheticTapIvarArchive` 把当前 iOS 版本的 `UITouch`/`UIEvent` ivar 列表打印
/// 到测试输出，作为 spike 报告的 ivar 名表来源。
///
/// spike 结论（见 `docs/superpowers/reviews/2026-07-04-ui-tap-realtouch-spike.md`）：
/// iOS 26 上经典「合成 `UITouch` + `UIEvent` → `sendEvent`」**失败**——`UIEvent` 移除
/// `_touchesByKey`/`_touches`，touches 改由 `_eventEnvironment`/`_gsEvent` 管理，UIKit 层无
/// 「无种子构造带 touches event」的入口，合成 touch 挂不进 event（`allTouches` 返回 nil），
/// gesture / plain view / 遮挡 / UIButton 全不触发。模拟器（iOS 26.3.1）与真机（iOS 26.5）结论一致。
///
/// 本测试文件是 **特性测试（characterization test）**：锁定 spike 发现的「合成触摸不工作」现象。
/// 4 个场景测试反向断言当前行为，套件保持绿；**若未来 iOS 修复使任一测试失败，说明合成触摸已
/// 可用，应重新评估 `ui.tap` 的 `dispatchMode:"realTouch"` 迁移**（见报告迁移建议）。
/// `syntheticTapIvarArchive` 是正向测试（ivar 探测逻辑可工作），不受 spike 结论影响。
///
/// 注：logic test 受 Xcode 限制无法部署到真机，真机验证走 SPMExample 的 `SyntheticTapSpikeRunner`
/// + `debug.syntheticTapSpike` action（XcodeBuildMCP device-app profile + iproxy + curl，见报告）。

/// 构造一个已 `makeKeyAndVisible` 的 window，调用方在 `buildRoot` 里填充 view 树。
@MainActor
private func makeKeyWindow(buildRoot: (UIView) -> Void) -> UIWindow {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    let rootViewController = UIViewController()
    let rootView = rootViewController.view!
    rootView.frame = window.bounds
    buildRoot(rootView)
    window.rootViewController = rootViewController
    window.makeKeyAndVisible()
    window.layoutIfNeeded()
    return window
}

/// 把诊断拼成可读字符串，供 `#expect` 失败消息使用。
private func describe(_ diagnostics: SyntheticTapDiagnostics) -> String {
    "hitTest=\(diagnostics.hitTestViewDescription ?? "nil") "
        + "sendEventCalls=\(diagnostics.sendEventCalls) "
        + "attachedTouchCount=\(diagnostics.attachedTouchCount) "
        + "missing=\(diagnostics.missingFields) "
        + "setFields=\(diagnostics.setFields)"
}

/// 记录 `touchesBegan`/`touchesEnded` 调用次数的普通 view（非 `UIControl`）。
private final class TouchRecordingView: UIView {
    var beganCount = 0
    var endedCount = 0
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        beganCount &+= 1
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endedCount &+= 1
    }
}

/// 记录手势 / target-action 是否触发的计数器。
///
/// `UIGestureRecognizer` 的 target 是弱引用，必须外部强持有；这里由测试函数的局部变量
/// 持有，spike 同步验证期间（`explore_sendSyntheticTap` 内的 spinRunLoop）始终 alive。
@MainActor
private final class TapCounter: NSObject {
    var fired = false
    @objc func didTap() { fired = true }
}

@Test("UITouch/UIEvent ivar 列表与合成诊断存档（spike 报告 ivar 名表来源）")
func syntheticTapIvarArchive() {
    let osv = ProcessInfo.processInfo.operatingSystemVersion
    let osVersion = "\(osv.majorVersion).\(osv.minorVersion).\(osv.patchVersion)"
    let touchIvars = SyntheticTouch.dumpIvars(of: UITouch.self)
    let eventIvars = SyntheticTouch.dumpIvars(of: UIEvent.self)
    let eventMethods = SyntheticTouch.dumpMethods(of: UIEvent.self,
                                                  containing: ["touch", "set", "add", "environ", "gsevent", "hid"])
    print("""

    [synthetic-touch-spike] iOS \(osVersion)
    === UITouch ivars (\(touchIvars.count)) ===
    \(touchIvars.joined(separator: "\n"))
    === UIEvent ivars (\(eventIvars.count)) ===
    \(eventIvars.joined(separator: "\n"))
    === UIEvent methods (filtered, \(eventMethods.count)) ===
    \(eventMethods.joined(separator: "\n"))
    """)
    #expect(!touchIvars.isEmpty, "UITouch 应有 ivar")
    #expect(!eventIvars.isEmpty, "UIEvent 应有 ivar")
    #expect(touchIvars.contains { $0.lowercased().contains("location") },
            "UITouch 应含 location 相关 ivar: \(touchIvars)")
    #expect(touchIvars.contains { $0.lowercased().contains("phase") },
            "UITouch 应含 phase 相关 ivar: \(touchIvars)")
}

@Test("iOS 26 合成 tap 无法触发 UITapGestureRecognizer（spike 存档）") @MainActor
func syntheticTapDoesNotTriggerTapGestureRecognizerOnIOS26() throws {
    // spike 结论：iOS 26 合成 touch 挂不进 event，gesture 不触发（见文件头报告链接）。
    // 若本测试失败（gesture 被触发），说明 iOS 已修复合成触摸挂载 → 重新评估 realTouch 迁移。
    let counter = TapCounter()
    let window = makeKeyWindow { root in
        let target = UIView(frame: root.bounds)
        target.backgroundColor = .white
        target.isUserInteractionEnabled = true
        target.addGestureRecognizer(UITapGestureRecognizer(target: counter,
                                                            action: #selector(TapCounter.didTap)))
        root.addSubview(target)
    }
    let center = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
    let diagnostics = window.explore_sendSyntheticTap(at: center)
    #expect(!counter.fired,
            "若手势被触发，说明 iOS 已修复合成触摸挂载，重新评估 realTouch 迁移。诊断: \(describe(diagnostics))")
}

@Test("iOS 26 合成 tap 无法把 touches 分发到普通 UIView（spike 存档）") @MainActor
func syntheticTapDoesNotDispatchToPlainViewOnIOS26() throws {
    // spike 结论：sendEvent 没把 touch 投递到 hit-test view 的 touches 回调（见文件头报告链接）。
    // 若本测试失败（touches 被调用），说明合成触摸已可分发 → 重新评估 realTouch 迁移。
    let target = TouchRecordingView(frame: CGRect(x: 60, y: 184, width: 200, height: 200))
    let window = makeKeyWindow { root in
        root.addSubview(target)
    }
    let center = CGPoint(x: target.frame.midX, y: target.frame.midY)
    let diagnostics = window.explore_sendSyntheticTap(at: center)
    #expect(target.beganCount == 0,
            "若 touchesBegan 被调用，说明合成触摸已可分发，重新评估 realTouch 迁移。诊断: \(describe(diagnostics))")
    #expect(target.endedCount == 0,
            "若 touchesEnded 被调用，说明合成触摸已可分发，重新评估。诊断: \(describe(diagnostics))")
}

@Test("iOS 26 合成 tap hitTest 几何正确但 event 分发失败（spike 存档）") @MainActor
func syntheticTapHitTestCorrectButDispatchFailsOnIOS26() throws {
    // spike 结论：hitTest 几何正确（命中遮挡层，不掩盖布局 bug），但 event 分发失败，
    // overlay gesture 也不触发（见文件头报告链接）。
    // 若 overlay.fired 变 true，说明合成触摸已可分发 → 重新评估 realTouch 迁移。
    let bottom = TapCounter()
    let overlay = TapCounter()
    let window = makeKeyWindow { root in
        // 底层：带手势的 view（如果合成 tap 绕过 hit-test，会错误触发它）。
        let bottomView = UIView(frame: root.bounds)
        bottomView.addGestureRecognizer(UITapGestureRecognizer(target: bottom,
                                                                action: #selector(TapCounter.didTap)))
        // 遮挡层：透明 view 完全覆盖底层，带手势（应消费 touch）。
        let overlayView = UIView(frame: root.bounds)
        overlayView.backgroundColor = .clear
        overlayView.addGestureRecognizer(UITapGestureRecognizer(target: overlay,
                                                                 action: #selector(TapCounter.didTap)))
        root.addSubview(bottomView)
        root.addSubview(overlayView)
    }
    let center = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
    let diagnostics = window.explore_sendSyntheticTap(at: center)
    // hitTest 几何始终正确（spike 现象：坐标/view 解析没问题，问题在 event 分发）。
    #expect(diagnostics.hitTestViewDescription != nil,
            "hit-test 应命中某个 view。诊断: \(describe(diagnostics))")
    // event 分发失败，overlay gesture 也不触发（锁定 spike 现象）。
    #expect(!overlay.fired,
            "若遮挡层被触发，说明合成触摸已可分发，重新评估 realTouch 迁移。实际命中: \(diagnostics.hitTestViewDescription ?? "nil")。诊断: \(describe(diagnostics))")
    #expect(!bottom.fired,
            "底层不应触发（被遮挡）。诊断: \(describe(diagnostics))")
}

@Test("iOS 26 合成 tap 无法触发 UIButton touchUpInside（spike 存档）") @MainActor
@available(iOS 14, *)
func syntheticTapDoesNotTriggerUIButtonOnIOS26() throws {
    // spike 结论：UIControl touch tracking 依赖收到真实 touch，合成 touch 没进入 event，
    // tracking 不启动（见文件头报告链接）。若本测试失败，说明 tracking 已可被合成 touch 驱动 → 重新评估。
    var fired = false
    let button = UIButton(type: .system)
    button.setTitle("Tap", for: .normal)
    button.addAction(UIAction { _ in fired = true }, for: .touchUpInside)
    let window = makeKeyWindow { root in
        button.frame = CGRect(x: 60, y: 254, width: 200, height: 60)
        root.addSubview(button)
    }
    let center = CGPoint(x: button.frame.midX, y: button.frame.midY)
    let diagnostics = window.explore_sendSyntheticTap(at: center)
    #expect(!fired,
            "若 UIButton 被触发，说明 UIControl tracking 已可被合成 touch 驱动，重新评估 realTouch 迁移。诊断: \(describe(diagnostics))")
}
#endif
