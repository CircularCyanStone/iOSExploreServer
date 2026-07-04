#if canImport(UIKit)
import UIKit
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

/// `ui.tap` 手势 target-action adapter（`UIGestureTargetExecutor` + `executeTap` 手势分支）的运行时测试。
///
/// 通过 `UIKitTestHost` 注入挂有 `UIGestureRecognizer` 的 view 树，先 `UIViewTargetsCollector.collect`
/// 签发 `viewSnapshotID`（带 gesture 的 view 是 canonical target，会被签发），再驱动 executor 的
/// locate / freshness / 手势 adapter 派发。覆盖：基础 1 参 action 触发、0/1/2 参签名适配、多 gesture
/// 全触发、单 gesture 多 target 全触发、target 已 dealloc 时安全降级到 `unsupported_target`。
///
/// 与 `UIKitActionExecutorTests` 的关系：那批测试覆盖 default 三路（button/switch/input）+
/// 无路由目标 unsupported；本批专测手势 adapter 补充分支，并验证 default 三路零回归（手势 adapter
/// 只在 default route nil 时介入）。
///
/// 注意：UIGestureRecognizer 的 target 是弱引用（与 UIControl 一致），target 必须由测试函数
/// 局部变量强持有，setup 闭包捕获后跨 `testViewSnapshotID` / `execute` 调用仍 alive。

/// 手势 target：记录触发次数，提供 0/1/2 参三种 action 签名供签名派发测试。
@MainActor
private final class GestureTarget: NSObject {
    var firedCount = 0
    @objc func actionZero() { firedCount &+= 1 }
    @objc func actionOne(_ sender: AnyObject) { firedCount &+= 1 }
    @objc func actionTwo(_ sender: AnyObject, forEvent event: UIEvent?) { firedCount &+= 1 }
}

/// 取一次 `ui.viewTargets` 签发的 viewSnapshotID，供 `ui.tap` 携带做 freshness 校验。
@MainActor
private func testViewSnapshotID(context: UIKitContextProvider.Context) -> String {
    let data = UIViewTargetsCollector.collect(query: .default, context: context)
    guard let id = data["viewSnapshotID"]?.stringValue else {
        Issue.record("collect should produce viewSnapshotID")
        return ""
    }
    return id
}

