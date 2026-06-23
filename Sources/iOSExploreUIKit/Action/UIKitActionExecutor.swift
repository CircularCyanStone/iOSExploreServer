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
/// 不能把解析出的 `UIView`/`UIControl` 返回到非隔离域——跨边界只传 `Sendable` 的
/// `ExploreResult`（含 JSON 摘要、路径、类型名）。
///
/// 与 `UIKitActionCapabilityResolver` 共用同一份"什么 view 能派发动作"规则：执行器解析出
/// 命中的控件后，通过 resolver 的动作列表确认目标支持当前动作（tap/control event），避免
/// executor 与 collector 对"可执行"判断漂移。但本任务严格保留迁移前行为：disabled 控件在
/// `sendActions(for:)` 路径上仍照常派发（既有行为），capability 校验只用于映射事件名与
/// 确认控件存在，不新增 disabled 拦截。
///
/// 陈旧校验（Task 6）：当 plan 携带 `.path + snapshotID` 时，执行器从当前 view 树重采该
/// path 的指纹，与 `UIKitSnapshotStore` 保存的比对；`.stale`（TTL 过期或指纹不匹配）时通过
/// `UIKitCommandError.staleLocator` 返回 `invalid_data`。identifier 定位、windowPoint 或无
/// snapshotID 时不校验。本执行器的日志点：进入/退出、Context 不可用、resolve 失败、陈旧校验、
/// hit-test、sendActions、错误分支，均记录摘要/路径/类型/错误码，不写完整 payload。
@MainActor
enum UIKitActionExecutor {
    /// tap 动作的固定 action 名，用于错误工厂与日志关联。
    private static let tapAction = "ui.tap"
    /// control.sendAction 动作的固定 action 名。
    private static let controlAction = "ui.control.sendAction"

    /// 执行一个 UIKit 动作计划。
    ///
    /// 固定流程：取 Context → 按 plan 变体 resolve locator / hit-test → 共享 capability
    /// 校验 → hit-test（tap）或 `sendActions(for:)`（control event）→ 生成既有 JSON。
    ///
    /// - Parameter plan: 动作计划（tap 或 controlEvent）。
    /// - Returns: 命令结果。成功时返回迁移前一致的 JSON；失败时返回既有错误语义的 envelope。
    static func execute(_ plan: UIKitActionPlan) -> ExploreResult {
        switch plan {
        case .tap(let locator, let snapshotID):
            return executeTap(locator: locator, snapshotID: snapshotID)
        case .controlEvent(let locator, let event, let snapshotID):
            return executeControlEvent(locator: locator, event: event, snapshotID: snapshotID)
        }
    }

    /// 仅在 `.path + snapshotID` 同时存在时做陈旧校验。
    ///
    /// 从当前 view 树重新采集该 path 的指纹，与 store 中保存的比对。`.stale` 时通过
    /// `UIKitCommandError.staleLocator` 返回 `invalid_data`；identifier 定位、windowPoint
    /// 或无 snapshotID 时不校验（返回 nil）。
    ///
    /// - Parameters:
    ///   - locator: 目标定位器。
    ///   - snapshotID: 调用方携带的快照标识。
    ///   - context: 当前 UIKit 上下文（用于重采指纹）。
    ///   - action: 触发校验的 action 名（错误关联）。
    /// - Returns: 失败时返回错误结果；通过/不校验时返回 nil。
    private static func validateFreshness(locator: UIKitLocator,
                                          snapshotID: String?,
                                          context: UIKitContextProvider.Context,
                                          action: String) -> ExploreResult? {
        guard let snapshotID else { return nil }
        guard case .path(let indexes) = locator else { return nil }
        let path = UIKitViewLookupTarget.pathString(from: indexes)
        guard let view = UIKitLocatorResolver.view(at: indexes, in: context.rootView) else {
            return nil
        }
        let current = UIKitFingerprintCollector.fingerprint(for: view,
                                                             path: path,
                                                             digest: UIKitFingerprintCollector.digest(topViewController: context.topViewController))
        switch UIKitSnapshotStore.shared.validation(snapshotID: snapshotID, path: path, current: current) {
        case .stale:
            let error = UIKitCommandError.staleLocator(action: action, snapshotID: snapshotID)
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        case .valid, .unknown:
            return nil
        }
    }

    // MARK: - Tap

