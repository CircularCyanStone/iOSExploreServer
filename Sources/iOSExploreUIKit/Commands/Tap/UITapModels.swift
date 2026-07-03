import Foundation
import iOSExploreServer

/// `ui.tap` 的命令参数。
///
/// `ui.tap` 是 Agent 层默认激活动作：对 `ui.viewTargets` 结构化观察签发的、且声明 `tap`
/// capability 的 canonical target，执行其类型对应的默认激活路由（UIButton → touchUpInside、
/// UISwitch → 翻转 + valueChanged、文本输入 → 聚焦）。它**不是**触摸注入、不接受裸坐标、
/// 不做 hit-test、不找祖先 UIControl fallback。
///
/// 输入只接受结构化 locator（`accessibilityIdentifier` 或 `path` 二选一）加必填的
/// `viewSnapshotID`（由 `ui.viewTargets` 签发）。identifier 与 path 都走同一 freshness 校验，
/// identifier 不再是绕过陈旧校验的后门。
public struct UITapInput: CommandInput, Sendable, Equatable {
    private enum Fields {
        static let accessibilityIdentifier = UIKitLocatorFields.accessibilityIdentifier
        static let path = UIKitLocatorFields.path
        static let viewSnapshotID = UIKitLocatorFields.viewSnapshotID

        static let all: [AnyCommandField] = [
            accessibilityIdentifier.erased,
            path.erased,
            viewSnapshotID.erased,
        ]
    }

    /// `ui.tap` 暴露给 help 和工具客户端的输入 schema。
    public static let inputSchema = CommandInputSchema(
        fields: Fields.all,
        constraints: [
            .exactlyOneOf(["accessibilityIdentifier", "path"]),
            .extensionMessage("viewSnapshotID is required and must come from ui.viewTargets"),
        ]
    )

    /// canonical target 定位方式（identifier 或 path）。
    public let target: UIKitViewLookupTarget
    /// `ui.viewTargets` 签发的结构化 target 指纹快照标识，必填；executor 用它做陈旧校验。
    public let viewSnapshotID: String

    /// 创建 tap 查询。
    ///
    /// - Parameters:
    ///   - target: canonical target 定位方式。
    ///   - viewSnapshotID: `ui.viewTargets` 签发的 viewSnapshotID。
    public init(target: UIKitViewLookupTarget, viewSnapshotID: String) {
        self.target = target
        self.viewSnapshotID = viewSnapshotID
    }

    /// 按 `CommandInputDecoder` 读取字段并执行 tap 输入校验。
    ///
    /// - Parameter decoder: 绑定 `inputSchema` 与请求 data 的字段读取器。
    /// - Returns: 已解析的 tap 命令输入。
    /// - Throws: 字段类型、定位互斥关系或 viewSnapshotID 缺失时抛出 `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UITapInput {
        let viewSnapshotID = try decoder.read(Fields.viewSnapshotID)
        let target = try UIKitLocatorInput.parse(decoder: &decoder,
                                                  identifierField: Fields.accessibilityIdentifier,
                                                  pathField: Fields.path)
        guard let viewSnapshotID else {
            throw CommandInputParseError("viewSnapshotID is required")
        }
        return UITapInput(target: target, viewSnapshotID: viewSnapshotID)
    }
}
