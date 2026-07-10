#if canImport(UIKit)
import UIKit
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

/// `UIInspectCollector` 与 `UIViewHierarchyCollector` 的端到端测试（Task 4/8 重构后）。
///
/// 通过 `UIKitTestHost` 注入可控 view 树，验证采集器整条流水线（遍历 → canonical 筛选 →
/// 生成摘要/树 → 只对返回 target 签发 viewSnapshotID）。重构后 `ui.inspect` 只输出
/// canonical interaction target（UIControl / UIScrollView 系），普通 identifier/label view
/// 不再进入 targets（其观察职责在 `ui.topViewHierarchy`）。

@Test("ui.inspect 只采集 canonical target 并签发 viewSnapshotID") @MainActor
func inspectCollectsCanonicalTargetsOnly() {
    let context = UIKitTestHost.context { root in
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = "submit"
        button.frame = CGRect(x: 10, y: 10, width: 80, height: 40)
        root.addSubview(button) // root/0 button（canonical：UIControl）

        let tagged = UIView()
        tagged.accessibilityIdentifier = "banner"
        tagged.frame = CGRect(x: 10, y: 60, width: 80, height: 20)
        root.addSubview(tagged) // root/1 tagged view（hasAccessibilityIdentifier → full）

        let plain = UIView(frame: CGRect(x: 0, y: 100, width: 100, height: 50))
        root.addSubview(plain) // root/2 plain（非 canonical → 不采集）
    }

    let data = UIInspectCollector.collect(query: .default, context: context)
    // button（UIControl）+ tagged（hasAccessibilityIdentifier）都是 full target；
    // root 容器 + plain 空容器是 minimal 结构节点（维持层级）。Task 6 后全节点输出：
    // fullCount=2（button+tagged），minimalCount=2（root+plain），targetCount=4。
    #expect(data["fullCount"]?.doubleValue == 2)
    #expect(data["minimalCount"]?.doubleValue == 2)
    #expect(data["targetCount"]?.doubleValue == 4)
    #expect(data["truncated"]?.boolValue == false)
    #expect(data["viewSnapshotID"]?.stringValue != nil)
    #expect(data["snapshotID"] == nil)

    guard case .array(let targets)? = data["targets"] else {
        Issue.record("targets not array")
        return
    }
    #expect(targets.count == 4)

    // minimal 节点 toJSON 只含 path/type（无 role）；按 role 定位 button（root/0）。
    guard case .object(let buttonTarget)? = targets.first(where: {
        if case .object(let o) = $0 { return o["path"]?.stringValue == "root/0" }
        return false
    }) else {
        Issue.record("button target at root/0 missing")
        return
    }
    #expect(buttonTarget["role"]?.stringValue == "button")
    guard case .array(let buttonActions)? = buttonTarget["availableActions"] else {
        Issue.record("button availableActions not array")
        return
    }
    #expect(buttonActions.isEmpty == false)
}

