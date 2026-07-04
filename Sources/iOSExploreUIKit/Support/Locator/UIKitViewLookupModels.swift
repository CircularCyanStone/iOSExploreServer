import Foundation

/// UIKit view 的通用定位目标。
///
/// 多个 UIKit 命令都会用 `accessibilityIdentifier` 或 `ui.topViewHierarchy` 返回的只读
/// `path` 定位当前页面元素。该类型把定位语义集中到一处，避免各命令分别解析路径导致规则
/// 漂移。
public enum UIKitViewLookupTarget: Sendable, Equatable {
    /// 按 accessibilityIdentifier 精确定位。
    case accessibilityIdentifier(String)
    /// 按 `root/0/2/1` 路径定位；数组保存每一级 subviews 下标。
    case path([Int])

    /// 用于日志和响应的摘要，不包含大块 payload。
    public var description: String {
        switch self {
        case .accessibilityIdentifier(let identifier):
            return "accessibilityIdentifier=\(identifier)"
        case .path(let indexes):
            return "path=" + Self.pathString(from: indexes)
        }
    }

    /// 仅供内部日志使用的脱敏定位摘要。
    public var logSummary: String {
        switch self {
        case .accessibilityIdentifier(let identifier):
            return "accessibilityIdentifierHash=\(UIKitTargetFingerprint.stableHash(identifier)) length=\(identifier.count)"
        case .path(let indexes):
            return "path=" + Self.pathString(from: indexes)
        }
    }

    /// 与 `ui.topViewHierarchy` 一致的路径字符串。
    ///
    /// - Parameter indexes: 从根 view 开始的 subviews 下标链。
    /// - Returns: `root` 或 `root/0/2/1`。
    public static func pathString(from indexes: [Int]) -> String {
        "root" + indexes.map { "/\($0)" }.joined()
    }

    /// 转换为统一定位器 `UIKitLocator`（执行层别名）。
    ///
    /// `UIKitLocator` 已是本类型的 typealias，故该属性返回自身；保留属性名是给执行层入口
    ///（`UIKitActionPlan` / `UIKitLocatorResolver`）一个显式语义标记：「把解析层 target
    /// 交给执行层 locator」，调用点读起来意图明确，不必让读者自行把两个名字对上。
    public var locator: UIKitLocator { self }

    /// 从 identifier/path 字段解析通用目标。
    ///
    /// - Parameters:
    ///   - identifier: accessibilityIdentifier 字段。
    ///   - rawPath: path 字段。
    /// - Returns: 定位目标。
    /// - Throws: `UIKitLocatorParseError`，文案可直接放入 `invalid_data`。
    public static func parse(identifier: String?, rawPath: String?) throws -> UIKitViewLookupTarget {
        if identifier != nil, rawPath != nil {
            throw UIKitLocatorParseError("accessibilityIdentifier and path are mutually exclusive")
        }
        if let identifier {
            if identifier.isEmpty {
                throw UIKitLocatorParseError("accessibilityIdentifier must not be empty")
            }
            return .accessibilityIdentifier(identifier)
        }
        if let rawPath {
            guard let indexes = parsePath(rawPath) else {
                throw UIKitLocatorParseError("path must be root or root/<non-negative-index>/...")
            }
            return .path(indexes)
        }
        throw UIKitLocatorParseError("either accessibilityIdentifier or path is required")
    }

    /// 解析 `root/0/2/1` 路径为下标数组。
    private static func parsePath(_ rawPath: String) -> [Int]? {
        if rawPath == "root" { return [] }
        let parts = rawPath.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.first == "root", parts.count > 1 else { return nil }
        var indexes: [Int] = []
        for part in parts.dropFirst() {
            guard !part.isEmpty, let index = Int(part), index >= 0 else { return nil }
            indexes.append(index)
        }
        return indexes
    }
}
