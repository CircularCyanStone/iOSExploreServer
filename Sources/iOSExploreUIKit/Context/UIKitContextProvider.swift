#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// UIKit 查询上下文提供者。
///
/// 负责在 `MainActor` 上读取当前前台 window 与顶部控制器，生成 UIKit 命令共享的查询上下文。
/// 该类型是 UIKit 命令进入 MainActor 隔离域的第一个入口：adapter（network queue 上的命令
/// handler）只能 `await` 其 `currentContext()`，不能把 `UIView`/`UIViewController` 等
/// UIKit 对象返回到非隔离域——跨边界只传 Sendable 值（路径、类型名、摘要）。
///
/// 从 `UIKitViewLookup` 拆出，使"前台 window + 顶部控制器"逻辑与"按 locator 解析 view"
/// 逻辑（`UIKitLocatorResolver`）各自单一职责。
@MainActor
enum UIKitContextProvider {
    /// 当前顶部控制器 view 查询上下文。
    ///
    /// 持有 UIKit 对象，**不可跨 MainActor 边界传递**；仅供同一 MainActor 域内的
    /// resolver / collector 使用。
    struct Context {
        /// 当前前台 window。
        let window: UIWindow
        /// window 的根控制器。
        let rootViewController: UIViewController
        /// 当前实际展示的顶部控制器。
        let topViewController: UIViewController
        /// 顶部控制器根 view。
        let rootView: UIView
    }

    /// 当前上下文查询结果。
    enum ContextResult {
        /// 查询成功。
        case success(Context)
        /// UIKit 上下文不可用，附带原因。
        case failure(String)
    }

    /// 获取当前顶部控制器 view 查询上下文。
    ///
    /// - Returns: 成功时返回上下文；失败时返回不可用原因（用于 `UIKitCommandError.hierarchyUnavailable`）。
    static func currentContext() -> ContextResult {
        guard let window = activeWindow() else {
            return .failure("active window not found")
        }
        guard let rootViewController = window.rootViewController else {
            return .failure("root view controller not found")
        }
        let topViewController = topViewController(from: rootViewController)
        guard let rootView = topViewController.view else {
            return .failure("top view controller view not found")
        }
        return .success(Context(window: window,
                                rootViewController: rootViewController,
                                topViewController: topViewController,
                                rootView: rootView))
    }

    /// 查找当前前台 scene 中可用的 window。
    private static func activeWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let foregroundScenes = scenes.filter {
            $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
        }
        let candidateScenes = foregroundScenes.isEmpty ? scenes : foregroundScenes
        for scene in candidateScenes {
            if let key = scene.windows.first(where: { $0.isKeyWindow }) {
                return key
            }
            if let visible = scene.windows.first(where: { !$0.isHidden && $0.alpha > 0 }) {
                return visible
            }
        }
        return nil
    }

    /// 从 root 控制器向下找到当前实际展示的顶部控制器。
    private static func topViewController(from controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController {
            return topViewController(from: presented)
        }
        if let navigation = controller as? UINavigationController, let visible = navigation.visibleViewController {
            return topViewController(from: visible)
        }
        if let tab = controller as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(from: selected)
        }
        if let split = controller as? UISplitViewController, let last = split.viewControllers.last {
            return topViewController(from: last)
        }
        return controller
    }
}
#endif
