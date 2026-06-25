import Foundation
import iOSExploreServer

/// UIKit 查询命令复用的筛选字段声明。
///
/// 这些字段只描述 Foundation-only 的输入形态，既供 `ui.topViewHierarchy` 和
/// `ui.viewTargets` 暴露 schema，也供 typed input 解析时保持默认值和错误文案一致。
public enum UIKitFilterFields {
    /// 按 accessibilityIdentifier 精确筛选。
    public static let accessibilityIdentifier = CommandFields.optionalString(
        "accessibilityIdentifier",
        description: "按 accessibilityIdentifier 精确筛选"
    )

    /// 按 accessibilityIdentifier 前缀筛选。
    public static let accessibilityIdentifierPrefix = CommandFields.optionalString(
        "accessibilityIdentifierPrefix",
        description: "按 accessibilityIdentifier 前缀筛选"
    )

    /// 最大递归深度，缺失时不限制。
    public static let maxDepth = CommandFields.optionalNonNegativeInt(
        "maxDepth",
        description: "最大递归深度, 0 表示仅根 view"
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
/// `snapshotID` 由各命令按自身语义决定是否允许。
public enum UIKitLocatorFields {
    /// 按 accessibilityIdentifier 精确定位目标 view。
    public static let accessibilityIdentifier = CommandFields.optionalString(
        "accessibilityIdentifier",
        description: "按 accessibilityIdentifier 精确定位目标 view"
    )

    /// 按 `ui.viewTargets` 或 `ui.topViewHierarchy` 返回的路径定位目标 view。
    public static let path = CommandFields.optionalString(
        "path",
        description: "按 ui.viewTargets 或 ui.topViewHierarchy 返回的 root/0/1 路径定位目标 view"
    )

    /// 快照标识，仅允许和 path 定位一起使用。
    public static let snapshotID = CommandFields.optionalString(
        "snapshotID",
        description: "快照标识, 用于 path 定位的陈旧校验"
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
        } catch let error as QueryParseError {
            throw CommandInputParseError(error.message)
        }
    }
}
