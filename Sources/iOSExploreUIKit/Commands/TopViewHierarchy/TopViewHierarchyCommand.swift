#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// 当前顶部控制器 view 层级命令。
///
/// action 为 `ui.topViewHierarchy`。命令会切换到 `MainActor` 读取当前前台 window 的顶部
/// 控制器 view，返回**结构、accessibility、文本、颜色和常见控件状态**等观察/排障字段。
/// 输出是嵌套 `root` 树，覆盖全量非隐藏视图节点（含 `UILabel`、container、image 等仅展示
/// view）。
///
/// 与 `ui.viewTargets` 的关键差异：
/// - **不签发 `viewSnapshotID`**——本命令的输出不参与 `ui.tap` / `ui.control.sendAction` /
///   `ui.input` 的陈旧校验，**不能**凭本命令的 path 直接 tap；执行事件下发前必须先调
///   `ui.viewTargets` 拿 `viewSnapshotID`。
/// - **覆盖全量视图节点** vs 后者只覆盖 canonical target（`UIControl` / `UIScrollView` /
///   挂 gesture 的 view）；典型页面 nodeCount≈88，targetCount≈29。
/// - **cell 节点本身挂 `indexPath`**：`UITableViewCell` / `UICollectionViewCell` 节点直接
///   带 `indexPath` 字段，subviews 不带；要看 cell 与 indexPath 的映射用本命令最直观。
///   `ui.viewTargets` 把 `indexPath` 挂在 cell 的子 view 上（canonical target 是子 view）。
/// - **支持 `detailLevel`**：`basic`（只结构与状态）/ `appearance`（含颜色、字体、图片等验收
///   字段，默认）/ `full`。要看 view 颜色 / 字体 / 控件状态用本命令。
/// - **支持 identifier 反查**：给定 `accessibilityIdentifier` 或前缀时切到 `matches` 模式，
///   只返回匹配节点列表（精简输出）。
///
/// 适用场景：
/// - 看页面整体结构、容器嵌套、视图层关系 → 本命令。
/// - 确认某 cell 对应的 indexPath（无后续 tap 意图，纯观察） → 本命令。
/// - 看 view 颜色 / 字体 / 图片 / 控件状态等验收字段 → 本命令 detailLevel=appearance/full。
/// - 要 tap / sendAction / input 一个目标 → **不要**用本命令，先用 `ui.viewTargets`。
struct TopViewHierarchyCommand: Command {
    /// typed 输入模型，负责 schema 暴露和 data 解析。
    typealias Input = UIViewHierarchyInput

    /// 固定 action 名，供注册、日志和错误工厂复用。
    static let actionName = "ui.topViewHierarchy"

    /// 命令名。
    let action = TopViewHierarchyCommand.actionName

    /// `help` 命令展示的说明。
    let description = "返回当前顶部控制器的完整视图层级树（结构 + accessibility + 文本 + 颜色等观察字段），cell 节点带 indexPath；不签发 viewSnapshotID，要 tap/sendAction 请先用 ui.viewTargets"

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
