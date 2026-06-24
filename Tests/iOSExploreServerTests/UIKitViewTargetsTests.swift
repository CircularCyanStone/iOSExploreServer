import Testing
@testable import iOSExploreServer
@testable import iOSExploreUIKit

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

@Test("UIViewTargetsQuery 解析 maxTargets 默认值和边界")
func viewTargetsQueryParsesMaxTargets() {
    guard case .success(let defaultQuery) = UIViewTargetsQuery.parse(from: [:]) else {
        Issue.record("default query should parse")
        return
    }
    #expect(defaultQuery.maxTargets == 200)

    guard case .success(let maximumQuery) = UIViewTargetsQuery.parse(from: ["maxTargets": 512]) else {
        Issue.record("maxTargets upper boundary should parse")
        return
    }
    #expect(maximumQuery.maxTargets == 512)

    for invalid: JSON in [
        ["maxTargets": 0],
        ["maxTargets": 513],
        ["maxTargets": 1.5],
        ["maxTargets": .double(Double.greatestFiniteMagnitude)],
    ] {
        guard case .failure = UIViewTargetsQuery.parse(from: invalid) else {
            Issue.record("invalid maxTargets accepted: \(invalid)")
            return
        }
    }
}

#if !canImport(UIKit)
@Test("UIViewTargetsQuery 拒绝无法安全转换为 Int 的数值")
func viewTargetsQueryRejectsOutOfRangeNumbers() {
    for data: JSON in [
        ["maxDepth": .double(Double.greatestFiniteMagnitude)],
        ["textLimit": .double(Double.greatestFiniteMagnitude)],
    ] {
        guard case .failure = UIViewTargetsQuery.parse(from: data) else {
            Issue.record("out-of-range number must be rejected before Int conversion")
            return
        }
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
