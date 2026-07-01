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

    /// 按通用目标定位 view，失败时抛出由调用方提供的业务错误。
    ///
    /// 仅解析 `accessibilityIdentifier` 与 `path` 变体；`windowPoint` 不应传入本方法（传入会抛
    /// `notFound()`，作为防御）。`notFound` / `ambiguous` 两个工厂由调用方提供——因为 tap 与
    /// control 命令对「未找到 / 歧义」使用不同 message/log 语境（`targetNotFound` vs
    /// `controlTargetNotFound` 工厂），定位器本身不持有调用语境，交由调用方决定。
    ///
    /// - Parameters:
    ///   - locator: 统一定位器。
    ///   - rootView: 顶部控制器根 view。
    ///   - notFound: 未命中时构造的业务错误工厂。
    ///   - ambiguous: 命中多个时构造的业务错误工厂，入参为命中数量。
    /// - Returns: 唯一命中的 `LocatedView`。
    /// - Throws: 调用方提供的 `UIKitCommandError`（未找到 / 歧义）。
    static func locate(locator: UIKitLocator,
                       in rootView: UIView,
                       notFound: () -> UIKitCommandError,
                       ambiguous: (Int) -> UIKitCommandError) throws -> LocatedView {
        switch locator {
        case .accessibilityIdentifier(let identifier):
            let matches = findViews(withAccessibilityIdentifier: identifier, in: rootView, path: [])
            if matches.isEmpty { throw notFound() }
            if matches.count > 1 { throw ambiguous(matches.count) }
            return matches[0]
        case .path(let indexes):
            guard let located = findView(at: indexes, in: rootView) else { throw notFound() }
            return located
        case .windowPoint:
            throw notFound()
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

    /// 判断 `rootView` 中是否存在匹配 `locator` 的 view（至少一个），不抛错。
    ///
    /// 供 `ui.wait` 的 targetExists / targetGone 判断存在性：与 `locate(...)` 不同，本方法
    /// 把"未找到 / 多个匹配"都视为存在性结果而非错误。`windowPoint` 不表达 view 存在性，返回 false。
    ///
    /// - Parameters:
    ///   - locator: 统一定位器（仅 accessibilityIdentifier / path 有意义）。
    ///   - rootView: 顶部控制器根 view。
    /// - Returns: 是否存在至少一个匹配 view。
    static func contains(locator: UIKitLocator, in rootView: UIView) -> Bool {
        switch locator {
        case .accessibilityIdentifier(let identifier):
            return !findViews(withAccessibilityIdentifier: identifier, in: rootView, path: []).isEmpty
        case .path(let indexes):
            return findView(at: indexes, in: rootView) != nil
        case .windowPoint:
            return false
        }
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
