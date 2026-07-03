import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

@Test("wait 默认超时和轮询间隔")
func waitDefaults() throws {
    let input = try UIWaitInput.parse(from: ["mode": "idle"])
    #expect(input.mode == .idle)
    #expect(input.timeoutMs == 3000)
    #expect(input.intervalMs == 100)
    #expect(input.stableMs == 300)
}

@Test("targetExists 必须提供 identifier 或 path")
func targetExistsRequiresLocator() {
    #expect(throws: Error.self) {
        try UIWaitInput.parse(from: ["mode": "targetExists"])
    }
}

@Test("targetExists 接受 path")
func targetExistsAcceptsPath() throws {
    let input = try UIWaitInput.parse(from: ["mode": "targetExists", "path": "root/0"])
    #expect(input.mode == .targetExists)
    #expect(input.target != nil)
}

@Test("snapshotChanged 接受 viewSnapshotID")
func waitSnapshotChangedParsesViewSnapshotID() throws {
    let input = try UIWaitInput.parse(from: [
        "mode": "snapshotChanged",
        "viewSnapshotID": "view_snapshot_test",
    ])
    #expect(input.mode == .snapshotChanged)
    #expect(input.viewSnapshotID == "view_snapshot_test")
}

@Test("snapshotChanged 必须提供 viewSnapshotID")
func waitSnapshotChangedRequiresViewSnapshotID() {
    #expect(throws: Error.self) {
        try UIWaitInput.parse(from: ["mode": "snapshotChanged"])
    }
}

@Test("snapshotChanged 拒绝旧 snapshotID 字段名")
func waitSnapshotChangedRejectsOldSnapshotID() {
    // 旧契约接受 snapshotID；新契约字段改名 viewSnapshotID，旧名属于未声明字段，
    // 同时 snapshotChanged 必须配 viewSnapshotID，故此组合必须失败。
    #expect(throws: Error.self) {
        try UIWaitInput.parse(from: ["mode": "snapshotChanged", "snapshotID": "snap-1"])
    }
}

@Test("textExists 必须提供 text")
func textExistsRequiresText() {
    #expect(throws: Error.self) {
        try UIWaitInput.parse(from: ["mode": "textExists"])
    }
}

@Test("wait 拒绝超范围 intervalMs")
func waitRejectsIntervalOutOfRange() {
    #expect(throws: Error.self) {
        try UIWaitInput.parse(from: ["mode": "idle", "intervalMs": 10])
    }
}
