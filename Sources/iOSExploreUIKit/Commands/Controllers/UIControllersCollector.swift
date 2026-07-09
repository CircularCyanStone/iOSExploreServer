#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// UIKit controller 结构骨架采集器。
///
/// 所有 UIKit 访问限制在 `MainActor`。采集器只读 controller 属性，从 `window.rootViewController`
/// 出发遍历整个 controller 结构（navigation stack / presented 链 / tab / split / childViewController），
/// 生成嵌套骨架树与每个 controller 的唯一定位 path，供 agent 看清全局界面结构。
///
/// 遍历采用**互斥类型分发**：每个 controller 按 UIKit 类型（`UINavigationController`/
/// `UITabBarController`/`UISplitViewController`/其它）经唯一一种机制枚举子节点，避免容器的
/// `viewControllers` 与 `.children` 双重计数。`presentedViewController` 正交于容器关系，
/// 统一作为最后一个子节点附加（视觉上内容在下、modal 在上）。
@MainActor
enum UIControllersCollector {
    /// 缺省最大深度兜底。
    ///
    /// `maxDepth` 缺省（nil）时使用，防止坏状态或自定义容器引入的环导致无限递归。结构良好的
    /// UIKit 是真树，这是防御性兜底。
    private static let hardMaxDepth = 32

    /// 采集当前 App 的 controller 结构骨架并转换为命令响应（生产入口）。
    ///
    /// - Parameter query: 采集参数。
    /// - Returns: 结构骨架 JSON。
    /// - Throws: `UIKitCommandError.hierarchyUnavailable`——active window / root / top 任一不可用时。
    static func collect(query: UIControllersInput) throws -> JSON {
        UIKitCommandLogging.info("command", "ui controllers collect mainactor start maxDepth=\(query.maxDepth.map(String.init) ?? "none")")
        let context = try UIKitContextProvider.currentContext(action: ControllersCommand.actionName)
        return collect(query: query, context: context)
    }

    /// 采集 controller 结构骨架（注入入口：测试与内部复用）。
    ///
    /// 与 `collect(query:)` 的唯一区别是 context 由调用方提供，使遍历流程可在测试里用
    /// 可控 controller 树（手动构造的 `UIKitContextProvider.Context`）驱动。
    ///
    /// - Parameters:
    ///   - query: 采集参数。
    ///   - context: 当前 UIKit 查询上下文。
    /// - Returns: 结构骨架 JSON。
    static func collect(query: UIControllersInput, context: UIKitContextProvider.Context) -> JSON {
        let topID = ObjectIdentifier(context.topViewController)
        var visited: Set<ObjectIdentifier> = []
        var topPath: String?
        let root = buildNode(context.rootViewController,
                             role: .root,
                             path: "root",
                             depth: 0,
                             isSelected: nil,
                             isVisible: nil,
                             query: query,
                             topID: topID,
                             visited: &visited,
                             topPath: &topPath)
        var data: JSON = [
            "screen": .object(screenJSON(window: context.window,
                                         rootViewController: context.rootViewController,
                                         topViewController: context.topViewController)),
            "controllerCount": .double(Double(root.nodeCount)),
            "topPath": topPath.map(JSONValue.string) ?? .null,
        ]
        data["root"] = .object(root.toJSON())
        UIKitCommandLogging.info("command", "ui controllers collect completed controllerCount=\(root.nodeCount) topPath=\(topPath ?? "none")")
        return data
    }

