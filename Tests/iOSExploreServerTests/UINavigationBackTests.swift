#if canImport(UIKit)
import UIKit
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

/// `ui.navigation.back` 执行核心的 iOS 测试。
///
/// 通过手动构造 `UINavigationController` + `UIWindow` + 注入 `Context` 覆盖 pop 成功路径，
/// 用 `UIKitTestHost` 覆盖无导航路径的失败路径。dismiss 路径依赖真实 present 转场，在 logic
/// test 不可靠，留作后续 framework runtime 覆盖。

@Test("navigationController strategy pop 顶层控制器") @MainActor
func navigationBackNavigationControllerStrategyPops() throws {
    let root = UIViewController()
    let detail = UIViewController()
    let navigation = UINavigationController(rootViewController: root)
    navigation.pushViewController(detail, animated: false)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    window.rootViewController = navigation
    window.makeKeyAndVisible()
    let context = UIKitContextProvider.Context(window: window,
                                               rootViewController: navigation,
                                               topViewController: detail,
                                               rootView: detail.view)
    let input = UINavigationBackInput(strategy: .navigationController, animated: false, waitAfterMs: 0)
    let data = try UINavigationBackExecutor.execute(input: input, context: context)
    #expect(data["performed"]?.boolValue == true)
    #expect(data["strategy"]?.stringValue == "navigationController")
    #expect(navigation.viewControllers.count == 1)
}

@Test("auto 无导航路径抛 navigationBackUnavailable") @MainActor
func navigationBackAutoWithoutPathThrowsUnavailable() {
    let context = UIKitTestHost.context { _ in }
    let input = UINavigationBackInput(strategy: .auto, waitAfterMs: 0)
    do {
        _ = try UINavigationBackExecutor.execute(input: input, context: context)
        Issue.record("expected failure, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .navigationBackUnavailable)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}
#endif
