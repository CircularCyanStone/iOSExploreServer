# UIKit View Targets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `ui.viewTargets`, a lightweight UIKit command that returns a flat list of actionable UI targets for `ui.tap`, `ui.control.sendAction`, and future event commands.

**Architecture:** Keep the existing network/router/protocol layers unchanged. Add Foundation-only models and tests for query parsing, text truncation, role/action mapping, and JSON conversion; add UIKit-only collector and command under `Handlers/UIKit/ViewTargets/`; register the command through the existing `UIKitHandlers` entrypoint.

**Tech Stack:** Swift 6.2 SPM, Swift Testing, UIKit under `#if canImport(UIKit)`, existing `Command` / `JSON` / `ExploreResult` / `ExploreLogger` types.

---

## File Structure

- Create `Tests/iOSExploreServerTests/UIKitViewTargetsTests.swift`: Foundation-only tests for query parsing, target summary JSON, role/action mapping, text truncation, and include policies.
- Create `Sources/iOSExploreServer/Handlers/UIKit/ViewTargets/UIViewTargetsModels.swift`: Foundation-only query, role, state, summary, filtering helpers, and JSON conversion.
- Create `Sources/iOSExploreServer/Handlers/UIKit/ViewTargets/UIViewTargetsCollector.swift`: UIKit-only MainActor traversal from top view controller root view to flat target summaries.
- Create `Sources/iOSExploreServer/Handlers/UIKit/ViewTargets/ViewTargetsCommand.swift`: `Command` wrapper for parsing, logging, collector invocation, and result handling.
- Modify `Sources/iOSExploreServer/Handlers/UIKit/UIKitHandlers.swift`: register `ViewTargetsCommand`.
- Modify `Sources/iOSExploreServer/Handlers/UIKit/Tap/UITapCommand.swift`: update parameter descriptions to mention `ui.viewTargets`.
- Modify `Sources/iOSExploreServer/Handlers/UIKit/ControlAction/UIControlSendActionCommand.swift`: update parameter descriptions to mention `ui.viewTargets`.
- Modify `docs/architecture/index.md`: document `ui.viewTargets` as the default target-discovery command before event dispatch.
- Modify `docs/tools/network-tools.md`: add a curl example for `ui.viewTargets`.

---

### Task 1: Foundation Models And Tests

**Files:**
- Create: `Tests/iOSExploreServerTests/UIKitViewTargetsTests.swift`
- Create: `Sources/iOSExploreServer/Handlers/UIKit/ViewTargets/UIViewTargetsModels.swift`

- [ ] **Step 1: Write failing tests for model behavior**

Create `Tests/iOSExploreServerTests/UIKitViewTargetsTests.swift`:

