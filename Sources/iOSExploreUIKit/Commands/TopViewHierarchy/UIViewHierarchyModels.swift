import Foundation
import iOSExploreServer

/// UI 层级节点的矩形值。
///
/// 该类型不依赖 UIKit，既可由 `CGRect` 转换而来，也便于测试中直接构造。命令响应中
/// `frame` 与 `bounds` 都使用它表达，方便 agent 判断元素位置与尺寸。
public struct UIViewHierarchyRect: Sendable, Equatable {
    /// X 坐标。
    public let x: Double
    /// Y 坐标。
    public let y: Double
    /// 宽度。
    public let width: Double
    /// 高度。
    public let height: Double

    /// 创建一个矩形描述。
    ///
    /// - Parameters:
    ///   - x: X 坐标。
    ///   - y: Y 坐标。
    ///   - width: 宽度。
    ///   - height: 高度。
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// 转为命令响应中的 JSON 对象。
    public func toJSON() -> JSON {
        ["x": .double(x), "y": .double(y), "width": .double(width), "height": .double(height)]
    }
}

/// UI 元素的 accessibility 语义信息。
///
/// 业务层可通过 `accessibilityIdentifier` 提供稳定语义锚点，例如
/// `mine.header.avatar`。库只读取这些系统字段，不主动写入业务 UI。
public struct UIViewHierarchyAccessibility: Sendable, Equatable {
    /// 业务层设置的稳定标识符。
    public let identifier: String?
    /// 辅助功能标签。
    public let label: String?
    /// 辅助功能值。
    public let value: String?
    /// 辅助功能提示。
    public let hint: String?

    /// 创建 accessibility 描述。
    ///
    /// - Parameters:
    ///   - identifier: 业务层设置的稳定标识符。
    ///   - label: 辅助功能标签。
    ///   - value: 辅助功能值。
    ///   - hint: 辅助功能提示。
    public init(identifier: String? = nil, label: String? = nil, value: String? = nil, hint: String? = nil) {
        self.identifier = identifier
        self.label = label
        self.value = value
        self.hint = hint
    }
}

/// UI 元素的基础状态。
///
/// 状态字段帮助 agent 判断节点是否可见、是否能接收交互，以及 alpha 导致的视觉效果。
public struct UIViewHierarchyState: Sendable, Equatable {
    /// 是否被隐藏。
    public let isHidden: Bool
    /// 透明度。
    public let alpha: Double
    /// 是否不透明。
    public let isOpaque: Bool
    /// 是否允许用户交互。
    public let isUserInteractionEnabled: Bool

    /// 创建基础状态描述。
    ///
    /// - Parameters:
    ///   - isHidden: 是否被隐藏。
    ///   - alpha: 透明度。
    ///   - isOpaque: 是否不透明。
    ///   - isUserInteractionEnabled: 是否允许用户交互。
    public init(isHidden: Bool, alpha: Double, isOpaque: Bool, isUserInteractionEnabled: Bool) {
        self.isHidden = isHidden
        self.alpha = alpha
        self.isOpaque = isOpaque
        self.isUserInteractionEnabled = isUserInteractionEnabled
    }

    /// 转为命令响应中的 JSON 对象。
    public func toJSON() -> JSON {
        [
            "isHidden": .bool(isHidden),
            "alpha": .double(alpha),
            "isOpaque": .bool(isOpaque),
            "isUserInteractionEnabled": .bool(isUserInteractionEnabled),
        ]
    }
}

/// 文本类 UI 的验收信息。
///
/// 用于描述 `UILabel`、`UIButton.titleLabel`、`UITextField`、`UITextView` 等可见文字。
public struct UIViewHierarchyText: Sendable, Equatable {
    /// 可见文本值。
    public let value: String?
    /// 字体名。
    public let fontName: String?
    /// 字号。
    public let fontSize: Double?
    /// 文本颜色，格式为 `#RRGGBBAA` 或 `#RRGGBB`。
    public let textColor: String?
    /// 文本对齐方式。
    public let textAlignment: String?
    /// 最大行数；UIKit 中 `0` 表示不限行。
    public let numberOfLines: Int?

