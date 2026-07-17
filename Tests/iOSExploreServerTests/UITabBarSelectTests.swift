import Testing
import Foundation
import iOSExploreServer
@testable import iOSExploreUIKit

#if canImport(UIKit)
import UIKit

// MARK: - UITabBarSelectInput 解析测试

@Test("UITabBarSelectInput 解析 index")
func tabBarSelectInputParsesIndex() throws {
    let input = try UITabBarSelectInput.parse(from: ["index": .double(1)])
    #expect(input.index == 1)
    #expect(input.title == nil)
    #expect(input.triggerDelegate == true)
    #expect(input.tabBarControllerPath == nil)
}

@Test("UITabBarSelectInput 解析 title")
func tabBarSelectInputParsesTitle() throws {
    let input = try UITabBarSelectInput.parse(from: ["title": .string("Tab 2")])
    #expect(input.index == nil)
    #expect(input.title == "Tab 2")
    #expect(input.triggerDelegate == true)
}

@Test("UITabBarSelectInput 解析 triggerDelegate=false")
func tabBarSelectInputParsesTriggerDelegateFalse() throws {
    let input = try UITabBarSelectInput.parse(from: ["index": .double(0), "triggerDelegate": .bool(false)])
    #expect(input.triggerDelegate == false)
}

@Test("UITabBarSelectInput 解析 tabBarControllerPath")
func tabBarSelectInputParsesPath() throws {
    let input = try UITabBarSelectInput.parse(from: [
        "index": .double(1),
        "tabBarControllerPath": .string("root.presented")
    ])
    #expect(input.tabBarControllerPath == "root.presented")
}

@Test("UITabBarSelectInput 拒绝同时提供 index 和 title")
func tabBarSelectInputRejectsBoth() {
    #expect(throws: CommandInputParseError.self) {
        _ = try UITabBarSelectInput.parse(from: ["index": .double(0), "title": .string("Tab 1")])
    }
}

@Test("UITabBarSelectInput 拒绝都不提供 index 和 title")
func tabBarSelectInputRejectsNeither() {
    #expect(throws: CommandInputParseError.self) {
        _ = try UITabBarSelectInput.parse(from: [:])
    }
}

@Test("UITabBarSelectInput schema 声明 4 个字段")
func tabBarSelectInputSchemaFields() {
    let fields = UITabBarSelectInput.inputSchema.fields.map(\.name)
    #expect(fields.contains("index"))
    #expect(fields.contains("title"))
    #expect(fields.contains("triggerDelegate"))
    #expect(fields.contains("tabBarControllerPath"))
}

// MARK: - UITabBarSelectExecutor 测试(需手动构造 UITabBarController 场景)

/// 构造测试用 UIKitContextProvider.Context。
private func makeContext(rootViewController: UIViewController,
                         topViewController: UIViewController,
                         rootView: UIView) -> UIKitContextProvider.Context {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    window.rootViewController = rootViewController
    window.makeKeyAndVisible()
    return UIKitContextProvider.Context(window: window,
                                        rootViewController: rootViewController,
                                        topViewController: topViewController,
                                        rootView: rootView)
}

@Test("按 index 切换 tab") @MainActor
func selectTabByIndex() throws {
    let tab1 = UIViewController()
    tab1.tabBarItem = UITabBarItem(title: "Tab 1", image: nil, tag: 0)
    let tab2 = UIViewController()
    tab2.tabBarItem = UITabBarItem(title: "Tab 2", image: nil, tag: 1)
    let tab3 = UIViewController()
    tab3.tabBarItem = UITabBarItem(title: "Tab 3", image: nil, tag: 2)

    let tbc = UITabBarController()
    tbc.viewControllers = [tab1, tab2, tab3]
    tbc.selectedIndex = 0

    let ctx = makeContext(rootViewController: tbc, topViewController: tab1, rootView: tab1.view)
    let input = UITabBarSelectInput(tabBarControllerPath: nil, index: 1, title: nil, triggerDelegate: false)
    let result = try UITabBarSelectExecutor.execute(input: input, context: ctx)

    #expect(result["previousIndex"]?.doubleValue == 0)
    #expect(result["selectedIndex"]?.doubleValue == 1)
    #expect(result["selectedTitle"]?.stringValue == "Tab 2")
    #expect(result["tabCount"]?.doubleValue == 3)
    #expect(tbc.selectedIndex == 1)
}