```swift
import Testing
@testable import iOSExploreServer

@Test("UIViewTargetsQuery 解析默认值和筛选参数")
func viewTargetsQueryParsesDefaultsAndFilters() {
    let result = UIViewTargetsQuery.parse(from: [
        "includeHidden": true,
        "includeDisabled": false,
        "includeStaticText": true,
        "includeContainers": true,
        "maxDepth": 3,
        "accessibilityIdentifierPrefix": "home.",
        "textLimit": 120,
    ])

    switch result {
    case .success(let query):
        #expect(query.includeHidden == true)
        #expect(query.includeDisabled == false)
        #expect(query.includeStaticText == true)
        #expect(query.includeContainers == true)
        #expect(query.maxDepth == 3)
        #expect(query.accessibilityIdentifierPrefix == "home.")
        #expect(query.textLimit == 120)
    case .failure(let message):
        Issue.record("unexpected parse failure: \(message)")
    }
}

@Test("UIViewTargetsQuery 拒绝非法 maxDepth 和 textLimit")
func viewTargetsQueryRejectsInvalidNumbers() {
    if case .success = UIViewTargetsQuery.parse(from: ["maxDepth": -1]) {
        Issue.record("negative maxDepth should fail")
    }
    if case .success = UIViewTargetsQuery.parse(from: ["maxDepth": 1.5]) {
        Issue.record("fractional maxDepth should fail")
    }
    if case .success = UIViewTargetsQuery.parse(from: ["textLimit": 201]) {
        Issue.record("textLimit above upper bound should fail")
    }
    if case .success = UIViewTargetsQuery.parse(from: ["textLimit": 0]) {
        Issue.record("textLimit below lower bound should fail")
    }
}

@Test("UIViewTargetRole 生成建议动作")
func viewTargetRoleSuggestedActions() {
    #expect(UIViewTargetRole.button.suggestedActions == ["tap", "control.touchUpInside"])
    #expect(UIViewTargetRole.switch.suggestedActions == ["tap", "control.valueChanged"])
    #expect(UIViewTargetRole.slider.suggestedActions == ["control.valueChanged"])
    #expect(UIViewTargetRole.textField.suggestedActions == ["tap", "control.editingDidBegin", "control.editingChanged"])
    #expect(UIViewTargetRole.view.suggestedActions == ["tap"])
}

@Test("UIViewTargetSummary 转 JSON 保留轻量字段")
func viewTargetSummaryJSONIncludesLightweightFields() {
    let summary = UIViewTargetSummary(
        path: "root/0/2",
        type: "UIButton",
        role: .button,
        accessibilityIdentifier: "home.submit",
        accessibilityLabel: "提交",
        title: "提交",
        text: nil,
        placeholder: nil,
        value: nil,
        frame: UIViewHierarchyRect(x: 24, y: 680, width: 327, height: 48),
        state: UIViewTargetState(isHidden: false,
                                 alpha: 1,
                                 isUserInteractionEnabled: true,
                                 isEnabled: true,
                                 isSelected: false,
                                 isHighlighted: false,
                                 hasGestureRecognizers: false)
    )

    let json = summary.toJSON()
    #expect(json["path"]?.stringValue == "root/0/2")
    #expect(json["type"]?.stringValue == "UIButton")
    #expect(json["role"]?.stringValue == "button")
    #expect(json["accessibilityIdentifier"]?.stringValue == "home.submit")
    #expect(json["title"]?.stringValue == "提交")
    guard case .array(let actions)? = json["suggestedActions"] else {
        Issue.record("suggestedActions not array")
        return
    }
    #expect(actions.map(\.stringValue) == ["tap", "control.touchUpInside"])
}

@Test("UIViewTargetText 截断长文本并保留短文本")
func viewTargetTextTruncatesLongValues() {
    #expect(UIViewTargetText.limited("提交", limit: 80) == "提交")
    #expect(UIViewTargetText.limited("1234567890", limit: 4) == "1234")
    #expect(UIViewTargetText.limited(nil, limit: 4) == nil)
}
```

- [ ] **Step 2: Run the new tests and verify they fail**

Run:

```bash
swift test --filter UIKitViewTargetsTests
```

Expected: FAIL because `UIViewTargetsQuery`, `UIViewTargetRole`, `UIViewTargetSummary`, `UIViewTargetState`, and `UIViewTargetText` do not exist yet.

- [ ] **Step 3: Implement Foundation-only target models**

Create `Sources/iOSExploreServer/Handlers/UIKit/ViewTargets/UIViewTargetsModels.swift`:

```swift
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
```

- [ ] **Step 4: Run the model tests and verify they pass**

Run:

```bash
swift test --filter UIKitViewTargetsTests
```

Expected: PASS.

- [ ] **Step 5: Commit model layer**

Run:

```bash
git add Tests/iOSExploreServerTests/UIKitViewTargetsTests.swift Sources/iOSExploreServer/Handlers/UIKit/ViewTargets/UIViewTargetsModels.swift
git commit -m "feat: add UIKit view target models"
```

---

### Task 2: UIKit Collector And Command

**Files:**
- Create: `Sources/iOSExploreServer/Handlers/UIKit/ViewTargets/UIViewTargetsCollector.swift`
- Create: `Sources/iOSExploreServer/Handlers/UIKit/ViewTargets/ViewTargetsCommand.swift`
- Modify: `Sources/iOSExploreServer/Handlers/UIKit/UIKitHandlers.swift`

- [ ] **Step 1: Add the UIKit collector**

