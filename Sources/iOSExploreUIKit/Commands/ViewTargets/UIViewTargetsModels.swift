import Foundation
import iOSExploreServer

/// 轻量 UI 目标查询参数。
///
/// 该类型保持 Foundation-only，负责解析 `ui.viewTargets` 的 data，并约束响应规模。
public struct UIViewTargetsInput: CommandInput, Sendable, Equatable {
    private enum Fields {
        static let includeHidden = UIKitFilterFields.includeHidden
        static let maxDepth = UIKitFilterFields.maxDepth
        static let accessibilityIdentifier = UIKitFilterFields.accessibilityIdentifier
        static let accessibilityIdentifierPrefix = UIKitFilterFields.accessibilityIdentifierPrefix
        static let textLimit = CommandFields.int(
            "textLimit",
            range: 1...200,
            default: 80,
            description: "title/text/placeholder/value 最大字符数, 默认 80, 上限 200"
        )
        static let maxTargets = CommandFields.int(
            "maxTargets",
            range: 1...UIKitSnapshotLimits.maxFingerprints,
            default: 200,
            description: "单次响应最多返回的目标数, 默认 200, 上限 512"
        )

        static let all: [AnyCommandField] = [
            includeHidden.erased,
            maxDepth.erased,
            accessibilityIdentifier.erased,
            accessibilityIdentifierPrefix.erased,
            textLimit.erased,
            maxTargets.erased,
        ]
    }

    /// `ui.viewTargets` 暴露给 help 和工具客户端的输入 schema。
    public static let inputSchema = CommandInputSchema(fields: Fields.all)

    /// 是否包含隐藏 view。
    public let includeHidden: Bool
    /// 最大递归深度，`nil` 表示不限制。
    public let maxDepth: Int?
    /// accessibilityIdentifier 精确匹配条件。
    public let accessibilityIdentifier: String?
    /// accessibilityIdentifier 前缀匹配条件。
    public let accessibilityIdentifierPrefix: String?
    /// title/text/placeholder/value 的最大返回字符数。
    public let textLimit: Int
    /// 单次响应最多返回的目标数。
    public let maxTargets: Int

    /// 默认查询：面向事件下发前的低成本目标发现。
    public static let `default` = UIViewTargetsInput()

    /// 创建查询参数。
    ///
    /// - Parameters:
    ///   - includeHidden: 是否包含隐藏 view。
    ///   - maxDepth: 最大递归深度。
    ///   - accessibilityIdentifier: accessibilityIdentifier 精确匹配条件。
    ///   - accessibilityIdentifierPrefix: accessibilityIdentifier 前缀匹配条件。
    ///   - textLimit: 文本字段最大字符数。
    public init(includeHidden: Bool = false,
                maxDepth: Int? = nil,
                accessibilityIdentifier: String? = nil,
                accessibilityIdentifierPrefix: String? = nil,
                textLimit: Int = 80,
                maxTargets: Int = 200) {
        self.includeHidden = includeHidden
        self.maxDepth = maxDepth
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessibilityIdentifierPrefix = accessibilityIdentifierPrefix
        self.textLimit = textLimit
        self.maxTargets = maxTargets
    }

    /// 是否包含 identifier 筛选条件。
    public var hasIdentifierFilter: Bool {
        accessibilityIdentifier != nil || accessibilityIdentifierPrefix != nil
    }

