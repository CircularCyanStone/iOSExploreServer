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

/// `ui.input` 单个字段的输入参数。
///
/// 每个字段要求调用方明确提供一个定位条件（`accessibilityIdentifier` 或 `path` 二选一）和
/// 必填的 `text`。`mode` 默认 `replace`（先清空），`submit` 默认 `false`，避免批量填写时
/// 每个字段都触发结束编辑；只有业务依赖 Return / Done / Search 或 `editingDidEnd` 时才显式打开。
///
/// 该类型整体 Foundation-only：字段声明与解析不依赖 UIKit，便于在 macOS 上做 schema 单测。
public struct UIInputField: CommandInput, Sendable, Equatable {
    private enum Fields {
        static let accessibilityIdentifier = UIKitLocatorFields.accessibilityIdentifier
        static let path = UIKitLocatorFields.path
        // 设计特性 F-27: text 经 UIKit insertText 字面量写入，无转义/不求值/无注入防护
        // （UITextField/UITextView 预期行为，非 HTML 渲染）。宿主把该文本拼进 SQL/HTML/Shell
        // 时必须自行参数化/转义。详见 UITextInputExecutor.execute 第 7 步注释。
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
            default: false,
            description: "输入完成后是否 resignFirstResponder / 触发结束编辑语义 (默认 false)"
        )

        static let all: [AnyCommandField] = [
            accessibilityIdentifier.erased,
            path.erased,
            text.erased,
            mode.erased,
            submit.erased,
        ]
    }

    /// 单个字段暴露给顶层 `fields.items` 的输入 schema。
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

    /// 创建一条字段输入。
    ///
    /// - Parameters:
    ///   - target: 目标文本控件定位方式。
    ///   - text: 要注入的文本。
    ///   - mode: 写入模式，默认 `.replace`。
    ///   - submit: 写完后是否 resignFirstResponder，默认 `false`。
    public init(target: UIKitViewLookupTarget,
                text: String,
                mode: InputMode = .replace,
                submit: Bool = false) {
        self.target = target
        self.text = text
        self.mode = mode
        self.submit = submit
    }

    /// 按 `CommandInputDecoder` 读取单个字段并执行定位互斥校验。
    ///
    /// - Parameter decoder: 绑定 `inputSchema` 与请求 data 的字段读取器。
    /// - Returns: 已解析的字段输入。
    /// - Throws: 字段类型或定位互斥关系非法时抛出 `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIInputField {
        let mode = try decoder.read(Fields.mode)
        let submit = try decoder.read(Fields.submit)
        let text = try decoder.read(Fields.text)
        let target = try UIKitLocatorInput.parse(decoder: &decoder,
                                                  identifierField: Fields.accessibilityIdentifier,
                                                  pathField: Fields.path)
        return UIInputField(target: target, text: text, mode: mode, submit: submit)
    }
}

/// `ui.input` 的命令参数。
///
/// `ui.input` 只有批量形态：调用方传入 `fields` 数组，单字段输入就是数组里只有一项。顶层
/// `viewSnapshotID` 可选，用于把这一批字段绑定到同一次 `ui.inspect` 签发的结构快照；执行时
/// 每个字段都会独立重新定位并做陈旧校验。`stopOnFailure` 默认 `true`，失败时不回滚已经写入的字段。
public struct UIInputInput: CommandInput, Sendable, Equatable {
    /// 单次 `ui.input` 最多处理的字段数，避免一次命令持有主线程过久。
    public static let maxFields = 16

    private enum Fields {
        static let fields = CommandFields.requiredArray(
            "fields",
            description: "要按顺序输入的字段数组；单字段输入也必须放在数组里",
            itemsSchema: UIInputField.inputSchema.toJSON(),
            minimumCount: 1,
            maximumCount: UIInputInput.maxFields
        )
        static let viewSnapshotID = UIKitLocatorFields.viewSnapshotID
        static let stopOnFailure = CommandFields.bool(
            "stopOnFailure",
            default: true,
            description: "某个字段失败后是否停止执行后续字段 (默认 true)"
        )

        static let all: [AnyCommandField] = [
            fields.erased,
            viewSnapshotID.erased,
            stopOnFailure.erased,
        ]
    }

    /// `ui.input` 暴露给 help 和工具客户端的输入 schema。
    public static let inputSchema = CommandInputSchema(fields: Fields.all)

    /// 按顺序执行的字段输入列表。
    public let fields: [UIInputField]
    /// 某个字段失败后是否停止执行后续字段。
    public let stopOnFailure: Bool
    /// `ui.inspect` 签发的结构化快照标识，可选，identifier / path 两种定位方式都接受陈旧校验。
    public let viewSnapshotID: String?

    /// 创建一条批量 input 查询。
    ///
    /// - Parameters:
    ///   - fields: 按顺序执行的字段输入列表。
    ///   - stopOnFailure: 某个字段失败后是否停止执行后续字段，默认 `true`。
    ///   - viewSnapshotID: 可选 viewSnapshotID（来自 ui.inspect），默认 nil。
    public init(fields: [UIInputField],
                stopOnFailure: Bool = true,
                viewSnapshotID: String? = nil) {
        self.fields = fields
        self.stopOnFailure = stopOnFailure
        self.viewSnapshotID = viewSnapshotID
    }

    /// 从原始 `data` 解析批量输入。
    ///
    /// `fields` 是对象数组，需要保留元素下标并逐项解析；因此本类型覆写 `parse(from:)`，先用
    /// 顶层 decoder 拒绝未知字段和读取默认值，再手写解析数组元素。
    ///
    /// - Parameter data: `ExploreRequest.data` 中的原始参数对象。
    /// - Returns: 已解析的批量 input 输入。
    /// - Throws: 顶层字段类型、字段数量、元素类型或单字段定位互斥关系非法时抛出 `CommandInputParseError`。
    public static func parse(from data: JSON) throws -> UIInputInput {
        var decoder = CommandInputDecoder(data, schema: inputSchema)
        try decoder.validateNoUnknownFields()
        let rawFields = try decoder.read(Fields.fields)
        let viewSnapshotID = try decoder.read(Fields.viewSnapshotID)
        let stopOnFailure = try decoder.read(Fields.stopOnFailure)
        try decoder.assertAllDeclaredFieldsRead()

        let parsedFields = try rawFields.enumerated().map { index, raw -> UIInputField in
            guard case .object(let object) = raw else {
                throw CommandInputParseError("fields[\(index)] must be an object")
            }
            do {
                return try UIInputField.parse(from: object)
            } catch let error as CommandInputParseError {
                throw CommandInputParseError("fields[\(index)]: \(error.message)")
            }
        }
        return UIInputInput(fields: parsedFields,
                            stopOnFailure: stopOnFailure,
                            viewSnapshotID: viewSnapshotID)
    }

    /// 协议要求的 decoder 入口。
    ///
    /// `fields` 对象数组需要从原始 `data` 逐项解析并附带下标错误文案，真实入口是 `parse(from:)`。
    ///
    /// - Parameter decoder: 绑定 `inputSchema` 与请求 data 的字段读取器。
    /// - Returns: 不返回；该入口始终抛错。
    /// - Throws: 始终抛出 `CommandInputParseError`，提示改用 `parse(from:)`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIInputInput {
        throw CommandInputParseError("UIInputInput must be parsed via parse(from:)")
    }
}
