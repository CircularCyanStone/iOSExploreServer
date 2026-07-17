#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// UIKit 查询上下文提供者。
///
/// 负责在 `MainActor` 上读取当前前台 window 与顶部控制器，生成 UIKit 命令共享的查询上下文。
/// 该类型是 UIKit 命令进入 MainActor 隔离域的第一个入口：adapter（network queue 上的命令
/// handler）只能 `await` 其 `currentContext(action:)`（失败时 `throws`），不能把
/// `UIView`/`UIViewController` 等 UIKit 对象返回到非隔离域——跨边界只传 Sendable 值（路径、类型名、摘要）。
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

    /// 获取当前顶部控制器 view 查询上下文，失败时抛出 `hierarchyUnavailable`。
    ///
    /// - Parameter action: 触发查询的 action 名，用于错误工厂的日志关联。
    /// - Returns: 当前查询上下文。
    /// - Throws: `UIKitCommandError.hierarchyUnavailable`——active window / root / top view 任一不可用时。
    static func currentContext(action: String) throws -> Context {
        guard let window = activeWindow() else {
            throw UIKitCommandError.hierarchyUnavailable(action: action, reason: "active window not found")
        }
        guard let rootViewController = window.rootViewController else {
            throw UIKitCommandError.hierarchyUnavailable(action: action, reason: "root view controller not found")
        }
        let topViewController = topViewController(from: rootViewController)
        // 采集根用「最外层容器 VC」的 view（hierarchyRootController），而非 topViewController（叶子 VC）
        // 的 view：容器 chrome（UITabBar / UINavigationBar 等）在最外层容器 VC.view 的子树里，在
        // 叶子 VC.view 子树里会丢失（这是「modal 容器采集根盲区」的根因）。topViewController 仍保留，
        // 供 UINavigationBarInspector / UIAlertInspector / fingerprint 摘要等「栈顶操作语义」使用。
        let hierarchyRoot = hierarchyRootController(from: rootViewController)
        guard let rootView = hierarchyRoot.view else {
            throw UIKitCommandError.hierarchyUnavailable(action: action, reason: "hierarchy root view not found")
        }
        return Context(window: window,
                       rootViewController: rootViewController,
                       topViewController: topViewController,
                       rootView: rootView)
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

    /// 从 root 控制器向下找到当前实际展示的**叶子**控制器。
    ///
    /// 沿 `presentedViewController` → `UINavigationController.visibleViewController` →
    /// `UITabBarController.selectedViewController` → `UISplitViewController.viewControllers.last`
    /// 一路钻到最深的叶子 VC。这是**操作类命令**（`ui.tap` / `ui.input` / `ui.control.sendAction`）
    /// 需要的语义：操作发生在最终承载 UI 的叶子 VC 上，locator 解析、默认激活路由、fingerprint
    /// 摘要都以它为基准。
    ///
    /// **不要用它作 view 子树采集根**：叶子 VC.view 与容器 chrome（如 `UITabBar`、容器自身的
    /// `UINavigationBar`）平级，chrome 不在叶子 VC.view 的子树里会丢失。采集命令用
    /// `hierarchyRootController(from:)`。
    ///
    /// 提为 internal 以便单测覆盖各容器组合（此前无测试覆盖）。
    ///
    /// - Parameter controller: window 的根控制器。
    /// - Returns: 钻到叶子后的顶部控制器。
    static func topViewController(from controller: UIViewController) -> UIViewController {
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

    /// 找到当前屏幕**最外层可见**的容器控制器，作为 view 子树采集根。
    ///
    /// 仅沿 `presentedViewController` 链向外走到最外层 presented VC，**不**钻 nav 栈、tab
    /// selection、split——这些容器（`UITabBarController` / `UINavigationController` /
    /// `UISplitViewController`）的 chrome（`UITabBar` / `UITabBarButton`、`UINavigationBar`、
    /// split 的 divider）是容器 VC.view 的子视图，与叶子 VC.view 平级。用本方法返回的容器
    /// VC.view 作采集根，chrome 才落在采集子树里，不再丢失。
    ///
    /// 与 `topViewController(from:)` 的分工（修复「modal 容器采集根盲区」）：
    /// - `topViewController` 钻叶子 → 操作命令用（`ui.tap` / `ui.input` / `ui.control.sendAction`
    ///   的操作发生在叶子 VC）；
    /// - `hierarchyRootController` 停在容器 → 采集命令用（`ui.inspect` / `ui.topViewHierarchy`
    ///   的采集需要 chrome）。
    /// 两者在 `currentContext` 里并列计算，分别填 `Context.topViewController` 与 `Context.rootView`。
    ///
    /// 各场景：
    /// - `present(UITabBarController)` → 返回该 `UITabBarController`（其 view 含 `UITabBar`）；
    /// - App 主界面 = `UITabBarController` 作 rootVC（无 presented）→ 返回它本身；
    /// - `present(UINavigationController)` → 返回该 nav（其 view 含 `UINavigationBar`）；
    /// - 纯 nav（无 modal）→ 返回 nav 本身；
    /// - 普通 VC（无容器无 modal）→ 返回自身，行为与 `topViewController` 相同。
    ///
    /// - Parameter controller: window 的根控制器。
    /// - Returns: 沿 presented 链走到头的最外层容器控制器。
    static func hierarchyRootController(from controller: UIViewController) -> UIViewController {
        var current = controller
        while let presented = current.presentedViewController {
            current = presented
        }
        return current
    }
}
#endif