Create `Sources/iOSExploreServer/Handlers/UIKit/ViewTargets/UIViewTargetsCollector.swift`:

```swift
#if canImport(UIKit)
import Foundation
import UIKit

/// UIKit 轻量目标采集器。
///
/// 采集器只读取事件下发前需要的目标摘要，不读取颜色、字体、图片、滚动详情等布局验收字段。
@MainActor
enum UIViewTargetsCollector {
    /// 采集当前顶部控制器 view 下的轻量目标列表。
    ///
    /// - Parameter query: 查询参数。
    /// - Returns: 成功时返回 screen 与 targets；失败时返回业务失败 envelope。
    static func collect(query: UIViewTargetsQuery) -> ExploreResult {
        ExploreLogger.info(.command, "ui view targets collect mainactor start includeHidden=\(query.includeHidden) includeDisabled=\(query.includeDisabled) includeStaticText=\(query.includeStaticText) includeContainers=\(query.includeContainers) maxDepth=\(query.maxDepth.map(String.init) ?? "none") hasFilter=\(query.hasIdentifierFilter) textLimit=\(query.textLimit)")
        let context: UIKitViewLookup.Context
        switch UIKitViewLookup.currentContext() {
        case .success(let value):
            context = value
        case .failure(let reason):
            let error = ExploreServerError.uiHierarchyUnavailable(action: ViewTargetsCommand.actionName,
                                                                  reason: reason)
            ExploreLogger.error(.command, error.logMessage)
            return .failure(code: error.code, message: error.message)
        }

        var visitedCount = 0
        var targets: [UIViewTargetSummary] = []
        collect(view: context.rootView,
                window: context.window,
                path: [],
                depth: 0,
                query: query,
                visitedCount: &visitedCount,
                targets: &targets)

        let data: JSON = [
            "screen": .object(screenJSON(window: context.window,
                                         rootViewController: context.rootViewController,
                                         topViewController: context.topViewController)),
            "targetCount": .double(Double(targets.count)),
            "visitedNodeCount": .double(Double(visitedCount)),
            "targets": .array(targets.map { .object($0.toJSON()) }),
        ]
        ExploreLogger.info(.command, "ui view targets collect completed visitedNodeCount=\(visitedCount) targetCount=\(targets.count) topViewController=\(String(describing: type(of: context.topViewController)))")
        return .success(data)
    }

    /// 递归遍历 view，并把符合策略的节点加入 targets。
    private static func collect(view: UIView,
                                window: UIWindow,
                                path: [Int],
                                depth: Int,
                                query: UIViewTargetsQuery,
                                visitedCount: inout Int,
                                targets: inout [UIViewTargetSummary]) {
        visitedCount += 1
        if shouldInclude(view: view, query: query),
           matchesIdentifier(view: view, query: query) {
            targets.append(summary(for: view, window: window, path: path, query: query))
        }
        if let maxDepth = query.maxDepth, depth >= maxDepth {
            return
        }
        for (index, child) in view.subviews.enumerated() {
            collect(view: child,
                    window: window,
                    path: path + [index],
                    depth: depth + 1,
                    query: query,
                    visitedCount: &visitedCount,
                    targets: &targets)
        }
    }

    /// 判断 view 是否应作为轻量目标输出。
    private static func shouldInclude(view: UIView, query: UIViewTargetsQuery) -> Bool {
        if !query.includeHidden, view.isHidden { return false }
        if let control = view as? UIControl, !query.includeDisabled, !control.isEnabled { return false }
        if view is UIControl { return true }
        if view.gestureRecognizers?.isEmpty == false, view.isUserInteractionEnabled { return true }
        if view.accessibilityIdentifier?.isEmpty == false { return true }
        if view.accessibilityLabel?.isEmpty == false { return true }
        if query.includeStaticText, textualValue(from: view)?.isEmpty == false { return true }
        if query.includeContainers, !view.subviews.isEmpty { return true }
        return false
    }

    /// 判断 identifier 筛选条件。
    private static func matchesIdentifier(view: UIView, query: UIViewTargetsQuery) -> Bool {
        guard query.hasIdentifierFilter else { return true }
        let identifier = view.accessibilityIdentifier
        if let expected = query.accessibilityIdentifier, identifier == expected {
            return true
        }
        if let prefix = query.accessibilityIdentifierPrefix, identifier?.hasPrefix(prefix) == true {
            return true
        }
        return false
    }

    /// 生成目标摘要。
    private static func summary(for view: UIView,
                                window: UIWindow,
                                path: [Int],
                                query: UIViewTargetsQuery) -> UIViewTargetSummary {
        let control = view as? UIControl
        let frame = view.convert(view.bounds, to: window)
        return UIViewTargetSummary(
            path: UIKitViewLookupTarget.pathString(from: path),
            type: String(describing: Swift.type(of: view)),
            role: role(for: view),
            accessibilityIdentifier: UIViewTargetText.limited(view.accessibilityIdentifier, limit: query.textLimit),
            accessibilityLabel: UIViewTargetText.limited(view.accessibilityLabel, limit: query.textLimit),
            title: UIViewTargetText.limited(title(from: view), limit: query.textLimit),
            text: UIViewTargetText.limited(textualValue(from: view), limit: query.textLimit),
            placeholder: UIViewTargetText.limited(placeholder(from: view), limit: query.textLimit),
            value: UIViewTargetText.limited(value(from: view), limit: query.textLimit),
            frame: UIViewHierarchyRect(rect: frame),
            state: UIViewTargetState(isHidden: view.isHidden,
                                     alpha: Double(view.alpha),
                                     isUserInteractionEnabled: view.isUserInteractionEnabled,
                                     isEnabled: control?.isEnabled,
                                     isSelected: control?.isSelected,
                                     isHighlighted: control?.isHighlighted,
                                     hasGestureRecognizers: view.gestureRecognizers?.isEmpty == false)
        )
    }

    /// 识别轻量目标角色。
    private static func role(for view: UIView) -> UIViewTargetRole {
        if view is UIButton { return .button }
        if view is UISwitch { return .switch }
        if view is UISlider { return .slider }
        if view is UISegmentedControl { return .segmentedControl }
        if view is UITextField { return .textField }
        if view is UITextView { return .textView }
        if view is UILabel { return .label }
        if view is UIImageView { return .imageView }
        if !view.subviews.isEmpty { return .container }
        return .view
    }

    /// 提取控件标题。
    private static func title(from view: UIView) -> String? {
        if let button = view as? UIButton {
            return button.title(for: .normal) ?? button.currentTitle
        }
        if let segmented = view as? UISegmentedControl, segmented.selectedSegmentIndex >= 0 {
            return segmented.titleForSegment(at: segmented.selectedSegmentIndex)
        }
        return nil
    }

    /// 提取可见文本。
    private static func textualValue(from view: UIView) -> String? {
        if let label = view as? UILabel { return label.text }
        if let textField = view as? UITextField { return textField.text }
        if let textView = view as? UITextView { return textView.text }
        return nil
    }

    /// 提取占位文本。
    private static func placeholder(from view: UIView) -> String? {
        (view as? UITextField)?.placeholder
    }

    /// 提取当前值。
    private static func value(from view: UIView) -> String? {
        if let switchView = view as? UISwitch { return switchView.isOn ? "on" : "off" }
        if let slider = view as? UISlider { return String(Double(slider.value)) }
        if let segmented = view as? UISegmentedControl { return String(segmented.selectedSegmentIndex) }
        return view.accessibilityValue
    }

    /// 生成屏幕上下文摘要。
    private static func screenJSON(window: UIWindow,
                                   rootViewController: UIViewController,
                                   topViewController: UIViewController) -> JSON {
        [
            "windowType": .string(String(describing: type(of: window))),
            "rootViewController": .string(String(describing: type(of: rootViewController))),
            "topViewController": .string(String(describing: type(of: topViewController))),
        ]
    }
}

private extension UIViewHierarchyRect {
    /// 从 UIKit 矩形转换为协议矩形。
    init(rect: CGRect) {
        self.init(x: Double(rect.origin.x),
                  y: Double(rect.origin.y),
                  width: Double(rect.size.width),
                  height: Double(rect.size.height))
    }
}
#endif
```

