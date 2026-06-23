import Foundation

/// 轻量 UI 目标查询参数。
///
/// 该类型保持 Foundation-only，负责解析 `ui.viewTargets` 的 data，并约束响应规模。
public struct UIViewTargetsQuery: Sendable, Equatable {
    /// 是否包含隐藏 view。
    public let includeHidden: Bool
    /// 是否包含 disabled control。
    public let includeDisabled: Bool
    /// 是否包含仅展示静态文本的节点。
    public let includeStaticText: Bool
    /// 是否包含普通容器 view。
    public let includeContainers: Bool
    /// 最大递归深度，`nil` 表示不限制。
    public let maxDepth: Int?
    /// accessibilityIdentifier 精确匹配条件。
    public let accessibilityIdentifier: String?
    /// accessibilityIdentifier 前缀匹配条件。
    public let accessibilityIdentifierPrefix: String?
    /// title/text/placeholder/value 的最大返回字符数。
    public let textLimit: Int

    /// 默认查询：面向事件下发前的低成本目标发现。
    public static let `default` = UIViewTargetsQuery()

    /// 创建查询参数。
    ///
    /// - Parameters:
    ///   - includeHidden: 是否包含隐藏 view。
    ///   - includeDisabled: 是否包含 disabled control。
    ///   - includeStaticText: 是否包含仅展示静态文本的节点。
    ///   - includeContainers: 是否包含普通容器 view。
    ///   - maxDepth: 最大递归深度。
    ///   - accessibilityIdentifier: accessibilityIdentifier 精确匹配条件。
    ///   - accessibilityIdentifierPrefix: accessibilityIdentifier 前缀匹配条件。
    ///   - textLimit: 文本字段最大字符数。
    public init(includeHidden: Bool = false,
                includeDisabled: Bool = true,
                includeStaticText: Bool = false,
                includeContainers: Bool = false,
                maxDepth: Int? = nil,
                accessibilityIdentifier: String? = nil,
                accessibilityIdentifierPrefix: String? = nil,
                textLimit: Int = 80) {
        self.includeHidden = includeHidden
        self.includeDisabled = includeDisabled
        self.includeStaticText = includeStaticText
        self.includeContainers = includeContainers
        self.maxDepth = maxDepth
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessibilityIdentifierPrefix = accessibilityIdentifierPrefix
        self.textLimit = textLimit
    }

    /// 是否包含 identifier 筛选条件。
    public var hasIdentifierFilter: Bool {
        accessibilityIdentifier != nil || accessibilityIdentifierPrefix != nil
    }

    /// 从命令 data 解析查询参数。
    ///
    /// - Parameter data: `ExploreRequest.data`。
    /// - Returns: 成功时返回查询对象；失败时返回可放入 `invalid_data` 的说明。
    public static func parse(from data: JSON) -> UIViewTargetsQueryParseResult {
        let maxDepth: Int?
        if let rawDepth = data["maxDepth"]?.doubleValue {
            let intDepth = Int(rawDepth)
            guard rawDepth >= 0, Double(intDepth) == rawDepth else {
                return .failure("maxDepth must be a non-negative integer")
            }
            maxDepth = intDepth
        } else {
            maxDepth = nil
        }

        let textLimit: Int
        if let rawLimit = data["textLimit"]?.doubleValue {
            let intLimit = Int(rawLimit)
            guard rawLimit >= 1, rawLimit <= 200, Double(intLimit) == rawLimit else {
                return .failure("textLimit must be an integer between 1 and 200")
            }
            textLimit = intLimit
        } else {
            textLimit = 80
        }

        return .success(UIViewTargetsQuery(
            includeHidden: data["includeHidden"]?.boolValue ?? false,
            includeDisabled: data["includeDisabled"]?.boolValue ?? true,
            includeStaticText: data["includeStaticText"]?.boolValue ?? false,
            includeContainers: data["includeContainers"]?.boolValue ?? false,
            maxDepth: maxDepth,
            accessibilityIdentifier: data["accessibilityIdentifier"]?.stringValue,
            accessibilityIdentifierPrefix: data["accessibilityIdentifierPrefix"]?.stringValue,
            textLimit: textLimit
        ))
    }
}

/// `ui.viewTargets` 查询参数解析结果。
public enum UIViewTargetsQueryParseResult: Sendable, Equatable {
    /// 解析成功。
    case success(UIViewTargetsQuery)
    /// 参数非法。
    case failure(String)
}

/// 轻量 UI 目标角色。
public enum UIViewTargetRole: String, Sendable, Equatable {
    /// 按钮。
    case button
    /// 开关。
    case `switch`
    /// 滑杆。
    case slider
    /// 分段控件。
    case segmentedControl
    /// 文本输入框。
    case textField
    /// 多行文本输入。
    case textView
    /// 标签。
    case label
    /// 图片视图。
    case imageView
    /// 容器。
    case container
    /// 普通 view。
    case view

    /// 面向 agent 的建议动作。
    public var suggestedActions: [String] {
        switch self {
        case .button:
            return ["tap", "control.touchUpInside"]
        case .switch:
            return ["tap", "control.valueChanged"]
        case .slider, .segmentedControl:
            return ["control.valueChanged"]
        case .textField:
            return ["tap", "control.editingDidBegin", "control.editingChanged"]
        case .textView, .label, .imageView, .container, .view:
            return ["tap"]
        }
    }
}

