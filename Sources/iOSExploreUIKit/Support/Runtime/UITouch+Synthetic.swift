#if DEBUG
#if canImport(UIKit)
import Foundation
import ObjectiveC
import UIKit

/// 合成 `UITouch`/`UIEvent` 并注入 `UIWindow.sendEvent` 的 Debug 探索入口（spike）。
///
/// spike 背景：`ui.tap` 默认激活路由（`UIKitDefaultActivationResolver`）只覆盖
/// `UIButton` / `UISwitch` / 文本输入，依赖 `UIGestureRecognizer` 的自定义 view 直接
/// 返回 `unsupported_target`。本扩展验证「合成 `UITouch` + `UIEvent` → `UIWindow.sendEvent`」
/// 能否触发手势识别器、普通 view 点击、hit-test 遮挡场景，为是否给 `ui.tap` 加
/// `dispatchMode:"realTouch"` 提供真机结论。**本轮只做 spike，不改 `ui.tap` 主路径。**
///
/// ivar 漂移策略：`UITouch`/`UIEvent` 在 iOS 9+ 无公开初始化器，且 ivar 名随 iOS 版本漂移
/// （13/14/16/17/26 都调过）。本扩展**不硬编码单一 ivar 名**：每个字段给一组历史候选名，
/// 用 `class_getInstanceVariable` 在当前 iOS 版本逐个探测，取第一个存在的；命中名记入
/// `SyntheticTapDiagnostics` 供 spike 报告存档。新 iOS 版本若候选全不中，只需补候选名，
/// 不改合成逻辑——漂移是工具的正常维护成本，按版本适配。
///
/// 隔离：参照 `UIAlertAction+Trigger.swift`，整体 `#if DEBUG` + `#if canImport(UIKit)` 双重
/// 隔离，绝不进 Release 二进制（`swift build -c release` 验证空编译）。
///
/// 复用模式：KVC 反射 + ObjC runtime 与 `UIAlertAction+Trigger.swift` 一致；不直接散写
/// ivar 偏移或 selector 名到命令层。
@MainActor
enum SyntheticTouch {

    /// 字段历史候选名（runtime 探测当前版本哪个存在，不硬编码单一名字）。
    ///
    /// 列表按「近期版本优先」排列；`class_getInstanceVariable` 取第一个存在的。
    /// 新版本若全不中，往这里补候选名即可。
    ///
    /// iOS 26 实测（见 spike 报告）：UITouch 移除 `_view`（改 `_responder`/`_cachedResponderView`/
    /// `_warpedIntoView`），UIEvent 移除 `_touchesByKey`/`_touches`（touches 改由
    /// `_eventEnvironment`/`_gsEvent` 管理）。
    private enum Field {
        // UITouch
        static let location = ["_locationInWindow", "locationInWindow"]
        static let previousLocation = ["_previousLocationInWindow", "previousLocationInWindow"]
        static let phase = ["_phase", "phase"]
        static let timestamp = ["_timestamp", "timestamp", "_timeStamp"]
        static let tapCount = ["_tapCount", "tapCount"]
        /// iOS ≤17 用 `_view`；iOS 26 移除，改用 responder 系列（view 也是 responder）。
        static let view = ["_cachedResponderView", "_responder", "_warpedIntoView", "_view", "view"]
        static let window = ["_window", "window"]
        // UIEvent
        static let touchesByKey = ["_touchesByKey", "touchesByKey"]
        static let eventTouches = ["_touches", "touches", "_touchSet"]
        static let eventTimestamp = ["_timestamp", "timestamp"]
        static let eventSubtype = ["_subtype", "subtype"]
    }

