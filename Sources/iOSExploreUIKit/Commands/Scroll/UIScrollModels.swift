import Foundation
import iOSExploreServer

/// `ui.scroll` 的滚动方向。
///
/// 该枚举保持 Foundation-only，UIKit 平台 executor 再据此推导 `contentOffset` 的 delta
/// （垂直方向调整 y、水平方向调整 x）。
///
/// - Note: case 声明顺序即 `CaseIterable.allCases` 顺序，被 `CommandFields.requiredEnum`
///   的 "must be one of ..." 错误文案依赖，勿随意重排。
public enum ScrollDirection: String, Sendable, Equatable, CaseIterable {
    /// 向上滚动（contentOffset.y 减小）。
    case up
    /// 向下滚动（contentOffset.y 增大）。
    case down
    /// 向左滚动（contentOffset.x 减小）。
    case left
    /// 向右滚动（contentOffset.x 增大）。
    case right

    /// 是否为垂直方向（up / down）。
    var isVertical: Bool { self == .up || self == .down }
}

/// `ui.scroll` 响应中 `reachedExtent` 的取值。
///
/// 独立于 `ScrollDirection`：方向描述「往哪滚」，extent 描述「滚完后停在哪条边」。
/// 例如向下滚到底时 `reachedExtent == .bottom`，而非 `.down`。对齐 spec §7。
public enum ScrollExtent: String, Sendable, Equatable {
    /// 已到顶部边界（`contentOffset.y <= -adjustedContentInset.top`）。
    case top
    /// 已到底部边界。
    case bottom
    /// 已到左边界（`contentOffset.x <= -adjustedContentInset.left`）。
    case left
    /// 已到右边界。
    case right
}

/// `ui.scroll` 的命令参数。
///
/// 命令要求调用方明确给出 `direction`；`amount` 缺省时按可见区一半滚动；定位条件
/// （`accessibilityIdentifier` / `path`）可同时缺省——此时 executor 回退到 keyWindow
/// 最前的 scrollView。`viewSnapshotID` 可选，仅允许与 `path` 搭配用于陈旧校验。
public struct UIScrollInput: CommandInput, Sendable, Equatable {
    private enum Fields {
        static let direction = CommandFields.requiredEnum(
            "direction",
            type: ScrollDirection.self,
            description: "滚动方向: up / down / left / right"
        )
        static let amount = CommandFields.optionalFiniteNumber(
            "amount",
            description: "滚动距离(pt), 必须 > 0; 缺省 = 可见区 × 0.5"
        )
        static let accessibilityIdentifier = UIKitLocatorFields.accessibilityIdentifier
        static let path = UIKitLocatorFields.path
        static let viewSnapshotID = UIKitLocatorFields.viewSnapshotID
        static let animated = CommandFields.bool(
            "animated",
            default: false,
            description: "是否动画(默认 false, 确定性)"
        )

        static let all: [AnyCommandField] = [
            direction.erased,
            amount.erased,
            accessibilityIdentifier.erased,
            path.erased,
            viewSnapshotID.erased,
            animated.erased,
        ]
    }

    /// `ui.scroll` 暴露给 help 和工具客户端的输入 schema。
    public static let inputSchema = CommandInputSchema(
        fields: Fields.all,
        constraints: [
            .extensionMessage("accessibilityIdentifier/path 都缺时滚动 keyWindow 最前 scrollView"),
            .extensionMessage("viewSnapshotID is valid only with path"),
        ]
    )

    /// 滚动方向。
    public let direction: ScrollDirection
    /// 滚动距离（pt），缺省时 executor 按可见区一半计算。
    public let amount: Double?
    /// 目标定位方式，缺省表示滚动 keyWindow 最前的 scrollView。
    public let locator: UIKitViewLookupTarget?
    /// `ui.viewTargets` 签发的结构化快照标识，可选，仅与 `.path` 定位搭配做陈旧校验。
    public let viewSnapshotID: String?
    /// 是否动画。默认 false（`setContentOffset` 同步更新，after/reachedExtent 为确定值）。
    public let animated: Bool

    /// 创建 scroll 输入。
    ///
    /// - Parameters:
    ///   - direction: 滚动方向。
    ///   - amount: 滚动距离；nil 表示按可见区一半。
    ///   - locator: 目标定位；nil 表示 keyWindow 最前 scrollView。
    ///   - viewSnapshotID: 可选 viewSnapshotID（来自 ui.viewTargets），默认 nil。
    ///   - animated: 是否动画，默认 false。
    public init(direction: ScrollDirection,
                amount: Double? = nil,
                locator: UIKitViewLookupTarget? = nil,
                viewSnapshotID: String? = nil,
                animated: Bool = false) {
        self.direction = direction
        self.amount = amount
        self.locator = locator
        self.viewSnapshotID = viewSnapshotID
        self.animated = animated
    }

    /// 按 `CommandInputDecoder` 读取字段并执行 amount/viewSnapshotID 组合校验。
    ///
    /// - Parameter decoder: 绑定 `inputSchema` 与请求 data 的字段读取器。
    /// - Returns: 已解析的 scroll 输入。
    /// - Throws: 字段类型、方向枚举、amount<=0 或 viewSnapshotID 搭配非法时抛出
    ///   `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIScrollInput {
        let direction = try decoder.read(Fields.direction)
        let amountRaw = try decoder.read(Fields.amount)
        let animated = try decoder.read(Fields.animated)
        let viewSnapshotID = try decoder.read(Fields.viewSnapshotID)
        let locator = try UIKitLocatorInput.parseOptional(decoder: &decoder)
        if let amount = amountRaw, amount <= 0 {
            throw CommandInputParseError("amount must be > 0")
        }
        if viewSnapshotID != nil, let locator, case .accessibilityIdentifier = locator {
            throw CommandInputParseError("viewSnapshotID is valid only with path")
        }
        return UIScrollInput(direction: direction,
                             amount: amountRaw,
                             locator: locator,
                             viewSnapshotID: viewSnapshotID,
                             animated: animated)
    }
}
