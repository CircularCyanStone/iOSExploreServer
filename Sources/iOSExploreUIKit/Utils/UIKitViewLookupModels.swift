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

    /// 转换为统一定位器 `UIKitLocator`。
    ///
    /// 本类型仅保留 identifier/path 两种语义，作为 path 文法的 compatibility wrapper；
    /// 新代码应直接使用 `UIKitLocator`。既有模型（`UITapQuery`/`UIControlSendActionQuery`）
    /// 仍持有本类型，交给 resolver 前通过本属性桥接为 `UIKitLocator`。
    public var locator: UIKitLocator {
        switch self {
        case .accessibilityIdentifier(let value):
            return .accessibilityIdentifier(value)
        case .path(let value):
            return .path(value)
        }
    }

    /// 从 identifier/path 字段解析通用目标。
    ///
    /// - Parameters:
    ///   - identifier: accessibilityIdentifier 字段。
    ///   - rawPath: path 字段。
    /// - Returns: 成功时返回定位目标；失败时返回可放入 `invalid_data` 的说明。
    public static func parse(identifier: String?, rawPath: String?) -> UIKitViewLookupTargetParseResult {
        if identifier != nil, rawPath != nil {
            return .failure("accessibilityIdentifier and path are mutually exclusive")
        }
        if let identifier {
            if identifier.isEmpty {
                return .failure("accessibilityIdentifier must not be empty")
            }
            return .success(.accessibilityIdentifier(identifier))
        }
        if let rawPath {
            guard let indexes = parsePath(rawPath) else {
                return .failure("path must be root or root/<non-negative-index>/...")
            }
            return .success(.path(indexes))
        }
        return .failure("either accessibilityIdentifier or path is required")
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

/// UIKit view 定位目标解析结果。
///
/// 失败分支是可返回给调用方的 `invalid_data` 文案，不代表 Swift 异常。
public enum UIKitViewLookupTargetParseResult: Sendable, Equatable {
    /// 解析成功。
    case success(UIKitViewLookupTarget)
    /// 参数非法。
    case failure(String)
}

/// 保留 `ui.control.sendAction` 既有模型名，实际复用通用定位目标。
public typealias UIControlSendActionTarget = UIKitViewLookupTarget