    /// 创建文本验收信息。
    ///
    /// - Parameters:
    ///   - value: 可见文本值。
    ///   - fontName: 字体名。
    ///   - fontSize: 字号。
    ///   - textColor: 文本颜色。
    ///   - textAlignment: 文本对齐方式。
    ///   - numberOfLines: 最大行数。
    public init(value: String? = nil,
                fontName: String? = nil,
                fontSize: Double? = nil,
                textColor: String? = nil,
                textAlignment: String? = nil,
                numberOfLines: Int? = nil) {
        self.value = value
        self.fontName = fontName
        self.fontSize = fontSize
        self.textColor = textColor
        self.textAlignment = textAlignment
        self.numberOfLines = numberOfLines
    }

    /// 转为命令响应中的 JSON 对象。
    public func toJSON() -> JSON {
        var json: JSON = [:]
        json["value"] = value.map(JSONValue.string) ?? .null
        json["fontName"] = fontName.map(JSONValue.string) ?? .null
        json["fontSize"] = fontSize.map(JSONValue.double) ?? .null
        json["textColor"] = textColor.map(JSONValue.string) ?? .null
        json["textAlignment"] = textAlignment.map(JSONValue.string) ?? .null
        json["numberOfLines"] = numberOfLines.map { .double(Double($0)) } ?? .null
        return json
    }
}

/// UI 元素的外观验收信息。
///
/// 这些字段覆盖常见设计验收：背景色、tint、圆角和边框。阴影、transform 等可后续按同一
/// 分组继续扩展。
public struct UIViewHierarchyAppearance: Sendable, Equatable {
    /// 背景色。
    public let backgroundColor: String?
    /// tint 颜色。
    public let tintColor: String?
    /// 圆角半径。
    public let cornerRadius: Double?
    /// 边框宽度。
    public let borderWidth: Double?
    /// 边框颜色。
    public let borderColor: String?

    /// 创建外观验收信息。
    ///
    /// - Parameters:
    ///   - backgroundColor: 背景色。
    ///   - tintColor: tint 颜色。
    ///   - cornerRadius: 圆角半径。
    ///   - borderWidth: 边框宽度。
    ///   - borderColor: 边框颜色。
    public init(backgroundColor: String? = nil,
                tintColor: String? = nil,
                cornerRadius: Double? = nil,
                borderWidth: Double? = nil,
                borderColor: String? = nil) {
        self.backgroundColor = backgroundColor
        self.tintColor = tintColor
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.borderColor = borderColor
    }

    /// 转为命令响应中的 JSON 对象。
    public func toJSON() -> JSON {
        var json: JSON = [:]
        json["backgroundColor"] = backgroundColor.map(JSONValue.string) ?? .null
        json["tintColor"] = tintColor.map(JSONValue.string) ?? .null
        json["cornerRadius"] = cornerRadius.map(JSONValue.double) ?? .null
        json["borderWidth"] = borderWidth.map(JSONValue.double) ?? .null
        json["borderColor"] = borderColor.map(JSONValue.string) ?? .null
        return json
    }
}

/// 控件类 UI 的状态和布局信息。
///
/// 主要用于按钮、输入框等 `UIControl` 子类，帮助 agent 判断是否可点击、选中或高亮。
public struct UIViewHierarchyControl: Sendable, Equatable {
    /// 控件是否可用。
    public let isEnabled: Bool?
    /// 控件是否选中。
    public let isSelected: Bool?
    /// 控件是否高亮。
    public let isHighlighted: Bool?
    /// 水平内容对齐方式。
    public let horizontalAlignment: String?
    /// 垂直内容对齐方式。
    public let verticalAlignment: String?

