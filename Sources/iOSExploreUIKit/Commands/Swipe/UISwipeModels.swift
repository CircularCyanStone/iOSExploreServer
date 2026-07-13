import Foundation
import iOSExploreServer

/// `ui.swipe` 的滑动方向，使用与 `ui.scroll` 相同的方向枚举。
///
/// - Note: case 声明顺序即 `CaseIterable.allCases` 顺序，被 `CommandFields.requiredEnum`
///   的 "must be one of ..." 错误文案依赖，勿随意重排。
public typealias SwipeDirection = ScrollDirection

/// `ui.swipe` 的命令参数。
///
/// 支持三种滑动场景：
/// 1. **UIScrollView swipe actions**：在 `UIScrollView` 上触发 pan gesture，模拟从边缘开始
///    的滑动以触发 swipe actions（如 swipe to delete）。需要提供 target view（会向上找
///    scrollView 祖先）和 direction（left/right 触发 leading/trailing swipe actions）。
/// 2. **自定义 swipe gesture**：对挂载了 `UISwipeGestureRecognizer` 的 view 触发其 target-action。
/// 3. **普通 view**：无 scrollView 祖先且无 swipe gesture 时，尝试合成 pan gesture 触摸事件。
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

        static let all: [AnyCommandField] = [
            direction.erased,
            distance.erased,
            accessibilityIdentifier.erased,
            path.erased,
            viewSnapshotID.erased,
        ]
    }

    /// `ui.swipe` 暴露给 help 和工具客户端的输入 schema。
    public static let inputSchema = CommandInputSchema(
        fields: Fields.all,
        constraints: [
            .extensionMessage("accessibilityIdentifier/path 都缺时滑动 keyWindow 最前的 scrollView"),
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

    /// 创建 swipe 输入。
    ///
    /// - Parameters:
    ///   - direction: 滑动方向。
    ///   - distance: 滑动距离比例（0-1]，nil 表示使用默认值 0.8。
    ///   - locator: 目标定位；nil 表示 keyWindow 最前 scrollView。
    ///   - viewSnapshotID: 可选 viewSnapshotID（来自 ui.inspect），默认 nil。
    public init(direction: SwipeDirection,
                distance: Double? = nil,
                locator: UIKitViewLookupTarget? = nil,
                viewSnapshotID: String? = nil) {
        self.direction = direction
        self.distance = distance
        self.locator = locator
        self.viewSnapshotID = viewSnapshotID
    }

    /// 按 `CommandInputDecoder` 读取字段并执行 distance 组合校验。
    ///
    /// - Parameter decoder: 绑定 `inputSchema` 与请求 data 的字段读取器。
    /// - Returns: 已解析的 swipe 输入。
    /// - Throws: 字段类型、方向枚举、distance 越界时抛出 `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UISwipeInput {
        let direction = try decoder.read(Fields.direction)
        let distanceRaw = try decoder.read(Fields.distance)
        let viewSnapshotID = try decoder.read(Fields.viewSnapshotID)
        let locator = try UIKitLocatorInput.parseOptional(decoder: &decoder)
        if let distance = distanceRaw, distance <= 0 || distance > 1 {
            throw CommandInputParseError("distance must be in range (0, 1]")
        }
        return UISwipeInput(direction: direction,
                            distance: distanceRaw,
                            locator: locator,
                            viewSnapshotID: viewSnapshotID)
    }
}
