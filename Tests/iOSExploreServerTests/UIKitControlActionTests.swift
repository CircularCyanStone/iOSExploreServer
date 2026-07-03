import Testing
@testable import iOSExploreServer
@testable import iOSExploreUIKit

// MARK: - ui.control.sendAction 精确事件契约

/// `ui.control.sendAction` 是精确 UIKit event 工具：只接受 canonical target 定位
/// （path 或 accessibilityIdentifier）+ 必填 `viewSnapshotID` + 显式 event，不再做
/// hit-test、不接受坐标、不找祖先 control。下面测试锁定该公共输入契约。
@Test("UIControlSendActionInput 从 path + viewSnapshotID + event 解析")
func sendActionInputParsesPathWithViewSnapshotIDAndEvent() throws {
    let query = try UIControlSendActionInput.parse(from: [
        "path": "root/0",
        "viewSnapshotID": "view_snapshot_test",
        "event": "touchUpInside",
    ])

    #expect(query.target == .path([0]))
    #expect(query.event == .touchUpInside)
    #expect(query.viewSnapshotID == "view_snapshot_test")
}

@Test("UIControlSendActionInput 从 identifier + viewSnapshotID + event 解析")
func sendActionInputParsesIdentifierWithViewSnapshotIDAndEvent() throws {
    let query = try UIControlSendActionInput.parse(from: [
        "accessibilityIdentifier": "checkout.submit",
        "viewSnapshotID": "view_snapshot_test",
        "event": "touchDown",
    ])

    #expect(query.target == .accessibilityIdentifier("checkout.submit"))
    #expect(query.event == .touchDown)
    #expect(query.viewSnapshotID == "view_snapshot_test")
}

@Test("UIControlSendActionInput path 与 identifier 都必须携带 viewSnapshotID")
func sendActionInputRejectsMissingViewSnapshotID() {
    #expect(throws: CommandInputParseError.self) {
        try UIControlSendActionInput.parse(from: ["path": "root/0", "event": "touchUpInside"])
    }
    #expect(throws: CommandInputParseError.self) {
        try UIControlSendActionInput.parse(from: [
            "accessibilityIdentifier": "checkout.submit",
            "event": "touchUpInside",
        ])
    }
}

@Test("UIControlSendActionInput 拒绝旧 snapshotID 字段名")
func sendActionInputRejectsOldSnapshotID() {
    #expect(throws: CommandInputParseError.self) {
        try UIControlSendActionInput.parse(from: [
            "path": "root/0",
            "snapshotID": "snap-1",
            "event": "touchUpInside",
        ])
    }
}

@Test("UIControlSendActionInput 拒绝 path 与 identifier 同时提供")
func sendActionInputRejectsMixedPathAndIdentifier() {
    #expect(throws: CommandInputParseError.self) {
        try UIControlSendActionInput.parse(from: [
            "path": "root/0",
            "accessibilityIdentifier": "checkout.submit",
            "viewSnapshotID": "view_snapshot_test",
            "event": "touchUpInside",
        ])
    }
}

@Test("UIControlSendActionInput schema 使用 viewSnapshotID 且无坐标")
func sendActionInputSchemaUsesViewSnapshotID() {
    #expect(UIControlSendActionInput.inputSchema.fields.map(\.name) == [
        "accessibilityIdentifier",
        "path",
        "viewSnapshotID",
        "event",
    ])
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
