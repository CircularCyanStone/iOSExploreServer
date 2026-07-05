import Foundation

/// 公有 API 路径（`indexPath(for:)`）解析到的 section/item 摘要。
///
/// 用于在 `UIViewHierarchyNode`（层级节点）和 `UICellSelectionAttempt`（cell selection 结果）
/// 中跨 MainActor 边界传输 indexPath 信息。
///
/// 该类型不依赖 UIKit，只含 `Int` 字段，`Sendable` + `Equatable`，可在 Foundation-only
/// 层与 UIKit 层之间自由传递。
public struct IndexPathSummary: Sendable, Equatable {
    /// section / 区索引。
    public let section: Int
    /// item / 行索引（取自 `IndexPath.row` 或 `IndexPath.item`，两者等价）。
    public let item: Int

    /// 创建一个 indexPath 摘要。
    ///
    /// - Parameters:
    ///   - section: section / 区索引。
    ///   - item: item / 行索引。
    public init(section: Int, item: Int) {
        self.section = section
        self.item = item
    }
}
