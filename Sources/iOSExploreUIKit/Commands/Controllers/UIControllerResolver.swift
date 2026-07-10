#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// controller 定位路径的 UIKit 端实时解析器。
///
/// `parseControllerPath` 把 path 字符串解析为段序列（Foundation-only），本类型沿段序列在
/// **当前** UIKit controller 树里线性跟踪，返回此刻对应的 `UIViewController`。path 是位置
/// 语义、非稳定 ID：push/pop/选中 tab 切换后同一 index 可能对应不同 controller，调用方自行
/// 承担定位失败或定位到非预期 controller 的风险，与现有 view path（`root/0/1`）同语义。
///
/// 仅与 `UIControllersCollector.edges(of:)` 一致的"互斥类型分发"判断对齐：每段按 UIKit
/// 类型走唯一一种子节点枚举（nav/tab/split 各取 `viewControllers`，其余取 `children`），
/// `presented` 取 `presentedViewController`。Resolver 不关心 `ControllerEdge` 的
/// `isSelected`/`isVisible` 元数据——只沿 path 走一条线。
@MainActor
enum UIControllerResolver {
    /// 沿 path 段序列从给定 root controller 走到目标 controller。
    ///
    /// 实时遍历当前 UIKit 树，**不缓存**：每次调用都沿 path 在此刻的结构里走一遍。空 path
    /// （入参 `"root"`）返回 root 自身。
    ///
    /// - Parameters:
    ///   - root: 遍历起点，通常是 `window.rootViewController`。
    ///   - path: `parseControllerPath` 解析出的段序列（空数组代表 `"root"`）。
    /// - Returns: path 终点对应的 `UIViewController`。
    /// - Throws: `UIKitCommandError.targetNotFound`——任何一段在当前 tree 上找不到对应子节点
    ///   （index 越界、容器类型不符、presented 不存在）。
    static func resolve(from root: UIViewController,
                        path parsed: [UIControllerPathSegment]) throws -> UIViewController {
        var current = root
        for segment in parsed {
            current = try match(segment, from: current)
        }
        return current
    }

    /// 单段匹配：在 `parent` 的子节点里按段类型 + index/value 找到对应子 controller。
    ///
    /// 与 `UIControllersCollector.edges(of:)` 同样的互斥类型分发，但只返回单步结果。
    /// - Parameters:
    ///   - segment: 待匹配的路径段。
    ///   - parent: 当前所在 controller。
    /// - Returns: 段指向的子 controller。
    /// - Throws: `UIKitCommandError.targetNotFound`——段与 parent 类型或当前子节点集合不匹配。
    private static func match(_ segment: UIControllerPathSegment,
                              from parent: UIViewController) throws -> UIViewController {
        switch segment {
        case .navigation(let index):
            guard let nav = parent as? UINavigationController else {
                throw segmentNotFound(parent: parent, segment: segment, reason: "not a UINavigationController")
            }
            guard index >= 0, index < nav.viewControllers.count else {
                throw segmentNotFound(parent: parent, segment: segment, reason: "nav index out of range")
            }
            return nav.viewControllers[index]
        case .tab(let index):
            guard let tab = parent as? UITabBarController else {
                throw segmentNotFound(parent: parent, segment: segment, reason: "not a UITabBarController")
            }
            guard let vcs = tab.viewControllers, index >= 0, index < vcs.count else {
                throw segmentNotFound(parent: parent, segment: segment, reason: "tab index out of range")
            }
            return vcs[index]
        case .split(let index):
            guard let split = parent as? UISplitViewController else {
                throw segmentNotFound(parent: parent, segment: segment, reason: "not a UISplitViewController")
            }
            guard index >= 0, index < split.viewControllers.count else {
                throw segmentNotFound(parent: parent, segment: segment, reason: "split index out of range")
            }
            return split.viewControllers[index]
        case .child(let index):
            guard index >= 0, index < parent.children.count else {
                throw segmentNotFound(parent: parent, segment: segment, reason: "child index out of range")
            }
            return parent.children[index]
        case .presented:
            guard let presented = parent.presentedViewController else {
                throw segmentNotFound(parent: parent, segment: segment, reason: "no presentedViewController")
            }
            return presented
        }
    }

    /// 构造段未命中的 `targetNotFound` 错误。
    ///
    /// 把失败段与父 controller 类型写进 logMessage，便于排障；对外 message 通用、不泄露内部类型名。
    private static func segmentNotFound(parent: UIViewController,
                                        segment: UIControllerPathSegment,
                                        reason: String) -> UIKitCommandError {
        let parentType = String(describing: type(of: parent))
        let pathTail = controllerPathString([segment])
        return UIKitCommandError.targetNotFound(
            action: "resolve",
            message: "controller path segment not found: \(pathTail)",
            logMessage: "ui controller resolve segment not found segment=\(segment.stringValue) parentType=\(parentType) reason=\(reason)"
        )
    }
}
#endif
