import Testing
@testable import iOSExploreServer
@testable import iOSExploreUIKit

@Test("UIViewTargetsInput 解析默认值和筛选参数")
func viewTargetsQueryParsesDefaultsAndFilters() throws {
    let query = try UIViewTargetsInput.parse(from: [
        "includeHidden": true,
        "maxDepth": 3,
        "accessibilityIdentifierPrefix": "home.",
        "textLimit": 120,
    ])

    #expect(query.includeHidden == true)
    #expect(query.maxDepth == 3)
    #expect(query.accessibilityIdentifierPrefix == "home.")
    #expect(query.textLimit == 120)
}

@Test("UIViewTargetsInput schema 按工具展示顺序声明字段")
func viewTargetsInputSchemaUsesExpectedFieldOrder() {
    #expect(UIViewTargetsInput.inputSchema.fields.map(\.name) == [
        "includeHidden",
        "maxDepth",
        "accessibilityIdentifier",
        "accessibilityIdentifierPrefix",
        "textLimit",
        "maxTargets",
    ])
}

@Test("UIViewTargetsInput 拒绝非法 maxDepth 和 textLimit")
func viewTargetsQueryRejectsInvalidNumbers() {
    #expect(throws: CommandInputParseError.self) { try UIViewTargetsInput.parse(from: ["maxDepth": -1]) }
    #expect(throws: CommandInputParseError.self) { try UIViewTargetsInput.parse(from: ["maxDepth": 1.5]) }
    #expect(throws: CommandInputParseError.self) { try UIViewTargetsInput.parse(from: ["textLimit": 201]) }
    #expect(throws: CommandInputParseError.self) { try UIViewTargetsInput.parse(from: ["textLimit": 0]) }
}

@Test("UIViewTargetsInput 解析 maxTargets 默认值和边界")
func viewTargetsQueryParsesMaxTargets() throws {
    let defaultQuery = try UIViewTargetsInput.parse(from: [:])
    #expect(defaultQuery.maxTargets == 200)

    let maximumQuery = try UIViewTargetsInput.parse(from: ["maxTargets": 512])
    #expect(maximumQuery.maxTargets == 512)

    for invalid: JSON in [
        ["maxTargets": 0],
        ["maxTargets": 513],
        ["maxTargets": 1.5],
        ["maxTargets": .double(Double.greatestFiniteMagnitude)],
    ] {
        #expect(throws: CommandInputParseError.self) { try UIViewTargetsInput.parse(from: invalid) }
    }
}

#if !canImport(UIKit)
@Test("UIViewTargetsInput 拒绝无法安全转换为 Int 的数值")
func viewTargetsQueryRejectsOutOfRangeNumbers() {
    for data: JSON in [
        ["maxDepth": .double(Double.greatestFiniteMagnitude)],
        ["textLimit": .double(Double.greatestFiniteMagnitude)],
    ] {
        #expect(throws: CommandInputParseError.self) { try UIViewTargetsInput.parse(from: data) }
    }
}
#endif

@Test("isFull: 任一识别/可操作条件为 true 即 full")
func viewTargetsQueryIsFullRules() {
    let input = UIViewTargetsInput()

    // 六条规则：任一为 true 即 full（带识别信息或可操作的 canonical interaction target）。
    // isControl / isScrollView / hasGestureRecognizers = 可操作；
    // hasStaticText / hasAccessibilityLabel / hasAccessibilityIdentifier = 带识别信息。
    #expect(input.isFull(candidate: .testCandidate(isControl: true)) == true)
    #expect(input.isFull(candidate: .testCandidate(isScrollView: true)) == true)
    #expect(input.isFull(candidate: .testCandidate(hasGestureRecognizers: true)) == true)
    #expect(input.isFull(candidate: .testCandidate(hasStaticText: true)) == true)
    #expect(input.isFull(candidate: .testCandidate(hasAccessibilityLabel: true)) == true)
    #expect(input.isFull(candidate: .testCandidate(hasAccessibilityIdentifier: true)) == true)
}

@Test("isFull: 全部条件为 false 即 minimal")
func viewTargetsQueryIsFullMinimal() {
    let input = UIViewTargetsInput()
    // 无识别信息且不可操作 → minimal，只输出 path+type 维持层级。
    #expect(input.isFull(candidate: .testCandidate()) == false)
}

