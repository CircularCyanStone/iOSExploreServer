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
