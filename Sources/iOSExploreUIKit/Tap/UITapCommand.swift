#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// 模拟页面点击语义的命令。
///
/// action 为 `ui.tap`。命令只负责解析请求并构造 `UIKitActionPlan.tap`，再
/// `await UIKitActionExecutor.execute(plan)`。第一版的执行语义（取 Context、resolve locator、
/// hit-test、对 UIControl 派发 `touchUpInside` fallback、对非 UIControl 返回不支持）全部
/// 收敛在 `UIKitActionExecutor` 中，本命令不再内联执行逻辑。
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
        CommandParameter(name: "snapshotID",
                         kind: .string,
                         required: false,
                         description: "快照标识, 用于 path 定位的陈旧校验"),
    ]

    /// 执行 tap。
    ///
    /// 解析请求构造 `UIKitActionPlan.tap`，在 MainActor 上 `await` executor。失败时返回明确原因。
    ///
    /// - Parameter request: 已通过顶层类型校验的命令请求。
    /// - Returns: 成功时返回命中目标与派发方式；失败时返回明确原因。
    func handle(_ request: ExploreRequest) async throws -> ExploreResult {
        UIKitCommandLogging.info("command", "command \(action) start payloadKeys=\(request.data.storage.count)")
        let query: UITapQuery
        do {
            query = try UITapQuery.parse(from: request.data)
        } catch let parseError as QueryParseError {
            let error = UIKitCommandError.invalidData(action: action, message: parseError.message)
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        }
        let plan = UIKitActionPlan.tap(locator: query.target.locator, snapshotID: query.snapshotID)
        let result = await UIKitActionExecutor.execute(plan)
        switch result {
        case .success(let data):
            UIKitCommandLogging.info("command", "command \(action) completed target=\(query.target.description) dispatchMode=\(data["dispatchMode"]?.stringValue ?? "unknown")")
        case .failure(let code, let message):
            UIKitCommandLogging.error("command", "command \(action) failed code=\(code.rawValue) message=\(message)")
        }
        return result
    }
}
#endif
