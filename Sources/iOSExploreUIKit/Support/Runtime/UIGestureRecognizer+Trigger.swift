#if DEBUG
#if canImport(UIKit)
import Foundation
import ObjectiveC
import UIKit

/// `UIGestureRecognizer` target-action 的 Debug 读取入口。
///
/// 公开 API 没有「枚举手势识别器的 target-action」的方法，但 Debug 探索工具需要让 `ui.tap`
/// 在不合成触摸的前提下，触发依赖 `UIGestureRecognizer`（`UITapGestureRecognizer`/
/// `UILongPressGestureRecognizer`/`UIPanGestureRecognizer` 等）的自定义 view——这类目标在
/// `UIKitDefaultActivationResolver` 里没有默认路由，原本直接 `unsupported_target`。本扩展把
/// runtime 读私有 ivar 的细节集中封装在 `UIGestureRecognizer` 自己身上；executor 只表达
/// 「读出 target-action 并按签名派发」，不直接接触私有 ivar 偏移或 ivar 名。
///
/// 路线与 Lookin（`LKS_GestureTargetActionsSearcher.m`）一致：`_targets` 数组 → 每个
/// `UIGestureRecognizerTarget` 私有对象的 `_target` + `_action`。区别是 Lookin 只 search
/// （列给 Mac 端展示），本扩展还要 invoke——invoke 在 `UIGestureTargetExecutor` 里按 selector
/// 签名派发（复用 `UINavigationBarButtonExecutor.invoke` 的 0/1/2 参签名适配）。
///
/// ivar 漂移策略：`UIGestureRecognizer._targets` 与 `UIGestureRecognizerTarget._target`/
/// `_action` 在 iOS 9~17 历史名稳定（Lookin iOS 17 实测），iOS 26 预期未漂移（见手势 adapter
/// 报告的 ivar 名表）。本扩展**不硬编码单一 ivar 名**：每个字段给候选名，用
/// `class_getInstanceVariable` 在类链上逐个探测，取首个存在的；新 iOS 版本若候选全不中，
/// 往 `GestureTargetField` 补候选名即可，不改读取与派发逻辑——漂移是工具的正常维护成本。
///
/// 异常规避：**全程用 ObjC runtime C API（`class_getInstanceVariable` + `ivar_getOffset` +
/// 裸内存 `load`），不用 KVC `value(forKey:)`**。Swift 无法 catch ObjC `NSException`，而
/// KVC 在 key 不存在时抛 `NSException`；C API 在 ivar 不存在时返回 `NULL`，安全降级返回
/// 空数组。`_target` 为 weak/assign 引用时，目标已 dealloc 则读出 nil，跳过该对（不 crash）。
///
/// 隔离：参照 `UIAlertAction+Trigger.swift`，整体 `#if DEBUG` + `#if canImport(UIKit)` 双重
/// 隔离，绝不进 Release 二进制（`swift build -c release` 验证空编译）。
extension UIGestureRecognizer {
    /// 读出手势识别器当前注册的 `(target, action)` 对。
    ///
    /// 读取链：`_targets`（`UIGestureRecognizerTarget*` 数组）→ 遍历每个 targetBox → 读其
    /// `_target`（目标对象）与 `_action`（SEL）。任一字段在当前 iOS 版本 ivar 不可读时跳过
    /// 该 targetBox；`_target` 读出 nil（weak 目标已 dealloc）也跳过。
    ///
    /// - Returns: `(target, action)` 对数组；无 target 或 ivar 全不命中时返回空数组（不抛异常）。
    @MainActor
    func explore_targetActionPairs() -> [(target: NSObject, action: Selector)] {
        guard let boxes = explore_readObjectArray(candidates: GestureTargetField.targets) else {
            return []
        }
        var pairs: [(target: NSObject, action: Selector)] = []
        for box in boxes {
            guard let target = GestureTargetReader.readObject(on: box, candidates: GestureTargetField.target) as? NSObject,
                  let action = GestureTargetReader.readSelector(on: box, candidates: GestureTargetField.action) else {
                continue
            }
            pairs.append((target, action))
        }
        return pairs
    }