- [ ] **Step 2: Add the command wrapper**

Create `Sources/iOSExploreServer/Handlers/UIKit/ViewTargets/ViewTargetsCommand.swift`:

```swift
#if canImport(UIKit)
import Foundation
import UIKit

/// 当前顶部控制器轻量交互目标查询命令。
///
/// action 为 `ui.viewTargets`。命令面向事件下发前的目标发现，只返回 path、语义、短文本、
/// window frame 和基础交互状态，不返回完整布局验收树。
struct ViewTargetsCommand: Command {
    /// 固定 action 名，供注册、日志和错误工厂复用。
    static let actionName = "ui.viewTargets"

    /// 命令名。
    let action = ViewTargetsCommand.actionName

    /// `help` 命令展示的说明。
    let description = "返回当前顶部控制器中可用于事件下发的轻量 UI 目标列表"

    /// 可选参数 schema。
    let parameters: [CommandParameter] = [
        CommandParameter(name: "includeHidden",
                         kind: .boolean,
                         required: false,
                         description: "是否包含隐藏 view, 默认 false"),
        CommandParameter(name: "includeDisabled",
                         kind: .boolean,
                         required: false,
                         description: "是否包含 disabled control, 默认 true"),
        CommandParameter(name: "includeStaticText",
                         kind: .boolean,
                         required: false,
                         description: "是否包含仅展示文本的节点, 默认 false"),
        CommandParameter(name: "includeContainers",
                         kind: .boolean,
                         required: false,
                         description: "是否包含普通容器 view, 默认 false"),
        CommandParameter(name: "maxDepth",
                         kind: .number,
                         required: false,
                         description: "最大递归深度, 0 表示仅根 view"),
        CommandParameter(name: "accessibilityIdentifier",
                         kind: .string,
                         required: false,
                         description: "按 accessibilityIdentifier 精确筛选"),
        CommandParameter(name: "accessibilityIdentifierPrefix",
                         kind: .string,
                         required: false,
                         description: "按 accessibilityIdentifier 前缀筛选"),
        CommandParameter(name: "textLimit",
                         kind: .number,
                         required: false,
                         description: "title/text/placeholder/value 最大字符数, 默认 80, 上限 200"),
    ]

    /// 执行轻量目标查询。
    ///
    /// - Parameter request: 已通过顶层类型校验的命令请求。
    /// - Returns: 成功时返回 targets 列表；参数非法时返回 `invalid_data`。
    func handle(_ request: ExploreRequest) async throws -> ExploreResult {
        ExploreLogger.info(.command, "command \(action) start payloadKeys=\(request.data.storage.count)")
        switch UIViewTargetsQuery.parse(from: request.data) {
        case .success(let query):
            let result = await UIViewTargetsCollector.collect(query: query)
            switch result {
            case .success(let data):
                let targetCount = data["targetCount"]?.doubleValue ?? 0
                let visitedCount = data["visitedNodeCount"]?.doubleValue ?? 0
                ExploreLogger.info(.command, "command \(action) completed targetCount=\(targetCount) visitedNodeCount=\(visitedCount)")
            case .failure(let code, let message):
                ExploreLogger.error(.command, "command \(action) failed code=\(code.rawValue) message=\(message)")
            }
            return result
        case .failure(let message):
            let error = ExploreServerError.invalidData(action: action, message: message)
            ExploreLogger.error(.command, error.logMessage)
            return .failure(code: error.code, message: error.message)
        }
    }
}
#endif
```

