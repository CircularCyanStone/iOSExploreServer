import Foundation
import iOSExploreServer

/// `ui.longPress` 的命令参数。
///
/// 用于在 view 上触发长按手势（`UILongPressGestureRecognizer`），支持：
/// - Context Menu（上下文菜单）
/// - 长按拖拽排序
/// - 3D Touch / Haptic Touch 预览
///
/// 定位参数（`accessibilityIdentifier`/`path`）可缺省——此时 executor 回退到 keyWindow 第一个可触发的 view。
/// `viewSnapshotID` 可选，支持 identifier / path 两种定位方式的陈旧校验。
public struct UILongPressInput: CommandInput, Sendable, Equatable {
    private enum Fields {
        /// 长按持续时间（秒）。默认 0.5 秒，足够触发 context menu。
        static let duration = CommandFields.optionalFiniteNumber(
            "duration",
            description: "长按持续时间(秒), 缺省=0.5"
        )
        static let accessibilityIdentifier = UIKitLocatorFields.accessibilityIdentifier
        static let path = UIKitLocatorFields.path
        static let viewSnapshotID = UIKitLocatorFields.viewSnapshotID

        static let all: [AnyCommandField] = [
            duration.erased,
            accessibilityIdentifier.erased,
            path.erased,
            viewSnapshotID.erased,
        ]
    }

    /// `ui.longPress` 暴露给 help 和工具客户端的输入 schema。
    public static let inputSchema = CommandInputSchema(
        fields: Fields.all,
        constraints: [
            .extensionMessage("accessibilityIdentifier/path 都缺时触发 keyWindow 第一个可长按的 view"),
        ]
    )

    /// 长按持续时间（秒），nil 表示使用默认值 0.5。
    public let duration: Double?
    /// 目标定位方式，缺省表示触发 keyWindow 第一个可长按的 view。
    public let locator: UIKitViewLookupTarget?
    /// `ui.inspect` 签发的结构化快照标识，可选，identifier / path 两种定位方式都支持陈旧校验
    ///（与 ui.tap 一致）；缺省时不校验。
    public let viewSnapshotID: String?

    /// 创建 longPress 输入。
    ///
    /// - Parameters:
    ///   - duration: 长按持续时间（秒），nil 表示使用默认值 0.5。
    ///   - locator: 目标定位；nil 表示 keyWindow 第一个可长按的 view。
    ///   - viewSnapshotID: 可选 viewSnapshotID（来自 ui.inspect），默认 nil。
    public init(duration: Double? = nil,
                locator: UIKitViewLookupTarget? = nil,
                viewSnapshotID: String? = nil) {
        self.duration = duration
        self.locator = locator
        self.viewSnapshotID = viewSnapshotID
    }

    /// 按 `CommandInputDecoder` 读取字段并执行 duration 组合校验。
    ///
    /// duration 上限 10 秒：长按手势触发 context menu / 拖拽排序等场景 10 秒已绰绰有余，
    /// 同时防止调用方误传大值（如 100）让 `@MainActor` 等待占据主线程过久、阻塞其它 ui.* 命令。
    ///
    /// - Parameter decoder: 绑定 `inputSchema` 与请求 data 的字段读取器。
    /// - Returns: 已解析的 longPress 输入。
    /// - Throws: 字段类型、duration 越界（<=0 或 >10）时抛出 `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UILongPressInput {
        let durationRaw = try decoder.read(Fields.duration)
        let viewSnapshotID = try decoder.read(Fields.viewSnapshotID)
        let locator = try UIKitLocatorInput.parseOptional(decoder: &decoder)
        if let duration = durationRaw {
            if duration <= 0 {
                throw CommandInputParseError("duration must be positive")
            }
            if duration > 10 {
                throw CommandInputParseError("duration must be in range (0, 10] seconds")
            }
        }
        return UILongPressInput(duration: durationRaw,
                                locator: locator,
                                viewSnapshotID: viewSnapshotID)
    }
}
