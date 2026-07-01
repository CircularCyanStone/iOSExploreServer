#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// UIKit 动作执行器。
///
/// 把 tap 与 control.sendAction 的实际 UIKit 执行逻辑收敛到单一入口。adapter
/// （`UITapCommand`/`UIControlSendActionCommand`）只解析请求、构造 `UIKitActionPlan`，再
/// `await executor.execute(plan)`；执行器在 `MainActor` 上完成固定流程：取 Context、resolve
/// locator、共享 capability 校验、hit-test（tap）或 `sendActions(for:)`（control event）、
/// 生成既有 JSON。
///
/// 该类型是 `@MainActor`：adapter（network queue 上的命令 handler）只能 `await` 其入口，
/// 不能把解析出的 `UIView`/`UIControl` 返回到非隔离域——跨边界只传 `Sendable` 的成功 `JSON`
/// 或 `throw UIKitCommandError`（由 handler 顶层 catch 转成 `ExploreResult` envelope）。
///
/// 与 `UIKitActionCapabilityResolver` 共用同一份"什么 view 能派发动作"规则：执行器解析出
/// 命中的控件后，必须用 resolver 的动作列表确认目标支持当前动作（tap/control event），避免
/// collector 宣告的 `availableActions` 与实际派发分叉。disabled 控件会被统一拒绝，调用方需
/// 重新查询或选择可用目标。
///
/// 陈旧校验（Task 6）：当 plan 携带 `.path + snapshotID` 时，执行器从当前 view 树重采该
/// path 的指纹，与 `UIKitSnapshotStore` 保存的比对；陈旧（TTL 过期或指纹不匹配）时抛出
/// `UIKitCommandError.staleLocator`（`stale_locator`）。identifier 定位、windowPoint 或无
/// snapshotID 时不校验。失败日志不在本执行器内记录——统一由 handler 顶层 catch 后记录
/// `error.failure.logMessage`；本执行器仅记录进入、hit-test、sendActions 等成功路径摘要，
/// 不写完整 payload。
@MainActor
enum UIKitActionExecutor {
    /// tap 动作的固定 action 名，用于错误工厂与日志关联。
    private static let tapAction = "ui.tap"
    /// control.sendAction 动作的固定 action 名。
    private static let controlAction = "ui.control.sendAction"

    /// 执行一个 UIKit 动作计划（生产入口：取真实 App 上下文后转调注入版本）。
    ///
    /// 在 `MainActor` 上读取当前前台 window 与顶部控制器；上下文不可用时抛出
    /// `hierarchyUnavailable`。取得上下文后转调 `execute(_:context:)`，使派发流程
    /// （locate / hit-test / capability / sendActions / 陈旧校验）可在测试里用可控 view 树
    /// 驱动，而不依赖真实 UIApplication scene。
    ///
    /// - Parameter plan: 动作计划（tap 或 controlEvent）。
    /// - Returns: 成功时返回迁移前一致的 JSON。
    /// - Throws: `UIKitCommandError`——上下文不可用 / 定位失败 / 能力不支持 / 陈旧等。
    static func execute(_ plan: UIKitActionPlan) throws -> JSON {
        let context = try UIKitContextProvider.currentContext(action: actionName(for: plan))
        return try execute(plan, context: context)
    }

    /// 执行一个 UIKit 动作计划（注入入口：测试与内部复用）。
    ///
    /// 与 `execute(_:)` 的唯一区别是上下文由调用方提供。固定流程：按 plan 变体 resolve
    /// locator / hit-test → 共享 capability 校验 → hit-test（tap）或 `sendActions(for:)`
    /// （control event）→ 生成既有 JSON。
    ///
    /// - Parameters:
    ///   - plan: 动作计划（tap 或 controlEvent）。
    ///   - context: 当前 UIKit 查询上下文（持有真实 window / rootView，可由测试构造）。
    /// - Returns: 成功时返回迁移前一致的 JSON。
    /// - Throws: `UIKitCommandError`——定位失败 / 能力不支持 / 陈旧等。
    static func execute(_ plan: UIKitActionPlan, context: UIKitContextProvider.Context) throws -> JSON {
        switch plan {
        case .tap(let locator, let snapshotID):
            return try executeTap(locator: locator, snapshotID: snapshotID, context: context)
        case .controlEvent(let locator, let event, let snapshotID):
            return try executeControlEvent(locator: locator, event: event, snapshotID: snapshotID, context: context)
        }
    }

