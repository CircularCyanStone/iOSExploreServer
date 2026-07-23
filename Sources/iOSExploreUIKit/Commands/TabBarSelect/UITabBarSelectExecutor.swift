#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.tabBar.selectTab` 命令的 executor。
///
/// 职责:在 MainActor 上定位 UITabBarController → 按 index/title 解析目标 tab → 设置
/// selectedIndex → 可选触发 delegate。完全走 controller 层,不依赖 view 子树遍历(因此不受
/// modal 场景 resolver 盲区影响)。
@MainActor
enum UITabBarSelectExecutor {
    /// 执行 tab 切换。
    ///
    /// - Parameters:
    ///   - input: 已校验的输入模型。
    ///   - context: 当前 UIKit 查询上下文。
    /// - Returns: 切换结果(previousIndex / selectedIndex / previousTitle / selectedTitle / tabCount)。
    /// - Throws: `UIKitCommandError`——TabBarController 未找到 / tab 索引越界 / title 匹配失败。
    static func execute(input: UITabBarSelectInput, context: UIKitContextProvider.Context) throws -> JSON {
        let action = "ui.tabBar.selectTab"

        // 1. 定位 UITabBarController
        let tabBarController: UITabBarController
        if let path = input.tabBarControllerPath {
            // 显式路径:解析 controller path
            guard let parsed = parseControllerPath(path) else {
                UIKitCommandLogger.error("command", "\(action) invalid controller path path=\(path)")
                throw UIKitCommandError.invalidData(action: action, message: "invalid controller path: \(path)")
            }
            let resolved = try UIControllerResolver.resolve(from: context.rootViewController, path: parsed)
            guard let tbc = resolved as? UITabBarController else {
                let msg = "controller at path '\(path)' is not a UITabBarController"
                UIKitCommandLogger.error("command", "\(action) controller type mismatch path=\(path) actualType=\(type(of: resolved))")
                throw UIKitCommandError.invalidData(action: action, message: msg)
            }
            tabBarController = tbc
            UIKitCommandLogger.info("command", "\(action) resolved explicit tabBarController path=\(path)")
        } else {
            // 自动查找:先沿 presented 链找最外层容器,若不是 UITabBarController 再从 topViewController 向上找
            tabBarController = try findTabBarController(context: context, action: action)
            UIKitCommandLogger.info("command", "\(action) auto-found tabBarController")
        }

        // 2. 读取当前状态
        guard let viewControllers = tabBarController.viewControllers, !viewControllers.isEmpty else {
            UIKitCommandLogger.error("command", "\(action) tabBarController has no viewControllers")
            throw UIKitCommandError.targetNotFound(
                action: action,
                message: "UITabBarController has no tabs",
                logMessage: "\(action) viewControllers empty or nil"
            )
        }

        let previousIndex = tabBarController.selectedIndex
        let previousTitle = (previousIndex >= 0 && previousIndex < viewControllers.count)
            ? viewControllers[previousIndex].tabBarItem?.title
            : nil

        // 3. 解析目标 index
        let targetIndex: Int
        if let index = input.index {
            targetIndex = index
        } else if let title = input.title {
            // 按 title 查找(首个匹配)
            guard let matchedIndex = viewControllers.firstIndex(where: { $0.tabBarItem?.title == title }) else {
                UIKitCommandLogger.error("command", "\(action) tab title not found title=\(title)")
                throw UIKitCommandError.targetNotFound(
                    action: action,
                    message: "tab with title '\(title)' not found",
                    logMessage: "\(action) title match failed title=\(title) availableTitles=\(viewControllers.compactMap(\.tabBarItem?.title))"
                )
            }
            targetIndex = matchedIndex
        } else {
            // 不可能走到这里(parse 已校验 index/title 必有其一)
            fatalError("unreachable: index and title both nil after parse")
        }

        // 4. 索引范围校验
        guard targetIndex >= 0, targetIndex < viewControllers.count else {
            let msg = "tab index \(targetIndex) out of range (total: \(viewControllers.count))"
            UIKitCommandLogger.error("command", "\(action) index out of range index=\(targetIndex) count=\(viewControllers.count)")
            throw UIKitCommandError.invalidData(action: action, message: msg)
        }

        // 5. 设置 selectedIndex
        tabBarController.selectedIndex = targetIndex
        let selectedVC = viewControllers[targetIndex]
        let selectedTitle = selectedVC.tabBarItem?.title

        // 6. 可选触发 delegate
        if input.triggerDelegate {
            tabBarController.delegate?.tabBarController?(tabBarController, didSelect: selectedVC)
            UIKitCommandLogger.info("command", "\(action) delegate triggered previousIndex=\(previousIndex) selectedIndex=\(targetIndex)")
        } else {
            UIKitCommandLogger.info("command", "\(action) delegate not triggered previousIndex=\(previousIndex) selectedIndex=\(targetIndex)")
        }

        // 7. 返回结果
        return [
            "previousIndex": .double(Double(previousIndex)),
            "selectedIndex": .double(Double(targetIndex)),
            "previousTitle": previousTitle.map(JSONValue.string) ?? .null,
            "selectedTitle": selectedTitle.map(JSONValue.string) ?? .null,
            "tabCount": .double(Double(viewControllers.count))
        ]
    }

    /// 自动查找当前层级中的 UITabBarController。
    ///
    /// 策略:
    /// 1. 沿 rootViewController → presentedViewController 链走到最外层可见 VC,若是
    ///    UITabBarController 直接返回(modal TabBar 场景)。
    /// 2. 否则从 topViewController 向上找最近的 UITabBarController 容器(App 主界面 TabBar 场景)。
    ///
    /// - Parameters:
    ///   - context: 当前查询上下文。
    ///   - action: 命令名(用于日志)。
    /// - Returns: 找到的 UITabBarController。
    /// - Throws: `UIKitCommandError.targetNotFound`——找不到 UITabBarController。
    private static func findTabBarController(context: UIKitContextProvider.Context, action: String) throws -> UITabBarController {
        // 策略 1:沿 presented 链找最外层
        var current = context.rootViewController
        while let presented = current.presentedViewController {
            current = presented
        }
        if let tbc = current as? UITabBarController {
            return tbc
        }

        // 策略 2:从 topViewController 向上找容器
        current = context.topViewController
        while true {
            if let tbc = current as? UITabBarController {
                return tbc
            }
            // UINavigationController 和 UITabBarController 的 parent 指向它们的容器
            if let parent = current.parent {
                current = parent
            } else {
                break
            }
        }

        UIKitCommandLogger.error("command", "\(action) no UITabBarController found in hierarchy")
        throw UIKitCommandError.targetNotFound(
            action: action,
            message: "no UITabBarController found in current view hierarchy",
            logMessage: "\(action) auto-find failed rootVC=\(type(of: context.rootViewController)) topVC=\(type(of: context.topViewController))"
        )
    }
}
#endif
