#if canImport(UIKit)
import Foundation
import UIKit

/// 当前顶部控制器轻量交互目标查询命令。
///
/// action 为 `ui.viewTargets`。命令面向事件下发前的目标发现，只返回 path、语义、短文本、
/// window frame 和基础交互状态，不返回完整布局验收树。
struct ViewTargetsCommand: Command {
    /// 固定 action 名，供注册、日志和错误工厂复用。
    static let actionName = "ui.viewTargets"

    /// 命令名。
    let action = ViewTargetsCommand.actionName

    /// `help` 命令展示的说明。
    let description = "返回当前顶部控制器中可用于事件下发的轻量 UI 目标列表"

    /// 可选参数 schema。
    let parameters: [CommandParameter] = [
        CommandParameter(name: "includeHidden",
                         kind: .boolean,
                         required: false,
                         description: "是否包含隐藏 view, 默认 false"),
        CommandParameter(name: "includeDisabled",
                         kind: .boolean,
                         required: false,
                         description: "是否包含 disabled control, 默认 true"),
        CommandParameter(name: "includeStaticText",
                         kind: .boolean,
                         required: false,
                         description: "是否包含仅展示文本的节点, 默认 false"),
        CommandParameter(name: "includeContainers",
                         kind: .boolean,
                         required: false,
                         description: "是否包含普通容器 view, 默认 false"),
        CommandParameter(name: "maxDepth",
                         kind: .number,
                         required: false,
                         description: "最大递归深度, 0 表示仅根 view"),
        CommandParameter(name: "accessibilityIdentifier",
                         kind: .string,
                         required: false,
                         description: "按 accessibilityIdentifier 精确筛选"),
        CommandParameter(name: "accessibilityIdentifierPrefix",
                         kind: .string,
                         required: false,
                         description: "按 accessibilityIdentifier 前缀筛选"),
        CommandParameter(name: "textLimit",
                         kind: .number,
                         required: false,
                         description: "title/text/placeholder/value 最大字符数, 默认 80, 上限 200"),
    ]

    /// 执行轻量目标查询。
    ///
    /// - Parameter request: 已通过顶层类型校验的命令请求。
    /// - Returns: 成功时返回 targets 列表；参数非法或 UIKit 上下文不可用时返回业务失败 envelope。
    func handle(_ request: ExploreRequest) async throws -> ExploreResult {
        ExploreLogger.info(.command, "command \(action) start payloadKeys=\(request.data.storage.count)")
        switch UIViewTargetsQuery.parse(from: request.data) {
        case .success(let query):
            let result = await UIViewTargetsCollector.collect(query: query)
            switch result {
            case .success(let data):
                let targetCount = data["targetCount"]?.doubleValue ?? 0
                let visitedCount = data["visitedNodeCount"]?.doubleValue ?? 0
                ExploreLogger.info(.command, "command \(action) completed targetCount=\(targetCount) visitedNodeCount=\(visitedCount)")
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
}
#endif
