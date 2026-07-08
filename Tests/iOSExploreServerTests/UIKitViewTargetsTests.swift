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
                              isScrollView: Bool = false) -> UIViewTargetCandidate {
        UIViewTargetCandidate(isHidden: isHidden,
                              isControl: isControl,
                              isUserInteractionEnabled: isUserInteractionEnabled,
                              hasGestureRecognizers: hasGestureRecognizers,
                              hasAccessibilityIdentifier: hasAccessibilityIdentifier,
                              hasAccessibilityLabel: hasAccessibilityLabel,
                              hasStaticText: hasStaticText,
                              isScrollView: isScrollView)
    }
}