@Test("isFull: hasStaticText 在 UIControl 子树内 rollup，否则仍 full")
func viewTargetsQueryIsFullRollsUpControlSubtreeLabel() {
    let input = UIViewTargetsInput()
    // 按钮内部 title label（UIButtonLabel）：hasStaticText + isInControlSubtree（祖先含 UIControl）。
    // 文本已通过父 control 的 semanticText（buttonTitle）汇总，独立签发只会让 agent tap 到
    // 返回 unsupported_target 的死节点，破坏"签发=可操作"——故 rollup，不独立 full。
    #expect(input.isFull(candidate: .testCandidate(hasStaticText: true, isInControlSubtree: true)) == false)
    // 即便同时带 accessibilityLabel，控件子树内仍 rollup（label 也属控件内嵌展示语义）。
    #expect(input.isFull(candidate: .testCandidate(hasAccessibilityLabel: true,
                                                    hasStaticText: true,
                                                    isInControlSubtree: true)) == false)
    // 独立 label（页面标题）/ cell 内 label：祖先无 UIControl（cell 非 UIControl）→ 仍 full。
    // 这是 spec §3.4「cell 内 UILabel 可被 agent 直接 tap 选中行」的核心，rollup 不得误伤。
    #expect(input.isFull(candidate: .testCandidate(hasStaticText: true, isInControlSubtree: false)) == true)
    // control 自身不计为 control 子树（isInControlSubtree=false），走 isControl 规则独立 full。
    #expect(input.isFull(candidate: .testCandidate(isControl: true, isInControlSubtree: false)) == true)
}

@Test("isFull: includeHidden=false 时 hidden 节点被剪枝")
func viewTargetsQueryIsFullHiddenPruned() {
    // includeHidden 默认 false：hidden 节点即便命中 canonical 条件也不输出。
    let input = UIViewTargetsInput()
    #expect(input.isFull(candidate: .testCandidate(isHidden: true, isControl: true)) == false)
    // includeHidden=true 时 hidden canonical target 仍进入输出。
    #expect(UIViewTargetsInput(includeHidden: true).isFull(candidate: .testCandidate(isHidden: true, isControl: true)) == true)
}

@Test("UIViewTargetsInput 不再声明 includeStaticText/includeContainers/includeDisabled")
func viewTargetsQueryDeadFieldsRemoved() {
    // schema additionalProperties=false：删除字段后，旧字段名应作为未知字段被拒绝，
    // 避免调用方误以为传值仍生效。
    #expect(throws: CommandInputParseError.self) {
        try UIViewTargetsInput.parse(from: ["includeStaticText": true])
    }
    #expect(throws: CommandInputParseError.self) {
        try UIViewTargetsInput.parse(from: ["includeDisabled": false])
    }
    #expect(throws: CommandInputParseError.self) {
        try UIViewTargetsInput.parse(from: ["includeContainers": true])
    }
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
    // suggestedActions 已移除：availableActions 是唯一动作字段，与 executor 派发一致，
    // 避免 role 粗略推断与真实能力分叉对 agent 造成歧义。
    #expect(json["suggestedActions"] == nil)
    // availableActions 默认为空：模型层不按 role 推断，真实能力由 resolver 在 UIKit 域生成
    guard case .array(let available)? = json["availableActions"] else {
        Issue.record("availableActions not array")
        return
    }
    #expect(available.isEmpty)
}

@Test("UIViewTargetSummary 携带 resolver 生成的 availableActions")
func viewTargetSummaryCarriesResolverAvailability() {
    let summary = UIViewTargetSummary(
        path: "root/0/1",
        type: "UISwitch",
        role: .switch,
        accessibilityIdentifier: "settings.notify",
        accessibilityLabel: nil,
        title: nil,
        text: nil,
        placeholder: nil,
        value: nil,
        frame: UIViewHierarchyRect(x: 0, y: 0, width: 51, height: 31),
        state: UIViewTargetState(isHidden: false,
                                 alpha: 1,
                                 isUserInteractionEnabled: true,
                                 isEnabled: true,
                                 isSelected: false,
                                 isHighlighted: false,
                                 hasGestureRecognizers: false),
        availableActions: UIKitActionAvailability(actions: [.tap, .controlValueChanged])
    )

    guard case .array(let available)? = summary.toJSON()["availableActions"] else {
        Issue.record("availableActions not array")
        return
    }
    #expect(available.map(\.stringValue) == ["tap", "control.valueChanged"])
}

@Test("UIViewTargetText 截断长文本并保留短文本")
func viewTargetTextTruncatesLongValues() {
    #expect(UIViewTargetText.limited("提交", limit: 80) == "提交")
    #expect(UIViewTargetText.limited("1234567890", limit: 4) == "1234")
    #expect(UIViewTargetText.limited(nil, limit: 4) == nil)
}

private extension UIViewTargetCandidate {
    static func testCandidate(isHidden: Bool = false,
                              isControl: Bool = false,
                              isUserInteractionEnabled: Bool = false,
                              hasGestureRecognizers: Bool = false,
                              hasAccessibilityIdentifier: Bool = false,
                              hasAccessibilityLabel: Bool = false,
                              hasStaticText: Bool = false,
                              isScrollView: Bool = false,
                              isInControlSubtree: Bool = false) -> UIViewTargetCandidate {
        UIViewTargetCandidate(isHidden: isHidden,
                              isControl: isControl,
                              isUserInteractionEnabled: isUserInteractionEnabled,
                              hasGestureRecognizers: hasGestureRecognizers,
                              hasAccessibilityIdentifier: hasAccessibilityIdentifier,
                              hasAccessibilityLabel: hasAccessibilityLabel,
                              hasStaticText: hasStaticText,
                              isScrollView: isScrollView,
                              isInControlSubtree: isInControlSubtree)
    }
}