@Test("按 title 切换 tab") @MainActor
func selectTabByTitle() throws {
    let tab1 = UIViewController()
    tab1.tabBarItem = UITabBarItem(title: "首页", image: nil, tag: 0)
    let tab2 = UIViewController()
    tab2.tabBarItem = UITabBarItem(title: "发现", image: nil, tag: 1)
    let tab3 = UIViewController()
    tab3.tabBarItem = UITabBarItem(title: "我的", image: nil, tag: 2)

    let tbc = UITabBarController()
    tbc.viewControllers = [tab1, tab2, tab3]
    tbc.selectedIndex = 0

    let ctx = makeContext(rootViewController: tbc, topViewController: tab1, rootView: tab1.view)
    let input = UITabBarSelectInput(tabBarControllerPath: nil, index: nil, title: "我的", triggerDelegate: false)
    let result = try UITabBarSelectExecutor.execute(input: input, context: ctx)

    #expect(result["selectedIndex"]?.doubleValue == 2)
    #expect(result["selectedTitle"]?.stringValue == "我的")
    #expect(tbc.selectedIndex == 2)
}

@Test("触发 delegate 回调") @MainActor
func selectTabTriggersDelegate() throws {
    class DelegateCapture: NSObject, UITabBarControllerDelegate {
        var didSelectCalled = false
        var selectedVC: UIViewController?

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            didSelectCalled = true
            selectedVC = viewController
        }
    }

    let tab1 = UIViewController()
    tab1.tabBarItem = UITabBarItem(title: "Tab 1", image: nil, tag: 0)
    let tab2 = UIViewController()
    tab2.tabBarItem = UITabBarItem(title: "Tab 2", image: nil, tag: 1)

    let tbc = UITabBarController()
    tbc.viewControllers = [tab1, tab2]
    tbc.selectedIndex = 0

    let delegate = DelegateCapture()
    tbc.delegate = delegate

    let ctx = makeContext(rootViewController: tbc, topViewController: tab1, rootView: tab1.view)
    let input = UITabBarSelectInput(tabBarControllerPath: nil, index: 1, title: nil, triggerDelegate: true)
    _ = try UITabBarSelectExecutor.execute(input: input, context: ctx)

    #expect(delegate.didSelectCalled == true)
    #expect(delegate.selectedVC === tab2)
}

@Test("triggerDelegate=false 不触发 delegate") @MainActor
func selectTabWithoutTriggeringDelegate() throws {
    class DelegateCapture: NSObject, UITabBarControllerDelegate {
        var didSelectCalled = false

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            didSelectCalled = true
        }
    }

    let tab1 = UIViewController()
    tab1.tabBarItem = UITabBarItem(title: "Tab 1", image: nil, tag: 0)
    let tab2 = UIViewController()
    tab2.tabBarItem = UITabBarItem(title: "Tab 2", image: nil, tag: 1)

    let tbc = UITabBarController()
    tbc.viewControllers = [tab1, tab2]
    tbc.selectedIndex = 0

    let delegate = DelegateCapture()
    tbc.delegate = delegate

    let ctx = makeContext(rootViewController: tbc, topViewController: tab1, rootView: tab1.view)
    let input = UITabBarSelectInput(tabBarControllerPath: nil, index: 1, title: nil, triggerDelegate: false)
    _ = try UITabBarSelectExecutor.execute(input: input, context: ctx)

    #expect(delegate.didSelectCalled == false)
    #expect(tbc.selectedIndex == 1)
}