    /// 创建控件状态描述。
    ///
    /// - Parameters:
    ///   - isEnabled: 控件是否可用。
    ///   - isSelected: 控件是否选中。
    ///   - isHighlighted: 控件是否高亮。
    ///   - horizontalAlignment: 水平内容对齐方式。
    ///   - verticalAlignment: 垂直内容对齐方式。
    public init(isEnabled: Bool? = nil,
                isSelected: Bool? = nil,
                isHighlighted: Bool? = nil,
                horizontalAlignment: String? = nil,
                verticalAlignment: String? = nil) {
        self.isEnabled = isEnabled
        self.isSelected = isSelected
        self.isHighlighted = isHighlighted
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
    }

    /// 转为命令响应中的 JSON 对象。
    public func toJSON() -> JSON {
        var json: JSON = [:]
        json["isEnabled"] = isEnabled.map(JSONValue.bool) ?? .null
        json["isSelected"] = isSelected.map(JSONValue.bool) ?? .null
        json["isHighlighted"] = isHighlighted.map(JSONValue.bool) ?? .null
        json["horizontalAlignment"] = horizontalAlignment.map(JSONValue.string) ?? .null
        json["verticalAlignment"] = verticalAlignment.map(JSONValue.string) ?? .null
        return json
    }
}

/// 图片类 UI 的验收信息。
///
/// 用于描述 `UIImageView` 或按钮图片，让 agent 能判断图片区域和渲染模式。
public struct UIViewHierarchyImage: Sendable, Equatable {
    /// 图片宽度。
    public let width: Double?
    /// 图片高度。
    public let height: Double?
    /// 图片渲染模式。
    public let renderingMode: String?
    /// 当前是否展示 highlighted 图片。
    public let isHighlighted: Bool?

    /// 创建图片验收信息。
    ///
    /// - Parameters:
    ///   - width: 图片宽度。
    ///   - height: 图片高度。
    ///   - renderingMode: 图片渲染模式。
    ///   - isHighlighted: 当前是否展示 highlighted 图片。
    public init(width: Double? = nil, height: Double? = nil, renderingMode: String? = nil, isHighlighted: Bool? = nil) {
        self.width = width
        self.height = height
        self.renderingMode = renderingMode
        self.isHighlighted = isHighlighted
    }

    /// 转为命令响应中的 JSON 对象。
    public func toJSON() -> JSON {
        var json: JSON = [:]
        json["width"] = width.map(JSONValue.double) ?? .null
        json["height"] = height.map(JSONValue.double) ?? .null
        json["renderingMode"] = renderingMode.map(JSONValue.string) ?? .null
        json["isHighlighted"] = isHighlighted.map(JSONValue.bool) ?? .null
        return json
    }
}

/// 滚动容器的验收信息。
///
/// 用于描述 `UIScrollView` 及其子类的可滚动范围和当前位置。
public struct UIViewHierarchyScroll: Sendable, Equatable {
    /// 内容尺寸。
    public let contentSize: UIViewHierarchyRect?
    /// 当前内容偏移。
    public let contentOffset: UIViewHierarchyRect?
    /// 内容 inset，按 top/left/bottom/right 表达。
    public let contentInset: JSON?
    /// 是否允许滚动。
    public let isScrollEnabled: Bool?

    /// 创建滚动信息。
    ///
    /// - Parameters:
    ///   - contentSize: 内容尺寸。
    ///   - contentOffset: 当前内容偏移。
    ///   - contentInset: 内容 inset。
    ///   - isScrollEnabled: 是否允许滚动。
    public init(contentSize: UIViewHierarchyRect? = nil,
                contentOffset: UIViewHierarchyRect? = nil,
                contentInset: JSON? = nil,
                isScrollEnabled: Bool? = nil) {
        self.contentSize = contentSize
        self.contentOffset = contentOffset
        self.contentInset = contentInset
        self.isScrollEnabled = isScrollEnabled
    }

    /// 转为命令响应中的 JSON 对象。
    public func toJSON() -> JSON {
        var json: JSON = [:]
        json["contentSize"] = contentSize.map { .object($0.toJSON()) } ?? .null
        json["contentOffset"] = contentOffset.map { .object($0.toJSON()) } ?? .null
        json["contentInset"] = contentInset.map(JSONValue.object) ?? .null
        json["isScrollEnabled"] = isScrollEnabled.map(JSONValue.bool) ?? .null
        return json
    }
}