#if canImport(UIKit)
import UIKit

/// `UIViewTargetsCollector.semanticText(for:limit:)` 的行为测试（Task 3 重构后）。
///
/// `semanticText` 是 collector 的私有方法，只能通过 `collect(query:context:)` 返回的 target
/// summary 间接观察。Task 3（e9922e4）把 `accessibilityIdentifier` 从最低优先提到最高，并新增
/// `segmentTitle` / `labelText` / `textViewText` 三个来源。这组测试锁定优先级与来源，防止回归。
///
/// 优先级：accessibilityIdentifier → accessibilityLabel → accessibilityValue →
/// buttonTitle → segmentTitle → labelText → placeholder → textViewText。
/// 从 collect 结果里取第 1 个 target 的 summary JSON，失败时记录并返回 nil。
@MainActor
private func firstTargetSummary(from data: JSON) -> JSON? {
    // 两个条件放同一个 guard：targets.first 是 JSONValue?，需要 ? 模式匹配；
    // 拆成两个 guard 会让前一个 guard-let 把 first 解包成非可选，后者 ? 模式就编译失败。
    guard case .array(let targets)? = data["targets"],
          case .object(let target)? = targets.first else {
        Issue.record("targets not array or first target not object")
        return nil
    }
    return target
}

@Test("semanticText: accessibilityIdentifier 优先于 buttonTitle") @MainActor
func semanticTextIdentifierBeatsButtonTitle() {
    // 同一按钮既有 accessibilityIdentifier 又有 title：identifier 是最稳定定位键，必须胜出。
    let context = UIKitTestHost.context { root in
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = "checkout.submit"
        button.setTitle("提交订单", for: .normal)
        button.frame = CGRect(x: 10, y: 10, width: 120, height: 40)
        root.addSubview(button)
    }

    guard let target = firstTargetSummary(
        from: UIViewTargetsCollector.collect(query: .default, context: context)) else { return }
    #expect(target["semanticText"]?.stringValue == "checkout.submit")
    #expect(target["semanticTextSource"]?.stringValue == "accessibilityIdentifier")
}

@Test("semanticText: UILabel 无 a11y 时用 labelText 兜底（spec §3.2 cell 文字可见核心）") @MainActor
func semanticTextLabelTextFallbackForPlainLabel() {
    // 无任何无障碍属性、仅 .text 非空的 UILabel：labelText 兜底让 agent 能读到 cell 文字。
    // 这是 spec §3.2「cell 内 UILabel 要带文字」的核心——没有 a11y 的纯展示 label 也必须可提取。
    let context = UIKitTestHost.context { root in
        let label = UILabel()
        label.text = "订单总额"
        label.frame = CGRect(x: 10, y: 10, width: 200, height: 20)
        root.addSubview(label)
    }

    guard let target = firstTargetSummary(
        from: UIViewTargetsCollector.collect(query: .default, context: context)) else { return }
    #expect(target["semanticText"]?.stringValue == "订单总额")
    #expect(target["semanticTextSource"]?.stringValue == "labelText")
}

@Test("semanticText: UISegmentedControl 选中段用 segmentTitle") @MainActor
func semanticTextSegmentTitleForSelectedSegment() {
    // 选中段标题作为语义文本来源。accessibilityIdentifier / accessibilityLabel 均未设置，
    // 避免更高优先级来源遮蔽 segmentTitle。
    let context = UIKitTestHost.context { root in
        let segmented = UISegmentedControl(items: ["日", "周", "月"])
        segmented.selectedSegmentIndex = 1
        segmented.frame = CGRect(x: 10, y: 10, width: 200, height: 28)
        root.addSubview(segmented)
    }

    guard let target = firstTargetSummary(
        from: UIViewTargetsCollector.collect(query: .default, context: context)) else { return }
    // selectedSegmentIndex=1 → 选中「周」。源是 segmentTitle（优先级 5）。
    // 注：UISegmentedControl 默认可能用选中段标题填充 accessibilityValue；若发生遮蔽，
    // 这里会暴露为 accessibilityValue，作为优先级设计的可观察事实。
    #expect(target["semanticText"]?.stringValue == "周")
    #expect(target["semanticTextSource"]?.stringValue == "segmentTitle")
}

@Test("semanticText: UITextView 有 .text 时用 textViewText") @MainActor
func semanticTextTextViewTextFallback() {
    // UITextView 无 a11y identifier/label/value 时，textViewText 兜底返回正文。
    let context = UIKitTestHost.context { root in
        let textView = UITextView()
        textView.text = "备注内容"
        textView.frame = CGRect(x: 10, y: 10, width: 200, height: 80)
        root.addSubview(textView)
    }

    guard let target = firstTargetSummary(
        from: UIViewTargetsCollector.collect(query: .default, context: context)) else { return }
    #expect(target["semanticText"]?.stringValue == "备注内容")
    #expect(target["semanticTextSource"]?.stringValue == "textViewText")
}
#endif
