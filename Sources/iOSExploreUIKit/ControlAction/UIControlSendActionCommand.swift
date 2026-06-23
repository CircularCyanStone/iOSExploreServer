#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// 向指定 UIControl 发送 target-action 事件的命令。
///
/// action 为 `ui.control.sendAction`。命令会在当前顶部控制器 view 层级中定位目标，校验它
/// 是 `UIControl`，然后在 `MainActor` 上调用 `sendActions(for:)`。该命令触发的是
/// target-action，不模拟真实触摸坐标和命中测试。
struct UIControlSendActionCommand: Command {
    /// 固定 action 名。
    static let actionName = "ui.control.sendAction"

    /// 命令名。
    let action = UIControlSendActionCommand.actionName

    /// `help` 命令展示的说明。
    let description = "向指定 UIControl 发送 target-action 事件"

    /// 可选参数 schema。
    let parameters: [CommandParameter] = [
        CommandParameter(name: "accessibilityIdentifier",
                         kind: .string,
                         required: false,
                         description: "按 accessibilityIdentifier 精确定位目标控件, 与 path 二选一"),
        CommandParameter(name: "path",
                         kind: .string,
                         required: false,
                         description: "按 ui.viewTargets 或 ui.topViewHierarchy 返回的 root/0/1 路径定位目标控件, 与 accessibilityIdentifier 二选一"),
        CommandParameter(name: "event",
                         kind: .string,
                         required: true,
                         description: "事件名: touchDown / touchUpInside / valueChanged / editingChanged / editingDidBegin / editingDidEnd"),
    ]

    /// 执行 sendAction。
    ///
    /// - Parameter request: 已通过顶层类型校验的命令请求。
    /// - Returns: 成功时返回目标摘要；失败时返回 `invalid_data` 或 UI 不可用错误。
    func handle(_ request: ExploreRequest) async throws -> ExploreResult {
        ExploreLogger.info(.command, "command \(action) start payloadKeys=\(request.data.storage.count)")
        switch UIControlSendActionQuery.parse(from: request.data) {
        case .success(let query):
            let result = await send(query: query)
            switch result {
            case .success(let data):
                ExploreLogger.info(.command, "command \(action) completed target=\(query.target.description) event=\(query.event.rawValue) type=\(data["type"]?.stringValue ?? "unknown")")
            case .failure(let code, let message):
                ExploreLogger.error(.command, "command \(action) failed code=\(code.rawValue) message=\(message)")
            }
            return result
        case .failure(let message):
            let error = ExploreServerError.invalidData(action: action, message: message)
            ExploreLogger.error(.command, error.logMessage)
            return .failure(code: error.code, message: error.message)
        }
    }

    /// 在 MainActor 中定位控件并发送事件。
    @MainActor
    private func send(query: UIControlSendActionQuery) -> ExploreResult {
        let context: UIKitViewLookup.Context
        switch UIKitViewLookup.currentContext() {
        case .success(let value):
            context = value
        case .failure(let reason):
            let error = ExploreServerError.uiHierarchyUnavailable(action: action, reason: reason)
            ExploreLogger.error(.command, error.logMessage)
            return .failure(code: error.code, message: error.message)
        }

        let located: UIKitViewLookup.LocatedView
        switch UIKitViewLookup.locate(target: query.target, in: context.rootView) {
        case .found(let value):
            located = value
        case .notFound:
            let error = ExploreServerError.uiControlTargetNotFound(action: action, target: query.target.description)
            ExploreLogger.error(.command, error.logMessage)
            return .failure(code: error.code, message: error.message)
        case .ambiguous(let count):
            let error = ExploreServerError.uiControlTargetAmbiguous(action: action,
                                                                    target: query.target.description,
                                                                    count: count)
            ExploreLogger.error(.command, error.logMessage)
            return .failure(code: error.code, message: error.message)
        }
        guard let control = located.view as? UIControl else {
            let error = ExploreServerError.uiControlTargetNotControl(action: action,
                                                                     target: located.pathString,
                                                                     type: String(describing: Swift.type(of: located.view)))
            ExploreLogger.error(.command, error.logMessage)
            return .failure(code: error.code, message: error.message)
        }

        ExploreLogger.info(.command, "ui control send action mainactor target=\(located.pathString) type=\(String(describing: Swift.type(of: control))) event=\(query.event.rawValue) enabled=\(control.isEnabled)")
        control.sendActions(for: query.event.uiControlEvent)
        return .success([
            "sent": .bool(true),
            "event": .string(query.event.rawValue),
            "path": .string(located.pathString),
            "type": .string(String(describing: Swift.type(of: control))),
            "accessibilityIdentifier": control.accessibilityIdentifier.map(JSONValue.string) ?? .null,
            "isEnabled": .bool(control.isEnabled),
            "isSelected": .bool(control.isSelected),
            "isHighlighted": .bool(control.isHighlighted),
        ])
    }
}

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