    /// 判定节点是 full（带识别信息或可操作）还是 minimal（仅结构）。
    ///
    /// `ui.viewTargets` / `ui.inspect` 的目标筛选口径：full 节点签发 fingerprint、可被
    /// `ui.tap`/`ui.control.sendAction` 操作，并进入轻量 targets；minimal 节点只输出 path+type
    /// 维持层级，强制 `actions=[]`、不签发。六条规则任一命中即 full：
    /// - `isControl` / `isScrollView` / `hasGestureRecognizers`：可操作（control/scroll 走
    ///   executor 默认路由，gesture 走 adapter 派发 target-action）；
    /// - `hasStaticText` / `hasAccessibilityLabel` / `hasAccessibilityIdentifier`：带识别信息，
    ///   让 agent 能在 target 上读到稳定语义而非去猜某个子 view 的归属。
    ///
    /// **rollup 例外（控件内嵌展示节点）**：`hasStaticText` 的节点若同时
    /// `isInControlSubtree`（自身非 `UIControl`、祖先链含 `UIControl`，典型如按钮内部
    /// 渲染 title 的 `UIButtonLabel`），不作为独立 full target——它的文本已通过父 control 的
    /// `semanticText`（buttonTitle 等）汇总给父 target，独立签发只会让 agent tap 到一个
    /// 返回 `unsupported_target` 的死节点，破坏"签发=可操作"不变式。
    ///
    /// cell 子树不受 rollup 影响：`UITableViewCell`/`UICollectionViewCell` 不是 `UIControl`，
    /// cell 内 label 的 `isInControlSubtree=false`，仍按 `hasStaticText` 进 full（spec §3.4
    /// 核心：cell 内 UILabel 可被 agent 直接 tap 选中行）。独立 label（不在 control/cell 子树，
    /// 如页面标题）祖先无 `UIControl`，同样仍 full。
    ///
    /// `includeHidden=false` 时 hidden 节点整棵剪枝（即便命中 canonical 条件也不输出），与
    /// collector 的递归剪枝一致。
    ///
    /// 该方法只依赖 Foundation-only 的候选摘要，便于在非 UIKit 测试中覆盖采集器的包含策略。
    ///
    /// - Parameter candidate: 从真实 view 或测试用例抽取出的候选摘要。
    /// - Returns: 当前查询参数下该候选是否为 full 节点。
    public func isFull(candidate: UIViewTargetCandidate) -> Bool {
        if !includeHidden, candidate.isHidden { return false }
        // rollup：控件内嵌展示节点（hasStaticText 且在 UIControl 子树内）rollup 到父 control，
        // 不独立 full。父 control 的 semanticText 已含其文本，独立签发会破坏"签发=可操作"。
        // cell 内 label 因 cell 非 UIControl 不命中此处，仍 full（详见上方文档）。
        if candidate.hasStaticText, candidate.isInControlSubtree {
            return false
        }
        return candidate.isControl || candidate.isScrollView || candidate.hasGestureRecognizers
            || candidate.hasStaticText || candidate.hasAccessibilityLabel || candidate.hasAccessibilityIdentifier
    }

    /// 按 `CommandInputDecoder` 读取声明字段并构造 typed input。
    ///
    /// - Parameter decoder: 绑定 `inputSchema` 与请求 data 的字段读取器。
    /// - Returns: 已完成默认值填充和范围校验的查询参数。
    /// - Throws: 字段类型或范围非法时抛出 `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIViewTargetsInput {
        UIViewTargetsInput(
            includeHidden: try decoder.read(Fields.includeHidden),
            maxDepth: try decoder.read(Fields.maxDepth),
            accessibilityIdentifier: try decoder.read(Fields.accessibilityIdentifier),
            accessibilityIdentifierPrefix: try decoder.read(Fields.accessibilityIdentifierPrefix),
            textLimit: try decoder.read(Fields.textLimit),
            maxTargets: try decoder.read(Fields.maxTargets)
        )
    }
}

/// `ui.viewTargets` 输出策略使用的 Foundation-only 候选摘要。
///
/// UIKit 采集器负责把真实 `UIView` 转成该摘要，模型层只根据这些布尔状态执行纯决策，
/// 避免把 UIKit 类型带入可在 macOS `swift test` 覆盖的策略测试。
public struct UIViewTargetCandidate: Sendable, Equatable {
    /// 是否隐藏。
    public let isHidden: Bool
    /// 是否为 UIControl 或等价控件候选。
    public let isControl: Bool
    /// 是否允许用户交互。
    public let isUserInteractionEnabled: Bool
    /// 是否挂有 gesture recognizer。
    public let hasGestureRecognizers: Bool
    /// 是否存在非空 accessibilityIdentifier。
    public let hasAccessibilityIdentifier: Bool
    /// 是否存在非空 accessibilityLabel。
    public let hasAccessibilityLabel: Bool
    /// 是否存在非空静态文本。
    public let hasStaticText: Bool
    /// 是否为 `UIScrollView` 系（含 `UITableView`/`UICollectionView`/`UITextView`）。
    public let isScrollView: Bool
    /// 是否位于 `UIControl` 子树内（自身非 `UIControl` 且祖先链含 `UIControl`）。
    ///
    /// 用于 rollup 判定：控件内嵌展示节点（如按钮内部 title label）的文本已通过父 control 的
    /// `semanticText`（buttonTitle 等）汇总，无需作为独立 full target 签发；独立签发其 tap 会
    /// 返回 `unsupported_target`，破坏"签发=可操作"不变式。cell 子树不受影响——
    /// `UITableViewCell`/`UICollectionViewCell` 不是 `UIControl`，cell 内 label 仍 full。
    public let isInControlSubtree: Bool