    /// 在指定坐标合成一次 tap（began → ended），注入 `UIWindow.sendEvent`。
    ///
    /// 流程：
    /// 1. hit-test 拿到目标 view（记录到诊断，用于验证遮挡层命中）。
    /// 2. `+alloc` 一个 `UITouch`（复用同一实例，began/ended 改 phase），填 ivar。
    /// 3. `+alloc` 一个 `UIEvent`（began、ended 各建一个，避免共用 touches 集合引用导致
    ///    phase 交叠），把 touch 挂进 touches ivar。
    /// 4. `window.sendEvent(event)`；`RunLoop` 短暂 spin 给手势识别器状态机时间。
    ///
    /// - Parameters:
    ///   - window: 真实 key window（调用方负责 `makeKeyAndVisible` + `layoutIfNeeded`）。
    ///   - point: window 坐标系下的触摸点。
    /// - Returns: 合成诊断（ivar 命中表、全量 ivar 存档、UIEvent 方法表、hit-test 命中 view、卡点）。
    @discardableResult
    static func sendTap(in window: UIWindow, at point: CGPoint) -> SyntheticTapDiagnostics {
        var diagnostics = SyntheticTapDiagnostics()
        diagnostics.touchIvars = dumpIvars(of: UITouch.self)
        diagnostics.eventIvars = dumpIvars(of: UIEvent.self)
        // 探测 UIEvent 方法表里有无 `_setTouches`/`_addTouch`/`_setGSEvent` 等替代入口，
        // 供 spike 报告判断 iOS 26 是「补候选名即可」还是「需逆向 GSEvent」。
        diagnostics.eventMethods = dumpMethods(of: UIEvent.self,
                                               containing: ["touch", "set", "add", "environ", "gsevent", "hid"])

        // hit-test 先拿目标 view（用 nil event，纯几何命中）——验证遮挡层是否被命中。
        let hitView = window.hitTest(point, with: nil)
        diagnostics.hitTestViewDescription = hitView.map { String(describing: Swift.type(of: $0)) }

        guard let touch = makeInstance(of: UITouch.self) as? UITouch else {
            diagnostics.recordMissing("alloc(UITouch)")
            UIKitCommandLogging.error("command", "synthetic tap failed alloc UITouch")
            return diagnostics
        }

        let began = ProcessInfo.processInfo.systemUptime
        // began
        configure(touch: touch, phase: 0, at: point, view: hitView, window: window,
                  timestamp: began, diagnostics: &diagnostics)
        if let beganEvent = makeInstance(of: UIEvent.self) as? UIEvent {
            configure(event: beganEvent, timestamp: began, diagnostics: &diagnostics)
            attach(touch: touch, to: beganEvent, diagnostics: &diagnostics)
            window.sendEvent(beganEvent)
            diagnostics.sendEventCalls &+= 1
        } else {
            diagnostics.recordMissing("alloc(UIEvent)")
        }
        spinRunLoop(seconds: 0.02)

        // ended（同一 touch 实例改 phase；新 event，避免共用 touches 集合引用交叠）
        let ended = ProcessInfo.processInfo.systemUptime
        configure(touch: touch, phase: 3, at: point, view: hitView, window: window,
                  timestamp: ended, diagnostics: &diagnostics)
        if let endedEvent = makeInstance(of: UIEvent.self) as? UIEvent {
            configure(event: endedEvent, timestamp: ended, diagnostics: &diagnostics)
            attach(touch: touch, to: endedEvent, diagnostics: &diagnostics)
            window.sendEvent(endedEvent)
            diagnostics.sendEventCalls &+= 1
        }
        spinRunLoop(seconds: 0.05)

        UIKitCommandLogging.info("command",
            "synthetic tap sent point=(\(point.x),\(point.y)) hitTest=\(diagnostics.hitTestViewDescription ?? "nil") "
            + "sendEventCalls=\(diagnostics.sendEventCalls) setFields=\(diagnostics.setFields) "
            + "missing=\(diagnostics.missingFields)")
        return diagnostics
    }

    // MARK: - alloc

    /// 用 runtime 拿类方法 `+alloc` 的 IMP 调用，返回 retained (+1) 实例。
    ///
    /// `UITouch`/`UIEvent` 无公开初始化器，`+alloc` 创建的实例 ivar 默认 nil/0，由
    /// `configure(touch:event:)` 填充。Swift 强引用接管 +1 计数，离开作用域由 ARC release。
    private static func makeInstance(of cls: AnyClass) -> AnyObject? {
        guard let method = class_getClassMethod(cls, NSSelectorFromString("alloc")) else { return nil }
        // `method_getImplementation` 返回非可选 `IMP`；`+alloc` 由 NSObject 定义、子类继承。
        let allocFn = unsafeBitCast(method_getImplementation(method),
                                    to: (@convention(c) (AnyClass, Selector) -> AnyObject).self)
        return allocFn(cls, NSSelectorFromString("alloc"))
    }

    // MARK: - configure

    /// 填充 `UITouch` 的关键字段。
    ///
    /// - Parameters:
    ///   - phase: `UITouchPhase` 原始值（0=began, 1=moved, 2=stationary, 3=ended, 4=cancelled）。
    private static func configure(touch: UITouch,
                                  phase: Int,
                                  at point: CGPoint,
                                  view: UIView?,
                                  window: UIWindow,
                                  timestamp: Double,
                                  diagnostics: inout SyntheticTapDiagnostics) {
        setPrimitive(touch, candidates: Field.location, value: point, field: "touch.location", diagnostics: &diagnostics)
        setPrimitive(touch, candidates: Field.previousLocation, value: point, field: "touch.previousLocation", diagnostics: &diagnostics)
        setPrimitive(touch, candidates: Field.phase, value: phase, field: "touch.phase", diagnostics: &diagnostics)
        setPrimitive(touch, candidates: Field.timestamp, value: timestamp, field: "touch.timestamp", diagnostics: &diagnostics)
        setPrimitive(touch, candidates: Field.tapCount, value: 1, field: "touch.tapCount", diagnostics: &diagnostics)
        setObject(touch, candidates: Field.view, value: view, field: "touch.view", diagnostics: &diagnostics)
        setObject(touch, candidates: Field.window, value: window, field: "touch.window", diagnostics: &diagnostics)
    }

