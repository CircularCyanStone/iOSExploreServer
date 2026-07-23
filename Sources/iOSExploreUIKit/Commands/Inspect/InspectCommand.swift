#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// 当前顶部控制器可操作交互目标查询命令。
///
/// action 为 `ui.inspect`。命令面向**事件下发前的目标发现**：返回可被现有公开命令
/// （`ui.tap` / `ui.control.sendAction` / `ui.input`）直接操作的 canonical target——
/// `UIControl`、`UIScrollView` 系、挂有 `UIGestureRecognizer` 的 view、**以及含静态文本、
/// accessibility label 或 accessibility identifier 的展示节点**。容器、纯装饰 view、
/// 无文本无 a11y 信息的非交互节点不进入列表。
///
/// 与 `ui.topViewHierarchy` 的关键差异：
/// - **签发 `viewSnapshotID`**——`ui.tap` / `ui.control.sendAction` / `ui.input` 调用前
///   **必须**先调本命令，并把同响应返回的 `viewSnapshotID` 原样传入；`topViewHierarchy`
///   不签发指纹，不能用于事件下发。**注意**：`viewSnapshotID` 在响应的顶层 `data.viewSnapshotID`
///   字段（全局快照标识，覆盖本次返回的所有 targets），而非单个 target 对象内部——每个
///   target 的 `viewSnapshotID` 字段为 `null`（设计如此）。
/// - **扁平 targets 数组** vs 后者的嵌套 root 树；本命令只覆盖 canonical target（典型页面
///   nodeCount≈88，targetCount≈29），后者覆盖全量视图节点。
/// - **cell 子 view 上挂 `indexPath`**：canonical target 通常是 cell 的内部子 view
///   （`UIListContentView`、cell accessory button 等），`indexPath` 直接挂在这些 target 上，
///   调用方按 section/item 选行不再依赖 subviews 物理顺序或 frame.y 猜——subviews 顺序由
///   z-order 决定，与行号无关。`UITableViewCell` / `UICollectionViewCell` 节点本身因不是
///   canonical target 不进入列表，要看 cell 节点本身用 `ui.topViewHierarchy`。
/// - **indexPath 字段在两者都已存在**，按命令用途择优：要后续 tap/sendAction 选 `ui.inspect`；
///   只看 cell 与 indexPath 的映射（无 tap 意图）选 `topViewHierarchy`，结构更接近视图树。
///
/// 适用场景：
/// - 选 table/collection 的某行 cell → 用本命令，按 `indexPath` 字段确认行号后用同响应的
///   `path` + `viewSnapshotID` 直接 tap，单命令完成。
/// - 已知 `accessibilityIdentifier` 想确认 view 是否可达 → 本命令比 `topViewHierarchy` 轻。
/// - 看完整视图结构 / 颜色 / 字体 / 验收字段 → 用 `ui.topViewHierarchy`。
struct InspectCommand: Command {
    /// typed 输入模型，负责 schema 暴露和 data 解析。
    typealias Input = UIInspectInput

    /// 固定 action 名，供注册、日志和错误工厂复用。
    static let actionName = "ui.inspect"

    /// 命令名。
    let action = InspectCommand.actionName

    /// `help` 命令展示的说明。
    let description = "返回可被 ui.tap / ui.control.sendAction / ui.input 直接操作的 canonical target 列表，签发 viewSnapshotID；调用方按 indexPath 字段选 cell，不依赖 subviews 顺序或 y 坐标"

    /// 执行轻量目标查询。
    ///
    /// - Parameter input: 已通过 typed schema 校验的查询参数。
    /// - Returns: 成功时返回 targets 列表；参数非法或 UIKit 上下文不可用时返回业务失败 envelope。
    func handle(_ input: UIInspectInput) async throws -> ExploreResult {
        UIKitCommandLogger.info("command", "command \(action) start input=typed")
        do {
            let data = try await UIInspectCollector.collect(query: input)
            let targetCount = data["targetCount"]?.doubleValue ?? 0
            let visitedCount = data["visitedNodeCount"]?.doubleValue ?? 0
            UIKitCommandLogger.info("command", "command \(action) completed targetCount=\(targetCount) visitedNodeCount=\(visitedCount)")
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogger.error("command", error.failure.logMessage)
            return error.result
        }
    }
}
#endif
