#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// UIKit locator 解析器。
///
/// 在 `MainActor` 上把 `UIKitLocator` 的 `accessibilityIdentifier`/`path` 变体解析为
/// 真实 `UIView`，并提供祖先判断与 nearest-control 查找。`windowPoint` 变体**不**在此
/// 解析（它交给 executor 用坐标 hit-test），本类型只负责 view 定位。
///
/// 该类型是 MainActor 隔离域的一部分：调用方（adapter）只能 `await` 其入口，不能把
/// 解析出的 `UIView` 返回到非隔离域——跨边界只传 Sendable 摘要（路径、类型名）。
@MainActor
enum UIKitLocatorResolver {
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

    /// 按通用目标定位 view。
    ///
    /// 仅解析 `accessibilityIdentifier` 与 `path` 变体；`windowPoint` 不应传入本方法。
    ///
    /// - Parameters:
    ///   - locator: 统一定位器。
    ///   - rootView: 顶部控制器根 view。
    /// - Returns: 定位结果。
    static func locate(locator: UIKitLocator, in rootView: UIView) -> LocateResult {
        switch locator {
        case .accessibilityIdentifier(let identifier):
            let matches = findViews(withAccessibilityIdentifier: identifier, in: rootView, path: [])
            if matches.isEmpty { return .notFound }
            if matches.count > 1 { return .ambiguous(count: matches.count) }
            return .found(matches[0])
        case .path(let indexes):
            guard let located = findView(at: indexes, in: rootView) else { return .notFound }
            return .found(located)
        case .windowPoint:
            return .notFound
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

    /// 按 path 下标链取出对应的 view（仅用于陈旧指纹重采，不关心完整结构）。
    ///
    /// - Parameters:
    ///   - indexes: 从根 view 开始的 subviews 下标链。
    ///   - rootView: 顶部控制器根 view。
    /// - Returns: 命中的 view；下标越界或路径不存在时返回 nil。
    static func view(at indexes: [Int], in rootView: UIView) -> UIView? {
        findView(at: indexes, in: rootView)?.view
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
