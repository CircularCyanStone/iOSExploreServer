#if canImport(UIKit)
import Foundation
import UIKit

/// 当前顶部控制器 view 层级命令。
///
/// action 为 `ui.topViewHierarchy`。命令会切换到 `MainActor` 读取当前前台 window 的顶部
/// 控制器 view，返回结构、定位、accessibility、文本、颜色和常见控件状态。
struct TopViewHierarchyCommand: Command {
    /// 固定 action 名，供注册、日志和错误工厂复用。
    static let actionName = "ui.topViewHierarchy"

    /// 命令名。
    let action = TopViewHierarchyCommand.actionName

    /// `help` 命令展示的说明。
    let description = "返回当前顶部控制器 view 及其子视图层级信息"

    /// 可选参数 schema。
    let parameters: [CommandParameter] = [
        CommandParameter(name: "detailLevel",
                         kind: .string,
                         required: false,
                         description: "详情级别: basic / appearance / full, 默认 appearance"),
        CommandParameter(name: "maxDepth",
                         kind: .number,
                         required: false,
                         description: "最大递归深度, 0 表示仅根 view"),
        CommandParameter(name: "includeHidden",
                         kind: .boolean,
                         required: false,
                         description: "是否包含隐藏 view, 默认 false"),
        CommandParameter(name: "accessibilityIdentifier",
                         kind: .string,
                         required: false,
                         description: "按 accessibilityIdentifier 精确筛选"),
        CommandParameter(name: "accessibilityIdentifierPrefix",
                         kind: .string,
                         required: false,
                         description: "按 accessibilityIdentifier 前缀筛选"),
    ]

    /// 执行顶部视图层级采集。
    ///
    /// - Parameter request: 已通过顶层类型校验的命令请求。
    /// - Returns: 成功时返回 root 树或 matches 列表；参数非法时返回 `invalid_data`。
    func handle(_ request: ExploreRequest) async throws -> ExploreResult {
        ExploreLogger.info(.command, "command \(action) start payloadKeys=\(request.data.storage.count)")
        switch UIViewHierarchyQuery.parse(from: request.data) {
        case .success(let query):
            let result = await UIViewHierarchyCollector.collectTopViewHierarchy(query: query)
            switch result {
            case .success(let data):
                let nodeCount = data["nodeCount"]?.doubleValue ?? 0
                let matchCount = data["matchCount"]?.doubleValue
                ExploreLogger.info(.command, "command \(action) completed nodeCount=\(nodeCount) matchCount=\(matchCount.map { String($0) } ?? "none")")
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
