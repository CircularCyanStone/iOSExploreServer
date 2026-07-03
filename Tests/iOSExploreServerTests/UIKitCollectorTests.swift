#if canImport(UIKit)
import UIKit
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

/// `UIViewTargetsCollector` 与 `UIViewHierarchyCollector` 的端到端测试（Task 4/8 重构后）。
///
/// 通过 `UIKitTestHost` 注入可控 view 树，验证采集器整条流水线（遍历 → canonical 筛选 →
/// 生成摘要/树 → 只对返回 target 签发 viewSnapshotID）。重构后 `ui.viewTargets` 只输出
/// canonical interaction target（UIControl / UIScrollView 系），普通 identifier/label view
/// 不再进入 targets（其观察职责在 `ui.topViewHierarchy`）。

@Test("viewTargets 只采集 canonical target 并签发 viewSnapshotID") @MainActor
func viewTargetsCollectsCanonicalTargetsOnly() {
    let context = UIKitTestHost.context { root in
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = "submit"
        button.frame = CGRect(x: 10, y: 10, width: 80, height: 40)
        root.addSubview(button) // root/0 button（canonical）

        let tagged = UIView()
        tagged.accessibilityIdentifier = "banner"
        tagged.frame = CGRect(x: 10, y: 60, width: 80, height: 20)
        root.addSubview(tagged) // root/1 普通 view（有 identifier，但非 canonical → 不采集）

        let plain = UIView(frame: CGRect(x: 0, y: 100, width: 100, height: 50))
        root.addSubview(plain) // root/2 plain（非 canonical → 不采集）
    }

    let data = UIViewTargetsCollector.collect(query: .default, context: context)
    // canonical-only：只有 button（UIControl）被采集；tagged(仅 identifier)/plain 不再进入。
    #expect(data["targetCount"]?.doubleValue == 1)
    #expect(data["truncated"]?.boolValue == false)
    #expect(data["viewSnapshotID"]?.stringValue != nil)
    #expect(data["snapshotID"] == nil)

    guard case .array(let targets)? = data["targets"] else {
        Issue.record("targets not array")
        return
    }
    #expect(targets.count == 1)

    guard case .object(let buttonTarget) = targets[0] else {
        Issue.record("button target not object")
        return
    }
    #expect(buttonTarget["path"]?.stringValue == "root/0")
    #expect(buttonTarget["role"]?.stringValue == "button")
    guard case .array(let buttonActions)? = buttonTarget["availableActions"] else {
        Issue.record("button availableActions not array")
        return
    }
    #expect(buttonActions.isEmpty == false)
}

@Test("viewTargets 签发的指纹集合等于返回的 target path 集合") @MainActor
func viewTargetsSignsFingerprintsForReturnedPathsOnly() throws {
    // 不变式：returned target paths == viewSnapshotID 签发 fingerprint paths == tap/sendAction 可执行集合。
    // 用 maxTargets 截断验证：两个 button 但 maxTargets=1，只返回/签发 1 个，第 2 个 path 视为 stale。
    let context = UIKitTestHost.context { root in
        let button1 = UIButton(type: .system)
        button1.frame = CGRect(x: 10, y: 10, width: 80, height: 40)
        root.addSubview(button1)

        let button2 = UIButton(type: .system)
        button2.frame = CGRect(x: 10, y: 60, width: 80, height: 40)
        root.addSubview(button2)
    }

    let query = UIViewTargetsInput(maxTargets: 1)
    let data = UIViewTargetsCollector.collect(query: query, context: context)
    #expect(data["targetCount"]?.doubleValue == 1)
    #expect(data["truncated"]?.boolValue == true)
    guard let viewSnapshotID = data["viewSnapshotID"]?.stringValue else {
        Issue.record("viewSnapshotID should be signed")
        return
    }

    // 返回的第 1 个 button path（root/0）应 freshness 通过；未返回的第 2 个（root/1）应 stale。
    let snapContext = UIKitFingerprintCollector.context(window: context.window,
                                                         topViewController: context.topViewController)
    let digest = UIKitFingerprintCollector.digest(topViewController: context.topViewController)
    let firstFp = UIKitFingerprintCollector.fingerprint(for: context.rootView.subviews[0],
                                                         path: "root/0",
                                                         rootView: context.rootView,
                                                         digest: digest)
    let secondFp = UIKitFingerprintCollector.fingerprint(for: context.rootView.subviews[1],
                                                          path: "root/1",
                                                          rootView: context.rootView,
                                                          digest: digest)
    #expect(UIKitSnapshotStore.shared.isStale(viewSnapshotID: viewSnapshotID, path: "root/0", context: snapContext, current: firstFp) == false)
    #expect(UIKitSnapshotStore.shared.isStale(viewSnapshotID: viewSnapshotID, path: "root/1", context: snapContext, current: secondFp))
}

@Test("viewTargets 把按钮语义文本汇总到 canonical target") @MainActor
func viewTargetsAggregatesButtonSemanticText() throws {
    let context = UIKitTestHost.context { root in
        let button = UIButton(type: .system)
        button.setTitle("提交订单", for: .normal)
        button.accessibilityIdentifier = "checkout.submit"
        button.frame = CGRect(x: 10, y: 10, width: 120, height: 40)
        root.addSubview(button)
    }

    let data = UIViewTargetsCollector.collect(query: .default, context: context)
    guard case .array(let targets)? = data["targets"], case .object(let buttonTarget)? = targets.first else {
        Issue.record("button target missing")
        return
    }
    // 按钮内部 label 不作为独立 target；其标题汇总到父 button 的 semanticText。
    #expect(buttonTarget["semanticText"]?.stringValue == "提交订单")
}

@Test("topViewHierarchy 采集注入 view 树的层级结构（不签发 viewSnapshotID）") @MainActor
func topViewHierarchyCollectsTreeInContext() throws {
    let context = UIKitTestHost.context { root in
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = "submit"
        button.frame = CGRect(x: 10, y: 10, width: 80, height: 40)
        root.addSubview(button)
    }

    let query = try UIViewHierarchyInput.parse(from: [:])

    let data = UIViewHierarchyCollector.collectTopViewHierarchy(query: query, context: context)
    // topViewHierarchy 不签发 viewSnapshotID（spec §1.2：只有 ui.viewTargets 签发）。
    #expect(data["viewSnapshotID"] == nil)
    #expect(data["snapshotID"] == nil)

    guard case .object(let root)? = data["root"] else {
        Issue.record("root not object")
        return
    }
    guard case .array(let subviews)? = root["subviews"] else {
        Issue.record("subviews not array")
        return
    }
    #expect(subviews.count == 1)
    guard case .object(let buttonNode) = subviews[0] else {
        Issue.record("button node not object")
        return
    }
    // UIButton(type:.system) 在不同 iOS 可能是 UIButton 的私有子类，故只校验类型名含 "Button"
    #expect(buttonNode["type"]?.stringValue?.contains("Button") == true)
}
#endif