    /// 读 `UIGestureRecognizer._targets` 数组型 ivar，返回 targetBox 列表；ivar 不存在返回 nil。
    private func explore_readObjectArray(candidates: [String]) -> [AnyObject]? {
        guard let ivar = GestureTargetReader.resolveIvar(on: self, candidates: candidates) else { return nil }
        let offset = ivar_getOffset(ivar)
        let basePtr = Unmanaged.passUnretained(self).toOpaque()
        // `_targets` 在 UIKit 内部是 NSMutableArray*；按对象指针读出，再桥接为 [AnyObject]。
        guard let arrayRef = basePtr.advanced(by: offset).load(as: AnyObject?.self),
              let array = arrayRef as? NSArray else {
            return nil
        }
        return array as [AnyObject]
    }
}

/// 私有 ivar 历史候选名（runtime 探测当前版本命中，不硬编码单一名字）。
///
/// 列表按「近期版本优先」排列；`class_getInstanceVariable` 在类链上取首个存在的。新 iOS 版本
/// 若候选全不中，往这里补候选名即可（漂移是工具的正常维护成本）。
///
/// iOS 26 实测命中（见 `docs/superpowers/reviews/2026-07-04-ui-tap-gesture-adapter.md`）：
/// `_targets` / `_target` / `_action` 均未漂移，与 Lookin（iOS 17）一致。
private enum GestureTargetField {
    /// `UIGestureRecognizer._targets`：`UIGestureRecognizerTarget*` 数组（UIKit 私有类）。
    static let targets = ["_targets", "targets"]
    /// `UIGestureRecognizerTarget._target`：目标对象（id，可能是 weak 引用，dealloc 后 nil）。
    static let target = ["_target", "target"]
    /// `UIGestureRecognizerTarget._action`：目标 selector（SEL）。
    static let action = ["_action", "action"]
}

/// ObjC runtime ivar 读取的纯 C 风格 helper。
///
/// 集中三类读取（ivar 解析、对象型 ivar、SEL 型 ivar），对 `UIGestureRecognizer` 与
/// `UIGestureRecognizerTarget`（私有 NSObject 子类）通用。全程 C API，不抛 `NSException`。
private enum GestureTargetReader {
    /// 在对象的类链上按候选名顺序找首个存在的 ivar。
    static func resolveIvar(on object: AnyObject, candidates: [String]) -> Ivar? {
        var current: AnyClass? = type(of: object)
        while let cls = current {
            for name in candidates {
                if let ivar = class_getInstanceVariable(cls, name) {
                    return ivar
                }
            }
            current = class_getSuperclass(cls)
        }
        return nil
    }

    /// 读对象型 ivar（`_target` 等），返回 Any?；ivar 不存在或读出 nil 返回 nil。
    ///
    /// 用裸内存 load：`Unmanaged.passUnretained` 取实例地址，`ivar_getOffset` 加偏移，`load`
    /// 读对象指针。weak ivar 在目标 dealloc 后被 runtime 自动置 nil，读出 nil 安全；strong
    /// ivar 读出有效指针。赋给调用方局部变量后由 ARC 接管引用计数。
    static func readObject(on object: AnyObject, candidates: [String]) -> Any? {
        guard let ivar = resolveIvar(on: object, candidates: candidates) else { return nil }
        let offset = ivar_getOffset(ivar)
        let basePtr = Unmanaged.passUnretained(object).toOpaque()
        return basePtr.advanced(by: offset).load(as: AnyObject?.self)
    }

    /// 读 SEL 型 ivar（`_action`），返回 Selector；ivar 不存在或读出 NULL 返回 nil。
    ///
    /// SEL 在内存里是 `objc_selector*` 指针，按指针宽度读出裸指针位模式，再 `unsafeBitCast`
    /// 为 `Selector`（两者在 64-bit 下都是 8 字节，位模式一致）。
    static func readSelector(on object: AnyObject, candidates: [String]) -> Selector? {
        guard let ivar = resolveIvar(on: object, candidates: candidates) else { return nil }
        let offset = ivar_getOffset(ivar)
        let basePtr = Unmanaged.passUnretained(object).toOpaque()
        guard let raw = basePtr.advanced(by: offset).load(as: UnsafeMutableRawPointer?.self) else {
            return nil
        }
        return unsafeBitCast(raw, to: Selector.self)
    }
}
#endif
#endif