/// 轻量目标的可见性和交互状态。
public struct UIViewTargetState: Sendable, Equatable {
    /// 是否隐藏。
    public let isHidden: Bool
    /// 透明度。
    public let alpha: Double
    /// 是否允许用户交互。
    public let isUserInteractionEnabled: Bool
    /// UIControl 是否可用。
    public let isEnabled: Bool?
    /// UIControl 是否选中。
    public let isSelected: Bool?
    /// UIControl 是否高亮。
    public let isHighlighted: Bool?
    /// 是否挂有 gesture recognizer。
    public let hasGestureRecognizers: Bool

    /// 创建目标状态。
    ///
    /// - Parameters:
    ///   - isHidden: 是否隐藏。
    ///   - alpha: 透明度。
    ///   - isUserInteractionEnabled: 是否允许用户交互。
    ///   - isEnabled: UIControl 是否可用。
    ///   - isSelected: UIControl 是否选中。
    ///   - isHighlighted: UIControl 是否高亮。
    ///   - hasGestureRecognizers: 是否挂有 gesture recognizer。
    public init(isHidden: Bool,
                alpha: Double,
                isUserInteractionEnabled: Bool,
                isEnabled: Bool? = nil,
                isSelected: Bool? = nil,
                isHighlighted: Bool? = nil,
                hasGestureRecognizers: Bool) {
        self.isHidden = isHidden
        self.alpha = alpha
        self.isUserInteractionEnabled = isUserInteractionEnabled
        self.isEnabled = isEnabled
        self.isSelected = isSelected
        self.isHighlighted = isHighlighted
        self.hasGestureRecognizers = hasGestureRecognizers
    }
}

/// 文本裁剪工具，避免目标查询返回大块文本。
public enum UIViewTargetText {
    /// 按字符数限制文本长度。
    ///
    /// - Parameters:
    ///   - value: 原始文本。
    ///   - limit: 最大字符数。
    /// - Returns: 原始文本为空时返回 nil；超长时返回前 limit 个字符。
    public static func limited(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        if value.count <= limit { return value }
        return String(value.prefix(limit))
    }
}

/// 单个轻量 UI 目标摘要。
public struct UIViewTargetSummary: Sendable, Equatable {
    /// 当前快照内路径。
    public let path: String
    /// 运行时类型名。
    public let type: String
    /// 目标角色。
    public let role: UIViewTargetRole
    /// 业务层设置的稳定标识符。
    public let accessibilityIdentifier: String?
    /// 辅助功能标签。
    public let accessibilityLabel: String?
    /// 控件标题。
    public let title: String?
    /// 可见文本。
    public let text: String?
    /// 输入占位文本。
    public let placeholder: String?
    /// 当前值。
    public let value: String?
    /// window 坐标系 frame。
    public let frame: UIViewHierarchyRect
    /// 目标状态。
    public let state: UIViewTargetState

    /// 创建目标摘要。
    ///
    /// - Parameters:
    ///   - path: 当前快照内路径。
    ///   - type: 运行时类型名。
    ///   - role: 目标角色。
    ///   - accessibilityIdentifier: 业务层设置的稳定标识符。
    ///   - accessibilityLabel: 辅助功能标签。
    ///   - title: 控件标题。
    ///   - text: 可见文本。
    ///   - placeholder: 输入占位文本。
    ///   - value: 当前值。
    ///   - frame: window 坐标系 frame。
    ///   - state: 目标状态。
    public init(path: String,
                type: String,
                role: UIViewTargetRole,
                accessibilityIdentifier: String?,
                accessibilityLabel: String?,
                title: String?,
                text: String?,
                placeholder: String?,
                value: String?,
                frame: UIViewHierarchyRect,
                state: UIViewTargetState) {
        self.path = path
        self.type = type
        self.role = role
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessibilityLabel = accessibilityLabel
        self.title = title
        self.text = text
        self.placeholder = placeholder
        self.value = value
        self.frame = frame
        self.state = state
    }

    /// 转为命令响应 JSON。
    ///
    /// - Returns: 只包含轻量定位、语义、状态和建议动作字段的 JSON 对象。
    public func toJSON() -> JSON {
        [
            "path": .string(path),
            "type": .string(type),
            "role": .string(role.rawValue),
            "accessibilityIdentifier": accessibilityIdentifier.map(JSONValue.string) ?? .null,
            "accessibilityLabel": accessibilityLabel.map(JSONValue.string) ?? .null,
            "title": title.map(JSONValue.string) ?? .null,
            "text": text.map(JSONValue.string) ?? .null,
            "placeholder": placeholder.map(JSONValue.string) ?? .null,
            "value": value.map(JSONValue.string) ?? .null,
            "frame": .object(frame.toJSON()),
            "isHidden": .bool(state.isHidden),
            "alpha": .double(state.alpha),
            "isUserInteractionEnabled": .bool(state.isUserInteractionEnabled),
            "isEnabled": state.isEnabled.map(JSONValue.bool) ?? .null,
            "isSelected": state.isSelected.map(JSONValue.bool) ?? .null,
            "isHighlighted": state.isHighlighted.map(JSONValue.bool) ?? .null,
            "hasGestureRecognizers": .bool(state.hasGestureRecognizers),
            "suggestedActions": .array(role.suggestedActions.map(JSONValue.string)),
        ]
    }
}
