#if canImport(UIKit)
import UIKit
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

@MainActor
private final class NavigationBarButtonReceiver: NSObject {
    var called = false

    @objc func fire() {
        called = true
    }
}

@MainActor
private func navigationContext(item: UIBarButtonItem) -> (UIKitContextProvider.Context, NavigationBarButtonReceiver) {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    let receiver = NavigationBarButtonReceiver()
    let root = UIViewController()
    root.title = "首页"
    item.target = receiver
    item.action = #selector(NavigationBarButtonReceiver.fire)
    root.navigationItem.rightBarButtonItem = item
    let navigation = UINavigationController(rootViewController: root)
    window.rootViewController = navigation
    window.makeKeyAndVisible()
    window.layoutIfNeeded()
    return (
        UIKitContextProvider.Context(window: window,
                                     rootViewController: navigation,
                                     topViewController: root,
                                     rootView: root.view),
        receiver
    )
}

@Test("navigationBar 摘要列出右侧 UIBarButtonItem") @MainActor
func navigationBarSummaryListsRightItem() {
    let item = UIBarButtonItem(title: "控件测试", style: .plain, target: nil, action: nil)
    item.accessibilityIdentifier = "example.controlTest"
    let (context, _) = navigationContext(item: item)

    let summary = UINavigationBarInspector.summarize(topViewController: context.topViewController)

    #expect(summary.available)
    #expect(summary.title == "首页")
    #expect(summary.rightItems.count == 1)
    #expect(summary.rightItems[0].placement == .right)
    #expect(summary.rightItems[0].index == 0)
    #expect(summary.rightItems[0].title == "控件测试")
    #expect(summary.rightItems[0].accessibilityIdentifier == "example.controlTest")
    #expect(summary.rightItems[0].isEnabled)
}

@Test("navigation bar button executor 触发 target-action") @MainActor
func navigationBarButtonExecutorTriggersTargetAction() throws {
    let item = UIBarButtonItem(title: "控件测试", style: .plain, target: nil, action: nil)
    item.accessibilityIdentifier = "example.controlTest"
    let (context, receiver) = navigationContext(item: item)

    let input = UINavigationBarButtonInput(placement: .right,
                                           index: 0,
                                           title: "控件测试",
                                           accessibilityIdentifier: "example.controlTest",
                                           waitAfterMs: 0)
    let data = try UINavigationBarButtonExecutor.execute(input: input, context: context)

    #expect(receiver.called)
    #expect(data["performed"]?.boolValue == true)
    #expect(data["title"]?.stringValue == "控件测试")
}

@Test("navigation bar button executor 拒绝 disabled item") @MainActor
func navigationBarButtonExecutorRejectsDisabledItem() {
    let item = UIBarButtonItem(title: "控件测试", style: .plain, target: nil, action: nil)
    item.isEnabled = false
    let (context, _) = navigationContext(item: item)
    let input = UINavigationBarButtonInput(placement: .right, index: 0, title: "控件测试", waitAfterMs: 0)

    #expect(throws: UIKitCommandError.self) {
        _ = try UINavigationBarButtonExecutor.execute(input: input, context: context)
    }
}

@Test("navigation bar button executor 拒绝 title mismatch") @MainActor
func navigationBarButtonExecutorRejectsTitleMismatch() {
    let item = UIBarButtonItem(title: "控件测试", style: .plain, target: nil, action: nil)
    let (context, _) = navigationContext(item: item)
    let input = UINavigationBarButtonInput(placement: .right, index: 0, title: "设置", waitAfterMs: 0)

    #expect(throws: UIKitCommandError.self) {
        _ = try UINavigationBarButtonExecutor.execute(input: input, context: context)
    }
}

@Test("viewTargets 和 topViewHierarchy 返回 navigationBar 摘要") @MainActor
func collectorsIncludeNavigationBarSummary() throws {
    let item = UIBarButtonItem(title: "控件测试", style: .plain, target: nil, action: nil)
    item.accessibilityIdentifier = "example.controlTest"
    let (context, _) = navigationContext(item: item)

    let targetsData = UIViewTargetsCollector.collect(query: .default, context: context)
    let hierarchyData = UIViewHierarchyCollector.collectTopViewHierarchy(query: try UIViewHierarchyInput.parse(from: [:]),
                                                                         context: context)

    let targetsNavigationBar = targetsData["navigationBar"]?.objectValue
    let hierarchyNavigationBar = hierarchyData["navigationBar"]?.objectValue
    #expect(targetsNavigationBar?["available"]?.boolValue == true)
    #expect(hierarchyNavigationBar?["available"]?.boolValue == true)
    #expect(targetsNavigationBar?["rightItems"]?.arrayValue?.count == 1)
    #expect(hierarchyNavigationBar?["rightItems"]?.arrayValue?.count == 1)
}
#endif
