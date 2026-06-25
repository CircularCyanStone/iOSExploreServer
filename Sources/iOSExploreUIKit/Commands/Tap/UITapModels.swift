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
public struct UITapInput: CommandInput, Sendable, Equatable {
    private enum Fields {
        static let accessibilityIdentifier = UIKitLocatorFields.accessibilityIdentifier
        static let path = UIKitLocatorFields.path
        static let snapshotID = UIKitLocatorFields.snapshotID
        static let x = CommandFields.optionalFiniteNumber(
            "x",
            description: "window 坐标 x, 需要与 y 同时提供"
        )
        static let y = CommandFields.optionalFiniteNumber(
            "y",
            description: "window 坐标 y, 需要与 x 同时提供"
        )
        static let coordinateSpace = CommandFields.enumValue(
            "coordinateSpace",
            type: UITapCoordinateSpace.self,
            default: .window,
            description: "坐标空间, 第一版仅支持 window"
        )

        static let all: [AnyCommandField] = [
            accessibilityIdentifier.erased,
            path.erased,
            snapshotID.erased,
            x.erased,
            y.erased,
            coordinateSpace.erased,
        ]
    }

    /// `ui.tap` 暴露给 help 和工具客户端的输入 schema。
    public static let inputSchema = CommandInputSchema(
        fields: Fields.all,
        constraints: [
            .extensionMessage("snapshotID is valid only with path"),
            .extensionMessage("coordinateSpace currently supports only window"),
        ]
    )

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

    /// 按 `CommandInputDecoder` 读取字段并执行 tap 目标互斥校验。
    ///
    /// - Parameter decoder: 绑定 `inputSchema` 与请求 data 的字段读取器。
    /// - Returns: 已解析的 tap 命令输入。
    /// - Throws: 字段类型、坐标成对关系、目标互斥关系或 snapshotID 搭配非法时抛出
    ///   `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UITapInput {
        let accessibilityIdentifier = try decoder.read(Fields.accessibilityIdentifier)
        let rawPath = try decoder.read(Fields.path)
        let snapshotID = try decoder.read(Fields.snapshotID)
        let x = try decoder.read(Fields.x)
        let y = try decoder.read(Fields.y)
        _ = try decoder.read(Fields.coordinateSpace)
        let hasCoordinateSpace = try decoder.contains(Fields.coordinateSpace)

        let hasIdentifier = accessibilityIdentifier != nil
        let hasPath = rawPath != nil
        let hasViewTarget = hasIdentifier || hasPath
        let hasPointTarget = x != nil || y != nil

        if hasIdentifier, hasPath {
            throw CommandInputParseError("accessibilityIdentifier and path are mutually exclusive")
        }
        if hasViewTarget, hasPointTarget {
            throw CommandInputParseError("view target and coordinate target are mutually exclusive")
        }
        if hasPointTarget {
            guard let x, let y else {
                throw CommandInputParseError("x and y must be provided together")
            }
            if snapshotID != nil {
                throw CommandInputParseError("snapshotID is valid only with path")
            }
            return UITapInput(target: .windowPoint(x: x, y: y), snapshotID: nil)
        }
        if hasPath, hasCoordinateSpace {
            throw CommandInputParseError("coordinateSpace is valid only with window point")
        }
        if snapshotID != nil, !hasPath {
            throw CommandInputParseError("snapshotID is valid only with path")
        }

        do {
            let target = try UIKitViewLookupTarget.parse(identifier: accessibilityIdentifier, rawPath: rawPath)
            return UITapInput(target: .view(target), snapshotID: snapshotID)
        } catch let error as QueryParseError {
            throw CommandInputParseError(error.message)
        }
    }
}

/// `ui.tap` 支持的坐标空间。
///
/// 当前仅允许 window 坐标，保留 enum 是为了让 schema 明确暴露唯一合法值，并给后续扩展留出
/// typed input 兼容点。
public enum UITapCoordinateSpace: String, Sendable, Equatable, CaseIterable {
    /// UIKit window 坐标系。
    case window
}

/// 保留旧查询类型名，减少 executor 和既有测试的迁移面。
public typealias UITapQuery = UITapInput