    /// plan 变体对应的 action 名，供上下文不可用时的错误工厂与日志关联。
    private static func actionName(for plan: UIKitActionPlan) -> String {
        switch plan {
        case .tap: return tapAction
        case .controlEvent: return controlAction
        }
    }

    /// 仅在 `.path + snapshotID` 同时存在时做陈旧校验。
    ///
    /// 复用调用方已 locate 的 `LocatedView`（避免对同一 path 二次遍历），重新采集该 path 的
    /// 指纹，与 store 中保存的比对。陈旧时抛出 `UIKitCommandError.staleLocator`（`stale_locator`）；
    /// 无 snapshotID 时不校验（直接返回）。"仅对 `.path` 校验"由调用方
    /// （`executeTap`/`executeControlEvent`）在调用前用 `if case .path` 把关。
    ///
    /// - Parameters:
    ///   - located: 调用方已 resolve 的定位视图（含 view 与 pathString）。
    ///   - snapshotID: 调用方携带的快照标识。
    ///   - context: 当前 UIKit 上下文（用于重采指纹）。
    ///   - action: 触发校验的 action 名（错误关联）。
    /// - Throws: `UIKitCommandError.staleLocator`——指纹陈旧时。
    private static func validateFreshness(located: UIKitLocatorResolver.LocatedView,
                                          snapshotID: String?,
                                          context: UIKitContextProvider.Context,
                                          action: String) throws {
        guard let snapshotID else { return }
        let path = located.pathString
        let current = UIKitFingerprintCollector.fingerprint(for: located.view,
                                                             path: path,
                                                             rootView: context.rootView,
                                                             digest: UIKitFingerprintCollector.digest(topViewController: context.topViewController))
        if UIKitSnapshotStore.shared.isStale(snapshotID: snapshotID,
                                             path: path,
                                             context: UIKitFingerprintCollector.context(window: context.window, topViewController: context.topViewController),
                                             current: current) {
            throw UIKitCommandError.staleLocator(action: action, snapshotID: snapshotID)
        }
    }

    // MARK: - Tap

    /// 执行 tap 动作。
    ///
    /// view 定位（identifier / path）先 `locate` 一次，陈旧校验与执行都复用该 `LocatedView`，
    /// 避免对同一 path 二次遍历。windowPoint 走 hit-test 分支，不涉及 path 校验。
    ///
    /// - Parameters:
    ///   - locator: 点击目标的统一定位器。
    ///   - snapshotID: 可选 snapshotID，仅在 `.path` 且非 nil 时校验。
    ///   - context: 当前 UIKit 查询上下文（由 `execute(_:)` 注入）。
    /// - Returns: tap 命令 JSON，与迁移前 `UITapCommand` 行为一致。
    /// - Throws: `UIKitCommandError`——定位失败 / 陈旧 / hit-test 失败 / 能力不支持。
    private static func executeTap(locator: UIKitLocator,
                                   snapshotID: String?,
                                   context: UIKitContextProvider.Context) throws -> JSON {
        switch locator {
        case .accessibilityIdentifier, .path:
            // 先 locate 一次，freshness 校验与执行都复用该 LocatedView（避免二次遍历同一 path）。
            let target = locatorSummary(locator)
            let located = try UIKitLocatorResolver.locate(
                locator: locator,
                in: context.rootView,
                notFound: { UIKitCommandError.targetNotFound(action: tapAction, targetDescription: target) },
                ambiguous: { UIKitCommandError.targetAmbiguous(action: tapAction, targetDescription: target, count: $0) })
            // 陈旧校验仅对 .path + snapshotID，复用 located.view 重采指纹。
            if case .path = locator, let snapshotID {
                try validateFreshness(located: located, snapshotID: snapshotID, context: context, action: tapAction)
            }
            return try executeTapViewTarget(located, context: context)
        case .windowPoint(let x, let y):
            return try executeTapWindowPoint(CGPoint(x: x, y: y),
                                             targetDescription: locatorSummary(locator),
                                             context: context)
        }
    }

