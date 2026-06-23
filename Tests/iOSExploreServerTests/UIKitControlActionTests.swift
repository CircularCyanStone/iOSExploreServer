import Testing
@testable import iOSExploreServer
@testable import iOSExploreUIKit

@Test("UIControlSendActionQuery 从 accessibilityIdentifier 解析目标和事件")
func controlSendActionQueryParsesIdentifierTarget() {
    let result = UIControlSendActionQuery.parse(from: [
        "accessibilityIdentifier": "mine.header.avatar",
        "event": "touchUpInside",
    ])

    switch result {
    case .success(let query):
        #expect(query.target == .accessibilityIdentifier("mine.header.avatar"))
        #expect(query.event == .touchUpInside)
    case .failure(let message):
        Issue.record("unexpected failure: \(message)")
    }
}

@Test("UIControlSendActionQuery 从 path 解析目标和事件")
func controlSendActionQueryParsesPathTarget() {
    let result = UIControlSendActionQuery.parse(from: [
        "path": "root/0/2/1",
        "event": "valueChanged",
    ])

    switch result {
    case .success(let query):
        #expect(query.target == .path([0, 2, 1]))
        #expect(query.event == .valueChanged)
    case .failure(let message):
        Issue.record("unexpected failure: \(message)")
    }
}

@Test("UIControlSendActionQuery 拒绝歧义目标和非法 path")
func controlSendActionQueryRejectsAmbiguousOrInvalidTarget() {
    if case .success = UIControlSendActionQuery.parse(from: [
        "accessibilityIdentifier": "mine.header.avatar",
        "path": "root/0",
        "event": "touchUpInside",
    ]) {
        Issue.record("identifier and path should be mutually exclusive")
    }

    if case .success = UIControlSendActionQuery.parse(from: [
        "path": "root/a",
        "event": "touchUpInside",
    ]) {
        Issue.record("invalid path should fail")
    }
}

@Test("UIControlSendActionEvent 支持常用 UIControl 事件名")
func controlSendActionEventParsesSupportedNames() {
    #expect(UIControlSendActionEvent(rawValue: "touchDown") == .touchDown)
    #expect(UIControlSendActionEvent(rawValue: "touchUpInside") == .touchUpInside)
    #expect(UIControlSendActionEvent(rawValue: "valueChanged") == .valueChanged)
    #expect(UIControlSendActionEvent(rawValue: "editingChanged") == .editingChanged)
    #expect(UIControlSendActionEvent(rawValue: "editingDidBegin") == .editingDidBegin)
    #expect(UIControlSendActionEvent(rawValue: "editingDidEnd") == .editingDidEnd)
}
