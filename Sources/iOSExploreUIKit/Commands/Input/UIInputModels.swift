import Foundation
import iOSExploreServer

/// `ui.input` 的文本写入模式。
///
/// 保持 Foundation-only，UIKit 平台据此决定是先清空再写（`replace`）还是追加（`append`）。
///
/// - Note: case 声明顺序即 `CaseIterable.allCases` 顺序，被 `CommandFields.enumValue`
///   的 "must be one of ..." 错误文案依赖，勿随意重排。
public enum InputMode: String, Sendable, Equatable, CaseIterable {
    /// 先清空原内容（selectAll + deleteBackward），再写入新文本。
    case replace
    /// 在原内容末尾追加新文本，不改动已有字符。
    case append
}

/// `ui.input` 的命令参数。
///
/// 命令要求调用方明确提供一个定位条件（`accessibilityIdentifier` 或 `path` 二选一）和
/// 必填的 `text`。`mode` 默认 `replace`（先清空），`submit` 默认 `true`（写完
/// `resignFirstResponder`）。`viewSnapshotID` 可选，用于陈旧校验（通过 located view 的
/// 当前 path 指纹与快照记录比对），identifier / path 两种定位方式均支持。
///
/// 该类型整体 Foundation-only：字段声明与解析不依赖 UIKit，便于在 macOS 上做 schema
/// 单测；UIKit 类型只在 executor 内部出现，不穿过 public 边界。
public struct UIInputInput: CommandInput, Sendable, Equatable {
    private enum Fields {
        static let accessibilityIdentifier = UIKitLocatorFields.accessibilityIdentifier
        static let path = UIKitLocatorFields.path
        static let viewSnapshotID = UIKitLocatorFields.viewSnapshotID
        static let text = CommandFields.requiredString(
            "text",
            description: "要输入的文本 (任意 Unicode, 含中文/emoji)"
        )
        static let mode = CommandFields.enumValue(
            "mode",
            type: InputMode.self,
            default: .replace,
            description: "replace(默认, 先清空原内容) / append(在末尾追加)"
        )
        static let submit = CommandFields.bool(
            "submit",
            default: true,
            description: "输入完成后是否 resignFirstResponder (默认 true)"
        )

        static let all: [AnyCommandField] = [
            accessibilityIdentifier.erased,
            path.erased,
            viewSnapshotID.erased,
            text.erased,
            mode.erased,
            submit.erased,
        ]
    }

    /// `ui.input` 暴露给 help 和工具客户端的输入 schema。
    public static let inputSchema = CommandInputSchema(
        fields: Fields.all,
        constraints: [
            .exactlyOneOf(["accessibilityIdentifier", "path"]),
        ]
    )

    /// 目标控件定位方式。
    public let target: UIKitViewLookupTarget
    /// 要注入的文本（任意 Unicode）。
    public let text: String
    /// 写入模式：replace（默认）或 append。
    public let mode: InputMode
    /// 写完后是否 resignFirstResponder。
    public let submit: Bool
    /// `ui.inspect` 签发的结构化快照标识，可选，identifier / path 两种定位方式都接受陈旧校验。
    public let viewSnapshotID: String?

    /// 创建一条 input 查询。
    ///
    /// - Parameters:
    ///   - target: 目标文本控件定位方式。
    ///   - text: 要注入的文本。
    ///   - mode: 写入模式，默认 `.replace`。
    ///   - submit: 写完后是否 resignFirstResponder，默认 `true`。
    ///   - viewSnapshotID: 可选 viewSnapshotID（来自 ui.inspect），默认 nil。
    public init(target: UIKitViewLookupTarget,
                text: String,
                mode: InputMode = .replace,
                submit: Bool = true,
                viewSnapshotID: String? = nil) {
        self.target = target
        self.text = text
        self.mode = mode
        self.submit = submit
        self.viewSnapshotID = viewSnapshotID
    }

    /// 按 `CommandInputDecoder` 读取字段并执行定位/viewSnapshotID 组合校验。
    ///
    /// - Parameter decoder: 绑定 `inputSchema` 与请求 data 的字段读取器。
    /// - Returns: 已解析的 input 输入。
    /// - Throws: 字段类型、定位互斥关系或 viewSnapshotID 搭配非法时抛出 `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIInputInput {
        let viewSnapshotID = try decoder.read(Fields.viewSnapshotID)
        let mode = try decoder.read(Fields.mode)
        let submit = try decoder.read(Fields.submit)
        let text = try decoder.read(Fields.text)
        let target = try UIKitLocatorInput.parse(decoder: &decoder,
                                                  identifierField: Fields.accessibilityIdentifier,
                                                  pathField: Fields.path)
        return UIInputInput(target: target, text: text, mode: mode, submit: submit, viewSnapshotID: viewSnapshotID)
    }
}