@Test("index 越界抛错") @MainActor
func selectTabIndexOutOfRange() throws {
    let tab1 = UIViewController()
    tab1.tabBarItem = UITabBarItem(title: "Tab 1", image: nil, tag: 0)

    let tbc = UITabBarController()
    tbc.viewControllers = [tab1]
    tbc.selectedIndex = 0

    let ctx = makeContext(rootViewController: tbc, topViewController: tab1, rootView: tab1.view)
    let input = UITabBarSelectInput(tabBarControllerPath: nil, index: 5, title: nil, triggerDelegate: false)

    #expect(throws: UIKitCommandError.self) {
        _ = try UITabBarSelectExecutor.execute(input: input, context: ctx)
    }
}

@Test("title 不匹配抛错") @MainActor
func selectTabTitleNotFound() throws {
    let tab1 = UIViewController()
    tab1.tabBarItem = UITabBarItem(title: "Tab 1", image: nil, tag: 0)

    let tbc = UITabBarController()
    tbc.viewControllers = [tab1]
    tbc.selectedIndex = 0

    let ctx = makeContext(rootViewController: tbc, topViewController: tab1, rootView: tab1.view)
    let input = UITabBarSelectInput(tabBarControllerPath: nil, index: nil, title: "不存在", triggerDelegate: false)

    #expect(throws: UIKitCommandError.self) {
        _ = try UITabBarSelectExecutor.execute(input: input, context: ctx)
    }
}

@Test("modal UITabBarController 自动查找") @MainActor
func selectTabAutoFindModalTabBar() throws {
    let baseVC = UIViewController()
    let nav = UINavigationController(rootViewController: baseVC)

    let tab1 = UIViewController()
    tab1.tabBarItem = UITabBarItem(title: "Tab 1", image: nil, tag: 0)
    let tab2 = UIViewController()
    tab2.tabBarItem = UITabBarItem(title: "Tab 2", image: nil, tag: 1)

    let tbc = UITabBarController()
    tbc.viewControllers = [tab1, tab2]
    tbc.selectedIndex = 0

    // 模拟 present:手动设置 presentedViewController
    nav.setValue(tbc, forKey: "presentedViewController")

    let ctx = makeContext(rootViewController: nav, topViewController: tab1, rootView: tab1.view)
    let input = UITabBarSelectInput(tabBarControllerPath: nil, index: 1, title: nil, triggerDelegate: false)
    let result = try UITabBarSelectExecutor.execute(input: input, context: ctx)

    #expect(result["selectedIndex"]?.doubleValue == 1)
    #expect(tbc.selectedIndex == 1)
}

@Test("显式 tabBarControllerPath 定位") @MainActor
func selectTabWithExplicitPath() throws {
    let baseVC = UIViewController()
    let nav = UINavigationController(rootViewController: baseVC)

    let tab1 = UIViewController()
    tab1.tabBarItem = UITabBarItem(title: "Tab 1", image: nil, tag: 0)
    let tab2 = UIViewController()
    tab2.tabBarItem = UITabBarItem(title: "Tab 2", image: nil, tag: 1)

    let tbc = UITabBarController()
    tbc.viewControllers = [tab1, tab2]
    tbc.selectedIndex = 0

    nav.setValue(tbc, forKey: "presentedViewController")

    let ctx = makeContext(rootViewController: nav, topViewController: tab1, rootView: tab1.view)
    let input = UITabBarSelectInput(tabBarControllerPath: "root.presented", index: 1, title: nil, triggerDelegate: false)
    let result = try UITabBarSelectExecutor.execute(input: input, context: ctx)

    #expect(result["selectedIndex"]?.doubleValue == 1)
}

@Test("无 UITabBarController 时抛错") @MainActor
func selectTabNoTabBarControllerFound() throws {
    let vc = UIViewController()
    let ctx = makeContext(rootViewController: vc, topViewController: vc, rootView: vc.view)
    let input = UITabBarSelectInput(tabBarControllerPath: nil, index: 0, title: nil, triggerDelegate: false)

    #expect(throws: UIKitCommandError.self) {
        _ = try UITabBarSelectExecutor.execute(input: input, context: ctx)
    }
}

#endif
