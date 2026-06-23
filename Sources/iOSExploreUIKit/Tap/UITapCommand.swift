#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// 模拟页面点击语义的命令。
///
/// action 为 `ui.tap`。第一版先完成定位、`hitTest` 校验和 UIControl fallback：对
/// UIControl 调用 `.touchUpInside`，对非 UIControl 明确返回不支持，避免伪造系统触摸事件。
struct UITapCommand: Command {
    /// 固定 action 名。
    static let actionName = "ui.tap"

    /// 命令名。
    let action = UITapCommand.actionName

    /// `help` 命令展示的说明。
    let description = "按 accessibilityIdentifier、path 或 window 坐标执行点击"

    /// 参数 schema。
    let parameters: [CommandParameter] = [
        CommandParameter(name: "accessibilityIdentifier",
                         kind: .string,
                         required: false,
                         description: "按 accessibilityIdentifier 精确定位目标 view, 与 path/x/y 互斥"),
        CommandParameter(name: "path",
                         kind: .string,
                         required: false,
                         description: "按 ui.viewTargets 或 ui.topViewHierarchy 返回的 root/0/1 路径定位目标 view, 与 accessibilityIdentifier/x/y 互斥"),
        CommandParameter(name: "x",
                         kind: .number,
                         required: false,
                         description: "window 坐标 x, 需要与 y 同时提供"),
        CommandParameter(name: "y",
                         kind: .number,
                         required: false,
                         description: "window 坐标 y, 需要与 x 同时提供"),
        CommandParameter(name: "coordinateSpace",
                         kind: .string,
                         required: false,
                         description: "坐标空间, 第一版仅支持 window"),
    ]

    /// 执行 tap。
    ///
    /// - Parameter request: 已通过顶层类型校验的命令请求。
    /// - Returns: 成功时返回命中目标与派发方式；失败时返回明确原因。
    func handle(_ request: ExploreRequest) async throws -> ExploreResult {
        UIKitCommandLogging.info("command", "command \(action) start payloadKeys=\(request.data.storage.count)")
        switch UITapQuery.parse(from: request.data) {
        case .success(let query):
            let result = await tap(query: query)
            switch result {
            case .success(let data):
                UIKitCommandLogging.info("command", "command \(action) completed target=\(query.target.description) dispatchMode=\(data["dispatchMode"]?.stringValue ?? "unknown")")
            case .failure(let code, let message):
                UIKitCommandLogging.error("command", "command \(action) failed code=\(code.rawValue) message=\(message)")
            }
            return result
        case .failure(let message):
            let error = UIKitCommandError.invalidData(action: action, message: message)
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        }
    }

    /// 在 MainActor 上定位、命中测试并派发点击。
    @MainActor
    private func tap(query: UITapQuery) -> ExploreResult {
        let context: UIKitContextProvider.Context
        switch UIKitContextProvider.currentContext() {
        case .success(let value):
            context = value
        case .failure(let reason):
            let error = UIKitCommandError.hierarchyUnavailable(action: action, reason: reason)
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        }

        switch query.target {
        case .view(let target):
            return tapViewTarget(target, context: context)
        case .windowPoint(let x, let y):
            return tapWindowPoint(CGPoint(x: x, y: y), targetDescription: query.target.description, context: context)
        }
    }

    /// 点击按 view 定位的目标。
    @MainActor
    private func tapViewTarget(_ target: UIKitViewLookupTarget,
                               context: UIKitContextProvider.Context) -> ExploreResult {
        let located: UIKitLocatorResolver.LocatedView
        switch UIKitLocatorResolver.locate(locator: target.locator, in: context.rootView) {
        case .found(let value):
            located = value
        case .notFound:
            let error = UIKitCommandError.targetNotFound(action: action, targetDescription: target.description)
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        case .ambiguous(let count):
            let error = UIKitCommandError.targetAmbiguous(action: action,
                                                          targetDescription: target.description,
                                                          count: count)
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        }

        let point = located.view.convert(CGPoint(x: located.view.bounds.midX,
                                                 y: located.view.bounds.midY),
                                         to: context.window)
        guard let hitView = context.window.hitTest(point, with: nil) else {
            let error = UIKitCommandError.hitTestFailed(action: action,
                                                       targetDescription: located.pathString,
                                                       x: Double(point.x),
                                                       y: Double(point.y))
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        }
        guard UIKitLocatorResolver.view(hitView, isDescendantOfOrSameAs: located.view) ||
              UIKitLocatorResolver.view(located.view, isDescendantOfOrSameAs: hitView) else {
            let error = UIKitCommandError.hitMismatch(action: action,
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
    @MainActor
    private func tapWindowPoint(_ point: CGPoint,
                                targetDescription: String,
                                context: UIKitContextProvider.Context) -> ExploreResult {
        guard let hitView = context.window.hitTest(point, with: nil) else {
            let error = UIKitCommandError.hitTestFailed(action: action,
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

    /// 对 UIControl 派发第一版 tap fallback。
    @MainActor
    private func dispatchTap(to control: UIControl?,
                             hitView: UIView,
                             point: CGPoint,
                             targetDescription: String,
                             context: UIKitContextProvider.Context) -> ExploreResult {
        guard let control else {
            let error = UIKitCommandError.unsupportedTarget(action: action,
                                                            targetDescription: targetDescription,
                                                            type: String(describing: Swift.type(of: hitView)))
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        }

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
}
#endif
