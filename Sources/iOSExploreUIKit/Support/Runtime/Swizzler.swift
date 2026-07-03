#if DEBUG
#if canImport(UIKit)
import Foundation
import ObjectiveC

/// UIKit 调试能力共用的 Objective-C runtime 替换工具。
///
/// 本项目是 Debug-only 探索工具，部分能力需要 hook UIKit 的 Objective-C 方法。
/// 该类型把“查找方法、从 block 创建 IMP、替换实现、返回原始 IMP”集中到一个入口，
/// 让具体控件扩展只描述自己要 hook 哪个 selector，不在命令层或多个文件里散写 runtime 细节。
enum Swizzler {
    /// runtime 替换失败的原因。
    ///
    /// 这些错误只用于 Debug 工具内部日志和测试断言；业务命令层会把它们包装成
    /// `UIKitCommandError`，避免对外暴露 Objective-C runtime 细节。
    enum Failure: Error, CustomStringConvertible {
        /// 找不到目标方法，通常表示 selector 在当前 iOS 版本发生了变化。
        case methodNotFound(className: String, selector: String, isClassMethod: Bool)
        /// `imp_implementationWithBlock` 未能创建 replacement IMP。
        case replacementCreationFailed(selector: String)

        /// 适合写入日志的失败说明。
        var description: String {
            switch self {
            case .methodNotFound(let className, let selector, let isClassMethod):
                let methodKind = isClassMethod ? "class" : "instance"
                return "runtime method not found class=\(className) selector=\(selector) kind=\(methodKind)"
            case .replacementCreationFailed(let selector):
                return "runtime replacement creation failed selector=\(selector)"
            }
        }
    }

    /// 查找并替换类方法。
    ///
    /// - Parameters:
    ///   - cls: 被 hook 的 Objective-C 类。
    ///   - selector: 被替换的类方法 selector。
    ///   - replacementBlock: `@convention(block)` block，签名必须与原方法兼容。
    /// - Returns: 替换前的原始 IMP，调用方可在 replacement 中继续调用系统原实现。
    /// - Throws: 找不到 selector 或无法从 block 创建 IMP 时抛出 `Failure`。
    static func replaceClassMethod(on cls: AnyClass,
                                   selector: Selector,
                                   with replacementBlock: Any) throws -> IMP {
        guard let method = class_getClassMethod(cls, selector) else {
            throw Failure.methodNotFound(className: NSStringFromClass(cls),
                                         selector: NSStringFromSelector(selector),
                                         isClassMethod: true)
        }
        return try replace(method: method, selector: selector, with: replacementBlock)
    }

    /// 用 block 替换已查到的方法实现。
    ///
    /// - Parameters:
    ///   - method: `class_getInstanceMethod` 或 `class_getClassMethod` 返回的方法。
    ///   - selector: 仅用于错误说明和日志。
    ///   - replacementBlock: `@convention(block)` block，签名必须与原方法兼容。
    /// - Returns: 替换前的原始 IMP。
    /// - Throws: `imp_implementationWithBlock` 创建 replacement IMP 失败。
    private static func replace(method: Method,
                                selector: Selector,
                                with replacementBlock: Any) throws -> IMP {
        let replacementIMP = imp_implementationWithBlock(replacementBlock)
        return method_setImplementation(method, replacementIMP)
    }
}
#endif
#endif
