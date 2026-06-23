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
}

/// `ui.tap` 参数解析结果。
///
/// 失败分支是可返回给调用方的 `invalid_data` 文案，不代表 Swift 异常。
public enum UITapQueryParseResult: Sendable, Equatable {
    /// 解析成功。
    case success(UITapQuery)
    /// 参数非法。
    case failure(String)
}

/// `ui.tap` 的命令参数。
///
/// 第一版支持两类输入：`accessibilityIdentifier`/`path` 定位 view，或 `x`/`y` 指定 window
/// 坐标。两类输入不能混用，避免同一请求里出现不同目标。
public struct UITapQuery: Sendable, Equatable {
    /// 点击目标。
    public let target: UITapTarget

    /// 创建 tap 查询。
    ///
    /// - Parameter target: 点击目标。
    public init(target: UITapTarget) {
        self.target = target
    }

    /// 从命令 `data` 解析查询参数。
    ///
    /// - Parameter data: `ExploreRequest.data`。
    /// - Returns: 成功时返回查询对象；失败时返回可直接放入 `invalid_data` 的说明。
    public static func parse(from data: JSON) -> UITapQueryParseResult {
        let hasViewTarget = data["accessibilityIdentifier"]?.stringValue != nil || data["path"]?.stringValue != nil
        let hasX = data["x"]?.doubleValue != nil
        let hasY = data["y"]?.doubleValue != nil
        let hasPointTarget = hasX || hasY

        if hasViewTarget, hasPointTarget {
            return .failure("view target and coordinate target are mutually exclusive")
        }
        if hasPointTarget {
            guard let x = data["x"]?.doubleValue, let y = data["y"]?.doubleValue else {
                return .failure("x and y must be provided together")
            }
            let coordinateSpace = data["coordinateSpace"]?.stringValue ?? "window"
            guard coordinateSpace == "window" else {
                return .failure("coordinateSpace must be window")
            }
            return .success(UITapQuery(target: .windowPoint(x: x, y: y)))
        }

        switch UIKitViewLookupTarget.parse(identifier: data["accessibilityIdentifier"]?.stringValue,
                                           rawPath: data["path"]?.stringValue) {
        case .success(let target):
            return .success(UITapQuery(target: .view(target)))
        case .failure(let message):
            return .failure(message)
        }
    }
}