    /// 创建轻量目标候选摘要。
    ///
    /// - Parameters:
    ///   - isHidden: 是否隐藏。
    ///   - isControl: 是否为 UIControl 或等价控件候选。
    ///   - isUserInteractionEnabled: 是否允许用户交互。
    ///   - hasGestureRecognizers: 是否挂有 gesture recognizer。
    ///   - hasAccessibilityIdentifier: 是否存在非空 accessibilityIdentifier。
    ///   - hasAccessibilityLabel: 是否存在非空 accessibilityLabel。
    ///   - hasStaticText: 是否存在非空静态文本。
    ///   - isScrollView: 是否为 UIScrollView 系。
    ///   - isInControlSubtree: 是否位于 UIControl 子树内（rollup 用，默认 false）。
    public init(isHidden: Bool,
                isControl: Bool,
                isUserInteractionEnabled: Bool,
                hasGestureRecognizers: Bool,
                hasAccessibilityIdentifier: Bool,
                hasAccessibilityLabel: Bool,
                hasStaticText: Bool,
                isScrollView: Bool = false,
                isInControlSubtree: Bool = false) {
        self.isHidden = isHidden
        self.isControl = isControl
        self.isUserInteractionEnabled = isUserInteractionEnabled
        self.hasGestureRecognizers = hasGestureRecognizers
        self.hasAccessibilityIdentifier = hasAccessibilityIdentifier
        self.hasAccessibilityLabel = hasAccessibilityLabel
        self.hasStaticText = hasStaticText
        self.isScrollView = isScrollView
        self.isInControlSubtree = isInControlSubtree
    }
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
    ///
    /// 完整保留，不按 `textLimit` 裁剪——identifier 是事件下发的稳定定位键，截断会导致
    /// 后续 `ui.tap`/`ui.control.sendAction` 无法精确定位。`textLimit` 只约束展示型文本字段。
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
    /// 汇总到 canonical target 的稳定语义文本（按钮标题 / a11y label / value 等）。
    ///
    /// 内部 label/image 不再作为独立 target；其文本汇总到可操作的父 target，让 Agent 在父
    /// target 上直接读到语义，而非去猜某个 `UILabel` 属于哪个按钮。不记录明文到日志。
    public let semanticText: String?
    /// `semanticText` 的来源（`accessibilityLabel` / `buttonTitle` / `accessibilityValue` 等）。
    public let semanticTextSource: String?
    /// window 坐标系 frame。
    public let frame: UIViewHierarchyRect
    /// 目标状态。
    public let state: UIViewTargetState
    /// executor 实际可派发的动作（来自 `UIKitActionCapabilityResolver`）。
    ///
    /// 与 `role` 无关，按真实 view 类型和 enabled 状态生成。非 canonical 目标或 disabled 控件
    /// 时为空，避免把静态节点标成可 tap；不会借祖先 `UIControl` 生成能力。
    public let availableActions: UIKitActionAvailability
    /// cell 的 indexPath（仅 `UITableViewCell`/`UICollectionViewCell` 相关的 target 有效）。
    ///
    /// 调用方可据此直接按 section/item 选 cell，不再依赖 subviews 物理顺序或 frame.y 猜行。
    public let indexPath: IndexPathSummary?
    /// 是否为 minimal 档（仅输出 `{path, type}` 的结构节点）。
    ///
    /// minimal 用于 collector 把无识别信息的结构节点（如 `UITableViewCell` 内层容器
    /// `UIView`）暴露给 agent 做父子结构遍历与路径定位，但不签 fingerprint、不输出
    /// `availableActions`/`frame`/`state` 等字段，避免引诱 agent 对不可操作的节点发起
    /// `ui.tap`/`ui.control.sendAction`。full 档（默认）输出全部字段，行为与改造前一致。
    ///
    /// 模型字段保持非 Optional：minimal 档的精简由 `toJSON` 分档短路完成（缺失即缺席），
    /// 不把 `frame`/`state`/`role` 改成 `Optional`，避免波及所有现有构造点与等值判定。
    public let isMinimal: Bool

