import Foundation
import iOSExploreServer

/// `ui.swipe` 的滑动方向，使用与 `ui.scroll` 相同的方向枚举。
///
/// - Note: case 声明顺序即 `CaseIterable.allCases` 顺序，被 `CommandFields.requiredEnum`
///   的 "must be one of ..." 错误文案依赖，勿随意重排。
public typealias SwipeDirection = ScrollDirection

/// `ui.swipe` 的命令参数。
///
/// 支持四种滑动场景：
/// 1. **UIScrollView swipe actions**（真正触发）：对 UITableView/UICollectionView 的某个 cell
///    触发 trailing/leading swipe actions（如删除/归档）。需提供 `cellLocator` 定位 cell +
///    `direction` (left→trailing, right→leading) + 可选 `actionTitle` 选择具体 action（nil 时选第一个）。
///    通过 delegate 拿 `UISwipeActionsConfiguration` 后直接调 action handler，绕过合成触摸死路。
/// 2. **UIScrollView swipe gesture**（不实现，返回 false）：对 scrollView 本身（不传 cellLocator）
///    滑动触发 swipe actions——iOS 无公开 API 合成触摸序列，诚实返回 false 落到后续策略。
/// 3. **自定义 swipe gesture**：对挂载了 `UISwipeGestureRecognizer` 的 view 触发其 target-action。
/// 4. **UIPanGestureRecognizer**：触发用户显式添加的 pan gesture（跳过 scrollView 系统 pan）。
///
/// 定位参数（`accessibilityIdentifier`/`path`）可缺省——此时 executor 回退到 keyWindow 最前的
/// scrollView。`viewSnapshotID` 可选，支持 identifier / path 两种定位方式的陈旧校验。
public struct UISwipeInput: CommandInput, Sendable, Equatable {
    private enum Fields {
        static let direction = CommandFields.requiredEnum(
            "direction",
            type: SwipeDirection.self,
            description: "滑动方向: up / down / left / right"
        )
        static let distance = CommandFields.optionalFiniteNumber(
            "distance",
            description: "滑动距离比例(0-1], 缺省=0.8。距离越大滑动越远"
        )
        static let accessibilityIdentifier = UIKitLocatorFields.accessibilityIdentifier
        static let path = UIKitLocatorFields.path
        static let viewSnapshotID = UIKitLocatorFields.viewSnapshotID

        // 新增：cell 定位和 action 选择参数
        static let cellAccessibilityIdentifier = CommandFields.optionalString(
            "cellAccessibilityIdentifier",
            description: "定位 swipe actions 的目标 cell（与 cellPath 互斥）"
        )
        static let cellPath = CommandFields.optionalString(
            "cellPath",
            description: "定位 swipe actions 的目标 cell 路径（与 cellAccessibilityIdentifier 互斥）"
        )
        static let actionTitle = CommandFields.optionalString(
            "actionTitle",
            description: "要触发的 swipe action 标题（如 '删除'/'归档'），nil 时触发第一个"
        )

        static let all: [AnyCommandField] = [
            direction.erased,
            distance.erased,
            accessibilityIdentifier.erased,
            path.erased,
            viewSnapshotID.erased,
            cellAccessibilityIdentifier.erased,
            cellPath.erased,
            actionTitle.erased,
        ]
    }

    /// `ui.swipe` 暴露给 help 和工具客户端的输入 schema。
    public static let inputSchema = CommandInputSchema(
        fields: Fields.all,
        constraints: [
            .extensionMessage("accessibilityIdentifier/path 都缺时滑动 keyWindow 最前的 scrollView"),
            .extensionMessage("cellAccessibilityIdentifier/cellPath 用于定位 UITableView/UICollectionView 的 cell 以触发 swipe actions"),
        ]
    )

    /// 滑动方向。
    public let direction: SwipeDirection
    /// 滑动距离比例（0-1]，缺省时 executor 使用默认值 0.8。
    public let distance: Double?
    /// 目标定位方式，缺省表示滑动 keyWindow 最前的 scrollView。
    public let locator: UIKitViewLookupTarget?
    /// `ui.inspect` 签发的结构化快照标识，可选，identifier / path 两种定位方式都支持陈旧校验
    ///（与 ui.tap 一致）；缺省时不校验。
    public let viewSnapshotID: String?
    /// cell 定位方式（用于 swipe actions 场景），nil 表示对 scrollView 本身滑动（回退原策略）。
    public let cellLocator: UIKitViewLookupTarget?
    /// 要触发的 action 标题，nil 表示触发第一个。
    public let actionTitle: String?

    /// 创建 swipe 输入。
    ///
    /// - Parameters:
    ///   - direction: 滑动方向。
    ///   - distance: 滑动距离比例（0-1]，nil 表示使用默认值 0.8。
    ///   - locator: 目标定位；nil 表示 keyWindow 最前 scrollView。
    ///   - viewSnapshotID: 可选 viewSnapshotID（来自 ui.inspect），默认 nil。
    ///   - cellLocator: cell 定位（用于 swipe actions），nil 表示对 scrollView 本身滑动。
    ///   - actionTitle: 要触发的 action 标题，nil 表示触发第一个。
    public init(direction: SwipeDirection,
                distance: Double? = nil,
                locator: UIKitViewLookupTarget? = nil,
                viewSnapshotID: String? = nil,
                cellLocator: UIKitViewLookupTarget? = nil,
                actionTitle: String? = nil) {
        self.direction = direction
        self.distance = distance
        self.locator = locator
        self.viewSnapshotID = viewSnapshotID
        self.cellLocator = cellLocator
        self.actionTitle = actionTitle
    }

    /// 按 `CommandInputDecoder` 读取字段并执行 distance 组合校验。
    ///
    /// - Parameter decoder: 绑定 `inputSchema` 与原始 data 的字段读取器。
    /// - Returns: 已解析的 swipe 输入。
    /// - Throws: 字段类型、方向枚举、distance 越界、cell 定位规则违规时抛出 `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UISwipeInput {
        let direction = try decoder.read(Fields.direction)
        let distanceRaw = try decoder.read(Fields.distance)
        let viewSnapshotID = try decoder.read(Fields.viewSnapshotID)
        let locator = try UIKitLocatorInput.parseOptional(decoder: &decoder)

        // 解析 cell 定位参数（与 scrollView locator 独立，两者都缺时返回 nil）
        let cellIdentifier = try decoder.read(Fields.cellAccessibilityIdentifier)
        let cellPathRaw = try decoder.read(Fields.cellPath)
        let cellLocator: UIKitViewLookupTarget?
        if cellIdentifier == nil && cellPathRaw == nil {
            cellLocator = nil
        } else {
            do {
                cellLocator = try UIKitViewLookupTarget.parse(identifier: cellIdentifier, rawPath: cellPathRaw)
            } catch let error as UIKitLocatorParseError {
                throw CommandInputParseError("cell locator: \(error.message)")
            }
        }

        let actionTitle = try decoder.read(Fields.actionTitle)

        if let distance = distanceRaw, distance <= 0 || distance > 1 {
            throw CommandInputParseError("distance must be in range (0, 1]")
        }
        return UISwipeInput(direction: direction,
                            distance: distanceRaw,
                            locator: locator,
                            viewSnapshotID: viewSnapshotID,
                            cellLocator: cellLocator,
                            actionTitle: actionTitle)
    }
}