    /// 填充 `UIEvent` 的关键字段。
    private static func configure(event: UIEvent,
                                  timestamp: Double,
                                  diagnostics: inout SyntheticTapDiagnostics) {
        setPrimitive(event, candidates: Field.eventSubtype, value: 0, field: "event.subtype", diagnostics: &diagnostics)
        setPrimitive(event, candidates: Field.eventTimestamp, value: timestamp, field: "event.timestamp", diagnostics: &diagnostics)
    }

    /// 把 touch 挂到 event 的 touches 集合。
    ///
    /// 入口探测（iOS 26 UIEvent 方法表）：
    /// - `_initWithEvent:touches:`（iOS 26 主入口）：`- (instancetype)_initWithEvent:(UIEvent*)template
    ///   touches:(NSSet*)touches`，在 init 阶段把 touches 挂入 event。iOS 26 移除 `_touchesByKey`
    ///   后这是 UIKit 层唯一已知的「构造带 touches event」入口。
    /// - `_touchesByKey` / `_touches`（旧版本 ivar 直写）：iOS ≤17 经典入口，iOS 26 已移除。
    ///
    /// spike 用 `_initWithEvent:touches:`（template 传 nil，依赖 ObjC nil 消息安全），随后读
    /// `event.allTouches` 的 count 验证挂载是否成功。
    private static func attach(touch: UITouch, to event: UIEvent, diagnostics: inout SyntheticTapDiagnostics) {
        let touchSet = NSSet(array: [touch])
        let initSelector = NSSelectorFromString("_initWithEvent:touches:")
        if event.responds(to: initSelector),
           let method = class_getInstanceMethod(type(of: event), initSelector) {
            // IMP 强转按签名调用（2 个对象参：template event、touches set）。
            let fn = unsafeBitCast(method_getImplementation(method),
                                   to: (@convention(c) (AnyObject, Selector, AnyObject?, NSSet) -> AnyObject).self)
            _ = fn(event, initSelector, nil, touchSet)
            diagnostics.setFields["event.touches"] = "_initWithEvent:touches:"
        } else if let ivar = resolveIvar(on: event, candidates: Field.touchesByKey) {
            let name = String(cString: ivar_getName(ivar)!)
            let dict = NSMutableDictionary()
            dict.setObject(touchSet, forKey: "explore.synthetic" as NSString)
            (event as NSObject).setValue(dict, forKey: name)
            diagnostics.setFields["event.touches"] = name
        } else if let ivar = resolveIvar(on: event, candidates: Field.eventTouches) {
            let name = String(cString: ivar_getName(ivar)!)
            (event as NSObject).setValue(touchSet, forKey: name)
            diagnostics.setFields["event.touches"] = name
        } else {
            diagnostics.recordMissing("event.touches")
        }
        // 读公开 allTouches 验证挂载结果（>0 成功）。
        diagnostics.attachedTouchCount = event.allTouches?.count ?? -1
    }

    // MARK: - ivar helpers

