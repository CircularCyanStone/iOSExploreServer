#if canImport(UIKit)
import UIKit
import ObjectiveC
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

/// `UIGestureRecognizer` target-action runtime 读取的 ivar 存档 + 正向验证测试。
///
/// 手势 adapter（`UIGestureRecognizer+Trigger.explore_targetActionPairs()`）依赖 UIKit 私有
/// ivar：`UIGestureRecognizer._targets`（`UIGestureRecognizerTarget*` 数组）+ 每个 targetBox 的
/// `_target`（目标对象）与 `_action`（SEL）。本文件做两件事：
///
/// 1. **ivar 名表存档**：`gestureRecognizerIvarArchive` dump 当前 iOS 版本的 `UIGestureRecognizer`/
///    `UITapGestureRecognizer` ivar 列表，并在 `gestureTargetActionPairsReadAndArchive` 里 dump
///    私有 `UIGestureRecognizerTarget` 的 ivar——作为手势 adapter 报告 ivar 名表来源，并正向
///    断言 `_targets`/`_target`/`_action` 在当前版本仍存在（候选名命中）。
/// 2. **读取闭环验证**：构造带 `UITapGestureRecognizer` 的 view，调用
///    `explore_targetActionPairs()`，断言读出的 target 与 action 与注册时一致（C API 读取链
///    `class_getInstanceVariable` + `ivar_getOffset` + 裸内存 load 真正工作）。
///
/// 与 `UITouchSyntheticSpikeTests` 的区别：本文件是**正向测试**（验证手势 adapter 读取链可工作），
/// 不是反向特性测试。若未来 iOS 改这三个 ivar 名，`_targets`/`_target`/`_action` 断言失败 →
/// 往 `GestureTargetField` 补候选名（见手势 adapter 报告）。

/// 记录手势 target-action 触发的计数器。
///
/// `UIGestureRecognizer` 的 target 是弱引用，必须外部强持有；这里由测试函数的局部变量持有。
@MainActor
private final class GestureTapCounter: NSObject {
    var firedCount = 0
    @objc func didTap() { firedCount &+= 1 }
    @objc func didTapWithSender(_ sender: AnyObject) { firedCount &+= 1 }
    @objc func didTapWithEvent(_ sender: AnyObject, forEvent event: UIEvent?) { firedCount &+= 1 }
}

@Test("UIGestureRecognizer ivar 列表存档（手势 adapter 报告 ivar 名表来源）")
func gestureRecognizerIvarArchive() {
    let osv = ProcessInfo.processInfo.operatingSystemVersion
    let osVersion = "\(osv.majorVersion).\(osv.minorVersion).\(osv.patchVersion)"
    let grIvars = SyntheticTouch.dumpIvars(of: UIGestureRecognizer.self)
    let tapIvars = SyntheticTouch.dumpIvars(of: UITapGestureRecognizer.self)
    print("""

    [gesture-adapter-spike] iOS \(osVersion)
    === UIGestureRecognizer ivars (\(grIvars.count)) ===
    \(grIvars.joined(separator: "\n"))
    === UITapGestureRecognizer ivars (\(tapIvars.count)) ===
    \(tapIvars.joined(separator: "\n"))
    """)
    #expect(!grIvars.isEmpty, "UIGestureRecognizer 应有 ivar")
    // _targets 是手势 adapter 读取链的根 ivar；候选名 _targets/targets 至少命中一个。
    #expect(grIvars.contains { $0.contains("_targets") || $0.contains(".targets") },
            "UIGestureRecognizer 应含 _targets ivar: \(grIvars)")
}

@Test("explore_targetActionPairs 读出注册的 target-action（正向）+ targetBox ivar 存档") @MainActor
func gestureTargetActionPairsReadAndArchive() {
    let osv = ProcessInfo.processInfo.operatingSystemVersion
    let osVersion = "\(osv.majorVersion).\(osv.minorVersion).\(osv.patchVersion)"
    let counter = GestureTapCounter()
    let view = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    let recognizer = UITapGestureRecognizer(target: counter, action: #selector(GestureTapCounter.didTap))
    view.addGestureRecognizer(recognizer)

    // 读取闭环：runtime 读 _targets → targetBox._target + _action。
    let pairs = recognizer.explore_targetActionPairs()
    #expect(pairs.count == 1, "应读出 1 对 target-action，实际: \(pairs.count)")
    #expect(pairs.first?.target === counter, "target 应是注册的 counter")
    #expect(pairs.first?.action == #selector(GestureTapCounter.didTap), "action 应是 didTap")

    // targetBox ivar 存档：inline 读 _targets 拿首个 targetBox，dump 私有类 ivar 名表。
    var boxIvars: [String] = []
    var boxClassName = "<unresolved>"
    if let targetsIvar = class_getInstanceVariable(UIGestureRecognizer.self, "_targets") {
        let offset = ivar_getOffset(targetsIvar)
        let basePtr = Unmanaged.passUnretained(recognizer).toOpaque()
        if let arrayRef = basePtr.advanced(by: offset).load(as: AnyObject?.self) as? NSArray,
           let box = arrayRef.firstObject as? AnyObject {
            boxClassName = NSStringFromClass(type(of: box))
            boxIvars = SyntheticTouch.dumpIvars(of: type(of: box))
        }
    }
    print("""

    [gesture-adapter-spike] iOS \(osVersion)
    === \(boxClassName) ivars (\(boxIvars.count)) ===
    \(boxIvars.joined(separator: "\n"))
    === explore_targetActionPairs result ===
    count=\(pairs.count) target=\(pairs.first.map { NSStringFromClass(type(of: $0.target)) } ?? "nil") action=\(pairs.first.map { NSStringFromSelector($0.action) } ?? "nil")
    """)
    // 私有 targetBox 应含 _target / _action ivar（候选名命中）。
    #expect(boxIvars.contains { $0.contains("_target") || $0.contains(".target") },
            "UIGestureRecognizerTarget 应含 _target ivar: \(boxIvars)")
    #expect(boxIvars.contains { $0.contains("_action") || $0.contains(".action") },
            "UIGestureRecognizerTarget 应含 _action ivar: \(boxIvars)")
}
#endif