@Test("ui.inspect 签发的指纹集合等于返回的 target path 集合") @MainActor
func inspectSignsFingerprintsForReturnedPathsOnly() throws {
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

    let query = UIInspectInput(maxTargets: 1)
    let data = UIInspectCollector.collect(query: query, context: context)
    // root（minimal）+ button1（full，fullCount=1 触发截断）。minimal 不占配额，button2 不签发。
    #expect(data["targetCount"]?.doubleValue == 2)
    #expect(data["fullCount"]?.doubleValue == 1)
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

@Test("ui.inspect 把按钮语义文本汇总到 canonical target") @MainActor
func inspectAggregatesButtonSemanticText() throws {
    let context = UIKitTestHost.context { root in
        let button = UIButton(type: .system)
        button.setTitle("提交订单", for: .normal)
        button.frame = CGRect(x: 10, y: 10, width: 120, height: 40)
        root.addSubview(button)
    }

    let data = UIInspectCollector.collect(query: .default, context: context)
    // minimal 节点（root 容器） toJSON 无 role；按 role 找 button full target。
    guard case .array(let targets)? = data["targets"],
          case .object(let buttonTarget)? = targets.first(where: {
              if case .object(let o) = $0 { return o["role"]?.stringValue == "button" }
              return false
          }) else {
        Issue.record("button target missing")
        return
    }
    // 按钮内部 label 不作为独立 target；其标题汇总到父 button 的 semanticText。
    // 故意不设 accessibilityIdentifier：semanticText 新优先级里 identifier 最高，
    // 设了会遮蔽 buttonTitle；此处要锁定的是「标题汇总到父 target」这条 source=buttonTitle 路径。
    // identifier 与 title 共存时 identifier 胜出，由 semanticTextIdentifierBeatsButtonTitle 覆盖。
    #expect(buttonTarget["semanticText"]?.stringValue == "提交订单")
    #expect(buttonTarget["semanticTextSource"]?.stringValue == "buttonTitle")
}

@Test("ui.inspect 按钮内部 title label rollup 到父 control，不独立签发") @MainActor
func inspectRollsUpButtonInternalLabel() throws {
    let context = UIKitTestHost.context { root in
        let button = UIButton(type: .system)
        button.setTitle("提交订单", for: .normal)
        button.frame = CGRect(x: 10, y: 10, width: 120, height: 40)
        root.addSubview(button)
    }
    // UIButton(type:.system) 内部有渲染 title 的 UIButtonLabel（UILabel 子类，有 .text）。
    // 不做 rollup 时它命中 hasStaticText → full → 被签发，agent tap 它会返回 unsupported_target
    // （label 无默认激活路由），破坏"签发=可操作"。rollup 后控件子树整棵剪枝：内部 label 既不
    // 进 full 也不进 minimal，更不签发 fingerprint（Task 6 的 isInControlSubtree 剪枝）。

    let data = UIInspectCollector.collect(query: .default, context: context)
    // root（minimal）+ button（full）。内部 title label 被剪枝，不出现在 targets。
    // 若剪枝失效，UIButtonLabel 会命中 hasStaticText 进 full 或沦为 minimal，targetCount > 2。
    #expect(data["targetCount"]?.doubleValue == 2)
    #expect(data["fullCount"]?.doubleValue == 1)

    guard case .array(let targets)? = data["targets"],
          case .object(let buttonTarget)? = targets.first(where: {
              if case .object(let o) = $0 { return o["role"]?.stringValue == "button" }
              return false
          }) else {
        Issue.record("button target missing")
        return
    }
    #expect(buttonTarget["path"]?.stringValue == "root/0")
    // 按钮标题已通过 semanticText（buttonTitle）汇总到父 target，agent 无需读内部 label。
    #expect(buttonTarget["semanticText"]?.stringValue == "提交订单")
    #expect(buttonTarget["semanticTextSource"]?.stringValue == "buttonTitle")
}

@Test("ui.inspect cell 内 label 不受 control rollup 影响，仍 full 签发") @MainActor
func inspectKeepsCellInternalLabelFull() throws {
    let context = UIKitTestHost.context { root in
        // UITableViewCell 不是 UIControl；cell 子树内 label 的祖先链
        // （label → contentView → cell → root）无 UIControl → isInControlSubtree=false → 仍 full。
        // 这是 rollup 判定的硬约束：cell 非 UIControl，cell 内 label 不得被误 rollup（spec §3.4）。
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        let label = UILabel()
        label.text = "滚动测试"
        label.frame = CGRect(x: 16, y: 12, width: 200, height: 20)
        cell.contentView.addSubview(label)
        cell.frame = CGRect(x: 0, y: 0, width: 320, height: 44)
        root.addSubview(cell)
    }

    let data = UIInspectCollector.collect(query: .default, context: context)
    guard case .array(let targets)? = data["targets"] else {
        Issue.record("targets not array")
        return
    }
    // cell 内 label 有 hasStaticText 且 isInControlSubtree=false → 仍 full，被采集。
    // 若 rollup 误伤 cell 子树，此 target 会缺失。
    let labelTarget = targets.first { target in
        guard case .object(let obj) = target else { return false }
        return obj["semanticText"]?.stringValue == "滚动测试"
    }
    #expect(labelTarget != nil, "cell 内 label 应作为 full target 被采集（spec §3.4）")
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
    // topViewHierarchy 不签发 viewSnapshotID（spec §1.2：只有 ui.inspect 签发）。
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

/// 回归测试：`UIView.tintColor` 为 nil（隐式解包可选触发阶段）时采集不崩溃（P2）。
///
/// 通过 `UIView` 的子类在 `tintColorDidChange()` 后把 `tintColor` 置 nil，模拟
/// UISegmentedControl/UIStepper sendAction 过渡态的场景。采集器应优雅 fallback
/// 为 tintColor=null 而非崩溃。
@Test("view hierarchy collector 处理 tintColor nil 时不崩溃") @MainActor
func viewHierarchyCollectorHandlesNilTintColorGracefully() throws {
    let context = UIKitTestHost.context { root in
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = "test.button"
        button.frame = CGRect(x: 10, y: 10, width: 80, height: 40)
        root.addSubview(button)
        // 强制把 tintColor 置 nil——模拟控制件 sendAction 后的过渡态。
        // UIView.tintColor 是 UIColor!，赋值 nil 后后续读取会走 nil 路径。
        button.tintColor = nil
    }

    let query = try UIViewHierarchyInput.parse(from: [:])
    // 不崩溃即通过：当年 P2 复现路径第 117 行 `view.tintColor.hierarchyHexString` 在 nil 时
    // 触发 `Fatal error: Unexpectedly found nil while implicitly unwrapping`。修复后 nil 路径
    // 应优雅 fallback 为 null（或继承非 nil 值），不应使采集 fatal exit。
    let data = UIViewHierarchyCollector.collectTopViewHierarchy(query: query, context: context)
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
    // tintColor 应在 JSON 中存在（null 或具体值都接受，关键是采集走完了）。
    guard case .object(let appearance)? = buttonNode["appearance"] else {
        Issue.record("appearance not object")
        return
    }
    #expect(appearance["tintColor"] != nil, "appearance.tintColor 字段必须存在")
    #expect(data["nodeCount"]?.doubleValue != nil)
}

/// 回归测试：UILabel.textColor 为 nil 时采集不崩溃（P2）。
///
/// `UILabel.textColor` 也是 `UIColor!`。某些复用/过渡期 label 的 textColor
/// 可能短暂 nil，采集器应 fallback 为 textColor=null。
@Test("view hierarchy collector 处理 UILabel textColor nil 时不崩溃") @MainActor
func viewHierarchyCollectorHandlesNilLabelTextColorGracefully() throws {
    let context = UIKitTestHost.context { root in
        let label = UILabel()
        label.text = "test"
        label.frame = CGRect(x: 10, y: 10, width: 80, height: 20)
        label.textColor = nil
        root.addSubview(label)
    }

    let query = try UIViewHierarchyInput.parse(from: [:])
    // 不崩溃即通过。当年 P2 复现路径第 153 行 `label.textColor.hierarchyHexString` 在 nil
    // 时崩溃。修复后应 fallback 为 textColor=null（或继承非 nil 值）。
    let data = UIViewHierarchyCollector.collectTopViewHierarchy(query: query, context: context)
    guard case .object(let root)? = data["root"] else {
        Issue.record("root not object")
        return
    }
    guard case .array(let subviews)? = root["subviews"] else {
        Issue.record("subviews not array")
        return
    }
    #expect(subviews.count == 1)
    guard case .object(let labelNode) = subviews[0] else {
        Issue.record("label node not object")
        return
    }
    guard case .object(let text)? = labelNode["text"] else {
        Issue.record("text not object")
        return
    }
    // textColor 字段必须存在（null 或具体值都接受）。
    #expect(text["textColor"] != nil, "label.textColor 字段必须存在")
}
#endif
