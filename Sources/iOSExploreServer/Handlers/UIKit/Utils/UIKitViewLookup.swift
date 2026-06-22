#if canImport(UIKit)
import Foundation
import UIKit

/// UIKit view 定位工具。
///
/// 所有方法都在 `MainActor` 上读取 UIKit 状态。工具只负责查找和描述 view，不触发事件、
/// 不修改业务 UI，供 `ui.control.sendAction`、`ui.tap` 等命令复用。
@MainActor
enum UIKitViewLookup {
    /// 当前顶部控制器 view 查询上下文。
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

    /// 已定位到的 UIKit view 及其路径。
    struct LocatedView {
        /// 目标 view。
        let view: UIView
        /// 从顶部控制器根 view 开始的 subviews 下标链。
        let indexes: [Int]

        /// 与 `ui.topViewHierarchy` 一致的路径字符串。
        var pathString: String {
            UIKitViewLookupTarget.pathString(from: indexes)
        }
    }

    /// 定位结果。
    enum LocateResult {
        /// 找到唯一 view。
        case found(LocatedView)
        /// 没有找到。
        case notFound
        /// identifier 匹配到多个 view。
        case ambiguous(count: Int)
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
    /// - Returns: 成功时返回上下文；失败时返回不可用原因。
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

    /// 按通用目标定位 view。
    ///
    /// - Parameters:
    ///   - target: 通用定位目标。
    ///   - rootView: 顶部控制器根 view。
    /// - Returns: 定位结果。
    static func locate(target: UIKitViewLookupTarget, in rootView: UIView) -> LocateResult {
        switch target {
        case .accessibilityIdentifier(let identifier):
            let matches = findViews(withAccessibilityIdentifier: identifier, in: rootView, path: [])
            if matches.isEmpty { return .notFound }
            if matches.count > 1 { return .ambiguous(count: matches.count) }
            return .found(matches[0])
        case .path(let indexes):
            guard let located = findView(at: indexes, in: rootView) else { return .notFound }
            return .found(located)
        }
    }

    /// 判断 candidate 是否为 ancestor 本身或其子孙。
    static func view(_ candidate: UIView, isDescendantOfOrSameAs ancestor: UIView) -> Bool {
        var current: UIView? = candidate
        while let view = current {
            if view === ancestor { return true }
            current = view.superview
        }
        return false
    }

    /// 从指定 view 向上查找最近的 UIControl，最多查到 boundary。
    static func nearestControl(from view: UIView, stoppingAt boundary: UIView?) -> UIControl? {
        var current: UIView? = view
        while let view = current {
            if let control = view as? UIControl { return control }
            if let boundary, view === boundary { return nil }
            current = view.superview
        }
        return nil
    }

    /// 在 root 中查找指定 view 的路径。
    static func locatedView(for target: UIView, in root: UIView) -> LocatedView? {
        if target === root {
            return LocatedView(view: root, indexes: [])
        }
        return locatedDescendant(for: target, in: root, path: [])
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

    /// 按 path 下标定位 view。
    private static func findView(at indexes: [Int], in root: UIView) -> LocatedView? {
        var current = root
        var path: [Int] = []
        for index in indexes {
            guard index < current.subviews.count else { return nil }
            current = current.subviews[index]
            path.append(index)
        }
        return LocatedView(view: current, indexes: path)
    }

    /// 按 accessibilityIdentifier 精确查找 view。
    private static func findViews(withAccessibilityIdentifier identifier: String,
                                  in root: UIView,
                                  path: [Int]) -> [LocatedView] {
        var matches: [LocatedView] = []
        if root.accessibilityIdentifier == identifier {
            matches.append(LocatedView(view: root, indexes: path))
        }
        for (index, child) in root.subviews.enumerated() {
            matches.append(contentsOf: findViews(withAccessibilityIdentifier: identifier,
                                                in: child,
                                                path: path + [index]))
        }
        return matches
    }

    /// 递归查找指定 view 的路径。
    private static func locatedDescendant(for target: UIView, in root: UIView, path: [Int]) -> LocatedView? {
        for (index, child) in root.subviews.enumerated() {
            let childPath = path + [index]
            if child === target {
                return LocatedView(view: child, indexes: childPath)
            }
            if let found = locatedDescendant(for: target, in: child, path: childPath) {
                return found
            }
        }
        return nil
    }
}
#endif
