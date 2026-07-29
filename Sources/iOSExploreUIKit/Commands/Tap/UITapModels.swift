import Foundation
import iOSExploreServer

/// `ui.tap` 的命令参数。
///
/// `ui.tap` 是 Agent 层默认激活动作：对 `ui.inspect` 结构化观察签发的、且声明 `tap`
/// capability 的 canonical target，执行其类型对应的默认激活路由（UIButton → touchUpInside、
/// UISwitch → 翻转 + valueChanged、文本输入 → 聚焦）。它**不是**触摸注入、不接受裸坐标、
/// 不做 hit-test、不找祖先 UIControl fallback。
///
/// 输入只接受结构化 locator（`accessibilityIdentifier` 或 `path` 二选一）加必填的
/// `viewSnapshotID`（由 `ui.inspect` 签发）。identifier 与 path 都走同一 freshness 校验，
/// identifier 不再是绕过陈旧校验的后门。
public struct UITapInput: CommandInput, Sendable, Equatable {
    /// `ui.tap` 在 Swift 执行端使用的 generated 输入定义。
    public static let inputDefinition = UIKitActionContracts.uiTapInput

    /// canonical target 定位方式（identifier 或 path）。
    public let target: UIKitViewLookupTarget
    /// `ui.inspect` 签发的结构化 target 指纹快照标识，必填；executor 用它做陈旧校验。
    public let viewSnapshotID: String

    /// 创建 tap 查询。
    ///
    /// - Parameters:
    ///   - target: canonical target 定位方式。
    ///   - viewSnapshotID: `ui.inspect` 签发的 viewSnapshotID。
    public init(target: UIKitViewLookupTarget, viewSnapshotID: String) {
        self.target = target
        self.viewSnapshotID = viewSnapshotID
    }

    /// 按 `CommandInputDecoder` 读取字段并执行 tap 输入校验。
    ///
    /// - Parameter decoder: 绑定 generated 输入定义与请求 data 的字段读取器。
    /// - Returns: 已解析的 tap 命令输入。
    /// - Throws: 字段类型、定位互斥关系或 viewSnapshotID 缺失时抛出 `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UITapInput {
        
        /// 校验参数的key，是否在定义的信息里面
        /// 并从参数中读取viewSnapshotID的值。
        let viewSnapshotID = try decoder.read(UIKitActionContracts.uiTapViewSnapshotIDField)
        let target = try UIKitLocatorInput.parse(decoder: &decoder,
                                                  identifierField: UIKitActionContracts.uiTapAccessibilityIdentifierField,
                                                  pathField: UIKitActionContracts.uiTapPathField)
        return UITapInput(target: target, viewSnapshotID: viewSnapshotID)
    }
}
