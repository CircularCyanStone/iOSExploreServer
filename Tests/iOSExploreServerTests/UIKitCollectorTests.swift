#if canImport(UIKit)
import UIKit
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

/// `UIViewTargetsCollector` 与 `UIViewHierarchyCollector` 的端到端测试。
///
/// 通过 `UIKitTestHost` 注入可控 view 树，验证采集器整条流水线（遍历 → 过滤 → 生成摘要/树 →
/// 签发 snapshot），补齐此前只测零件、未测组装的盲区——与 executor 端到端测试同源。

@Test("viewTargets 采集注入 view 树的扁平目标并签发 snapshot") @MainActor
func viewTargetsCollectsTargetsInContext() {
    let context = UIKitTestHost.context { root in
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = "submit"
        button.frame = CGRect(x: 10, y: 10, width: 80, height: 40)
        root.addSubview(button)

        let tagged = UIView()
        tagged.accessibilityIdentifier = "banner"
        tagged.frame = CGRect(x: 10, y: 60, width: 80, height: 20)
        root.addSubview(tagged)

        let plain = UIView(frame: CGRect(x: 0, y: 100, width: 100, height: 50))
        root.addSubview(plain)
    }

    let result = UIViewTargetsCollector.collect(query: .default, context: context)

    guard case .success(let data) = result else {
        Issue.record("expected success, got \(result)")
        return
    }
    // 默认策略：button（control）与 tagged（有 identifier）被采集；plain（无语义/交互）被过滤
    #expect(data["targetCount"]?.doubleValue == 2)
    #expect(data["truncated"]?.boolValue == false)
    #expect(data["snapshotID"]?.stringValue != nil)

    guard case .array(let targets)? = data["targets"] else {
        Issue.record("targets not array")
        return
    }
    #expect(targets.count == 2)

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

    guard case .object(let taggedTarget) = targets[1] else {
        Issue.record("tagged target not object")
        return
    }
    #expect(taggedTarget["path"]?.stringValue == "root/1")
    #expect(taggedTarget["role"]?.stringValue == "view")
    guard case .array(let taggedActions)? = taggedTarget["availableActions"] else {
        Issue.record("tagged availableActions not array")
        return
    }
    #expect(taggedActions.isEmpty)
}

@Test("topViewHierarchy 采集注入 view 树的层级结构") @MainActor
func topViewHierarchyCollectsTreeInContext() {
    let context = UIKitTestHost.context { root in
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = "submit"
        button.frame = CGRect(x: 10, y: 10, width: 80, height: 40)
        root.addSubview(button)
    }

    let query: UIViewHierarchyQuery
    switch UIViewHierarchyQuery.parse(from: [:]) {
    case .success(let q): query = q
    case .failure(let message):
        Issue.record("default query parse failed: \(message)")
        return
    }

    let result = UIViewHierarchyCollector.collectTopViewHierarchy(query: query, context: context)

    guard case .success(let data) = result else {
        Issue.record("expected success, got \(result)")
        return
    }
    #expect(data["snapshotID"]?.stringValue != nil)

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