    /// 在 `object` 的类链上按候选名顺序找第一个存在的 ivar。
    private static func resolveIvar(on object: AnyObject, candidates: [String]) -> Ivar? {
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

    /// 设原始类型 ivar（`CGPoint` / `Int` / `Double`）—— KVC + `NSValue`/`NSNumber` 包装。
    ///
    /// 用 KVC 而非裸内存写：KVC 按 ivar 声明语义正确处理 retain（对象）/ 原始值拷贝，
    /// 且能访问私有 ivar（NSObject 默认 `accessInstanceVariablesDirectively = YES`）。
    private static func setPrimitive(_ object: NSObject,
                                     candidates: [String],
                                     value: Any,
                                     field: String,
                                     diagnostics: inout SyntheticTapDiagnostics) {
        guard let ivar = resolveIvar(on: object, candidates: candidates) else {
            diagnostics.recordMissing(field)
            return
        }
        let name = String(cString: ivar_getName(ivar)!)
        let wrapped: Any
        switch value {
        case let point as CGPoint: wrapped = NSValue(cgPoint: point)
        case let integer as Int: wrapped = NSNumber(value: integer)
        case let double as Double: wrapped = NSNumber(value: double)
        default: wrapped = value
        }
        object.setValue(wrapped, forKey: name)
        diagnostics.setFields[field] = name
    }

    /// 设对象 ivar（`UIView` / `UIWindow`）—— KVC 直接设对象。
    private static func setObject(_ object: NSObject,
                                  candidates: [String],
                                  value: AnyObject?,
                                  field: String,
                                  diagnostics: inout SyntheticTapDiagnostics) {
        guard let ivar = resolveIvar(on: object, candidates: candidates) else {
            diagnostics.recordMissing(field)
            return
        }
        let name = String(cString: ivar_getName(ivar)!)
        object.setValue(value, forKey: name)
        diagnostics.setFields[field] = name
    }

    /// 枚举类链上所有 ivar 全名（`class.ivar` 形式），spike 报告存档用。
    ///
    /// 标记 `nonisolated`：纯 ObjC runtime 操作，不依赖 MainActor，测试可在任意隔离域
    /// 调用，用于存档当前 iOS 版本的 ivar 列表。
    nonisolated static func dumpIvars(of cls: AnyClass) -> [String] {
        var names: [String] = []
        var current: AnyClass? = cls
        while let c = current {
            var count: UInt32 = 0
            if let ivars = class_copyIvarList(c, &count) {
                for index in 0..<Int(count) {
                    if let name = ivar_getName(ivars[index]) {
                        names.append("\(NSStringFromClass(c)).\(String(cString: name))")
                    }
                }
                free(ivars)
            }
            current = class_getSuperclass(c)
        }
        return names
    }

    /// 枚举类链上方法名（`class.selector` 形式），可按子串过滤，spike 报告判断有无替代入口。
    ///
    /// 标记 `nonisolated`：纯 ObjC runtime 操作，不依赖 MainActor。
    nonisolated static func dumpMethods(of cls: AnyClass, containing substrings: [String] = []) -> [String] {
        var names: [String] = []
        var current: AnyClass? = cls
        while let c = current {
            var count: UInt32 = 0
            if let methods = class_copyMethodList(c, &count) {
                for index in 0..<Int(count) {
                    let selector = NSStringFromSelector(method_getName(methods[index]))
                    let lower = selector.lowercased()
                    if substrings.isEmpty || substrings.contains(where: { lower.contains($0) }) {
                        names.append("\(NSStringFromClass(c)).\(selector)")
                    }
                }
                free(methods)
            }
            current = class_getSuperclass(c)
        }
        return names
    }

    /// 在主线程 run loop 上短暂 spin，给手势识别器状态机时间处理 touch。
    private static func spinRunLoop(seconds: TimeInterval) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
    }
}

/// 合成 tap 诊断——记录当前 iOS 版本 ivar 命中情况、卡点，供 spike 报告存档。
///
/// 该结构是值类型且所有字段 `Sendable`，可跨 MainActor 边界传回测试断言。
public struct SyntheticTapDiagnostics: Sendable {
    /// 全量 `UITouch` ivar（`class.ivar` 形式），spike 报告 ivar 名表来源。
    public var touchIvars: [String] = []
    /// 全量 `UIEvent` ivar。
    public var eventIvars: [String] = []
    /// `UIEvent` 方法表（过滤后），用于判断有无 `_setTouches`/`_addTouch`/`_setGSEvent` 替代入口。
    public var eventMethods: [String] = []
    /// 字段 → 实际命中的 ivar 名（runtime 探测结果，验证候选策略有效性）。
    public var setFields: [String: String] = [:]
    /// 未找到 ivar 的字段（候选名全不中）—— ivar 漂移告军，spike 报告标记卡点。
    public var missingFields: [String] = []
    /// `sendEvent` 调用次数（应为 2：began + ended；小于 2 说明 event alloc 失败）。
    public var sendEventCalls: Int = 0
    /// attach 后 `event.allTouches` 的 count（>0 表示 touch 成功挂进 event；0 表示挂载失败）。
    public var attachedTouchCount: Int = -1
    /// 该坐标 hit-test 命中的 view 类型描述（验证遮挡层是否被命中）。
    public var hitTestViewDescription: String?

    /// 去重记录缺失字段。
    mutating func recordMissing(_ field: String) {
        if !missingFields.contains(field) {
            missingFields.append(field)
        }
    }
}

extension UIWindow {
    /// 在指定坐标合成一次 tap 注入 `sendEvent`，返回合成诊断。
    ///
    /// spike 入口：调用方（spike 测试 / SPMExample runner）负责先 `makeKeyAndVisible` +
    /// `layoutIfNeeded`，再调本方法。**生产代码不调用**——本方法仅用于真机验证合成触摸可行性。
    @discardableResult
    @MainActor
    public func explore_sendSyntheticTap(at point: CGPoint) -> SyntheticTapDiagnostics {
        SyntheticTouch.sendTap(in: self, at: point)
    }
}
#endif
#endif
