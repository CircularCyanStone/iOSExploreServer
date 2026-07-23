#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// 当前 App controller 结构骨架命令。
///
/// action 为 `ui.controllers`。命令切换到 `MainActor` 从 `window.rootViewController` 出发遍历
/// 整个 controller 结构（navigation stack / presented 链 / tab / split / childViewController），
/// 返回嵌套骨架树 + 每个 controller 的唯一定位 path + `topPath` 摘要。只读，不修改 UI。
///
/// 与 `ui.topViewHierarchy` / `ui.inspect` 的关键差异：那两者只从**顶部控制器 view** 采集视图树，
/// 看不到 navigation stack 非栈顶 VC、presented 链底层、未选中 tab、childVC 嵌套；本命令补上
/// "全局 controller 结构"这个维度。返回的 `topPath` 直接回答"现在在哪个界面"，每个节点的 `path`
/// 为后续让这两个命令接收 `controller` 定位参数（取非顶层 controller 的视图）建立可解析标识。
struct ControllersCommand: Command {
    /// typed 输入模型，负责 schema 暴露和 data 解析。
    typealias Input = UIControllersInput

    /// 固定 action 名，供注册、日志和错误工厂复用。
    static let actionName = "ui.controllers"

    /// 命令名。
    let action = ControllersCommand.actionName

    /// `help` 命令展示的说明。
    let description = "返回从 window.rootViewController 出发的完整 controller 结构树（navigation stack / presented 链 / tab / split / child），每个节点带唯一定位 path 与 topPath 摘要"

    /// 执行 controller 结构骨架采集。
    ///
    /// - Parameter input: 已通过 typed schema 校验的查询参数。
    /// - Returns: 成功时返回骨架树；UIKit 上下文不可用时返回业务失败 envelope。
    func handle(_ input: UIControllersInput) async throws -> ExploreResult {
        UIKitCommandLogger.info("command", "command \(action) start input=typed")
        do {
            let data = try await UIControllersCollector.collect(query: input)
            let controllerCount = data["controllerCount"]?.doubleValue ?? 0
            let topPath = data["topPath"]?.stringValue
            UIKitCommandLogger.info("command", "command \(action) completed controllerCount=\(controllerCount) topPath=\(topPath ?? "none")")
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogger.error("command", error.failure.logMessage)
            return error.result
        }
    }
}
#endif
