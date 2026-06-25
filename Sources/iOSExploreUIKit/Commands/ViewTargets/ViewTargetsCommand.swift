#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// 当前顶部控制器轻量交互目标查询命令。
///
/// action 为 `ui.viewTargets`。命令面向事件下发前的目标发现，只返回 path、语义、短文本、
/// window frame 和基础交互状态，不返回完整布局验收树。
struct ViewTargetsCommand: Command {
    /// typed 输入模型，负责 schema 暴露和 data 解析。
    typealias Input = UIViewTargetsInput

    /// 固定 action 名，供注册、日志和错误工厂复用。
    static let actionName = "ui.viewTargets"

    /// 命令名。
    let action = ViewTargetsCommand.actionName

    /// `help` 命令展示的说明。
    let description = "返回当前顶部控制器中可用于事件下发的轻量 UI 目标列表"

    /// 执行轻量目标查询。
    ///
    /// - Parameter input: 已通过 typed schema 校验的查询参数。
    /// - Returns: 成功时返回 targets 列表；参数非法或 UIKit 上下文不可用时返回业务失败 envelope。
    func handle(_ input: UIViewTargetsInput) async throws -> ExploreResult {
        UIKitCommandLogging.info("command", "command \(action) start input=typed")
        do {
            let data = try await UIViewTargetsCollector.collect(query: input)
            let targetCount = data["targetCount"]?.doubleValue ?? 0
            let visitedCount = data["visitedNodeCount"]?.doubleValue ?? 0
            UIKitCommandLogging.info("command", "command \(action) completed targetCount=\(targetCount) visitedNodeCount=\(visitedCount)")
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        }
    }
}
#endif
