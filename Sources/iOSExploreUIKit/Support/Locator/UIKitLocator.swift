import Foundation

/// UIKit 命令统一目标定位器。
///
/// 把 `accessibilityIdentifier`、`ui.topViewHierarchy`/`ui.viewTargets` 返回的只读 `path`，
/// 以及 `window` 坐标三种定位语义收敛到一个枚举。所有 UIKit 命令（tap、control.sendAction、
/// 截图、手势等）都用本类型表达"操作的目标"，避免各命令分别解析导致规则漂移。
///
/// 本类型是 Foundation-only 值类型（`Sendable, Equatable`），可在 macOS 测试覆盖；
/// 解析为真实 `UIView` 的工作交给 `UIKitLocatorResolver`（`@MainActor`，仅 iOS 编译）。
public enum UIKitLocator: Sendable, Equatable {
    /// 按 `accessibilityIdentifier` 精确定位。
    case accessibilityIdentifier(String)
    /// 按 `root/0/2/1` 路径定位，数组保存每一级 subviews 下标。
    case path([Int])
    /// 按 window 坐标定位（hit-test 派发，不解析为具体 view）。
    case windowPoint(x: Double, y: Double)
}

public extension UIKitLocator {
    /// 仅供内部日志使用的脱敏定位摘要。
    var logSummary: String {
        switch self {
        case .accessibilityIdentifier(let identifier):
            return "accessibilityIdentifierHash=\(UIKitTargetFingerprint.stableHash(identifier)) length=\(identifier.count)"
        case .path(let indexes):
            return "path=" + UIKitViewLookupTarget.pathString(from: indexes)
        case .windowPoint(let x, let y):
            return "windowPoint=(\(x),\(y))"
        }
    }

    /// 从请求字段解析统一定位器。
    ///
    /// view 定位（identifier/path）与坐标定位（x/y）互斥；坐标必须成对提供。identifier/path
    /// 部分复用既有 `UIKitViewLookupTarget.parse` 的文法（保持向后兼容），再映射为本枚举。
    ///
    /// - Parameters:
    ///   - identifier: accessibilityIdentifier 字段。
    ///   - path: `root/0/2` 路径字段。
    ///   - x: window 坐标 x，需与 y 同时提供。
    ///   - y: window 坐标 y，需与 x 同时提供。
    /// - Returns: 解析出的定位器。
    /// - Throws: `QueryParseError`，文案可直接放入 `invalid_data`。
    static func parse(identifier: String?, path: String?, x: Double?, y: Double?) throws -> UIKitLocator {
        let hasViewLocator = identifier != nil || path != nil
        let hasPointLocator = x != nil || y != nil
        if hasViewLocator, hasPointLocator {
            throw QueryParseError("view locator and window point are mutually exclusive")
        }
        if hasPointLocator {
            guard let x, let y else {
                throw QueryParseError("x and y must be provided together")
            }
            return .windowPoint(x: x, y: y)
        }
        switch try UIKitViewLookupTarget.parse(identifier: identifier, rawPath: path) {
        case .accessibilityIdentifier(let value):
            return .accessibilityIdentifier(value)
        case .path(let value):
            return .path(value)
        }
    }
}
