#if canImport(UIKit)
import Foundation
import iOSExploreServer

/// `ui.picker.selectRow` 命令的输入模型。
///
/// 通过 `accessibilityIdentifier` 或 `path` 定位 `UIPickerView`,在指定 `component`(列)
/// 选择某一行。目标行用 `row`(索引)或 `title`(标题,读 dataSource/delegate 的
/// `titleForRow` 比对)二选一。`animated` 控制滚动动画(默认 false)。
public struct UIPickerSelectRowInput: CommandInput, Sendable, Equatable {
    private enum Fields {
        static let accessibilityIdentifier = UIKitLocatorFields.accessibilityIdentifier
        static let path = UIKitLocatorFields.path
        static let viewSnapshotID = UIKitLocatorFields.viewSnapshotID

        static let component = CommandFields.optionalNonNegativeInt(
            "component", description: "目标列索引(0-based,必填)"
        )
        static let row = CommandFields.optionalNonNegativeInt(
            "row", description: "目标行索引(0-based),与 title 二选一"
        )
        static let title = CommandFields.optionalString(
            "title", description: "目标行标题(读 dataSource/delegate 的 titleForRow 比对首个匹配),与 row 二选一"
        )
        static let animated = CommandFields.bool(
            "animated", default: false, description: "是否动画滚动到目标行(默认 false)"
        )

        static let all: [AnyCommandField] = [
            accessibilityIdentifier.erased,
            path.erased,
            viewSnapshotID.erased,
            component.erased,
            row.erased,
            title.erased,
            animated.erased,
        ]
    }

    /// 目标 UIPickerView 定位方式(accessibilityIdentifier / path)。
    public let target: UIKitViewLookupTarget
    /// `ui.inspect` 签发的结构化快照标识,可选;identifier / path 两种定位方式都接受陈旧校验。
    public let viewSnapshotID: String?
    /// 目标列索引(0-based)。
    public let component: Int
    /// 目标行索引(与 `title` 互斥)。
    public let row: Int?
    /// 目标行标题(与 `row` 互斥)。
    public let title: String?
    /// 是否动画滚动。
    public let animated: Bool

    /// 创建行选择输入。
    public init(target: UIKitViewLookupTarget,
                viewSnapshotID: String?,
                component: Int,
                row: Int?,
                title: String?,
                animated: Bool) {
        self.target = target
        self.viewSnapshotID = viewSnapshotID
        self.component = component
        self.row = row
        self.title = title
        self.animated = animated
    }

    /// 输入 schema(暴露给 MCP 客户端)。
    public static let inputSchema = CommandInputSchema(
        fields: Fields.all,
        constraints: [.exactlyOneOf(["row", "title"])]
    )

    /// 从声明式 decoder 解析输入。
    ///
    /// - Throws: `component` 缺失、`row`/`title` 互斥关系不满足、或字段类型错误时抛 `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIPickerSelectRowInput {
        let viewSnapshotID = try decoder.read(Fields.viewSnapshotID)
        let animated = try decoder.read(Fields.animated)
        let component = try decoder.read(Fields.component)
        let row = try decoder.read(Fields.row)
        let title = try decoder.read(Fields.title)
        let target = try UIKitLocatorInput.parse(decoder: &decoder,
                                                  identifierField: Fields.accessibilityIdentifier,
                                                  pathField: Fields.path)

        guard let component = component else {
            throw CommandInputParseError("component 必填(0-based 列索引)")
        }
        // row 与 title 必须且只能提供一个(schema constraint 仅作文档,此处强制)
        if (row != nil) == (title != nil) {
            throw CommandInputParseError("row 和 title 必须且只能提供一个")
        }

        return UIPickerSelectRowInput(target: target,
                                      viewSnapshotID: viewSnapshotID,
                                      component: component,
                                      row: row,
                                      title: title,
                                      animated: animated)
    }
}
#endif
