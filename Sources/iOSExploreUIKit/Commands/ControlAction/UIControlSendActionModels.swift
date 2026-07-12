import Foundation
import iOSExploreServer

/// `ui.control.sendAction` 支持的 UIControl 事件名。
///
/// 该枚举保持 Foundation-only，UIKit 平台再把它映射为 `UIControl.Event`。
///
/// - Note: case 声明顺序即 `CaseIterable.allCases` 顺序，被 `CommandFields.requiredEnum`
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

    /// 是否为文本编辑事件族（editingChanged / editingDidBegin / editingDidEnd）。
    ///
    /// 这三个事件只服务 `UITextField` 文本编辑；agent 若用 `ui.control.sendAction` + 字符串
    /// value 尝试设文本（误把 sendAction 当文本输入入口），value 的 number schema 会拒绝。
    /// 解析阶段据此标志把通用 number 错误改写成引导 `ui.input` 的友好错误，让 agent 知道
    /// 文本输入应走专用 `ui.input` 命令而非 sendAction。
    var isEditingEvent: Bool {
        switch self {
        case .editingChanged, .editingDidBegin, .editingDidEnd: return true
        case .touchDown, .touchUpInside, .valueChanged: return false
        }
    }
}

/// `ui.control.sendAction` 的命令参数。
///
/// 它是精确 UIKit event 工具：对自身为 `UIControl` 的 canonical target 发送调用方显式指定的
/// `UIControl.Event`。命令要求调用方明确提供一个定位条件（`accessibilityIdentifier` 或 `path`
/// 二选一）、必填的 `viewSnapshotID` 和一个事件名。可选 `value` 字段只对
/// `UISlider`/`UISegmentedControl`/`UIStepper`/`UISwitch` 生效；缺省则只发事件不改值。
/// 它不做 hit-test、不接受坐标、不找祖先 control、不承担默认激活。成功只表示已向该
/// UIControl 发出指定 event。
public struct UIControlSendActionInput: CommandInput, Sendable, Equatable {
    private enum Fields {
        static let accessibilityIdentifier = UIKitLocatorFields.accessibilityIdentifier
        static let path = UIKitLocatorFields.path
        static let viewSnapshotID = UIKitLocatorFields.viewSnapshotID
        static let event = CommandFields.requiredEnum(
            "event",
            type: UIControlSendActionEvent.self,
            description: "事件名: touchDown / touchUpInside / valueChanged / editingChanged / editingDidBegin / editingDidEnd"
        )
        static let value = CommandFields.number(
            "value",
            required: false,
            description: "可选目标值；对 UISlider/UISegmentedControl/UIStepper/UISwitch 有效，缺省则只发事件不改值"
        )

        static let all: [AnyCommandField] = [
            accessibilityIdentifier.erased,
            path.erased,
            viewSnapshotID.erased,
            event.erased,
            value.erased,
        ]
    }

    /// `ui.control.sendAction` 暴露给 help 和工具客户端的输入 schema。
    public static let inputSchema = CommandInputSchema(
        fields: Fields.all,
        constraints: [
            .exactlyOneOf(["accessibilityIdentifier", "path"]),
            .extensionMessage("viewSnapshotID is required and must come from ui.inspect"),
        ]
    )

    /// 目标控件定位方式。
    public let target: UIKitViewLookupTarget
    /// 要发送的 UIControl 事件。
    public let event: UIControlSendActionEvent
    /// 要在发送事件前写入控件的可选值；缺省表示只派发事件，不修改控件当前值。
    public let value: JSONValue?
    /// `ui.inspect` 签发的结构化 target 指纹快照标识，必填；executor 用它做陈旧校验。
    public let viewSnapshotID: String

    /// 创建 sendAction 查询。
    ///
    /// - Parameters:
    ///   - target: 目标控件定位方式。
    ///   - event: 要发送的 UIControl 事件。
    ///   - viewSnapshotID: `ui.inspect` 签发的 viewSnapshotID。
    ///   - value: 要在发送事件前写入控件的可选值。
    public init(target: UIKitViewLookupTarget,
                event: UIControlSendActionEvent,
                viewSnapshotID: String,
                value: JSONValue? = nil) {
        self.target = target
        self.event = event
        self.value = value
        self.viewSnapshotID = viewSnapshotID
    }

    /// 按 `CommandInputDecoder` 读取字段并执行定位/viewSnapshotID/event 校验。
    ///
    /// 当 event 属于 editing* 族（editingChanged/editingDidBegin/editingDidEnd）且 value 解析
    /// 失败（agent 传了非数值的字符串文本）时，把通用的 "value must be a finite number" 改写成
    /// 明确引导 `ui.input` 的错误——editing* 事件服务 UITextField，文本输入是 `ui.input` 的职责，
    /// `sendAction` 的 value 只接受数值控件（slider/segmented/stepper/switch）。非 editing 事件
    /// 传错 value 仍走原 number schema 错误，避免误伤数值控件的文案。
    ///
    /// - Parameter decoder: 绑定 `inputSchema` 与请求 data 的字段读取器。
    /// - Returns: 已解析的 control action 输入。
    /// - Throws: 字段类型、事件枚举、定位互斥关系或 viewSnapshotID 缺失时抛出
    ///   `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIControlSendActionInput {
        let viewSnapshotID = try decoder.read(Fields.viewSnapshotID)
        let event = try decoder.read(Fields.event)
        let value = try readValue(decoder: &decoder, for: event)
        let target = try UIKitLocatorInput.parse(decoder: &decoder,
                                                 identifierField: Fields.accessibilityIdentifier,
                                                 pathField: Fields.path)
        guard let viewSnapshotID else {
            throw CommandInputParseError("viewSnapshotID is required")
        }
        return UIControlSendActionInput(target: target, event: event, viewSnapshotID: viewSnapshotID, value: value)
    }

    /// 读取可选 `value` 字段；editing* 事件族下解析失败时改写为引导 `ui.input` 的友好错误。
    ///
    /// 把 value 读取单独抽出，使引导逻辑与主 parse 流程解耦：主流程仍按 schema 顺序读取各字段，
    /// 只在 value 这一步按 event 类型决定错误文案。引导只在 editing* 事件触发，其余事件透传
    /// 原始 number schema 错误（如 valueChanged + 字符串 value 仍报 "value must be a finite number"）。
    private static func readValue(decoder: inout CommandInputDecoder,
                                  for event: UIControlSendActionEvent) throws -> JSONValue? {
        do {
            return try decoder.read(Fields.value)
        } catch {
            guard event.isEditingEvent else { throw error }
            throw CommandInputParseError(
                "event '\(event.rawValue)' 服务 UITextField 文本编辑，文本输入请使用 ui.input 命令；"
                + "ui.control.sendAction 的 value 只接受数值（UISlider/UISegmentedControl/UIStepper/UISwitch）"
            )
        }
    }
}