@Test("executor tap 带 UITapGestureRecognizer 的 view 走手势 adapter 触发 1 参 action") @MainActor
func tapGestureViewTriggersOneArgAction() throws {
    let target = GestureTarget()
    let context = UIKitTestHost.context { root in
        let view = UIView(frame: CGRect(x: 10, y: 10, width: 200, height: 200))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(UITapGestureRecognizer(target: target, action: #selector(GestureTarget.actionOne(_:))))
        root.addSubview(view)
    }
    let viewSnapshotID = testViewSnapshotID(context: context)

    let data = try UIKitActionExecutor.execute(.tap(locator: .path([0]), viewSnapshotID: viewSnapshotID),
                                               context: context)

    #expect(data["activated"]?.boolValue == true)
    #expect(data["activationRoute"]?.stringValue == "gesture.targetAction")
    #expect(data["type"]?.stringValue == "UIView")
    #expect(data["path"]?.stringValue == "root/0")
    #expect(data["triggeredCount"]?.doubleValue == 1)
    #expect(target.firedCount == 1, "1 参 action 应被触发一次")
    // gestures 数组结构：每个元素含 gestureType / targetType / action。
    let gestures = data["gestures"]?.arrayValue
    #expect(gestures?.count == 1)
    let first = gestures?.first?.objectValue
    #expect(first?["gestureType"]?.stringValue == "UITapGestureRecognizer")
    #expect(first?["targetType"]?.stringValue == "GestureTarget")
    #expect(first?["action"]?.stringValue == "actionOne:")
}

@Test("executor tap 手势 0 参 action 按无参派发") @MainActor
func tapGestureZeroArgumentActionTriggers() throws {
    let target = GestureTarget()
    let context = UIKitTestHost.context { root in
        let view = UIView(frame: CGRect(x: 10, y: 10, width: 200, height: 200))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(UITapGestureRecognizer(target: target, action: #selector(GestureTarget.actionZero)))
        root.addSubview(view)
    }
    let viewSnapshotID = testViewSnapshotID(context: context)

    let data = try UIKitActionExecutor.execute(.tap(locator: .path([0]), viewSnapshotID: viewSnapshotID),
                                               context: context)

    #expect(data["activationRoute"]?.stringValue == "gesture.targetAction")
    #expect(target.firedCount == 1, "0 参 action（func action()）应按 method_getNumberOfArguments=2 走无参派发")
}

@Test("executor tap 手势 2 参 action(_:forEvent:) 按两参派发") @MainActor
func tapGestureTwoArgumentActionTriggers() throws {
    let target = GestureTarget()
    let context = UIKitTestHost.context { root in
        let view = UIView(frame: CGRect(x: 10, y: 10, width: 200, height: 200))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(UITapGestureRecognizer(target: target, action: #selector(GestureTarget.actionTwo(_:forEvent:))))
        root.addSubview(view)
    }
    let viewSnapshotID = testViewSnapshotID(context: context)

    let data = try UIKitActionExecutor.execute(.tap(locator: .path([0]), viewSnapshotID: viewSnapshotID),
                                               context: context)

    #expect(data["activationRoute"]?.stringValue == "gesture.targetAction")
    #expect(target.firedCount == 1, "2 参 action（func action(_:forEvent:)）应按 method_getNumberOfArguments=4 走两参派发，event 传 nil")
}

@Test("executor tap 多 gesture 的 view 全部触发（tap + longPress）") @MainActor
func tapViewWithMultipleGesturesTriggersAll() throws {
    let target = GestureTarget()
    let context = UIKitTestHost.context { root in
        let view = UIView(frame: CGRect(x: 10, y: 10, width: 200, height: 200))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(UITapGestureRecognizer(target: target, action: #selector(GestureTarget.actionOne(_:))))
        view.addGestureRecognizer(UILongPressGestureRecognizer(target: target, action: #selector(GestureTarget.actionOne(_:))))
        root.addSubview(view)
    }
    let viewSnapshotID = testViewSnapshotID(context: context)

    let data = try UIKitActionExecutor.execute(.tap(locator: .path([0]), viewSnapshotID: viewSnapshotID),
                                               context: context)

    // 全触发决策：adapter 不知道调用方意图，view 上所有 gesture 的所有 target-action 都派发。
    #expect(data["triggeredCount"]?.doubleValue == 2)
    #expect(target.firedCount == 2, "tap + longPress 两个手势的 action 都应触发")
    let types = data["gestures"]?.arrayValue?.compactMap { $0.objectValue?["gestureType"]?.stringValue }
    #expect(types?.contains("UITapGestureRecognizer") == true)
    #expect(types?.contains("UILongPressGestureRecognizer") == true)
}

@Test("executor tap 单 gesture 多 target 全部触发") @MainActor
func tapGestureWithMultipleTargetsTriggersAll() throws {
    let target1 = GestureTarget()
    let target2 = GestureTarget()
    let context = UIKitTestHost.context { root in
        let view = UIView(frame: CGRect(x: 10, y: 10, width: 200, height: 200))
        view.isUserInteractionEnabled = true
        let gesture = UITapGestureRecognizer(target: target1, action: #selector(GestureTarget.actionOne(_:)))
        gesture.addTarget(target2, action: #selector(GestureTarget.actionOne(_:)))
        view.addGestureRecognizer(gesture)
        root.addSubview(view)
    }
    let viewSnapshotID = testViewSnapshotID(context: context)

    let data = try UIKitActionExecutor.execute(.tap(locator: .path([0]), viewSnapshotID: viewSnapshotID),
                                               context: context)

    #expect(data["triggeredCount"]?.doubleValue == 2)
    #expect(target1.firedCount == 1)
    #expect(target2.firedCount == 1)
}

@Test("executor tap gesture 的 target 已 dealloc 时安全降级到 unsupported_target") @MainActor
func tapGestureWithDeallocatedTargetFallsThroughToUnsupported() {
    // UIGestureRecognizer 的 target 是弱引用（与 UIControl 一致）：释放外部强引用后，私有
    // `_target` ivar 被 runtime 自动 nilify。adapter 用 C API 读出 nil 跳过该 pair，不 crash，
    // 最终 0 pair → fallthrough 到 unsupported_target。
    var targetHolder: GestureTarget? = GestureTarget()
    let context = UIKitTestHost.context { root in
        let view = UIView(frame: CGRect(x: 10, y: 10, width: 200, height: 200))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(UITapGestureRecognizer(target: targetHolder!, action: #selector(GestureTarget.actionOne(_:))))
        root.addSubview(view)
    }
    targetHolder = nil
    let viewSnapshotID = testViewSnapshotID(context: context)

    do {
        _ = try UIKitActionExecutor.execute(.tap(locator: .path([0]), viewSnapshotID: viewSnapshotID),
                                            context: context)
        Issue.record("expected unsupported_target after target dealloc, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .unsupportedTarget,
               "target dealloc 后读出 0 pair，应 fallthrough 到 unsupported_target 而非 crash 或假成功")
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}
#endif
