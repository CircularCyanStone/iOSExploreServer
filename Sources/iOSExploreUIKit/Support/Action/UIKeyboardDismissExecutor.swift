#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.keyboard.dismiss` 的执行核心。
///
/// 在 `MainActor` 上完成 first responder 查找与键盘收起。成功返回纯 `JSON`，失败
/// `throw UIKitCommandError`，由命令 handler 顶层 catch 转成 `ExploreResult` envelope。
///
/// 日志点：执行完成时记录是否收起、策略和 first responder 类型变化；失败日志由 command
/// adapter 顶层统一记录，避免同一失败重复打点。
@MainActor
enum UIKeyboardDismissExecutor {
    /// 执行一次键盘收起。
    ///
    /// - Parameters:
    ///   - input: 已通过 typed schema 校验的 keyboard dismiss 参数。
    ///   - context: 由调用方在 MainActor 上取好的查询上下文。
    /// - Returns: 成功时返回 dismissed、strategy、firstResponderBefore/After 摘要。
    /// - Throws: `UIKitCommandError.keyboardDismissFailed`——尝试后仍存在 first responder。
    static func execute(input: UIKeyboardDismissInput, context: UIKitContextProvider.Context) throws -> JSON {
        let before = firstResponder(in: context.window)
        let beforeType = before.map { String(describing: type(of: $0)) }

        guard before != nil else {
            settle(milliseconds: input.waitAfterMs)
            UIKitCommandLogger.info("command", "ui keyboard dismiss complete dismissed=false strategy=\(input.strategy.rawValue) before=nil after=nil")
            return response(dismissed: false,
                            strategy: input.strategy,
                            firstResponderBefore: nil,
                            firstResponderAfter: nil)
        }

        switch input.strategy {
        case .auto:
            before?.resignFirstResponder()
            if firstResponder(in: context.window) != nil {
                context.window.endEditing(true)
            }
        case .resignFirstResponder:
            before?.resignFirstResponder()
        case .endEditing:
            context.window.endEditing(true)
        }

        settle(milliseconds: input.waitAfterMs)

        let after = firstResponder(in: context.window)
        let afterType = after.map { String(describing: type(of: $0)) }
        guard after == nil else {
            throw UIKitCommandError.keyboardDismissFailed(action: KeyboardDismissCommand.actionName,
                                                         strategy: input.strategy.rawValue)
        }

        UIKitCommandLogger.info("command", "ui keyboard dismiss complete dismissed=true strategy=\(input.strategy.rawValue) before=\(beforeType ?? "nil") after=nil")
        return response(dismissed: true,
                        strategy: input.strategy,
                        firstResponderBefore: beforeType,
                        firstResponderAfter: afterType)
    }

    /// 递归查找当前 view 树里的 first responder。
    private static func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for subview in view.subviews {
            if let responder = firstResponder(in: subview) {
                return responder
            }
        }
        return nil
    }

    /// 在主线程 run loop 上短暂等待 UIKit responder 状态稳定。
    private static func settle(milliseconds: Int) {
        guard milliseconds > 0 else { return }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: Double(milliseconds) / 1000.0))
    }

    /// 构造对外 JSON 响应，保持 null 与字符串字段稳定。
    private static func response(dismissed: Bool,
                                 strategy: KeyboardDismissStrategy,
                                 firstResponderBefore: String?,
                                 firstResponderAfter: String?) -> JSON {
        [
            "dismissed": .bool(dismissed),
            "strategy": .string(strategy.rawValue),
            "firstResponderBefore": firstResponderBefore.map(JSONValue.string) ?? .null,
            "firstResponderAfter": firstResponderAfter.map(JSONValue.string) ?? .null,
        ]
    }
}
#endif
