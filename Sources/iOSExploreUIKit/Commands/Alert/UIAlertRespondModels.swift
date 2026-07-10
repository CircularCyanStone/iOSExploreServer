import Foundation
import iOSExploreServer

/// `ui.alert.respond` 的按钮角色，对齐 `UIAlertAction.Style`。
public enum AlertButtonRole: String, Sendable, Equatable, CaseIterable {
    case `default`
    case cancel
    case destructive
}

/// `ui.alert.respond` 的命令参数。
///
/// 触发当前 alert 的按钮：按 `buttonTitle`、`buttonIndex` 或 `role` 选择一个按钮并触发其
/// `UIAlertAction` handler，并请求关闭 alert。三个选择条件互斥，只能提供一个；都不提供时仅
/// 单按钮 alert 可用（默认点唯一按钮），多按钮 alert 抛 `alertButtonRequired`，避免 agent
/// 猜测默认按钮而误点。
///
/// 查询 alert 结构（标题/消息/按钮/输入框）请用 `ui.inspect`——其顶层 `alert` 区块含每个按钮
/// 与输入框的 `path` / `availableActions`，信息更全；本命令只负责「触发」，不再承担查询职责。
public struct UIAlertRespondInput: CommandInput, Sendable, Equatable {
    private enum Fields {
        static let buttonTitle = CommandFields.optionalString(
            "buttonTitle",
            description: "要触发的按钮标题"
        )
        static let buttonIndex = CommandFields.optionalNonNegativeInt(
            "buttonIndex",
            description: "要触发的按钮下标"
        )
        static let role = CommandFields.optionalString(
            "role",
            description: "按钮角色: default / cancel / destructive"
        )

        static let all: [AnyCommandField] = [
            buttonTitle.erased,
            buttonIndex.erased,
            role.erased,
        ]
    }

    /// `ui.alert.respond` 暴露给 help 和工具客户端的输入 schema。
    public static let inputSchema = CommandInputSchema(
        fields: Fields.all,
        constraints: [.extensionMessage("buttonTitle/buttonIndex/role 最多提供一个")]
    )

    /// 按钮标题选择器。
    public let buttonTitle: String?
    /// 按钮下标选择器。
    public let buttonIndex: Int?
    /// 按钮角色选择器（rawValue）。
    public let role: String?

    /// 创建一条 alert respond 输入。
    public init(buttonTitle: String? = nil,
                buttonIndex: Int? = nil,
                role: String? = nil) {
        self.buttonTitle = buttonTitle
        self.buttonIndex = buttonIndex
        self.role = role
    }

    /// 按 `CommandInputDecoder` 读取字段并校验选择器互斥。
    ///
    /// - Parameter decoder: 绑定 `inputSchema` 与请求 data 的字段读取器。
    /// - Returns: 已解析的 alert respond 输入。
    /// - Throws: 字段类型非法或选择器多于一个时抛出 `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIAlertRespondInput {
        let buttonTitle = try decoder.read(Fields.buttonTitle)
        let buttonIndex = try decoder.read(Fields.buttonIndex)
        let role = try decoder.read(Fields.role)

        let selectorCount = [buttonTitle != nil, buttonIndex != nil, role != nil].filter { $0 }.count
        if selectorCount > 1 {
            throw CommandInputParseError("buttonTitle/buttonIndex/role are mutually exclusive")
        }

        return UIAlertRespondInput(buttonTitle: buttonTitle, buttonIndex: buttonIndex, role: role)
    }
}
