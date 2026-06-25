#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// 当前顶部控制器 view 层级命令。
///
/// action 为 `ui.topViewHierarchy`。命令会切换到 `MainActor` 读取当前前台 window 的顶部
/// 控制器 view，返回结构、定位、accessibility、文本、颜色和常见控件状态。
struct TopViewHierarchyCommand: Command {
    /// typed 输入模型，负责 schema 暴露和 data 解析。
    typealias Input = UIViewHierarchyInput

    /// 固定 action 名，供注册、日志和错误工厂复用。
    static let actionName = "ui.topViewHierarchy"

    /// 命令名。
    let action = TopViewHierarchyCommand.actionName

    /// `help` 命令展示的说明。
    let description = "返回当前顶部控制器 view 及其子视图层级信息"

    /// 执行顶部视图层级采集。
    ///
    /// - Parameter input: 已通过 typed schema 校验的层级查询参数。
    /// - Returns: 成功时返回 root 树或 matches 列表；参数非法时返回 `invalid_data`。
    func handle(_ input: UIViewHierarchyInput) async throws -> ExploreResult {
        UIKitCommandLogging.info("command", "command \(action) start input=typed")
        do {
            let data = try await UIViewHierarchyCollector.collectTopViewHierarchy(query: input)
            let nodeCount = data["nodeCount"]?.doubleValue ?? 0
            let matchCount = data["matchCount"]?.doubleValue
            UIKitCommandLogging.info("command", "command \(action) completed nodeCount=\(nodeCount) matchCount=\(matchCount.map { String($0) } ?? "none")")
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        }
    }
}
#endif
