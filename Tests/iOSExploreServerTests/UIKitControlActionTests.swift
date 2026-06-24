import Testing
@testable import iOSExploreServer
@testable import iOSExploreUIKit

@Test("UIControlSendActionQuery 从 accessibilityIdentifier 解析目标和事件")
func controlSendActionQueryParsesIdentifierTarget() throws {
    let query = try UIControlSendActionQuery.parse(from: [
        "accessibilityIdentifier": "mine.header.avatar",
        "event": "touchUpInside",
    ])

    #expect(query.target == .accessibilityIdentifier("mine.header.avatar"))
    #expect(query.event == .touchUpInside)
}

@Test("UIControlSendActionQuery 从 path 解析目标和事件")
func controlSendActionQueryParsesPathTarget() throws {
    let query = try UIControlSendActionQuery.parse(from: [
        "path": "root/0/2/1",
        "event": "valueChanged",
    ])

    #expect(query.target == .path([0, 2, 1]))
    #expect(query.event == .valueChanged)
}

@Test("UIControlSendActionQuery 拒绝歧义目标和非法 path")
func controlSendActionQueryRejectsAmbiguousOrInvalidTarget() {
    #expect(throws: QueryParseError.self) {
        try UIControlSendActionQuery.parse(from: [
            "accessibilityIdentifier": "mine.header.avatar",
            "path": "root/0",
            "event": "touchUpInside",
        ])
    }

    #expect(throws: QueryParseError.self) {
        try UIControlSendActionQuery.parse(from: [
            "path": "root/a",
            "event": "touchUpInside",
        ])
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
