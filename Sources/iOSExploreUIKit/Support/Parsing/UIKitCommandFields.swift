import Foundation
import iOSExploreServer

/// UIKit 查询命令复用的筛选字段声明。
///
/// 这些字段只描述 Foundation-only 的输入形态，既供 `ui.topViewHierarchy` 和
/// `ui.inspect` 暴露 schema，也供 typed input 解析时保持默认值和错误文案一致。
public enum UIKitFilterFields {
    /// 按 accessibilityIdentifier 精确筛选（完全相等匹配，不是子串/前缀）。
    ///
    /// 示例：identifier='test.button' 只匹配 accessibilityIdentifier 恰好为
    /// 'test.button' 的 view；identifierPrefix='test.' 匹配所有以 'test.' 开头的 view。
    public static let accessibilityIdentifier = CommandFields.optionalString(
        "accessibilityIdentifier",
        description: "按 accessibilityIdentifier 精确筛选（完全相等，非子串/前缀；前缀匹配用 identifierPrefix）"
    )

    /// 按 accessibilityIdentifier 前缀筛选（匹配开头一致的所有 view）。
    ///
    /// 示例：identifierPrefix='mine.' 匹配所有 accessibilityIdentifier 以 'mine.' 开头的
    /// view（如 'mine.header.avatar'、'mine.menu.settings'）。
    public static let accessibilityIdentifierPrefix = CommandFields.optionalString(
        "accessibilityIdentifierPrefix",
        description: "按 accessibilityIdentifier 前缀筛选（匹配开头一致的所有 view）"
    )

    /// 最大递归深度，缺失时不限制。
    public static let maxDepth = CommandFields.optionalNonNegativeInt(
        "maxDepth",
        description: "最大递归深度, 0 表示仅根节点"
    )

    /// 是否包含隐藏 view，默认不包含。
    public static let includeHidden = CommandFields.bool(
        "includeHidden",
        default: false,
        description: "是否包含隐藏 view, 默认 false"
    )
}

/// UIKit 交互命令复用的定位字段声明。
///
/// `accessibilityIdentifier` 与 `path` 由 `UIKitLocatorInput` 统一做互斥和路径文法校验，
/// `viewSnapshotID` 由各命令按自身语义决定是否必填：
/// - `ui.tap` / `ui.control.sendAction`：必填，且 path 与 identifier 都走 freshness 校验；
/// - `ui.scroll` / `ui.input`：可选，仅与 path 搭配做陈旧校验；
/// - `ui.wait` 的 snapshotChanged 模式：必填。
public enum UIKitLocatorFields {
    /// 按 accessibilityIdentifier 精确定位目标 view。
    public static let accessibilityIdentifier = CommandFields.optionalString(
        "accessibilityIdentifier",
        description: "按 accessibilityIdentifier 精确定位目标 view"
    )

    /// 按 `ui.inspect` 或 `ui.topViewHierarchy` 返回的路径定位目标 view。
    public static let path = CommandFields.optionalString(
        "path",
        description: "按 ui.inspect 或 ui.topViewHierarchy 返回的 root/0/1 路径定位目标 view"
    )

    /// `ui.inspect` 签发的结构化 target 指纹快照标识，用于交互命令的陈旧校验。
    ///
    /// 它是 UIKit 结构指纹快照标识，**不是**截图 ID / 图像 hash / VLM 结果。只有
    /// `ui.inspect` 会签发它（`ui.screenshot` 不再签发）。交互命令携带它时，executor
    /// 会重采当前 target 指纹并与签发表比对，任一不一致即拒绝（`stale_locator`），
    /// 防止页面变化后旧定位器指向错误目标。
    public static let viewSnapshotID = CommandFields.optionalString(
        "viewSnapshotID",
        description: "ui.inspect 签发的结构化 target 指纹快照标识"
    )
}

/// UIKit view 定位输入解析工具。
///
/// 该类型不代表一个完整命令输入，而是把多个命令共享的 identifier/path 读取和
/// `UIKitViewLookupTarget` 转换集中到一处，避免 tap/control action 分别维护互斥规则。
public enum UIKitLocatorInput {
    /// 从 command input decoder 读取定位字段并解析为通用 view 定位目标。
    ///
    /// - Parameters:
    ///   - decoder: 已绑定命令 schema 的 typed input decoder。
    ///   - identifierField: identifier 字段声明，默认使用 `accessibilityIdentifier`。
    ///   - pathField: path 字段声明，默认使用 `path`。
    /// - Returns: 可交给 UIKit resolver/executor 的定位目标。
    /// - Throws: 字段读取失败或定位规则失败时抛出 `CommandInputParseError`。
    public static func parse(decoder: inout CommandInputDecoder,
                             identifierField: CommandField<String?> = UIKitLocatorFields.accessibilityIdentifier,
                             pathField: CommandField<String?> = UIKitLocatorFields.path) throws -> UIKitViewLookupTarget {
        let identifier = try decoder.read(identifierField)
        let rawPath = try decoder.read(pathField)
        do {
            return try UIKitViewLookupTarget.parse(identifier: identifier, rawPath: rawPath)
        } catch let error as UIKitLocatorParseError {
            throw CommandInputParseError(error.message)
        }
    }

    /// 从 command input decoder 读取定位字段并解析为通用 view 定位目标，定位字段都缺时返回 nil。
    ///
    /// 与 `parse(decoder:identifierField:pathField:)` 行为一致，唯一差异：当 `accessibilityIdentifier`
    /// 与 `path` 同时缺失时返回 `nil`（供 `ui.scroll` 等命令在两者都缺时回退到"最前 scrollView"
    /// 的默认语义），而非抛错。互斥、空值、路径文法等校验规则保持不变。
    ///
    /// - Parameters:
    ///   - decoder: 已绑定命令 schema 的 typed input decoder。
    ///   - identifierField: identifier 字段声明，默认使用 `accessibilityIdentifier`。
    ///   - pathField: path 字段声明，默认使用 `path`。
    /// - Returns: 可交给 UIKit resolver/executor 的定位目标；两个字段都缺时返回 `nil`。
    /// - Throws: 字段读取失败或定位规则失败（如两者同时给出、identifier 为空、path 文法非法）时抛出 `CommandInputParseError`。
    public static func parseOptional(decoder: inout CommandInputDecoder,
                                     identifierField: CommandField<String?> = UIKitLocatorFields.accessibilityIdentifier,
                                     pathField: CommandField<String?> = UIKitLocatorFields.path) throws -> UIKitViewLookupTarget? {
        let identifier = try decoder.read(identifierField)
        let rawPath = try decoder.read(pathField)
        guard identifier != nil || rawPath != nil else { return nil }
        do {
            return try UIKitViewLookupTarget.parse(identifier: identifier, rawPath: rawPath)
        } catch let error as UIKitLocatorParseError {
            throw CommandInputParseError(error.message)
        }
    }
}