    /// 点击按 view 定位的目标（identifier / path）。
    ///
    /// - Parameters:
    ///   - located: 调用方已 resolve 的定位视图（复用，不再二次 locate）。
    ///   - context: 当前 UIKit 上下文。
    /// - Throws: `UIKitCommandError`——hit-test 失败 / 命中不一致 / 能力不支持。
    private static func executeTapViewTarget(_ located: UIKitLocatorResolver.LocatedView,
                                             context: UIKitContextProvider.Context) throws -> JSON {
        let point = located.view.convert(CGPoint(x: located.view.bounds.midX,
                                                 y: located.view.bounds.midY),
                                         to: context.window)
        guard let hitView = context.window.hitTest(point, with: nil) else {
            throw UIKitCommandError.hitTestFailed(action: tapAction,
                                                  targetDescription: located.pathString,
                                                  x: Double(point.x),
                                                  y: Double(point.y))
        }
        guard UIKitLocatorResolver.view(hitView, isDescendantOfOrSameAs: located.view) ||
              UIKitLocatorResolver.view(located.view, isDescendantOfOrSameAs: hitView) else {
            throw UIKitCommandError.hitMismatch(action: tapAction,
                                                targetDescription: located.pathString,
                                                hitType: String(describing: Swift.type(of: hitView)))
        }

        let control = (located.view as? UIControl) ??
            UIKitLocatorResolver.nearestControl(from: hitView, stoppingAt: located.view.superview)
        return try dispatchTap(to: control,
                               hitView: hitView,
                               point: point,
                               targetDescription: located.pathString,
                               context: context)
    }

    /// 点击 window 坐标。
    private static func executeTapWindowPoint(_ point: CGPoint,
                                              targetDescription: String,
                                              context: UIKitContextProvider.Context) throws -> JSON {
        guard let hitView = context.window.hitTest(point, with: nil) else {
            throw UIKitCommandError.hitTestFailed(action: tapAction,
                                                  targetDescription: targetDescription,
                                                  x: Double(point.x),
                                                  y: Double(point.y))
        }
        let control = UIKitLocatorResolver.nearestControl(from: hitView, stoppingAt: nil)
        return try dispatchTap(to: control,
                               hitView: hitView,
                               point: point,
                               targetDescription: targetDescription,
                               context: context)
    }

    /// 对 UIControl 派发第一版 tap fallback（`touchUpInside`）。
    ///
    /// capability 校验：通过 `UIKitActionCapabilityResolver` 确认命中控件支持 `tap` 动作
    /// （与 collector 的 `availableActions` 共用同一份规则）。不可用控件会抛出
    /// `invalid_data`，不会绕过 discovery 声明直接派发 `touchUpInside`。
    private static func dispatchTap(to control: UIControl?,
                                    hitView: UIView,
                                    point: CGPoint,
                                    targetDescription: String,
                                    context: UIKitContextProvider.Context) throws -> JSON {
        guard let control else {
            throw UIKitCommandError.unsupportedTarget(action: tapAction,
                                                      targetDescription: targetDescription,
                                                      type: String(describing: Swift.type(of: hitView)))
        }

        let availability = UIKitActionCapabilityResolver.resolve(view: control,
                                                                  rootView: context.rootView,
                                                                  nearestControl: control)
        guard availability.actions.contains(.tap) else {
            throw UIKitCommandError.unsupportedAction(action: tapAction,
                                                      targetDescription: targetDescription,
                                                      requestedAction: UIKitActionKind.tap.rawValue)
        }

        let locatedControl = UIKitLocatorResolver.locatedView(for: control, in: context.rootView)
        let locatedHit = UIKitLocatorResolver.locatedView(for: hitView, in: context.rootView)
        UIKitCommandLogging.info("command", "ui tap dispatch controlActionFallback target=\(targetDescription) controlType=\(String(describing: Swift.type(of: control))) hitType=\(String(describing: Swift.type(of: hitView))) x=\(Double(point.x)) y=\(Double(point.y))")
        control.sendActions(for: .touchUpInside)
        return [
            "tapped": .bool(true),
            "dispatchMode": .string("controlActionFallback"),
            "event": .string("touchUpInside"),
            "x": .double(Double(point.x)),
            "y": .double(Double(point.y)),
            "target": .string(targetDescription),
            "hitType": .string(String(describing: Swift.type(of: hitView))),
            "hitPath": locatedHit.map { .string($0.pathString) } ?? .null,
            "controlType": .string(String(describing: Swift.type(of: control))),
            "controlPath": locatedControl.map { .string($0.pathString) } ?? .null,
            "accessibilityIdentifier": control.accessibilityIdentifier.map(JSONValue.string) ?? .null,
        ]
    }