/// UI 层级采集的详情级别。
///
/// `basic` 只保留结构、布局和状态；`appearance` 增加文本、颜色、控件等常见验收字段；
/// `full` 预留给后续更高成本字段。第一版中 `appearance` 与 `full` 字段集合相同。
///
/// - Note: case 声明顺序即 `CaseIterable.allCases` 顺序，被 `CommandFields.enumValue`
///   的 "must be one of ..." 错误文案依赖，勿随意重排。
public enum UIViewHierarchyDetailLevel: String, Sendable, CaseIterable {
    /// 结构、布局和状态。
    case basic
    /// 常见 UI 验收字段。
    case appearance
    /// 预留完整详情。
    case full
}

/// UI 层级采集和筛选参数。
///
/// 命令会从请求 `data` 解析为该类型；测试中也直接用它约束递归和筛选行为。
public struct UIViewHierarchyInput: CommandInput, Sendable, Equatable {
    private enum Fields {
        static let detailLevel = CommandFields.enumValue(
            "detailLevel",
            type: UIViewHierarchyDetailLevel.self,
            default: .appearance,
            description: "详情级别: basic / appearance / full, 默认 appearance"
        )
        static let maxDepth = UIKitFilterFields.maxDepth
        static let includeHidden = UIKitFilterFields.includeHidden
        static let accessibilityIdentifier = UIKitFilterFields.accessibilityIdentifier
        static let accessibilityIdentifierPrefix = UIKitFilterFields.accessibilityIdentifierPrefix
        static let controller = CommandFields.optionalString(
            "controller",
            description: "按 ui.controllers 返回的 controller 定位 path（如 root.tab[0].nav[1]）指定采集起点 controller，缺省为当前顶部控制器"
        )

        static let all: [AnyCommandField] = [
            detailLevel.erased,
            maxDepth.erased,
            includeHidden.erased,
            accessibilityIdentifier.erased,
            accessibilityIdentifierPrefix.erased,
            controller.erased,
        ]
    }

    /// `ui.topViewHierarchy` 暴露给 help 和工具客户端的输入 schema。
    public static let inputSchema = CommandInputSchema(fields: Fields.all)

    /// 详情级别。
    public let detailLevel: UIViewHierarchyDetailLevel
    /// 最大递归深度，`nil` 表示不限制。
    public let maxDepth: Int?
    /// 是否包含隐藏视图。
    public let includeHidden: Bool
    /// accessibilityIdentifier 精确匹配条件。
    public let accessibilityIdentifier: String?
    /// accessibilityIdentifier 前缀匹配条件。
    public let accessibilityIdentifierPrefix: String?
    /// controller 定位 path（来自 `ui.controllers`），缺省为 `nil` 表示从顶部控制器 view 采集。
    ///
    /// 入参非空时由 `UIControllerResolver` 沿 path 实时定位到目标 controller，取其 `view`
    /// 作为采集起点。`"root"` 表示 `window.rootViewController`，与缺省（`topViewController`）语义不同。
    public let controller: String?

    /// 默认查询：返回非隐藏视图的 appearance 级完整树。
    public static let `default` = UIViewHierarchyInput()

    /// 创建查询参数。
    ///
    /// - Parameters:
    ///   - detailLevel: 详情级别。
    ///   - maxDepth: 最大递归深度。
    ///   - includeHidden: 是否包含隐藏视图。
    ///   - accessibilityIdentifier: identifier 精确匹配条件。
    ///   - accessibilityIdentifierPrefix: identifier 前缀匹配条件。
    ///   - controller: controller 定位 path，缺省 `nil` 走顶部控制器。
    public init(detailLevel: UIViewHierarchyDetailLevel = .appearance,
                maxDepth: Int? = nil,
                includeHidden: Bool = false,
                accessibilityIdentifier: String? = nil,
                accessibilityIdentifierPrefix: String? = nil,
                controller: String? = nil) {
        self.detailLevel = detailLevel
        self.maxDepth = maxDepth
        self.includeHidden = includeHidden
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessibilityIdentifierPrefix = accessibilityIdentifierPrefix
        self.controller = controller
    }

