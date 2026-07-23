#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.navigation.back` 的执行核心。
///
/// 在 `MainActor` 上完成导航返回。成功返回纯 `JSON`，失败 `throw UIKitCommandError`
/// （典型为 `navigationBackUnavailable`），由命令 handler 顶层 catch 转 `ExploreResult`
/// envelope。
///
/// 策略语义：
/// - `dismiss`：仅当顶层控制器被 present 时 `dismiss`，否则失败。
/// - `navigationController`：仅当存在 `count > 1` 的导航栈时 `pop`，否则失败。
/// - `auto`：先尝试 dismiss，再尝试 pop；两者都不可用才失败。
///
/// 返回的 `strategy` 是**实际生效**的策略（`auto` 成功时反映 dismiss / navigationController），
/// 便于 agent 判断到底走了哪条返回路径。
///
/// 日志点：执行完成时记录 performed、生效策略、animated；失败日志由 command adapter
/// 顶层统一记录，避免同一失败重复打点。
@MainActor
enum UINavigationBackExecutor {
    /// 执行一次导航返回。
    ///
    /// - Parameters:
    ///   - input: 已通过 typed schema 校验的 navigation back 参数。
    ///   - context: 由调用方在 MainActor 上取好的查询上下文。
    /// - Returns: 成功时返回 performed、生效 strategy 与 topBefore/topAfter 控制器类型摘要。
    /// - Throws: `UIKitCommandError.navigationBackUnavailable`——dismiss 与 pop 均不可用时。
    static func execute(input: UINavigationBackInput, context: UIKitContextProvider.Context) throws -> JSON {
        let topBefore = context.topViewController
        let topBeforeDescription = describe(topBefore)
        // dismiss 转场完成后 UIKit 会清空被 dismiss 控制器的 presentingViewController，故在 dismiss
        // 之前先捕获，settle 之后用它作 topAfter，避免读到 nil 回退成刚 dismiss 的死 VC。
        let presentingBeforeDismiss = topBefore.presentingViewController

        var resolvedTop: UIViewController?
        var usedStrategy: NavigationBackStrategy?
        var dismissHappened = false

        switch input.strategy {
        case .dismiss:
            if performDismiss(topBefore, animated: input.animated) {
                usedStrategy = .dismiss
                dismissHappened = true
            }
        case .navigationController:
            if let popped = performPop(topBefore, animated: input.animated) {
                resolvedTop = popped
                usedStrategy = .navigationController
            }
        case .auto:
            if performDismiss(topBefore, animated: input.animated) {
                usedStrategy = .dismiss
                dismissHappened = true
            } else if let popped = performPop(topBefore, animated: input.animated) {
                resolvedTop = popped
                usedStrategy = .navigationController
            }
        }

        guard let usedStrategy else {
            throw UIKitCommandError.navigationBackUnavailable(action: NavigationBackCommand.actionName,
                                                              top: topBeforeDescription)
        }

        // settle 提前到读 topAfter 之前：dismiss/pop 转场在 MainActor run loop 上完成，
        // settle 后再读顶部，animated 与非 animated 行为一致（修 performDismiss 竞态）。
        settle(milliseconds: input.waitAfterMs)

        let topAfter: UIViewController
        if let resolved = resolvedTop {
            topAfter = resolved
        } else if dismissHappened, let presenting = presentingBeforeDismiss {
            topAfter = presenting
        } else {
            topAfter = topBefore
        }
        let topAfterDescription = describe(topAfter)
        UIKitCommandLogger.info("command", "ui navigation back complete performed=true strategy=\(usedStrategy.rawValue) animated=\(input.animated)")
        return response(strategy: usedStrategy,
                        topBefore: topBeforeDescription,
                        topAfter: topAfterDescription)
    }

    /// dismiss 被 present 的控制器；不可 dismiss（无 presenting）时返回 false。
    ///
    /// 只返回是否触发 dismiss，不返回新顶部——dismiss 后立即读 `presentingViewController` 在
    /// `animated=true` 时取决于 UIKit 内部转场时序。调用方在 `settle` 之后再读新顶部。
    private static func performDismiss(_ controller: UIViewController, animated: Bool) -> Bool {
        guard controller.presentingViewController != nil else { return false }
        controller.dismiss(animated: animated)
        return true
    }

    /// pop 导航栈顶层控制器，返回 pop 后的栈顶；不可 pop（无导航栈或仅一层）时返回 nil。
    private static func performPop(_ controller: UIViewController, animated: Bool) -> UIViewController? {
        guard let navigation = controller.navigationController,
              navigation.viewControllers.count > 1 else { return nil }
        navigation.popViewController(animated: animated)
        return navigation.viewControllers.last
    }

    /// 控制器类型名摘要，用于响应与日志，不暴露 UIKit 对象本身。
    private static func describe(_ controller: UIViewController) -> String {
        String(describing: type(of: controller))
    }

    /// 在主线程 run loop 上短暂等待转场稳定。
    private static func settle(milliseconds: Int) {
        guard milliseconds > 0 else { return }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: Double(milliseconds) / 1000.0))
    }

    /// 构造对外 JSON 响应，performed 恒为 true（失败已提前抛出）。
    private static func response(strategy: NavigationBackStrategy,
                                 topBefore: String,
                                 topAfter: String) -> JSON {
        [
            "performed": .bool(true),
            "strategy": .string(strategy.rawValue),
            "topBefore": .string(topBefore),
            "topAfter": .string(topAfter),
        ]
    }
}
#endif
