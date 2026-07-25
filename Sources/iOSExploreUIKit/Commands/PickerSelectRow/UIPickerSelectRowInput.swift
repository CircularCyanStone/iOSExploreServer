#if canImport(UIKit)
import Foundation
import iOSExploreServer

/// `ui.picker.selectRow` 命令的输入模型。
///
/// 通过 `accessibilityIdentifier` 或 `path` 定位 `UIPickerView`,在指定 `component`(列)
/// 选择某一行。目标行用 `row`(索引)或 `title`(标题,读 dataSource/delegate 的
/// `titleForRow` 比对)二选一。`animated` 控制滚动动画(默认 false)。
public struct UIPickerSelectRowInput: CommandInput, Sendable, Equatable {
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

    /// Swift 执行端的 generated 输入定义。
    public static let inputDefinition = UIKitActionContracts.uiPickerSelectRowInput

    /// 从声明式 decoder 解析输入。
    ///
    /// - Throws: `component` 缺失、`row`/`title` 互斥关系不满足、或字段类型错误时抛 `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIPickerSelectRowInput {
        let viewSnapshotID = try decoder.read(UIKitActionContracts.uiPickerSelectRowViewSnapshotIDField)
        let animated = try decoder.read(UIKitActionContracts.uiPickerSelectRowAnimatedField)
        let component = try decoder.read(UIKitActionContracts.uiPickerSelectRowComponentField)
        let row = try decoder.read(UIKitActionContracts.uiPickerSelectRowRowField)
        let title = try decoder.read(UIKitActionContracts.uiPickerSelectRowTitleField)
        let target = try UIKitLocatorInput.parse(decoder: &decoder,
                                                  identifierField: UIKitActionContracts.uiPickerSelectRowAccessibilityIdentifierField,
                                                  pathField: UIKitActionContracts.uiPickerSelectRowPathField)

        // 领域约束：row 与 title 必须且只能提供一个；合同扩展描述语义，parser 负责执行。
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