    /// 是否包含筛选条件。
    public var hasIdentifierFilter: Bool {
        accessibilityIdentifier != nil || accessibilityIdentifierPrefix != nil
    }

    /// 按 `CommandInputDecoder` 读取字段并构造 typed input。
    ///
    /// - Parameter decoder: 绑定 `inputSchema` 与请求 data 的字段读取器。
    /// - Returns: 已完成默认值填充和范围校验的层级查询参数。
    /// - Throws: 字段类型、枚举值或范围非法时抛出 `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIViewHierarchyInput {
        UIViewHierarchyInput(
            detailLevel: try decoder.read(Fields.detailLevel),
            maxDepth: try decoder.read(Fields.maxDepth),
            includeHidden: try decoder.read(Fields.includeHidden),
            accessibilityIdentifier: try decoder.read(Fields.accessibilityIdentifier),
            accessibilityIdentifierPrefix: try decoder.read(Fields.accessibilityIdentifierPrefix),
            controller: try decoder.read(Fields.controller)
        )
    }
}

/// 可被 `UIViewHierarchyBuilder` 转换为层级节点的抽象 UI 元素。
///
/// 该协议让核心递归、路径生成和筛选逻辑脱离 UIKit；真实 UIKit 采集器和测试 fake 元素
/// 都可以复用同一套 builder。
public protocol UIViewHierarchyElement {
    /// 子元素类型。
    associatedtype Child: UIViewHierarchyElement

    /// 运行时类型名。
    var type: String { get }
    /// accessibility 语义信息。
    var accessibility: UIViewHierarchyAccessibility { get }
    /// frame。
    var frame: UIViewHierarchyRect { get }
    /// bounds。
    var bounds: UIViewHierarchyRect { get }
    /// 基础状态。
    var state: UIViewHierarchyState { get }
    /// 文本验收信息。
    var text: UIViewHierarchyText? { get }
    /// 外观验收信息。
    var appearance: UIViewHierarchyAppearance? { get }
    /// 控件验收信息。
    var control: UIViewHierarchyControl? { get }
    /// 图片验收信息。
    var image: UIViewHierarchyImage? { get }
    /// 滚动验收信息。
    var scroll: UIViewHierarchyScroll? { get }
    /// 子元素，顺序与真实 `subviews` 顺序一致。
    var subviews: [Child] { get }
    /// cell 的 indexPath（仅 `UITableViewCell`/`UICollectionViewCell` 有效）。
    ///
    /// 默认实现返回 `nil`（非 cell 节点）；UIKit 采集器在 `UIKitViewElement` 中真实填充。
    /// 该字段不穿过 Foundation-only builder 的协议抽象——只在 UIKit 采集器侧与 `UIViewHierarchyNode`
    /// 之间传递，用于 `ui.topViewHierarchy` 响应中 cell 节点的定位。
    var indexPath: IndexPathSummary? { get }
}

extension UIViewHierarchyElement {
    /// 默认实现：非 cell 节点无 indexPath。
    public var indexPath: IndexPathSummary? { nil }
}

