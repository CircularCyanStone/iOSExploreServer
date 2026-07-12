#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.navigation.tapBarButton` 的执行核心。
///
/// 执行器只触发当前 `UINavigationItem` 上的 `UIBarButtonItem`，不走坐标、不依赖导航栏内部
/// 私有 view。成功只表示按钮动作已发出；调用方仍需等待或重新观察页面。
@MainActor
enum UINavigationBarButtonExecutor {
    /// 执行一次导航栏按钮触发。
    ///
    /// - Parameters:
    ///   - input: 已通过 typed schema 校验的按钮选择输入。
    ///   - context: 当前 UIKit 查询上下文。
    /// - Returns: 成功时返回按钮摘要和前后顶部控制器类型。
    /// - Throws: `UIKitCommandError`——导航栏不可用、按钮不存在、不匹配、不可用或不支持触发。
    static func execute(input: UINavigationBarButtonInput,
                        context: UIKitContextProvider.Context) throws -> JSON {
        let topBefore = describe(context.topViewController)
        let (item, placement, index) = try UINavigationBarInspector.item(for: input, topViewController: context.topViewController)
        guard item.isEnabled else {
            throw UIKitCommandError.navigationBarItemDisabled(
                action: NavigationBarButtonCommand.actionName,
                selector: input.selectorSummary
            )
        }

        guard trigger(item: item) else {
            throw UIKitCommandError.navigationBarItemUnsupported(
                action: NavigationBarButtonCommand.actionName,
                selector: input.selectorSummary
            )
        }

        settle(milliseconds: input.waitAfterMs)
        let topAfter = describe(context.topViewController.navigationController?.topViewController ?? context.topViewController)
        UIKitCommandLogging.info("command", "ui navigation bar button complete performed=true placement=\(placement.rawValue) index=\(index)")
        return [
            "performed": .bool(true),
            "placement": .string(placement.rawValue),
            "index": .double(Double(index)),
            "title": item.title.map(JSONValue.string) ?? .null,
            "accessibilityIdentifier": item.accessibilityIdentifier.map(JSONValue.string) ?? .null,
            "topBefore": .string(topBefore),
            "topAfter": .string(topAfter),
        ]
    }

    /// 触发按钮。customView 为 UIControl 时发送 `.touchUpInside`，否则走 UIBarButtonItem 的 action。
    ///
    /// 只要 item 携带 `action` 即视为可触发：target 非 nil 时按 selector 实际签名派发，nil 时走
    /// responder chain。不直接用 `UIApplication.sendAction`——它在模拟器单测里对无参 selector
    /// 不会真正派发，会让 `func action()` 这类常见签名（如 Example App 的 `openControlTest()`）
    /// 被静默吞掉。走 NSObject `perform` 路径与 UIControl / UIBarButtonItem 内部 dispatch 行为一致。
    /// 真正"无可触发动作"的 item（action 为 nil 且 customView 非 UIControl）才返回 false。
    private static func trigger(item: UIBarButtonItem) -> Bool {
        if let control = item.customView as? UIControl {
            control.sendActions(for: .touchUpInside)
            return true
        }
        guard let action = item.action else { return false }
        if let target = item.target as? NSObject {
            invoke(target: target, action: action, sender: item)
            return true
        }
        // target 为 nil 时走 responder chain，由 UIApplication 按 action 签名适配派发。
        UIApplication.shared.sendAction(action, to: item.target, from: item, for: nil)
        return true
    }

    /// 按 selector 实际签名派发 action，适配 UIBarButtonItem 的 0/1/2 参三种 action 签名。
    ///
    /// 用 ObjC runtime 读方法真实参数个数（含 `self`/`_cmd` 两个隐式参数），因此无参 action 为 2、
    /// 一参 action 为 3、两参 `(_:forEvent:)` action 为 4。这与 UIControl target-action 派发规则一致，
    /// 也避开 `UIApplication.sendAction` 在单测里不派发无参 selector 的问题。
    private static func invoke(target: NSObject, action: Selector, sender: UIBarButtonItem) {
        let argumentCount: UInt
        if let method = class_getInstanceMethod(type(of: target), action) {
            argumentCount = UInt(method_getNumberOfArguments(method))
        } else {
            argumentCount = 2
        }
        switch argumentCount {
        case 3:
            // func action(_:Any)
            target.perform(action, with: sender)
        case 4:
            // func action(_:Any, forEvent:UIEvent?)
            target.perform(action, with: sender, with: nil)
        default:
            // func action() 或其他未知签名：按无参派发
            target.perform(action)
        }
    }

    /// 控制器类型名摘要。
    private static func describe(_ controller: UIViewController) -> String {
        String(describing: type(of: controller))
    }

    /// 在主线程 run loop 上短暂等待转场稳定。
    private static func settle(milliseconds: Int) {
        guard milliseconds > 0 else { return }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: Double(milliseconds) / 1000.0))
    }
}
#endif

