#if DEBUG
#if canImport(UIKit)
import Foundation
import ObjectiveC
import UIKit

/// 关联对象 key 使用固定整数，在调用 Objective-C API 时临时转成指针。
///
/// 这样避免 Swift 6 把传统 `static var UInt8` key 判定为非隔离可变全局状态，也避免把
/// 非 Sendable 的 `UnsafeRawPointer` 存成全局常量。Objective-C associated object 只比较
/// key 指针值，不会解引用该地址。
private let alertActionHandlerAssociationKeyValue: UInt = 0x6953454148414c54

/// 每次使用时从 Sendable 的整数常量生成 key 指针，避免持有全局 pointer 状态。
private func alertActionHandlerAssociationKey() -> UnsafeRawPointer {
    UnsafeRawPointer(bitPattern: alertActionHandlerAssociationKeyValue)!
}

/// `UIAlertAction` handler 捕获与触发入口。
///
/// 公开 API 没有提供“执行某个 `UIAlertAction` handler”的方法，但 Debug 探索工具需要让
/// `ui.alert.respond` 在不模拟真实手指点击的情况下响应弹窗按钮。本扩展把 runtime hook、
/// 关联对象、KVC 兜底和 block 调用签名集中封装在 `UIAlertAction` 自己身上；命令 executor
/// 只表达“选择并触发按钮”，不直接接触私有 ivar 或 swizzle 细节。
extension UIAlertAction {
    /// handler 触发失败的内部原因。
    ///
    /// 这里保留 runtime 层的具体失败信息，命令层会转换成稳定的业务错误码。
    enum ExploreTriggerFailure: Error, CustomStringConvertible {
        /// 未能从关联对象或 KVC 路径中取到 handler block。
        case handlerUnavailable
        /// 安装 handler 捕获时 runtime hook 失败。
        case captureInstallFailed(String)

        /// 适合写入日志的失败说明。
        var description: String {
            switch self {
            case .handlerUnavailable:
                return "ui alert action handler unavailable"
            case .captureInstallFailed(let reason):
                return "ui alert action handler capture install failed reason=\(reason)"
            }
        }
    }

    /// `UIAlertAction` handler 的 Objective-C block 签名。
    private typealias HandlerBlock = @convention(block) (UIAlertAction) -> Void

    /// `+[UIAlertAction actionWithTitle:style:handler:]` 的原始 C 函数签名。
    private typealias ActionFactory = @convention(c) (AnyClass, Selector, NSString?, Int, AnyObject?) -> AnyObject

    /// 安装状态锁，确保多次注册 UIKit 命令时只 hook 一次。
    private static let exploreHandlerCaptureLock = NSLock()
    /// 是否已经安装 handler 捕获。
    private static var exploreHandlerCaptureInstalled = false
    /// 保留原始 IMP，便于 replacement 调用系统原实现，也便于调试确认 hook 已安装。
    private static var exploreOriginalActionFactoryIMP: IMP?

    /// 安装 `UIAlertAction` handler 捕获。
    ///
    /// 该方法 hook `actionWithTitle:style:handler:` 类方法：先调用系统原实现创建 action，
    /// 再把传入的 handler block 通过关联对象保存到 action 实例上。这样 hook 之后创建的
    /// alert action 可以不依赖私有 ivar 直接取回 handler；hook 之前已创建的 action 仍由
    /// `explore_performHandler()` 的 KVC 兜底路径处理。
    ///
    /// - Throws: 当前 iOS 版本找不到目标 selector，或 replacement IMP 创建失败。
    static func explore_installHandlerCapture() throws {
        exploreHandlerCaptureLock.lock()
        defer { exploreHandlerCaptureLock.unlock() }

        guard !exploreHandlerCaptureInstalled else {
            UIKitCommandLogger.info("command", "ui alert action handler capture already installed")
            return
        }

        let selector = NSSelectorFromString("actionWithTitle:style:handler:")
        guard let method = class_getClassMethod(UIAlertAction.self, selector) else {
            let failure = ExploreTriggerFailure.captureInstallFailed(
                "missing selector \(NSStringFromSelector(selector))"
            )
            UIKitCommandLogger.error("command", failure.description)
            throw failure
        }

        let originalIMP = method_getImplementation(method)
        let originalFactory = unsafeBitCast(originalIMP, to: ActionFactory.self)
        let replacement: @convention(block) (AnyClass, NSString?, Int, AnyObject?) -> AnyObject = {
            actionClass, title, style, handler in
            let action = originalFactory(actionClass, selector, title, style, handler)
            if let handler {
                objc_setAssociatedObject(action,
                                         alertActionHandlerAssociationKey(),
                                         handler,
                                         .OBJC_ASSOCIATION_COPY_NONATOMIC)
            }
            return action
        }

        do {
            _ = try Swizzler.replaceClassMethod(on: UIAlertAction.self,
                                                selector: selector,
                                                with: replacement)
            exploreOriginalActionFactoryIMP = originalIMP
            exploreHandlerCaptureInstalled = true
            UIKitCommandLogger.info("command", "ui alert action handler capture installed selector=actionWithTitle:style:handler:")
        } catch {
            let failure = ExploreTriggerFailure.captureInstallFailed("\(error)")
            UIKitCommandLogger.error("command", failure.description)
            throw failure
        }
    }

    /// 触发当前 action 的 handler。
    ///
    /// 触发顺序是：先读 swizzle 捕获到的关联对象；如果 action 创建早于 hook 安装或来自更早
    /// 的第三方代码，再尝试 KVC key `handler`，它在当前 iOS 26.x 对应 `_handler` ivar。
    /// 取到 block 后按 spike 验证过的 `(UIAlertAction) -> Void` 签名调用。
    ///
    /// - Throws: 两条路径都取不到 handler 时抛出 `ExploreTriggerFailure.handlerUnavailable`。
    func explore_performHandler() throws {
        guard let handlerObject = explore_capturedHandler() ?? explore_kvcHandler() else {
            let failure = ExploreTriggerFailure.handlerUnavailable
            UIKitCommandLogger.error("command", failure.description)
            throw failure
        }

        let handler = unsafeBitCast(handlerObject, to: HandlerBlock.self)
        handler(self)
        UIKitCommandLogger.info("command", "ui alert action handler performed")
    }

    /// 读取 hook 创建 action 时保存的 handler。
    ///
    /// - Returns: 关联对象中的 block；如果 action 创建早于 hook 安装则返回 nil。
    private func explore_capturedHandler() -> AnyObject? {
        objc_getAssociatedObject(self, alertActionHandlerAssociationKey()) as AnyObject?
    }

    /// 使用当前 iOS 26.x 已验证的 KVC key 读取 handler。
    ///
    /// - Returns: KVC `handler` 对应的 block；如果当前系统版本路径不存在则返回 nil。
    private func explore_kvcHandler() -> AnyObject? {
        value(forKey: "handler") as AnyObject?
    }
}
#endif
#endif