/// 单个 UI 节点及其递归子节点。
///
/// `path` 是快照内只读定位路径，`accessibilityIdentifier` 是业务层语义锚点，两者共同
/// 支撑 agent 理解页面、筛选视图并为后续操作命令提供引用。
public struct UIViewHierarchyNode: Sendable, Equatable {
    /// 只读定位路径。
    public let path: String
    /// 运行时类型名。
    public let type: String
    /// accessibility 语义信息。
    public let accessibility: UIViewHierarchyAccessibility
    /// frame。
    public let frame: UIViewHierarchyRect
    /// bounds。
    public let bounds: UIViewHierarchyRect
    /// 基础状态。
    public let state: UIViewHierarchyState
    /// 文本验收信息。
    public let text: UIViewHierarchyText?
    /// 外观验收信息。
    public let appearance: UIViewHierarchyAppearance?
    /// 控件验收信息。
    public let control: UIViewHierarchyControl?
    /// 图片验收信息。
    public let image: UIViewHierarchyImage?
    /// 滚动验收信息。
    public let scroll: UIViewHierarchyScroll?
    /// 递归子节点。
    public let subviews: [UIViewHierarchyNode]
    /// cell 的 indexPath（仅 `UITableViewCell`/`UICollectionViewCell` 节点有效）。
    public let indexPath: IndexPathSummary?

    /// 创建 UI 层级节点。
    ///
    /// - Parameters:
    ///   - path: 只读定位路径。
    ///   - type: 运行时类型名。
    ///   - accessibility: accessibility 语义信息。
    ///   - frame: frame。
    ///   - bounds: bounds。
    ///   - state: 基础状态。
    ///   - text: 文本验收信息。
    ///   - appearance: 外观验收信息。
    ///   - control: 控件验收信息。
    ///   - image: 图片验收信息。
    ///   - scroll: 滚动验收信息。
    ///   - subviews: 递归子节点。
    ///   - indexPath: cell 的 indexPath（仅 cell 节点有效）。
    public init(path: String,
                type: String,
                accessibility: UIViewHierarchyAccessibility,
                frame: UIViewHierarchyRect,
                bounds: UIViewHierarchyRect,
                state: UIViewHierarchyState,
                text: UIViewHierarchyText? = nil,
                appearance: UIViewHierarchyAppearance? = nil,
                control: UIViewHierarchyControl? = nil,
                image: UIViewHierarchyImage? = nil,
                scroll: UIViewHierarchyScroll? = nil,
                subviews: [UIViewHierarchyNode] = [],
                indexPath: IndexPathSummary? = nil) {
        self.path = path
        self.type = type
        self.accessibility = accessibility
        self.frame = frame
        self.bounds = bounds
        self.state = state
        self.text = text
        self.appearance = appearance
        self.control = control
        self.image = image
        self.scroll = scroll
        self.subviews = subviews
        self.indexPath = indexPath
    }

    /// 转为命令响应中的 JSON 对象。
    ///
    /// - Parameter includePath: 是否输出 `path` 字段。`ui.topViewHierarchy` 在传入 `controller`
    ///   参数时（非栈顶观察模式）会把 `includePath` 设为 `false`：节点 path 相对于目标
    ///   controller view，与 `ui.tap` / `ui.inspect` 以栈顶 view 为根的语义不匹配，输出会
    ///   引诱 agent 误用，故直接省略；其余结构 / accessibility / 文本 / 颜色 / 控件状态 /
    ///   indexPath 等观察字段全部保留。
    public func toJSON(includePath: Bool = true) -> JSON {
        var json: JSON = [
            "type": .string(type),
            "accessibilityIdentifier": accessibility.identifier.map(JSONValue.string) ?? .null,
            "accessibilityLabel": accessibility.label.map(JSONValue.string) ?? .null,
            "accessibilityValue": accessibility.value.map(JSONValue.string) ?? .null,
            "accessibilityHint": accessibility.hint.map(JSONValue.string) ?? .null,
            "frame": .object(frame.toJSON()),
            "bounds": .object(bounds.toJSON()),
            "state": .object(state.toJSON()),
            "subviews": .array(subviews.map { .object($0.toJSON(includePath: includePath)) }),
        ]
        if includePath {
            json["path"] = .string(path)
        }
        if let text { json["text"] = .object(text.toJSON()) }
        if let appearance { json["appearance"] = .object(appearance.toJSON()) }
        if let control { json["control"] = .object(control.toJSON()) }
        if let image { json["image"] = .object(image.toJSON()) }
        if let scroll { json["scroll"] = .object(scroll.toJSON()) }
        if let indexPath {
            json["indexPath"] = .object([
                "section": .double(Double(indexPath.section)),
                "item": .double(Double(indexPath.item)),
            ])
        }
        return json
    }

