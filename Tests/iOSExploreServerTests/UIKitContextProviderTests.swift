#if canImport(UIKit)
import UIKit
import Testing
@testable import iOSExploreUIKit

/// `UIKitContextProvider` 的纯函数测试。
///
/// 此前 `topViewController(from:)` 与 `currentContext` 均无测试覆盖（依赖真实 UIApplication scene，
/// logic test 没有）。本文件把两个**纯函数**——操作命令用的 `topViewController(from:)`（钻到叶子 VC）
/// 与采集命令用的 `hierarchyRootController(from:)`（停在最外层容器 VC）——直接驱动，锁定两者在
/// 各容器组合下的差异。这是修复「modal 容器采集根盲区」的语义基线：
/// - `topViewController` 钻 nav/tab/split 到叶子，丢失容器 chrome（UITabBar 等）→ 操作命令的正确语义；
/// - `hierarchyRootController` 不钻容器，停在 UITabBarController/UINavigationController 本身，
///   让采集命令的采集根包含 chrome。

@Test("topViewController 钻 nav 栈顶") @MainActor
func topViewControllerDrillsNavigationStack() {
    let root = UIViewController()
    let detail = UIViewController()
    let nav = UINavigationController(rootViewController: root)
    nav.pushViewController(detail, animated: false)

    let top = UIKitContextProvider.topViewController(from: nav)
    #expect(top === detail, "topViewController 应钻到 nav 栈顶 detail")
}

@Test("topViewController 钻 tab selected（盲区根因）") @MainActor
func topViewControllerDrillsTabSelected() {
    // 这正是盲区根因：topViewController 钻 tab 到 selectedVC（叶子），UITabBar 与 selectedVC.view
    // 平级、不在 selectedVC.view 子树里，故以 topViewController.view 作采集根时永远采不到 UITabBar。
    let first = UIViewController()
    let second = UIViewController()
    let tab = UITabBarController()
    tab.viewControllers = [first, second]
    tab.selectedIndex = 1

    let top = UIKitContextProvider.topViewController(from: tab)
    #expect(top === second, "topViewController 应钻到 tab selected (second)")
}

@Test("topViewController 无容器返回自身") @MainActor
func topViewControllerPlainReturnsSelf() {
    let vc = UIViewController()

    let top = UIKitContextProvider.topViewController(from: vc)
    #expect(top === vc)
}

@Test("hierarchyRootController 不钻 tab，停在 UITabBarController 容器（修复核心）") @MainActor
func hierarchyRootStopsAtTabBarContainer() {
    // 对照根因：topViewController 钻 tab → tab1 叶子（chrome 丢失）。
    // hierarchyRootController 不钻 → 停在 UITabBarController，UITabBar 在其 view 子树里可被采集。
    let tab1 = UIViewController()
    let tab2 = UIViewController()
    let tab3 = UIViewController()
    let tab = UITabBarController()
    tab.viewControllers = [tab1, tab2, tab3]
    tab.selectedIndex = 0

    let hierarchyRoot = UIKitContextProvider.hierarchyRootController(from: tab)
    #expect(hierarchyRoot === tab,
            "hierarchyRootController 应停在 UITabBarController 容器，而非钻到 tab1")

    // 对照：topViewController 仍钻到 tab1——操作命令依赖此语义，本修复不改它。
    let top = UIKitContextProvider.topViewController(from: tab)
    #expect(top === tab1, "topViewController 仍应钻到 tab1（操作命令语义不变）")
}

@Test("hierarchyRootController 不钻 nav，停在 UINavigationController 容器") @MainActor
func hierarchyRootStopsAtNavigationController() {
    let root = UIViewController()
    let detail = UIViewController()
    let nav = UINavigationController(rootViewController: root)
    nav.pushViewController(detail, animated: false)

    let hierarchyRoot = UIKitContextProvider.hierarchyRootController(from: nav)
    #expect(hierarchyRoot === nav,
            "hierarchyRootController 应停在 UINavigationController 容器，而非钻到栈顶 detail")
}

@Test("hierarchyRootController 无容器返回自身") @MainActor
func hierarchyRootPlainReturnsSelf() {
    let vc = UIViewController()

    let hierarchyRoot = UIKitContextProvider.hierarchyRootController(from: vc)
    #expect(hierarchyRoot === vc)
}

@Test("hierarchyRootController 沿 presented 走到最外层（不钻容器）") @MainActor
func hierarchyRootWalksPresentedChainToContainer() {
    // modal 容器场景：nav present 一个 UITabBarController。
    // hierarchyRootController 应沿 presented 走到 UITabBarController（最外层），不再钻其 tab；
    // topViewController 则一路钻 nav→presented(tab)→tab selected 到叶子。
    let host = UIViewController()
    let nav = UINavigationController(rootViewController: host)
    let tab = UITabBarController()
    let tab1 = UIViewController()
    let tab2 = UIViewController()
    tab.viewControllers = [tab1, tab2]
    tab.selectedIndex = 0

    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    window.rootViewController = nav
    window.makeKeyAndVisible()
    nav.present(tab, animated: false)
    // animated:false 的 present 在 logic test 偶发不就绪；未就绪时跳过，
    // modal 场景的真实采集由 SPMExample 端到端验证覆盖（见修复记录）。
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    guard nav.presentedViewController === tab else { return }

    let hierarchyRoot = UIKitContextProvider.hierarchyRootController(from: nav)
    #expect(hierarchyRoot === tab,
            "hierarchyRootController 应走到 presented 的 UITabBarController，不钻其 tab")

    let top = UIKitContextProvider.topViewController(from: nav)
    #expect(top === tab1, "topViewController 应钻到 presented tab 的 selected (tab1)")
}

@Test("hierarchyRootController 沿多层 presented 走到最外层") @MainActor
func hierarchyRootWalksMultiLevelPresentedChain() {
    // 链式 modal：A present B present C。hierarchyRoot 应走到最外层 C。
    let a = UIViewController()
    let b = UIViewController()
    let c = UIViewController()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    window.rootViewController = a
    window.makeKeyAndVisible()
    a.present(b, animated: false)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    guard a.presentedViewController === b else { return }
    b.present(c, animated: false)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    guard b.presentedViewController === c else { return }

    let hierarchyRoot = UIKitContextProvider.hierarchyRootController(from: a)
    #expect(hierarchyRoot === c, "hierarchyRootcontroller 应走到最外层 presented (c)")
}
#endif