    /// 创建目标摘要。
    ///
    /// - Parameters:
    ///   - path: 当前快照内路径。
    ///   - type: 运行时类型名。
    ///   - role: 目标角色。
    ///   - accessibilityIdentifier: 业务层设置的稳定标识符（完整保留，不裁剪）。
    ///   - accessibilityLabel: 辅助功能标签。
    ///   - title: 控件标题。
    ///   - text: 可见文本。
    ///   - placeholder: 输入占位文本。
    ///   - value: 当前值。
    ///   - semanticText: 汇总到 canonical target 的稳定语义文本。
    ///   - semanticTextSource: `semanticText` 的来源标签。
    ///   - frame: window 坐标系 frame。
    ///   - state: 目标状态。
    ///   - availableActions: executor 实际可派发的动作集合。
    ///   - indexPath: cell 的 indexPath。
    ///   - isMinimal: 是否为 minimal 档，默认 `false`（full）。现有 collector 构造点不传此参数，
    ///     保持 full 输出与改造前逐字节一致；仅 collector 对结构节点显式置 `true`。
    public init(path: String,
                type: String,
                role: UIViewTargetRole,
                accessibilityIdentifier: String?,
                accessibilityLabel: String?,
                title: String?,
                text: String?,
                placeholder: String?,
                value: String?,
                semanticText: String? = nil,
                semanticTextSource: String? = nil,
                frame: UIViewHierarchyRect,
                state: UIViewTargetState,
                availableActions: UIKitActionAvailability = UIKitActionAvailability(actions: []),
                indexPath: IndexPathSummary? = nil,
                isMinimal: Bool = false) {
        self.path = path
        self.type = type
        self.role = role
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessibilityLabel = accessibilityLabel
        self.title = title
        self.text = text
        self.placeholder = placeholder
        self.value = value
        self.semanticText = semanticText
        self.semanticTextSource = semanticTextSource
        self.frame = frame
        self.state = state
        self.availableActions = availableActions
        self.indexPath = indexPath
        self.isMinimal = isMinimal
    }

    /// 转为命令响应 JSON。
    ///
    /// 按 `isMinimal` 分档输出：
    /// - minimal 档只输出 `{path, type}`，让 agent 能看到结构但不对其发起操作；
    /// - full 档输出全部字段（定位、语义、状态、可执行动作等），行为与改造前一致。
    ///
    /// - Returns: minimal 档为仅含 `path`/`type` 的 JSON 对象；full 档为完整字段 JSON 对象。
    public func toJSON() -> JSON {
        if isMinimal {
            return [
                "path": .string(path),
                "type": .string(type),
            ]
        }
        var json: JSON = [
            "path": .string(path),
            "type": .string(type),
            "role": .string(role.rawValue),
            "accessibilityIdentifier": accessibilityIdentifier.map(JSONValue.string) ?? .null,
            "accessibilityLabel": accessibilityLabel.map(JSONValue.string) ?? .null,
            "title": title.map(JSONValue.string) ?? .null,
            "text": text.map(JSONValue.string) ?? .null,
            "placeholder": placeholder.map(JSONValue.string) ?? .null,
            "value": value.map(JSONValue.string) ?? .null,
            "semanticText": semanticText.map(JSONValue.string) ?? .null,
            "semanticTextSource": semanticTextSource.map(JSONValue.string) ?? .null,
            "frame": .object(frame.toJSON()),
            "isHidden": .bool(state.isHidden),
            "alpha": .double(state.alpha),
            "isUserInteractionEnabled": .bool(state.isUserInteractionEnabled),
            "isEnabled": state.isEnabled.map(JSONValue.bool) ?? .null,
            "isSelected": state.isSelected.map(JSONValue.bool) ?? .null,
            "isHighlighted": state.isHighlighted.map(JSONValue.bool) ?? .null,
            "hasGestureRecognizers": .bool(state.hasGestureRecognizers),
            "availableActions": .array(availableActions.rawValues.map(JSONValue.string)),
        ]
        if let indexPath {
            json["indexPath"] = .object([
                "section": .double(Double(indexPath.section)),
                "item": .double(Double(indexPath.item)),
            ])
        }
        return json
    }
}
