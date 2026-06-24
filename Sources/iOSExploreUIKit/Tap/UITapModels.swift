import Foundation
import iOSExploreServer

/// `ui.tap` 的点击目标。
///
/// view 目标通过通用定位能力解析；windowPoint 目标用于直接按 window 坐标点击。
public enum UITapTarget: Sendable, Equatable {
    /// 按 view 语义定位点击。
    case view(UIKitViewLookupTarget)
    /// 按 window 坐标点击。
    case windowPoint(x: Double, y: Double)

    /// 用于日志和响应的摘要。
    public var description: String {
        switch self {
        case .view(let target):
            return target.description
        case .windowPoint(let x, let y):
            return "windowPoint=(\(x),\(y))"
        }
    }

    /// 转换为 `UIKitActionPlan.tap` 所需的统一定位器。
    ///
    /// 既有 `UITapQuery` 持有 `UIKitViewLookupTarget`（identifier/path 兼容文法），构造
    /// `UIKitActionPlan` 前经本属性桥接为 `UIKitLocator`，交由 executor 解析。windowPoint
    /// 直接透传坐标。
    public var locator: UIKitLocator {
        switch self {
        case .view(let target):
            return target.locator
        case .windowPoint(let x, let y):
            return .windowPoint(x: x, y: y)
        }
    }
}

/// `ui.tap` 的命令参数。
///
/// 第一版支持两类输入：`accessibilityIdentifier`/`path` 定位 view，或 `x`/`y` 指定 window
/// 坐标。两类输入不能混用，避免同一请求里出现不同目标。
public struct UITapQuery: Sendable, Equatable {
    /// 点击目标。
    public let target: UITapTarget
    /// 可选的快照标识，用于对 `.path` 定位做陈旧校验；查询类命令返回，交互命令回传。
    public let snapshotID: String?

    /// 创建 tap 查询。
    ///
    /// - Parameters:
    ///   - target: 点击目标。
    ///   - snapshotID: 可选 snapshotID，默认 nil。
    public init(target: UITapTarget, snapshotID: String? = nil) {
        self.target = target
        self.snapshotID = snapshotID
    }

    /// 从命令 `data` 解析查询参数。
    ///
    /// - Parameter data: `ExploreRequest.data`。
    /// - Returns: 解析出的查询对象。
    /// - Throws: `QueryParseError`，文案可直接放入 `invalid_data`。
    public static func parse(from data: JSON) throws -> UITapQuery {
        let snapshotID = data["snapshotID"]?.stringValue
        let hasViewTarget = data["accessibilityIdentifier"]?.stringValue != nil || data["path"]?.stringValue != nil
        let hasX = data["x"]?.doubleValue != nil
        let hasY = data["y"]?.doubleValue != nil
        let hasPointTarget = hasX || hasY

        if hasViewTarget, hasPointTarget {
            throw QueryParseError("view target and coordinate target are mutually exclusive")
        }
        if hasPointTarget {
            guard let x = data["x"]?.doubleValue, let y = data["y"]?.doubleValue else {
                throw QueryParseError("x and y must be provided together")
            }
            let coordinateSpace = data["coordinateSpace"]?.stringValue ?? "window"
            guard coordinateSpace == "window" else {
                throw QueryParseError("coordinateSpace must be window")
            }
            return UITapQuery(target: .windowPoint(x: x, y: y), snapshotID: snapshotID)
        }

        let target = try UIKitViewLookupTarget.parse(identifier: data["accessibilityIdentifier"]?.stringValue,
                                                     rawPath: data["path"]?.stringValue)
        return UITapQuery(target: .view(target), snapshotID: snapshotID)
    }
}