- [ ] **Step 3: Register the command**

Modify `Sources/iOSExploreServer/Handlers/UIKit/UIKitHandlers.swift`:

```swift
#if canImport(UIKit)
import Foundation

/// UIKit 内置命令注册入口。
///
/// 该文件只在 UIKit 可用的平台编译。它把所有 UIKit 相关命令集中注册到同一个
/// `Router`，避免基础网络层直接依赖 UIKit。
enum UIKitHandlers {
    /// 注册 UIKit 命令。
    ///
    /// - Parameter router: 命令路由器。
    static func registerAll(into router: Router) {
        ExploreLogger.info(.command, "uikit handlers register all")
        router.register(TopViewHierarchyCommand())
        router.register(ViewTargetsCommand())
        router.register(UIControlSendActionCommand())
        router.register(UITapCommand())
    }
}
#endif
```

- [ ] **Step 4: Run targeted tests**

Run:

```bash
swift test --filter UIKitViewTargetsTests
```

Expected: PASS.

- [ ] **Step 5: Build the package**

Run:

```bash
swift build
```

Expected: build completes successfully.

- [ ] **Step 6: Commit collector and command**

Run:

```bash
git add Sources/iOSExploreServer/Handlers/UIKit/ViewTargets/UIViewTargetsCollector.swift Sources/iOSExploreServer/Handlers/UIKit/ViewTargets/ViewTargetsCommand.swift Sources/iOSExploreServer/Handlers/UIKit/UIKitHandlers.swift
git commit -m "feat: add UIKit view targets command"
```

