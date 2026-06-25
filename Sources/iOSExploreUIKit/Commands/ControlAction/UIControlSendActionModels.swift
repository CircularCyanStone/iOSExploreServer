import Foundation
import iOSExploreServer

/// `ui.control.sendAction` 支持的 UIControl 事件名。
///
/// 该枚举保持 Foundation-only，UIKit 平台再把它映射为 `UIControl.Event`。
///
/// - Note: case 声明顺序即 `CaseIterable.allCases` 顺序，被 `QueryDecoder.requiredEnum`
///   的 "must be one of ..." 错误文案依赖，勿随意重排。
public enum UIControlSendActionEvent: String, Sendable, Equatable, CaseIterable {
    /// 按下控件。
    case touchDown
    /// 常见按钮点击完成事件。
    case touchUpInside
    /// 值变化事件，适用于 switch、slider、segmented control 等。
    case valueChanged
    /// 文本编辑变化事件。
    case editingChanged
    /// 文本编辑开始事件。
    case editingDidBegin
    /// 文本编辑结束事件。
    case editingDidEnd
}

/// `ui.control.sendAction` 的命令参数。
///
/// 命令要求调用方明确提供一个定位条件和一个事件名。定位条件只能二选一，避免同一请求里
/// identifier 与 path 指向不同控件导致误触发。
public struct UIControlSendActionInput: CommandInput, Sendable, Equatable {
    private enum Fields {
        static let accessibilityIdentifier = UIKitLocatorFields.accessibilityIdentifier
        static let path = UIKitLocatorFields.path
        static let snapshotID = UIKitLocatorFields.snapshotID
        static let event = CommandFields.requiredEnum(
            "event",
            type: UIControlSendActionEvent.self,
            description: "事件名: touchDown / touchUpInside / valueChanged / editingChanged / editingDidBegin / editingDidEnd"
        )

        static let all: [AnyCommandField] = [
            accessibilityIdentifier.erased,
            path.erased,
            snapshotID.erased,
            event.erased,
        ]
    }

    /// `ui.control.sendAction` 暴露给 help 和工具客户端的输入 schema。
    public static let inputSchema = CommandInputSchema(
        fields: Fields.all,
        constraints: [
            .exactlyOneOf(["accessibilityIdentifier", "path"]),
            .extensionMessage("snapshotID is valid only with path"),
        ]
    )

    /// 目标控件定位方式。
    public let target: UIControlSendActionTarget
    /// 要发送的 UIControl 事件。
    public let event: UIControlSendActionEvent
    /// 可选的快照标识，用于对 `.path` 定位做陈旧校验。
    public let snapshotID: String?

    /// 创建 sendAction 查询。
    ///
    /// - Parameters:
    ///   - target: 目标控件定位方式。
    ///   - event: 要发送的 UIControl 事件。
    ///   - snapshotID: 可选 snapshotID，默认 nil。
    public init(target: UIControlSendActionTarget, event: UIControlSendActionEvent, snapshotID: String? = nil) {
        self.target = target
        self.event = event
        self.snapshotID = snapshotID
    }

    /// 按 `CommandInputDecoder` 读取字段并执行定位/snapshotID 组合校验。
    ///
    /// - Parameter decoder: 绑定 `inputSchema` 与请求 data 的字段读取器。
    /// - Returns: 已解析的 control action 输入。
    /// - Throws: 字段类型、事件枚举、定位互斥关系或 snapshotID 搭配非法时抛出
    ///   `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIControlSendActionInput {
        let snapshotID = try decoder.read(Fields.snapshotID)
        let event = try decoder.read(Fields.event)
        let target = try UIKitLocatorInput.parse(decoder: &decoder,
                                                 identifierField: Fields.accessibilityIdentifier,
                                                 pathField: Fields.path)
        if snapshotID != nil, case .accessibilityIdentifier = target {
            throw CommandInputParseError("snapshotID is valid only with path")
        }
        return UIControlSendActionInput(target: target, event: event, snapshotID: snapshotID)
    }
}

/// 保留旧查询类型名，减少 executor 和既有测试的迁移面。
public typealias UIControlSendActionQuery = UIControlSendActionInput