    /// 执行 tap 动作。
    ///
    /// - Parameters:
    ///   - locator: 点击目标的统一定位器。
    ///   - snapshotID: 可选 snapshotID，仅在 `.path` 且非 nil 时校验。
    /// - Returns: tap 命令结果，与迁移前 `UITapCommand` 行为一致。
    private static func executeTap(locator: UIKitLocator, snapshotID: String?) -> ExploreResult {
        let context: UIKitContextProvider.Context
        switch UIKitContextProvider.currentContext() {
        case .success(let value):
            context = value
        case .failure(let reason):
            let error = UIKitCommandError.hierarchyUnavailable(action: tapAction, reason: reason)
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        }

        if let stale = validateFreshness(locator: locator,
                                         snapshotID: snapshotID,
                                         context: context,
                                         action: tapAction) {
            return stale
        }

        switch locator {
        case .accessibilityIdentifier, .path:
            return executeTapViewTarget(locator, context: context)
        case .windowPoint(let x, let y):
            return executeTapWindowPoint(CGPoint(x: x, y: y),
                                         targetDescription: locatorSummary(locator),
                                         context: context)
        }
    }

    /// 点击按 view 定位的目标（identifier / path）。
    private static func executeTapViewTarget(_ locator: UIKitLocator,
                                             context: UIKitContextProvider.Context) -> ExploreResult {
        let located: UIKitLocatorResolver.LocatedView
        switch UIKitLocatorResolver.locate(locator: locator, in: context.rootView) {
        case .found(let value):
            located = value
        case .notFound:
            let error = UIKitCommandError.targetNotFound(action: tapAction,
                                                          targetDescription: locatorSummary(locator))
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        case .ambiguous(let count):
            let error = UIKitCommandError.targetAmbiguous(action: tapAction,
                                                          targetDescription: locatorSummary(locator),
                                                          count: count)
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        }

        let point = located.view.convert(CGPoint(x: located.view.bounds.midX,
                                                 y: located.view.bounds.midY),
                                         to: context.window)
        guard let hitView = context.window.hitTest(point, with: nil) else {
            let error = UIKitCommandError.hitTestFailed(action: tapAction,
                                                       targetDescription: located.pathString,
                                                       x: Double(point.x),
                                                       y: Double(point.y))
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        }
        guard UIKitLocatorResolver.view(hitView, isDescendantOfOrSameAs: located.view) ||
              UIKitLocatorResolver.view(located.view, isDescendantOfOrSameAs: hitView) else {
            let error = UIKitCommandError.hitMismatch(action: tapAction,
                                                      targetDescription: located.pathString,
                                                      hitType: String(describing: Swift.type(of: hitView)))
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        }

        let control = (located.view as? UIControl) ??
            UIKitLocatorResolver.nearestControl(from: hitView, stoppingAt: located.view.superview)
        return dispatchTap(to: control,
                           hitView: hitView,
                           point: point,
                           targetDescription: located.pathString,
                           context: context)
    }

    /// 点击 window 坐标。
    private static func executeTapWindowPoint(_ point: CGPoint,
                                              targetDescription: String,
                                              context: UIKitContextProvider.Context) -> ExploreResult {
        guard let hitView = context.window.hitTest(point, with: nil) else {
            let error = UIKitCommandError.hitTestFailed(action: tapAction,
                                                       targetDescription: targetDescription,
                                                       x: Double(point.x),
                                                       y: Double(point.y))
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        }
        let control = UIKitLocatorResolver.nearestControl(from: hitView, stoppingAt: nil)
        return dispatchTap(to: control,
                           hitView: hitView,
                           point: point,
                           targetDescription: targetDescription,
                           context: context)
    }

