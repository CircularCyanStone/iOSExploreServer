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

/// `UIKitLocator.parse` 的结果。
///
/// 失败分支携带可放入 `invalid_data` envelope 的说明文案，不代表 Swift 异常。
public enum UIKitLocatorParseResult: Sendable, Equatable {
    /// 解析成功。
    case success(UIKitLocator)
    /// 参数非法。
    case failure(String)
}

public extension UIKitLocator {
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
    /// - Returns: 成功时返回定位器；失败时返回可放入 `invalid_data` 的说明。
    static func parse(identifier: String?, path: String?, x: Double?, y: Double?) -> UIKitLocatorParseResult {
        let hasViewLocator = identifier != nil || path != nil
        let hasPointLocator = x != nil || y != nil
        if hasViewLocator, hasPointLocator {
            return .failure("view locator and window point are mutually exclusive")
        }
        if hasPointLocator {
            guard let x, let y else {
                return .failure("x and y must be provided together")
            }
            return .success(.windowPoint(x: x, y: y))
        }
        switch UIKitViewLookupTarget.parse(identifier: identifier, rawPath: path) {
        case .success(let target):
            switch target {
            case .accessibilityIdentifier(let value):
                return .success(.accessibilityIdentifier(value))
            case .path(let value):
                return .success(.path(value))
            }
        case .failure(let message):
            return .failure(message)
        }
    }
}
