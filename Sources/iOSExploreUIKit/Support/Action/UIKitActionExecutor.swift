#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// UIKit 动作执行器。
///
/// 把 tap 与 control.sendAction 的实际 UIKit 执行逻辑收敛到单一入口。adapter
/// （`UITapCommand`/`UIControlSendActionCommand`）只解析请求、构造 `UIKitActionPlan`，再
/// `await executor.execute(plan)`；执行器在 `MainActor` 上完成固定流程：取 Context、resolve
/// locator、统一 freshness 校验、capability 校验、默认激活路由或 `sendActions(for:)`、
/// 生成语义 JSON。
///
/// 重构后执行器不再做 hit-test、不接受坐标、不找 nearest ancestor `UIControl`：
/// - `ui.tap` 只作用于 `ui.viewTargets` 签发的 canonical target，按默认激活路由
///   （`UIKitDefaultActivationResolver`）执行：UIButton → `touchUpInside`；UISwitch → 翻转 +
///   `valueChanged`；文本输入 → `becomeFirstResponder`（聚焦）。无确定路由的目标抛
///   `unsupported_target`。
/// - `ui.control.sendAction` 对自身为 `UIControl` 的 canonical target 发送显式 event。
/// - 两者都用同一 `validateViewSnapshot`：path 与 identifier 都走 path/context/fingerprint/
///   semanticDigest 陈旧校验，identifier 不再是绕过 stale guard 的后门。
///
/// 该类型是 `@MainActor`：adapter（network queue 上的命令 handler）只能 `await` 其入口，
/// 不能把解析出的 `UIView`/`UIControl` 返回到非隔离域——跨边界只传 `Sendable` 的成功 `JSON`
/// 或 `throw UIKitCommandError`（由 handler 顶层 catch 转成 `ExploreResult` envelope）。
///
/// 失败日志不在本执行器内记录——统一由 handler 顶层 catch 后记录
/// `error.failure.logMessage`；本执行器仅记录进入、默认激活路由、sendActions 等成功路径摘要，
/// 不写完整 payload 或业务明文。
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
    /// （locate / freshness / capability / 默认激活 / sendActions）可在测试里用可控 view 树
    /// 驱动，而不依赖真实 UIApplication scene。
    ///
    /// - Parameter plan: 动作计划（tap 或 controlEvent）。
    /// - Returns: 成功时返回语义 JSON（activationRoute / sent 等）。
    /// - Throws: `UIKitCommandError`——上下文不可用 / 定位失败 / 能力不支持 / 陈旧等。
    static func execute(_ plan: UIKitActionPlan) throws -> JSON {
        let context = try UIKitContextProvider.currentContext(action: actionName(for: plan))
        return try execute(plan, context: context)
    }

    /// 执行一个 UIKit 动作计划（注入入口：测试与内部复用）。
    ///
    /// 与 `execute(_:)` 的唯一区别是上下文由调用方提供。固定流程：按 plan 变体 resolve
    /// locator → 统一 freshness 校验 → capability 校验 → 默认激活路由或 `sendActions(for:)`
    /// → 生成语义 JSON。
    ///
    /// - Parameters:
    ///   - plan: 动作计划（tap 或 controlEvent）。
    ///   - context: 当前 UIKit 查询上下文（持有真实 window / rootView，可由测试构造）。
    /// - Returns: 成功时返回语义 JSON。
    /// - Throws: `UIKitCommandError`——定位失败 / 能力不支持 / 陈旧等。
    static func execute(_ plan: UIKitActionPlan, context: UIKitContextProvider.Context) throws -> JSON {
        switch plan {
        case .tap(let locator, let viewSnapshotID):
            return try executeTap(locator: locator, viewSnapshotID: viewSnapshotID, context: context)
        case .controlEvent(let locator, let event, let value, let viewSnapshotID):
            return try executeControlEvent(locator: locator,
                                           event: event,
                                           value: value,
                                           viewSnapshotID: viewSnapshotID,
                                           context: context)
        }
    }

    /// plan 变体对应的 action 名，供上下文不可用时的错误工厂与日志关联。
    private static func actionName(for plan: UIKitActionPlan) -> String {
        switch plan {
        case .tap: return tapAction
        case .controlEvent: return controlAction
        }
    }

    /// 统一的 viewSnapshot 陈旧校验（tap 与 control.sendAction 共用）。
    ///
    /// 无论 locator 是 path 还是 identifier，都用调用方已 locate 的 `LocatedView` 重采该 path
    /// 的指纹（含 `semanticDigest`），与 store 中 viewSnapshotID 对应记录比对。陈旧（snapshot
    /// 未知/过期、context 变化、path 未签发或指纹不匹配）时抛 `stale_locator`，提示调用方重新
    /// `ui.viewTargets`。
    ///
    /// - Parameters:
    ///   - located: 调用方已 resolve 的定位视图（含 view 与 pathString）。
    ///   - viewSnapshotID: `ui.viewTargets` 签发的结构化快照标识。
    ///   - context: 当前 UIKit 上下文（用于重采指纹）。
    ///   - action: 触发校验的 action 名（错误关联）。
    /// - Throws: `UIKitCommandError.staleLocator`——指纹陈旧时。
    private static func validateViewSnapshot(located: UIKitLocatorResolver.LocatedView,
                                             viewSnapshotID: String,
                                             context: UIKitContextProvider.Context,
                                             action: String) throws {
        let path = located.pathString
        let current = UIKitFingerprintCollector.fingerprint(for: located.view,
                                                             path: path,
                                                             rootView: context.rootView,
                                                             digest: UIKitFingerprintCollector.digest(topViewController: context.topViewController))
        if UIKitSnapshotStore.shared.isStale(viewSnapshotID: viewSnapshotID,
                                             path: path,
                                             context: UIKitFingerprintCollector.context(window: context.window, topViewController: context.topViewController),
                                             current: current) {
            throw UIKitCommandError.staleLocator(action: action, viewSnapshotID: viewSnapshotID)
        }
    }

    // MARK: - Tap

    /// 执行 tap 默认激活动作。
    ///
    /// 先 locate、做统一 freshness 校验，再用 `UIKitDefaultActivationResolver` 决定默认激活路由
    /// （UIButton→touchUpInside / UISwitch→翻转+valueChanged / 文本输入→聚焦）。无确定公开路由
    /// 但目标挂有 `UIGestureRecognizer` 时，走手势 target-action adapter（`UIGestureTargetExecutor`
    /// runtime 读私有 ivar 派发）作为补充；adapter 也不可达（无 gesture / ivar 漂移 / Release）
    /// 的目标才抛 `unsupported_target`。
    ///
    /// - Parameters:
    ///   - locator: canonical target 的统一定位器（identifier / path）。
    ///   - viewSnapshotID: `ui.viewTargets` 签发的结构化快照标识。
    ///   - context: 当前 UIKit 查询上下文（由 `execute(_:)` 注入）。
    /// - Returns: tap 语义 JSON（activated / activationRoute / type 等）。
    /// - Throws: `UIKitCommandError`——定位失败 / 陈旧 / 不支持 / first responder 失败。
    private static func executeTap(locator: UIKitLocator,
                                   viewSnapshotID: String,
                                   context: UIKitContextProvider.Context) throws -> JSON {
        let target = locatorSummary(locator)
        let located = try UIKitLocatorResolver.locate(
            locator: locator,
            in: context.rootView,
            notFound: { UIKitCommandError.targetNotFound(action: tapAction, targetDescription: target) },
            ambiguous: { UIKitCommandError.targetAmbiguous(action: tapAction, targetDescription: target, count: $0) })
        try validateViewSnapshot(located: located, viewSnapshotID: viewSnapshotID, context: context, action: tapAction)

        guard let route = UIKitDefaultActivationResolver.route(for: located.view) else {
            // 无 default 公开路由：尝试手势 target-action adapter（依赖 `UIGestureRecognizer` 的
            // 自定义 view）。adapter 是 executeTap 内部补充分支，不改 default 三路行为，也不改
            // `ui.tap` schema/协议——agent 据 `ui.viewTargets` 响应的 `hasGestureRecognizers` 字段
            // 推断可试 tap，用 path/identifier + viewSnapshotID 发 `ui.tap`，executor 在此触发。
            // `availableActions` 不声明 tap：gesture 触发是启发式补充（runtime 读私有 ivar 派发），
            // 非 UIButton/UISwitch/文本输入那样的确定公开激活路由。
            //
            // 只对非 `UIControl` 的 view 触发：`UISlider`/`UISegmentedControl` 等 UIControl 内部
            // 也挂 gesture（用于自身交互），adapter 若介入会误触发其内部 target-action，破坏原本
            // `unsupported_target` 语义；UIControl 子类应走 default route 或 `control.sendAction`。
            //
            // adapter 返回空（非 UIControl 但无 gesture，或 iOS 版本 ivar 漂移读不出 target-action，
            // 或 Release 下 runtime 入口隔离成空壳）时，fallthrough 到 `unsupported_target`，与原行为一致。
            // [SPIKE] cell 子树优先：cell 内子 view 上挂的 _longPressGestureRecognized: 是误触，
            // 先尝试 cellSelection 看是否能 invoke selectGestureHandler: 触发真实 didSelectRow。
            if let cellAttempt = UIGestureTargetExecutor.executeCellSelection(on: located.view) {
                UIKitCommandLogging.info("command",
                    "ui tap cell selection route=\(cellAttempt.activationRoute) path=\(located.pathString) type=\(cellAttempt.viewType) container=\(cellAttempt.containerViewType ?? "nil") indexPath=\(cellAttempt.indexPathSummary.map { "\($0.section)-\($0.item)" } ?? "nil")")
                return [
                    "activated": .bool(cellAttempt.activated),
                    "activationRoute": .string(cellAttempt.activationRoute),
                    "path": .string(located.pathString),
                    "type": .string(cellAttempt.viewType),
                    "containerType": cellAttempt.containerViewType.map(JSONValue.string) ?? .null,
                    "cellType": cellAttempt.cellType.map(JSONValue.string) ?? .null,
                    "indexPath": cellAttempt.indexPathSummary.map { indexPathJSON($0) } ?? .null,
                ]
            }
            if !(located.view is UIControl),
               let triggered = UIGestureTargetExecutor.execute(on: located.view), !triggered.isEmpty {
                UIKitCommandLogging.info("command",
                    "ui tap default activation route=gesture.targetAction path=\(located.pathString) type=\(String(describing: Swift.type(of: located.view))) triggered=\(triggered.count)")
                return [
                    "activated": .bool(true),
                    "activationRoute": .string("gesture.targetAction"),
                    "path": .string(located.pathString),
                    "type": .string(String(describing: Swift.type(of: located.view))),
                    "gestures": .array(triggered.map { gestureTriggeredJSON($0) }),
                    "triggeredCount": .double(Double(triggered.count)),
                ]
            }
            throw UIKitCommandError.unsupportedTarget(action: tapAction,
                                                      targetDescription: located.pathString,
                                                      type: String(describing: Swift.type(of: located.view)))
        }

        switch route {
        case .controlTouchUpInside:
            guard let control = located.view as? UIControl else {
                throw UIKitCommandError.unsupportedTarget(action: tapAction,
                                                          targetDescription: located.pathString,
                                                          type: String(describing: Swift.type(of: located.view)))
            }
            UIKitCommandLogging.info("command", "ui tap default activation route=control.touchUpInside path=\(located.pathString) type=\(String(describing: Swift.type(of: control)))")
            control.sendActions(for: .touchUpInside)
            return [
                "activated": .bool(true),
                "activationRoute": .string(route.rawValue),
                "path": .string(located.pathString),
                "type": .string(String(describing: Swift.type(of: control))),
                "event": .string("touchUpInside"),
                "accessibilityIdentifier": control.accessibilityIdentifier.map(JSONValue.string) ?? .null,
            ]
        case .switchToggle:
            guard let switchView = located.view as? UISwitch else {
                throw UIKitCommandError.unsupportedTarget(action: tapAction,
                                                          targetDescription: located.pathString,
                                                          type: String(describing: Swift.type(of: located.view)))
            }
            let previous = switchView.isOn
            UIKitCommandLogging.info("command", "ui tap default activation route=switch.toggle path=\(located.pathString) previous=\(previous)")
            switchView.setOn(!previous, animated: false)
            switchView.sendActions(for: .valueChanged)
            return [
                "activated": .bool(true),
                "activationRoute": .string(route.rawValue),
                "path": .string(located.pathString),
                "type": .string(String(describing: Swift.type(of: switchView))),
                "event": .string("valueChanged"),
                "previousValue": .bool(previous),
                "currentValue": .bool(switchView.isOn),
            ]
        case .inputFocus:
            UIKitCommandLogging.info("command", "ui tap default activation route=input.focus path=\(located.pathString) type=\(String(describing: Swift.type(of: located.view)))")
            let focused = located.view.becomeFirstResponder()
            guard focused else {
                throw UIKitCommandError.becomeFirstResponderFailed(action: tapAction, target: located.pathString)
            }
            return [
                "activated": .bool(true),
                "activationRoute": .string(route.rawValue),
                "path": .string(located.pathString),
                "type": .string(String(describing: Swift.type(of: located.view))),
                "isFirstResponder": .bool(located.view.isFirstResponder),
            ]
        }
    }

    // MARK: - Control Event

    /// 执行 control.sendAction 动作。
    ///
    /// 先 locate、做统一 freshness 校验、校验目标自身为 `UIControl` 且当前声明该精确 event；
    /// 若携带 `value`，先按控件真实类型写入 `UISlider.value`、
    /// `UISegmentedControl.selectedSegmentIndex`、`UIStepper.value` 或 `UISwitch.isOn`，再
    /// `sendActions(for:)`。不做 hit-test、不找祖先 control。
    ///
    /// - Parameters:
    ///   - locator: 目标控件的统一定位器（identifier / path）。
    ///   - event: 要发送的 UIControl 事件。
    ///   - value: 要在发送事件前写入控件的可选值。
    ///   - viewSnapshotID: `ui.viewTargets` 签发的结构化快照标识。
    ///   - context: 当前 UIKit 查询上下文（由 `execute(_:)` 注入）。
    /// - Returns: control.sendAction 语义 JSON（sent / event / type 等）。
    /// - Throws: `UIKitCommandError`——定位失败 / 非 control / 能力不支持 / 陈旧。
    private static func executeControlEvent(locator: UIKitLocator,
                                            event: UIControlSendActionEvent,
                                            value: JSONValue?,
                                            viewSnapshotID: String,
                                            context: UIKitContextProvider.Context) throws -> JSON {
        let target = locatorSummary(locator)
        let located = try UIKitLocatorResolver.locate(
            locator: locator,
            in: context.rootView,
            notFound: { UIKitCommandError.controlTargetNotFound(action: controlAction, targetDescription: target) },
            ambiguous: { UIKitCommandError.controlTargetAmbiguous(action: controlAction, targetDescription: target, count: $0) })
        try validateViewSnapshot(located: located, viewSnapshotID: viewSnapshotID, context: context, action: controlAction)

        guard let control = located.view as? UIControl else {
            throw UIKitCommandError.controlTargetNotControl(action: controlAction,
                                                            targetDescription: located.pathString,
                                                            type: String(describing: Swift.type(of: located.view)))
        }

        let requestedAction = UIKitActionCapabilityResolver.actionKind(for: event)
        let availability = UIKitActionCapabilityResolver.resolve(view: control, rootView: context.rootView)
        guard availability.actions.contains(requestedAction) else {
            throw UIKitCommandError.unsupportedAction(action: controlAction,
                                                      targetDescription: located.pathString,
                                                      requestedAction: requestedAction.rawValue)
        }

        applyValue(value, to: control)

        UIKitCommandLogging.info("command", "ui control send action mainactor target=\(located.pathString) type=\(String(describing: Swift.type(of: control))) event=\(event.rawValue) enabled=\(control.isEnabled) valueProvided=\(value != nil)")
        control.sendActions(for: event.uiControlEvent)
        return [
            "sent": .bool(true),
            "event": .string(event.rawValue),
            "path": .string(located.pathString),
            "type": .string(String(describing: Swift.type(of: control))),
            "accessibilityIdentifier": control.accessibilityIdentifier.map(JSONValue.string) ?? .null,
            "isEnabled": .bool(control.isEnabled),
            "isSelected": .bool(control.isSelected),
        ]
    }

    // MARK: - Helpers

    /// locator 的日志/响应摘要，复用 `UIKitLocator` 文案。
    private static func locatorSummary(_ locator: UIKitLocator) -> String {
        locator.logSummary
    }

    /// 在派发 valueChanged 前按 UIKit 控件类型写入调用方提供的目标值。
    ///
    /// 非 value 型控件或不适配当前控件类型的 JSON 值会被忽略，保持旧的“只发事件”语义；这样
    /// 调用方缺省或误带 value 时不会改变 touch/editing 事件的派发路径。
    private static func applyValue(_ value: JSONValue?, to control: UIControl) {
        guard let value else { return }

        if let slider = control as? UISlider, let newValue = value.doubleValue {
            slider.value = Float(newValue)
        } else if let segmented = control as? UISegmentedControl, let index = value.intValue {
            segmented.selectedSegmentIndex = index
        } else if let stepper = control as? UIStepper, let newValue = value.doubleValue {
            stepper.value = newValue
        } else if let switchView = control as? UISwitch, let isOn = value.switchBoolValue {
            switchView.isOn = isOn
        }
    }

    /// 把一对已触发的手势 target-action 摘要序列化进 `ui.tap` 响应的 `gestures` 数组。
    ///
    /// 只输出类型名与 selector 名，不含 target 对象引用或原始 payload，避免泄露业务对象。
    private static func gestureTriggeredJSON(_ pair: UIGestureTriggeredPair) -> JSONValue {
        .object(JSON([
            "gestureType": .string(pair.gestureType),
            "targetType": .string(pair.targetType),
            "action": .string(pair.action),
        ]))
    }

    /// 把 cell selection 的 indexPath 摘要序列化进 `ui.tap` 响应。
    private static func indexPathJSON(_ summary: IndexPathSummary) -> JSONValue {
        .object(JSON([
            "section": .double(Double(summary.section)),
            "item": .double(Double(summary.item)),
        ]))
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

private extension JSONValue {
    /// 当 JSON number 可精确表达为 Swift `Int` 时返回整数值。
    var intValue: Int? {
        guard let value = doubleValue,
              value.isFinite,
              value.rounded(.towardZero) == value else {
            return nil
        }
        return Int(exactly: value)
    }

    /// UISwitch 接受的布尔输入：JSON bool 或 JSON number 0/1。
    var switchBoolValue: Bool? {
        if let value = boolValue {
            return value
        }
        if doubleValue == 0 {
            return false
        }
        if doubleValue == 1 {
            return true
        }
        return nil
    }
}
#endif
