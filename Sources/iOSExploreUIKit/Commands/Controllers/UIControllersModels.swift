import Foundation
import iOSExploreServer

/// `ui.controllers` 命令暴露的 controller 在结构中的角色。
///
/// 与 `UIControllerPathSegment` 一一对应（除 `root` 外）：`root` 是遍历起点 `window.rootViewController`，
/// 其余角色由路径段派生。角色冗余于 path 段存在——单节点读 `role` 比正则解析 path 更快，
/// 且 `root` 节点的 path 就是 `"root"`，无法从 path 段机械反推角色。
public enum UIControllerRole: String, Sendable, Equatable, CaseIterable {
    /// 遍历起点，即 `window.rootViewController`。
    case root
    /// `UINavigationController.viewControllers` 的成员。
    case navigation
    /// `UITabBarController.viewControllers` 的成员。
    case tab
    /// `UISplitViewController.viewControllers` 的成员。
    case split
    /// 普通/自定义容器的 `children` 成员。
    case child
    /// `presentedViewController`（modal/alert/sheet 链）。
    case presented
}

/// controller 定位路径的单一段。
///
/// 对应 `root` 之后由 `.` 分隔的每一段。`presented` 是单值（UIKit 保证
/// `presentedViewController` 同时只有一个），容器类带 `[非负整数下标]`。段类型互斥可区分
/// （`presented` 无括号，其余四个有唯一字面前缀），保证 `parseControllerPath` 无歧义。
public enum UIControllerPathSegment: Sendable, Equatable {
    /// `presentedViewController`，链式多层用重复段表达（`presented.presented`）。
    case presented
    /// `UINavigationController.viewControllers[index]`，0 = 栈底。
    case navigation(Int)
    /// `UITabBarController.viewControllers[index]`。
    case tab(Int)
    /// `UISplitViewController.viewControllers[index]`，0 = primary。
    case split(Int)
    /// 普通 controller 的 `children[index]`。
    case child(Int)

    /// 段的字符串形式，拼入 path（如 `nav[1]`、`presented`）。
    public var stringValue: String {
        switch self {
        case .presented: return "presented"
        case .navigation(let index): return "nav[\(index)]"
        case .tab(let index): return "tab[\(index)]"
        case .split(let index): return "split[\(index)]"
        case .child(let index): return "child[\(index)]"
        }
    }

    /// 由段派生的角色（`root` 角色由遍历起点单独赋，不在此处）。
    public var role: UIControllerRole {
        switch self {
        case .presented: return .presented
        case .navigation: return .navigation
        case .tab: return .tab
        case .split: return .split
        case .child: return .child
        }
    }
}

/// 解析 controller 定位路径字符串为段序列。
///
/// 合法形式：`"root"` 或 `"root." + 段1 + "." + 段2 + ...`，段为 `presented` 或
/// `<kind>[<非负整数>]`（`kind` ∈ `nav`/`tab`/`split`/`child`）。
///
/// 该函数与 `controllerPathString(_:)` 互为逆运算，供第二步（让 `ui.topViewHierarchy` /
/// `ui.inspect` 接收 `controller` 定位参数）把入参字符串解析回段序列后逐段映射 UIKit 调用。
/// 实现为 Foundation-only，便于在 macOS 下用单元测试钉牢文法。
///
/// - Parameter raw: 原始路径字符串。
/// - Returns: 段序列（`"root"` 返回空数组）；任何非法形式返回 `nil`。
public func parseControllerPath(_ raw: String) -> [UIControllerPathSegment]? {
    if raw == "root" { return [] }
    guard raw.hasPrefix("root.") else { return nil }
    let body = raw.dropFirst("root.".count)
    // "root." 末尾多余的点是非法的：body 为空说明除了前缀没有任何段。
    if body.isEmpty { return nil }
    var segments: [UIControllerPathSegment] = []
    // omittingEmptySubsequences: false 让连续点（"root..nav[0]"）暴露为空 token，便于拒绝。
    for token in body.split(separator: ".", omittingEmptySubsequences: false) {
        if token.isEmpty { return nil }
        if token == "presented" {
            segments.append(.presented)
            continue
        }
        guard let openBracket = token.firstIndex(of: "["), token.last == "]" else { return nil }
        let kind = String(token[..<openBracket])
        // 括号内子串：openBracket 之后到末尾 ']' 之前。
        let indexStart = token.index(after: openBracket)
        let indexEnd = token.index(before: token.endIndex)
        let indexPart = token[indexStart..<indexEnd]
        guard let index = Int(indexPart), index >= 0 else { return nil }
        switch kind {
        case "nav": segments.append(.navigation(index))
        case "tab": segments.append(.tab(index))
        case "split": segments.append(.split(index))
        case "child": segments.append(.child(index))
        default: return nil
        }
    }
    return segments
}

