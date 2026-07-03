import Foundation

/// UIKit 命令统一目标定位器。
///
/// 把 `accessibilityIdentifier` 与 `ui.topViewHierarchy`/`ui.viewTargets` 返回的只读
/// `path` 两种定位语义收敛到一个枚举。所有 UIKit 命令（tap、control.sendAction、input、
/// scroll 等）都用本类型表达"操作的目标"，避免各命令分别解析导致规则漂移。
///
/// 重构后**不再支持 window 坐标定位**：`ui.tap` 已收敛为只作用于 `ui.viewTargets` 签发的
/// canonical target 的默认激活，不做 hit-test、不接受裸坐标。若未来需要纯观察的坐标诊断，
/// 另开 `ui.hitTest` 命令，不在本类型表达执行性坐标定位。
///
/// 本类型是 Foundation-only 值类型（`Sendable, Equatable`），可在 macOS 测试覆盖；
/// 解析为真实 `UIView` 的工作交给 `UIKitLocatorResolver`（`@MainActor`，仅 iOS 编译）。
public enum UIKitLocator: Sendable, Equatable {
    /// 按 `accessibilityIdentifier` 精确定位。
    case accessibilityIdentifier(String)
    /// 按 `root/0/2/1` 路径定位，数组保存每一级 subviews 下标。
    case path([Int])
}

public extension UIKitLocator {
    /// 仅供内部日志使用的脱敏定位摘要。
    var logSummary: String {
        switch self {
        case .accessibilityIdentifier(let identifier):
            return "accessibilityIdentifierHash=\(UIKitTargetFingerprint.stableHash(identifier)) length=\(identifier.count)"
        case .path(let indexes):
            return "path=" + UIKitViewLookupTarget.pathString(from: indexes)
        }
    }

    /// 从请求字段解析统一定位器。
    ///
    /// identifier 与 path 互斥，且必须提供其一；identifier 不得为空，path 必须符合
    /// `root` / `root/<index>/...` 文法。复用 `UIKitViewLookupTarget.parse` 的文法校验，
    /// 再映射为本枚举。
    ///
    /// - Parameters:
    ///   - identifier: accessibilityIdentifier 字段。
    ///   - path: `root/0/2` 路径字段。
    /// - Returns: 解析出的定位器。
    /// - Throws: `UIKitLocatorParseError`，文案可直接放入 `invalid_data`。
    static func parse(identifier: String?, path: String?) throws -> UIKitLocator {
        switch try UIKitViewLookupTarget.parse(identifier: identifier, rawPath: path) {
        case .accessibilityIdentifier(let value):
            return .accessibilityIdentifier(value)
        case .path(let value):
            return .path(value)
        }
    }
}