    /// 递归构建 controller 骨架节点。
    ///
    /// - Parameters:
    ///   - controller: 当前 controller。
    ///   - role: 当前角色（root 由入口赋，其余由父边段派生）。
    ///   - path: 当前 path。
    ///   - depth: 当前深度（root = 0）。
    ///   - isSelected: 由父容器边计算的选中态（仅 tab 子节点非 nil）。
    ///   - isVisible: 由父容器边计算的可见态（仅 navigation 栈顶非 nil）。
    ///   - query: 采集参数（含 maxDepth）。
    ///   - topID: `topViewController` 的 ObjectIdentifier，用于捕获 topPath。
    ///   - visited: 已展开 children 的 controller 集合（cycle 防护），inout 递归累积。
    ///   - topPath: 捕获到的 topViewController path，inout 递归回写。
    /// - Returns: 当前 controller 的骨架节点。
    private static func buildNode(_ controller: UIViewController,
                                  role: UIControllerRole,
                                  path: String,
                                  depth: Int,
                                  isSelected: Bool?,
                                  isVisible: Bool?,
                                  query: UIControllersInput,
                                  topID: ObjectIdentifier,
                                  visited: inout Set<ObjectIdentifier>,
                                  topPath: inout String?) -> UIControllerNode {
        if ObjectIdentifier(controller) == topID { topPath = path }

        // cycle 防护：首次访问展开 children 并登记；重复访问（坏状态/自定义容器成环）作为叶子。
        let id = ObjectIdentifier(controller)
        let alreadyVisited = visited.contains(id)
        if !alreadyVisited { visited.insert(id) }

        var children: [UIControllerNode] = []
        if !alreadyVisited {
            let limit = query.maxDepth ?? hardMaxDepth
            if depth < limit {
                for edge in edges(of: controller) {
                    children.append(buildNode(edge.child,
                                              role: edge.segment.role,
                                              path: path + "." + edge.segment.stringValue,
                                              depth: depth + 1,
                                              isSelected: edge.isSelected,
                                              isVisible: edge.isVisible,
                                              query: query,
                                              topID: topID,
                                              visited: &visited,
                                              topPath: &topPath))
                }
            }
        }
        return UIControllerNode(path: path,
                                type: String(describing: type(of: controller)),
                                role: role,
                                title: controller.title,
                                isViewLoaded: controller.isViewLoaded,
                                isSelected: isSelected,
                                isVisible: isVisible,
                                children: children)
    }

    /// 父 controller 到子 controller 的边。
    private struct ControllerEdge {
        /// 子节点路径段（决定 path 段与角色）。
        let segment: UIControllerPathSegment
        /// 子 controller。
        let child: UIViewController
        /// 是否选中（仅 tab 子节点非 nil）。
        let isSelected: Bool?
        /// 是否可见（仅 navigation 栈顶非 nil）。
        let isVisible: Bool?
    }

    /// 按 controller 的 UIKit 类型枚举子节点（互斥类型分发）。
    ///
    /// 容器（nav/tab/split）走各自的 `viewControllers`，普通 controller 走 `children`，
    /// 保证每个子 controller 经唯一一种机制枚举、不被双重计数。`presentedViewController`
    /// 正交于容器关系，附为最后一个子节点。
    /// - Parameter controller: 待枚举子节点的 controller。
    /// - Returns: 边列表。
    private static func edges(of controller: UIViewController) -> [ControllerEdge] {
        var result: [ControllerEdge] = []
        if let nav = controller as? UINavigationController {
            let topIndex = nav.viewControllers.count - 1
            for (index, vc) in nav.viewControllers.enumerated() {
                result.append(ControllerEdge(segment: .navigation(index),
                                              child: vc,
                                              isSelected: nil,
                                              isVisible: index == topIndex))
            }
        } else if let tab = controller as? UITabBarController {
            // tab.viewControllers 是可选数组；为 nil（极端）时不枚举，不报错。
            if let vcs = tab.viewControllers {
                let selected = tab.selectedViewController
                for (index, vc) in vcs.enumerated() {
                    result.append(ControllerEdge(segment: .tab(index),
                                                  child: vc,
                                                  isSelected: selected === vc,
                                                  isVisible: nil))
                }
            }
        } else if let split = controller as? UISplitViewController {
            for (index, vc) in split.viewControllers.enumerated() {
                result.append(ControllerEdge(segment: .split(index),
                                              child: vc,
                                              isSelected: nil,
                                              isVisible: nil))
            }
        } else {
            for (index, vc) in controller.children.enumerated() {
                result.append(ControllerEdge(segment: .child(index),
                                              child: vc,
                                              isSelected: nil,
                                              isVisible: nil))
            }
        }
        // presented 正交：任何 controller（含容器）都可能 present，附为最后子节点。
        if let presented = controller.presentedViewController {
            result.append(ControllerEdge(segment: .presented,
                                          child: presented,
                                          isSelected: nil,
                                          isVisible: nil))
        }
        return result
    }

    /// 生成响应 `screen` 摘要：window/root/top 的运行时类型名。
    private static func screenJSON(window: UIWindow,
                                   rootViewController: UIViewController,
                                   topViewController: UIViewController) -> JSON {
        [
            "windowType": .string(String(describing: type(of: window))),
            "rootViewController": .string(String(describing: type(of: rootViewController))),
            "topViewController": .string(String(describing: type(of: topViewController))),
        ]
    }
}
#endif