    // MARK: - Control Event

    /// 执行 control.sendAction 动作。
    ///
    /// - Parameters:
    ///   - locator: 目标控件的统一定位器（identifier / path）。
    ///   - event: 要发送的 UIControl 事件。
    ///   - snapshotID: 可选 snapshotID，仅在 `.path` 且非 nil 时校验。
    ///   - context: 当前 UIKit 查询上下文（由 `execute(_:)` 注入）。
    /// - Returns: control.sendAction 命令 JSON，与迁移前 `UIControlSendActionCommand` 行为一致。
    /// - Throws: `UIKitCommandError`——定位失败 / 非 control / 能力不支持 / 陈旧。
    private static func executeControlEvent(locator: UIKitLocator,
                                            event: UIControlSendActionEvent,
                                            snapshotID: String?,
                                            context: UIKitContextProvider.Context) throws -> JSON {
        // 先 locate，后续 freshness 校验与派发都复用 located（避免二次遍历同一 path）。
        let target = locatorSummary(locator)
        let located = try UIKitLocatorResolver.locate(
            locator: locator,
            in: context.rootView,
            notFound: { UIKitCommandError.controlTargetNotFound(action: controlAction, targetDescription: target) },
            ambiguous: { UIKitCommandError.controlTargetAmbiguous(action: controlAction, targetDescription: target, count: $0) })
        // 陈旧校验仅对 .path + snapshotID，复用 located.view 重采指纹。
        if case .path = locator, let snapshotID {
            try validateFreshness(located: located, snapshotID: snapshotID, context: context, action: controlAction)
        }
        guard let control = located.view as? UIControl else {
            throw UIKitCommandError.controlTargetNotControl(action: controlAction,
                                                            targetDescription: located.pathString,
                                                            type: String(describing: Swift.type(of: located.view)))
        }

        let requestedAction = UIKitActionCapabilityResolver.actionKind(for: event)
        let availability = UIKitActionCapabilityResolver.resolve(view: control,
                                                                  rootView: context.rootView,
                                                                  nearestControl: control)
        guard availability.actions.contains(requestedAction) else {
            throw UIKitCommandError.unsupportedAction(action: controlAction,
                                                      targetDescription: located.pathString,
                                                      requestedAction: requestedAction.rawValue)
        }

        UIKitCommandLogging.info("command", "ui control send action mainactor target=\(located.pathString) type=\(String(describing: Swift.type(of: control))) event=\(event.rawValue) enabled=\(control.isEnabled)")
        control.sendActions(for: event.uiControlEvent)
        return [
            "sent": .bool(true),
            "event": .string(event.rawValue),
            "path": .string(located.pathString),
            "type": .string(String(describing: Swift.type(of: control))),
            "accessibilityIdentifier": control.accessibilityIdentifier.map(JSONValue.string) ?? .null,
            "isEnabled": .bool(control.isEnabled),
            "isSelected": .bool(control.isSelected),
            "isHighlighted": .bool(control.isHighlighted),
        ]
    }

    // MARK: - Helpers

    /// locator 的日志/响应摘要，复用 `UIKitViewLookupTarget` 文案保持迁移前一致。
    private static func locatorSummary(_ locator: UIKitLocator) -> String {
        locator.logSummary
    }
}

/// 把 `UIControlSendActionEvent` 映射为 UIKit 的 `UIControl.Event`。
///
/// 该映射从原 `UIControlSendActionCommand` 迁移而来，保持事件名与 executor 派发一一对应。
private extension UIControlSendActionEvent {
    /// 映射为 UIKit 的 `UIControl.Event`。
    var uiControlEvent: UIControl.Event {
        switch self {
        case .touchDown:
            return .touchDown
        case .touchUpInside:
            return .touchUpInside
        case .valueChanged:
            return .valueChanged
        case .editingChanged:
            return .editingChanged
        case .editingDidBegin:
            return .editingDidBegin
        case .editingDidEnd:
            return .editingDidEnd
        }
    }
}
#endif