/// 由段序列生成 controller 定位路径字符串。
///
/// 与 `parseControllerPath(_:)` 互为逆运算：空序列生成 `"root"`，非空序列生成
/// `"root" + ".seg" + ".seg" + ...`。
///
/// - Parameter segments: 段序列。
/// - Returns: 完整路径字符串。
public func controllerPathString(_ segments: [UIControllerPathSegment]) -> String {
    segments.isEmpty ? "root" : "root" + segments.map { "." + $0.stringValue }.joined()
}

/// `ui.controllers` 响应中单个 controller 的骨架节点。
///
/// 不持有 UIKit 对象，是纯值类型，可安全跨 MainActor 边界传递。`children` 递归表达容器
/// 嵌套结构；`path` 是该节点在整棵树中的唯一定位路径。
public struct UIControllerNode: Sendable, Equatable {
    /// 唯一定位路径，如 `root.tab[0].nav[1]`。
    public let path: String
    /// 运行时类型名。
    public let type: String
    /// 在结构中的角色。
    public let role: UIControllerRole
    /// `controller.title`，可能为 nil。
    public let title: String?
    /// `controller.isViewLoaded`，无副作用读取，供判断该 controller 的 view 树是否已建。
    public let isViewLoaded: Bool
    /// 仅 tab 子节点有意义：是否为当前选中 tab。
    public let isSelected: Bool?
    /// 仅 navigation 子节点有意义：是否为导航栈当前可见 VC（栈顶）。
    public let isVisible: Bool?
    /// 递归子节点。
    public let children: [UIControllerNode]

    /// 创建一个 controller 骨架节点。
    ///
    /// - Parameters:
    ///   - path: 唯一定位路径。
    ///   - type: 运行时类型名。
    ///   - role: 在结构中的角色。
    ///   - title: controller 标题，可空。
    ///   - isViewLoaded: view 是否已加载。
    ///   - isSelected: 仅 tab 子节点传入。
    ///   - isVisible: 仅 navigation 子节点传入。
    ///   - children: 递归子节点。
    public init(path: String,
                type: String,
                role: UIControllerRole,
                title: String?,
                isViewLoaded: Bool,
                isSelected: Bool? = nil,
                isVisible: Bool? = nil,
                children: [UIControllerNode] = []) {
        self.path = path
        self.type = type
        self.role = role
        self.title = title
        self.isViewLoaded = isViewLoaded
        self.isSelected = isSelected
        self.isVisible = isVisible
        self.children = children
    }

    /// 转为命令响应中的 JSON 对象。
    ///
    /// `title` 始终存在（nil 写为 null）；`isSelected`/`isVisible` 仅在有值时输出，不适用时省略，
    /// 镜像 `UIViewHierarchyNode` 的可选字段省略约定。
    /// - Returns: 可嵌入响应 `children` 数组的 JSON 对象。
    public func toJSON() -> JSON {
        var json: JSON = [
            "path": .string(path),
            "type": .string(type),
            "role": .string(role.rawValue),
            "title": title.map(JSONValue.string) ?? .null,
            "isViewLoaded": .bool(isViewLoaded),
            "children": .array(children.map { .object($0.toJSON()) }),
        ]
        if let isSelected { json["isSelected"] = .bool(isSelected) }
        if let isVisible { json["isVisible"] = .bool(isVisible) }
        return json
    }

    /// 当前节点及其所有后代节点总数。
    public var nodeCount: Int {
        1 + children.reduce(0) { $0 + $1.nodeCount }
    }
}

/// `ui.controllers` 的命令参数。
///
/// 命令默认返回从 `window.rootViewController` 出发的完整 controller 结构树；可选 `maxDepth`
/// 限制递归深度，防止容器嵌套过深时输出过大。presented 链（alert/sheet）始终展开，是高频
/// 关键信息，不设开关。
public struct UIControllersInput: CommandInput, Sendable, Equatable {
    private enum Fields {
        static let maxDepth = UIKitFilterFields.maxDepth

        static let all: [AnyCommandField] = [
            maxDepth.erased,
        ]
    }

    /// `ui.controllers` 暴露给 help 和工具客户端的输入 schema。
    public static let inputSchema = CommandInputSchema(fields: Fields.all)

    /// 最大递归深度，`nil` 表示不限制（遍历器另有硬上限兜底防坏状态）。
    public let maxDepth: Int?

    /// 默认查询：不限制深度，返回完整结构树。
    public static let `default` = UIControllersInput()

    /// 创建查询参数。
    ///
    /// - Parameter maxDepth: 最大递归深度，`nil` 不限制。
    public init(maxDepth: Int? = nil) {
        self.maxDepth = maxDepth
    }

    /// 按 `CommandInputDecoder` 读取声明字段并构造 typed input。
    ///
    /// - Parameter decoder: 绑定 `inputSchema` 与请求 data 的字段读取器。
    /// - Returns: 已完成默认值填充和范围校验的 controller 查询参数。
    /// - Throws: `maxDepth` 非非负整数时抛出 `CommandInputParseError`（→ `invalid_data`）。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIControllersInput {
        UIControllersInput(maxDepth: try decoder.read(Fields.maxDepth))
    }
}
