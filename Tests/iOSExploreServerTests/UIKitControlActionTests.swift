import Testing
@testable import iOSExploreServer
@testable import iOSExploreUIKit

@Test("UIControlSendActionInput 从 accessibilityIdentifier 解析目标和事件")
func controlSendActionQueryParsesIdentifierTarget() throws {
    let query = try UIControlSendActionInput.parse(from: [
        "accessibilityIdentifier": "mine.header.avatar",
        "event": "touchUpInside",
    ])

    #expect(query.target == .accessibilityIdentifier("mine.header.avatar"))
    #expect(query.event == .touchUpInside)
}

@Test("UIControlSendActionInput 从 path 解析目标和事件")
func controlSendActionQueryParsesPathTarget() throws {
    let query = try UIControlSendActionInput.parse(from: [
        "path": "root/0/2/1",
        "event": "valueChanged",
    ])

    #expect(query.target == .path([0, 2, 1]))
    #expect(query.event == .valueChanged)
}

@Test("UIControlSendActionInput 拒绝歧义目标和非法 path")
func controlSendActionQueryRejectsAmbiguousOrInvalidTarget() {
    #expect(throws: CommandInputParseError.self) {
        try UIControlSendActionInput.parse(from: [
            "accessibilityIdentifier": "mine.header.avatar",
            "path": "root/0",
            "event": "touchUpInside",
        ])
    }

    #expect(throws: CommandInputParseError.self) {
        try UIControlSendActionInput.parse(from: [
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

@Test("UIControlSendActionInput schema 声明字段顺序和约束")
func controlSendActionInputSchemaUsesExpectedFieldsAndConstraints() {
    #expect(UIControlSendActionInput.inputSchema.fields.map(\.name) == [
        "accessibilityIdentifier",
        "path",
        "snapshotID",
        "event",
    ])
    #expect(UIControlSendActionInput.inputSchema.constraints.contains(.exactlyOneOf([
        "accessibilityIdentifier",
        "path",
    ])))
    #expect(UIControlSendActionInput.inputSchema.constraints.contains(.extensionMessage(
        "snapshotID is valid only with path"
    )))
}

@Test("UIControlSendActionInput 接受 identifier 或 path+snapshotID")
func controlSendActionInputParsesValidMatrix() throws {
    let identifier = try UIControlSendActionInput.parse(from: [
        "accessibilityIdentifier": "home.submit",
        "event": "touchUpInside",
    ])
    #expect(identifier.target == .accessibilityIdentifier("home.submit"))
    #expect(identifier.event == .touchUpInside)
    #expect(identifier.snapshotID == nil)

    let path = try UIControlSendActionInput.parse(from: [
        "path": "root/0/1",
        "snapshotID": "snap-1",
        "event": "valueChanged",
    ])
    #expect(path.target == .path([0, 1]))
    #expect(path.event == .valueChanged)
    #expect(path.snapshotID == "snap-1")
}

@Test("UIControlSendActionInput 拒绝缺事件、缺目标和 snapshotID 非法组合")
func controlSendActionInputRejectsInvalidMatrixAsCommandInputError() {
    let invalidCases: [JSON] = [
        ["accessibilityIdentifier": "home.submit"],
        ["event": "touchUpInside"],
        ["accessibilityIdentifier": "home.submit", "path": "root/0", "event": "touchUpInside"],
        ["accessibilityIdentifier": "home.submit", "snapshotID": "snap-1", "event": "touchUpInside"],
        ["path": "root/a", "event": "touchUpInside"],
        ["path": "root/0", "event": "unknown"],
    ]

    for data in invalidCases {
        #expect(throws: CommandInputParseError.self) {
            try UIControlSendActionInput.parse(from: data)
        }
    }
}
