#if canImport(UIKit)
import Foundation
import ObjectiveC
import iOSExploreServer
import UIKit

/// 一对已触发的 `(gesture, target, action)` 摘要，供 `UIKitActionExecutor.executeTap` 序列化进
/// `ui.tap` 响应 JSON。
///
/// 值类型且全字段 `Sendable`，可跨 `MainActor` 边界传回命令 handler。字段只含类型名与 selector
/// 名（不含 target 对象引用或原始 payload），避免泄露业务对象。
struct UIGestureTriggeredPair: Sendable {
    /// 手势识别器类型名（如 `UITapGestureRecognizer`）。
    let gestureType: String
    /// target 对象类型名（如 `MyViewController`）。
    let targetType: String
    /// 已派发的 selector 名（如 `handleTap:`）。
    let action: String
}

/// `ui.tap` 的手势 target-action 显式 adapter 执行核心。
///
/// 背景：`UIKitDefaultActivationResolver` 只为 `UIButton`/`UISwitch`/文本输入三类确定目标提供
/// 默认激活路由；依赖 `UIGestureRecognizer`（`UITapGestureRecognizer`/`UILongPressGestureRecognizer`/
/// `UIPanGestureRecognizer` 等）的自定义 view 没有公开激活入口，原本直接 `unsupported_target`。
/// 合成触摸（`UITouch+Synthetic`）在 iOS 26 已被证不可行（见 realTouch spike 报告）。本 executor
/// 是降级方案：**不合成 event**，直接 runtime 读 view 上每个手势的 `_targets` → `_target` +
/// `_action`，按 selector 签名派发——与 Lookin（`LKS_GestureTargetActionsSearcher.m`）同路径，
/// 区别是 Lookin 只 search，本 executor 还 invoke。
///
/// 多手势 / 多 target 决策：**全触发**。一个 view 可能挂多个手势（tap + longPress + pan…），每个
/// 手势的 `_targets` 也可能多元素；adapter 不知道调用方意图，全触发最透明，由调用方据响应里的
/// `gestures` 列表自行判断结果。该决策写进手势 adapter 报告并由 `UIKitActionExecutorTests` 覆盖。
///
/// 隔离：本 executor 跟随 `UIKitActionExecutor` 的 `#if canImport(UIKit)`（不额外 `#if DEBUG`）——
/// 它在 Release 也要编译（macOS 空壳）。但底层 runtime 入口 `explore_targetActionPairs()` 是
/// `#if DEBUG #if canImport(UIKit)` 双隔离（私有 ivar 读取绝不进 Release）；因此调用它的逻辑用
/// `#if DEBUG ... #else 兜底 #endif` 包裹（参照 `UIAlertRespondExecutor.perform` 的隔离边界），
/// Release 下 `execute(on:)` 直接返回 `nil`，让 `executeTap` fallthrough 到 `unsupported_target`。
@MainActor
enum UIGestureTargetExecutor {
    /// 对 view 上所有手势的所有 target-action 按签名派发。
    ///
    /// - Parameter view: 已定位的目标 view（`executeTap` 传入的 canonical target）。
    /// - Returns: 触发摘要列表。`nil` 表示 view 无 `gestureRecognizers`（不该走 adapter，调用方
    ///   fallthrough 到默认路由或 `unsupported_target`）；空数组表示有手势但当前 iOS 版本
    ///   ivar 读不出 target-action（漂移，调用方同样 fallthrough）；非空表示已成功触发这些 pair。
    static func execute(on view: UIView) -> [UIGestureTriggeredPair]? {
        guard let gestures = view.gestureRecognizers, !gestures.isEmpty else {
            return nil
        }
        #if DEBUG
        var triggered: [UIGestureTriggeredPair] = []
        for gesture in gestures {
            for pair in gesture.explore_targetActionPairs() {
                invoke(target: pair.target, action: pair.action, sender: gesture)
                triggered.append(UIGestureTriggeredPair(
                    gestureType: String(describing: Swift.type(of: gesture)),
                    targetType: String(describing: Swift.type(of: pair.target)),
                    action: NSStringFromSelector(pair.action)))
            }
        }
        UIKitCommandLogging.info("command",
            "ui tap gesture adapter path-type=UIView gestures=\(gestures.count) triggered=\(triggered.count)")
        return triggered
        #else
        // Release：私有 ivar 读取入口整体 #if DEBUG 隔离，adapter 不可用。返回 nil 让 executeTap
        // fallthrough 到 unsupported_target（与 default 行为一致，绝不假装成功）。
        return nil
        #endif
    }

    /// 按 selector 实际签名派发 action，适配手势 target-action 的 0/1/2 参三种签名。
    ///
    /// 复用 `UINavigationBarButtonExecutor.invoke` 的签名探测逻辑：用 ObjC runtime 读方法真实
    /// 参数个数（含 `self`/`_cmd` 两个隐式参数），因此无参 action 为 2、一参 action 为 3、两参
    /// `(_:forEvent:)` action 为 4。不走 `UIApplication.sendAction`——它在模拟器单测里对无参
    /// selector 不会真正派发（见 `UINavigationBarButtonExecutor.trigger` 注释）。
    ///
    /// `sender` 传手势识别器本身：手势 target-action 约定第一个参数（如有）是 `UIGestureRecognizer`，
    /// 不是 view（与 UIControl 的 sender 是控件本身同理）。
    private static func invoke(target: NSObject, action: Selector, sender: UIGestureRecognizer) {
        let argumentCount: UInt
        if let method = class_getInstanceMethod(type(of: target), action) {
            argumentCount = UInt(method_getNumberOfArguments(method))
        } else {
            argumentCount = 2
        }
        switch argumentCount {
        case 3:
            // func action(_:UIGestureRecognizer)
            target.perform(action, with: sender)
        case 4:
            // func action(_:UIGestureRecognizer, forEvent:UIEvent?)
            target.perform(action, with: sender, with: nil)
        default:
            // func action() 或其他未知签名：按无参派发
            target.perform(action)
        }
    }
}
#endif