---

### Task 3: Command Help Text And Documentation

**Files:**
- Modify: `Sources/iOSExploreServer/Handlers/UIKit/Tap/UITapCommand.swift`
- Modify: `Sources/iOSExploreServer/Handlers/UIKit/ControlAction/UIControlSendActionCommand.swift`
- Modify: `docs/architecture/index.md`
- Modify: `docs/tools/network-tools.md`

- [ ] **Step 1: Update tap path parameter description**

In `Sources/iOSExploreServer/Handlers/UIKit/Tap/UITapCommand.swift`, change the `path` parameter description to:

```swift
CommandParameter(name: "path",
                 kind: .string,
                 required: false,
                 description: "按 ui.viewTargets 或 ui.topViewHierarchy 返回的 root/0/1 路径定位目标 view, 与 accessibilityIdentifier/x/y 互斥"),
```

- [ ] **Step 2: Update control action path parameter description**

In `Sources/iOSExploreServer/Handlers/UIKit/ControlAction/UIControlSendActionCommand.swift`, change the `path` parameter description to:

```swift
CommandParameter(name: "path",
                 kind: .string,
                 required: false,
                 description: "按 ui.viewTargets 或 ui.topViewHierarchy 返回的 root/0/1 路径定位目标控件, 与 accessibilityIdentifier 二选一"),
```

- [ ] **Step 3: Update architecture docs**

In `docs/architecture/index.md`, add this paragraph under `UIKit 层级快照` after the `accessibilityIdentifier` and `path` paragraph:

```markdown
`ui.viewTargets` 是事件下发前的轻量目标发现命令，返回扁平 targets 列表，不返回完整 `subviews` 树。每个 target 包含 `path`、运行时类型、轻量 role、`accessibilityIdentifier`、短文本、window 坐标 frame 和基础交互状态；agent 应优先调用它来找到 `ui.tap`、`ui.control.sendAction` 以及后续事件命令所需的目标。
```

- [ ] **Step 4: Add network tools example**

In `docs/tools/network-tools.md`, add this example near the UIKit command examples:

```bash
curl -X POST http://localhost:38321/ \
  -H 'Content-Type: application/json' \
  -d '{"action":"ui.viewTargets","data":{"includeStaticText":true,"textLimit":80}}'
```

- [ ] **Step 5: Run full test suite**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 6: Commit docs and descriptions**

Run:

```bash
git add Sources/iOSExploreServer/Handlers/UIKit/Tap/UITapCommand.swift Sources/iOSExploreServer/Handlers/UIKit/ControlAction/UIControlSendActionCommand.swift docs/architecture/index.md docs/tools/network-tools.md
git commit -m "docs: document UIKit view targets"
```

---

### Task 4: Framework Build Verification

**Files:**
- No source files expected.

- [ ] **Step 1: Build the framework project**

Run:

```bash
xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator build
```

Expected: build succeeds and compiles the shared `Sources/iOSExploreServer/` files, including `Handlers/UIKit/ViewTargets/`.

- [ ] **Step 2: Run final package tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 3: Inspect final changed files**

Run:

```bash
git status --short
```

Expected: only intentional working-tree changes remain. If unrelated pre-existing changes are present, leave them untouched and call them out in the final report.