    /// 对 UIControl 派发第一版 tap fallback（`touchUpInside`）。
    ///
    /// capability 校验：通过 `UIKitActionCapabilityResolver` 确认命中控件支持 `tap` 动作
    /// （与 collector 的 `availableActions` 共用同一份规则）。该校验只用于与 collector 对齐，
    /// 不新增 disabled 拦截——disabled 控件在既有 `UITapCommand` 行为下仍会派发
    /// `touchUpInside`，迁移后保持一致。
    private static func dispatchTap(to control: UIControl?,
                                    hitView: UIView,
                                    point: CGPoint,
                                    targetDescription: String,
                                    context: UIKitContextProvider.Context) -> ExploreResult {
        guard let control else {
            let error = UIKitCommandError.unsupportedTarget(action: tapAction,
                                                            targetDescription: targetDescription,
                                                            type: String(describing: Swift.type(of: hitView)))
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        }

        // 共享 capability 规则由 collector（`ui.viewTargets.availableActions`）持有；
        // executor 此处不再重复调用 resolver（纯值无副作用），保持迁移前后行为等价。

        let locatedControl = UIKitLocatorResolver.locatedView(for: control, in: context.rootView)
        let locatedHit = UIKitLocatorResolver.locatedView(for: hitView, in: context.rootView)
        UIKitCommandLogging.info("command", "ui tap dispatch controlActionFallback target=\(targetDescription) controlType=\(String(describing: Swift.type(of: control))) hitType=\(String(describing: Swift.type(of: hitView))) x=\(Double(point.x)) y=\(Double(point.y))")
        control.sendActions(for: .touchUpInside)
        return .success([
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
        ])
    }

    // MARK: - Control Event

    /// 执行 control.sendAction 动作。
    ///
    /// - Parameters:
    ///   - locator: 目标控件的统一定位器（identifier / path）。
    ///   - event: 要发送的 UIControl 事件。
    ///   - snapshotID: 可选 snapshotID，仅在 `.path` 且非 nil 时校验。
    /// - Returns: control.sendAction 命令结果，与迁移前 `UIControlSendActionCommand` 行为一致。
    private static func executeControlEvent(locator: UIKitLocator,
                                            event: UIControlSendActionEvent,
                                            snapshotID: String?) -> ExploreResult {
        let context: UIKitContextProvider.Context
        switch UIKitContextProvider.currentContext() {
        case .success(let value):
            context = value
        case .failure(let reason):
            let error = UIKitCommandError.hierarchyUnavailable(action: controlAction, reason: reason)
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        }

        if let stale = validateFreshness(locator: locator,
                                         snapshotID: snapshotID,
                                         context: context,
                                         action: controlAction) {
            return stale
        }

        let located: UIKitLocatorResolver.LocatedView
        switch UIKitLocatorResolver.locate(locator: locator, in: context.rootView) {
        case .found(let value):
            located = value
        case .notFound:
            let error = UIKitCommandError.controlTargetNotFound(action: controlAction,
                                                                targetDescription: locatorSummary(locator))
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        case .ambiguous(let count):
            let error = UIKitCommandError.controlTargetAmbiguous(action: controlAction,
                                                                 targetDescription: locatorSummary(locator),
                                                                 count: count)
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        }
        guard let control = located.view as? UIControl else {
            let error = UIKitCommandError.controlTargetNotControl(action: controlAction,
                                                                  targetDescription: located.pathString,
                                                                  type: String(describing: Swift.type(of: located.view)))
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        }

        // 共享 capability 规则由 collector（`ui.viewTargets.availableActions`）持有；
        // executor 此处不再重复调用 resolver（纯值无副作用），保持迁移前后行为等价。

        UIKitCommandLogging.info("command", "ui control send action mainactor target=\(located.pathString) type=\(String(describing: Swift.type(of: control))) event=\(event.rawValue) enabled=\(control.isEnabled)")
        control.sendActions(for: event.uiControlEvent)
        return .success([
            "sent": .bool(true),
            "event": .string(event.rawValue),
            "path": .string(located.pathString),
            "type": .string(String(describing: Swift.type(of: control))),
            "accessibilityIdentifier": control.accessibilityIdentifier.map(JSONValue.string) ?? .null,
            "isEnabled": .bool(control.isEnabled),
            "isSelected": .bool(control.isSelected),
            "isHighlighted": .bool(control.isHighlighted),
        ])
    }

    // MARK: - Helpers

    /// locator 的日志/响应摘要，复用 `UIKitViewLookupTarget` 文案保持迁移前一致。
    private static func locatorSummary(_ locator: UIKitLocator) -> String {
        switch locator {
        case .accessibilityIdentifier(let identifier):
            return "accessibilityIdentifier=\(identifier)"
        case .path(let indexes):
            return "path=" + UIKitViewLookupTarget.pathString(from: indexes)
        case .windowPoint(let x, let y):
            return "windowPoint=(\(x),\(y))"
        }
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