    /// 兼容旧调用方的无参入口，等价于 `toJSON(includePath: true)`。
    public func toJSON() -> JSON {
        toJSON(includePath: true)
    }

    /// 统计当前节点及其所有子节点数量。
    public var nodeCount: Int {
        1 + subviews.reduce(0) { $0 + $1.nodeCount }
    }
}

/// UI 层级构建和筛选工具。
///
/// 它负责递归生成只读 path、应用隐藏视图和深度过滤，并支持按
/// `accessibilityIdentifier` 查找节点。真实 UIKit 采集器只负责把 `UIView` 映射成
/// `UIViewHierarchyElement`。
public enum UIViewHierarchyBuilder {
    /// 从抽象元素构建完整节点树。
    ///
    /// - Parameters:
    ///   - element: 根元素。
    ///   - query: 采集参数。
    /// - Returns: 根节点。
    public static func build<Element: UIViewHierarchyElement>(from element: Element,
                                                              query: UIViewHierarchyInput) -> UIViewHierarchyNode {
        build(from: element, query: query, path: "root", depth: 0)
    }

    /// 返回所有符合 identifier 筛选条件的节点。
    ///
    /// - Parameters:
    ///   - element: 根元素。
    ///   - query: 筛选参数。
    /// - Returns: 按遍历顺序排列的匹配节点。
    public static func matches<Element: UIViewHierarchyElement>(in element: Element,
                                                               query: UIViewHierarchyInput) -> [UIViewHierarchyNode] {
        let root = build(from: element, query: query)
        var results: [UIViewHierarchyNode] = []
        collectMatches(from: root, query: query, into: &results)
        return results
    }

    /// 递归构建节点。
    private static func build<Element: UIViewHierarchyElement>(from element: Element,
                                                              query: UIViewHierarchyInput,
                                                              path: String,
                                                              depth: Int) -> UIViewHierarchyNode {
        let childNodes: [UIViewHierarchyNode]
        if let maxDepth = query.maxDepth, depth >= maxDepth {
            childNodes = []
        } else {
            childNodes = element.subviews.enumerated().compactMap { index, child in
                if !query.includeHidden, child.state.isHidden { return nil }
                return build(from: child,
                             query: query,
                             path: "\(path)/\(index)",
                             depth: depth + 1)
            }
        }
        let includeDetails = query.detailLevel != .basic
        return UIViewHierarchyNode(path: path,
                                   type: element.type,
                                   accessibility: element.accessibility,
                                   frame: element.frame,
                                   bounds: element.bounds,
                                   state: element.state,
                                   text: includeDetails ? element.text : nil,
                                   appearance: includeDetails ? element.appearance : nil,
                                   control: includeDetails ? element.control : nil,
                                   image: includeDetails ? element.image : nil,
                                   scroll: includeDetails ? element.scroll : nil,
                                   subviews: childNodes,
                                   indexPath: element.indexPath)
    }

    /// 收集匹配节点。
    private static func collectMatches(from node: UIViewHierarchyNode,
                                       query: UIViewHierarchyInput,
                                       into results: inout [UIViewHierarchyNode]) {
        if matches(node, query: query) {
            results.append(node)
        }
        for child in node.subviews {
            collectMatches(from: child, query: query, into: &results)
        }
    }

    /// 判断节点是否符合 identifier 条件。
    private static func matches(_ node: UIViewHierarchyNode, query: UIViewHierarchyInput) -> Bool {
        guard query.hasIdentifierFilter else { return true }
        let identifier = node.accessibility.identifier
        if let expected = query.accessibilityIdentifier, identifier == expected {
            return true
        }
        if let prefix = query.accessibilityIdentifierPrefix, identifier?.hasPrefix(prefix) == true {
            return true
        }
        return false
    }
}
