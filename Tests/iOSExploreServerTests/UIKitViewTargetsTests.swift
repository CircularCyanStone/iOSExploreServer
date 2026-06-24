import Testing
@testable import iOSExploreServer
@testable import iOSExploreUIKit

@Test("UIViewTargetsQuery 解析默认值和筛选参数")
func viewTargetsQueryParsesDefaultsAndFilters() throws {
    let query = try UIViewTargetsQuery.parse(from: [
        "includeHidden": true,
        "includeDisabled": false,
        "includeStaticText": true,
        "includeContainers": true,
        "maxDepth": 3,
        "accessibilityIdentifierPrefix": "home.",
        "textLimit": 120,
    ])

    #expect(query.includeHidden == true)
    #expect(query.includeDisabled == false)
    #expect(query.includeStaticText == true)
    #expect(query.includeContainers == true)
    #expect(query.maxDepth == 3)
    #expect(query.accessibilityIdentifierPrefix == "home.")
    #expect(query.textLimit == 120)
}

@Test("UIViewTargetsQuery 拒绝非法 maxDepth 和 textLimit")
func viewTargetsQueryRejectsInvalidNumbers() {
    #expect(throws: QueryParseError.self) { try UIViewTargetsQuery.parse(from: ["maxDepth": -1]) }
    #expect(throws: QueryParseError.self) { try UIViewTargetsQuery.parse(from: ["maxDepth": 1.5]) }
    #expect(throws: QueryParseError.self) { try UIViewTargetsQuery.parse(from: ["textLimit": 201]) }
    #expect(throws: QueryParseError.self) { try UIViewTargetsQuery.parse(from: ["textLimit": 0]) }
}

@Test("UIViewTargetsQuery 解析 maxTargets 默认值和边界")
func viewTargetsQueryParsesMaxTargets() throws {
    let defaultQuery = try UIViewTargetsQuery.parse(from: [:])
    #expect(defaultQuery.maxTargets == 200)

    let maximumQuery = try UIViewTargetsQuery.parse(from: ["maxTargets": 512])
    #expect(maximumQuery.maxTargets == 512)

    for invalid: JSON in [
        ["maxTargets": 0],
        ["maxTargets": 513],
        ["maxTargets": 1.5],
        ["maxTargets": .double(Double.greatestFiniteMagnitude)],
    ] {
        #expect(throws: QueryParseError.self) { try UIViewTargetsQuery.parse(from: invalid) }
    }
}

#if !canImport(UIKit)
@Test("UIViewTargetsQuery 拒绝无法安全转换为 Int 的数值")
func viewTargetsQueryRejectsOutOfRangeNumbers() {
    for data: JSON in [
        ["maxDepth": .double(Double.greatestFiniteMagnitude)],
        ["textLimit": .double(Double.greatestFiniteMagnitude)],
    ] {
        #expect(throws: QueryParseError.self) { try UIViewTargetsQuery.parse(from: data) }
    }
}
#endif

@Test("UIViewTargetsQuery include 策略覆盖可交互和可选节点")
func viewTargetsQueryShouldIncludeCandidates() {
    let defaultQuery = UIViewTargetsQuery.default

    #expect(defaultQuery.shouldInclude(candidate: .testCandidate(isControl: true)) == true)
    #expect(defaultQuery.shouldInclude(candidate: .testCandidate(isControl: true, isEnabled: false)) == true)
    #expect(UIViewTargetsQuery(includeDisabled: false).shouldInclude(candidate: .testCandidate(isControl: true, isEnabled: false)) == false)
    #expect(defaultQuery.shouldInclude(candidate: .testCandidate(isHidden: true, isControl: true)) == false)
    #expect(defaultQuery.shouldInclude(candidate: .testCandidate(hasStaticText: true)) == false)
    #expect(defaultQuery.shouldInclude(candidate: .testCandidate(hasSubviews: true)) == false)
    #expect(UIViewTargetsQuery(includeStaticText: true).shouldInclude(candidate: .testCandidate(hasStaticText: true)) == true)
    #expect(UIViewTargetsQuery(includeContainers: true).shouldInclude(candidate: .testCandidate(hasSubviews: true)) == true)
    #expect(defaultQuery.shouldInclude(candidate: .testCandidate(isUserInteractionEnabled: true, hasGestureRecognizers: true)) == true)
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
                              isEnabled: Bool = true,
                              isUserInteractionEnabled: Bool = false,
                              hasGestureRecognizers: Bool = false,
                              hasAccessibilityIdentifier: Bool = false,
                              hasAccessibilityLabel: Bool = false,
                              hasStaticText: Bool = false,
                              hasSubviews: Bool = false) -> UIViewTargetCandidate {
        UIViewTargetCandidate(isHidden: isHidden,
                              isControl: isControl,
                              isEnabled: isEnabled,
                              isUserInteractionEnabled: isUserInteractionEnabled,
                              hasGestureRecognizers: hasGestureRecognizers,
                              hasAccessibilityIdentifier: hasAccessibilityIdentifier,
                              hasAccessibilityLabel: hasAccessibilityLabel,
                              hasStaticText: hasStaticText,
                              hasSubviews: hasSubviews)
    }
}
