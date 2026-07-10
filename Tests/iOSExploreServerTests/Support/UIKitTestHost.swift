#if canImport(UIKit)
import UIKit
@testable import iOSExploreUIKit

/// UIKit 命令测试宿主：构造可控的 window + view 树，生成可注入的查询上下文。
///
/// `UIInspectCollector.collect(query:context:)` 与 `UIKitActionExecutor.execute(_:context:)`
/// 接受注入上下文。本类型在 iOS 测试里构造一个**不依赖真实 UIApplication scene** 的上下文
/// （真实 `UIWindow` + `UIViewController` + 自定义 view 树），使 collector/executor 的派发
/// 路径（遍历、hit-test、sendActions、陈旧校验）能在测试里被真实驱动——这是此前 executor
/// 零运行时覆盖的根因（`currentContext()` 读真实 App，测试 host 没有 UI scene）。
@MainActor
enum UIKitTestHost {
    /// 构造一个挂载自定义 view 树的查询上下文。
    ///
    /// 闭包接收根 view，由调用方填充子树并设置 frame；返回的上下文可直接喂给
    /// `UIKitActionExecutor.execute(_:context:)` 或 `UIInspectCollector.collect(query:context:)`。
    ///
    /// - Parameter buildRoot: 接收根 view 的配置闭包。
    /// - Returns: 顶部控制器根 view 为已配置根 view 的查询上下文。
    static func context(buildRoot: (UIView) -> Void) -> UIKitContextProvider.Context {
        // 测试 host 是 logic test，没有 UIWindowScene，只能用 frame 创建 window。
        // UIWindow(frame:) 在 iOS 26 SDK 触发 deprecation warning，但功能正常且无需 scene。
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        let rootViewController = UIViewController()
        let rootView = rootViewController.view!
        rootView.frame = window.bounds
        buildRoot(rootView)
        window.rootViewController = rootViewController
        window.makeKeyAndVisible()
        // 触发布局，让 hitTest/convert 在没有真实渲染循环时也能基于正确几何计算。
        window.layoutIfNeeded()
        return UIKitContextProvider.Context(window: window,
                                             rootViewController: rootViewController,
                                             topViewController: rootViewController,
                                             rootView: rootView)
    }
}
#endif
