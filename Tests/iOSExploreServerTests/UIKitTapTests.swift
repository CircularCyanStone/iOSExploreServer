import Testing
@testable import iOSExploreServer
@testable import iOSExploreUIKit

@Test("UIKitViewLookupTarget 解析 path 并生成一致路径描述")
func viewLookupTargetParsesPath() throws {
    let target = try UIKitViewLookupTarget.parse(identifier: nil, rawPath: "root/0/2/1")

    #expect(target == .path([0, 2, 1]))
    #expect(target.description == "path=root/0/2/1")
    #expect(UIKitViewLookupTarget.pathString(from: [0, 2, 1]) == "root/0/2/1")
}

// MARK: - ui.tap 结构化默认激活契约

/// `ui.tap` 已从“坐标 / hit-test / 祖先 fallback 的伪点击”收敛为：只接受
/// `ui.inspect` 签发的 canonical target 定位（path 或 accessibilityIdentifier）
/// 加必填的 `viewSnapshotID`。下面的测试锁定该公共输入契约。
@Test("UITapInput 从 path + viewSnapshotID 解析默认激活目标")
func tapInputParsesPathWithViewSnapshotID() throws {
    let query = try UITapInput.parse(from: [
        "path": "root/0/2/1",
        "viewSnapshotID": "view_snapshot_test",
    ])

    #expect(query.target == .path([0, 2, 1]))
    #expect(query.viewSnapshotID == "view_snapshot_test")
}

@Test("UITapInput 从 accessibilityIdentifier + viewSnapshotID 解析默认激活目标")
func tapInputParsesIdentifierWithViewSnapshotID() throws {
    let query = try UITapInput.parse(from: [
        "accessibilityIdentifier": "checkout.submit",
        "viewSnapshotID": "view_snapshot_test",
    ])

    #expect(query.target == .accessibilityIdentifier("checkout.submit"))
    #expect(query.viewSnapshotID == "view_snapshot_test")
}

@Test("UITapInput path 定位必须携带 viewSnapshotID")
func tapInputRequiresViewSnapshotIDForPath() {
    #expect(throws: CommandInputParseError.self) {
        try UITapInput.parse(from: ["path": "root/0"])
    }
}

@Test("UITapInput accessibilityIdentifier 定位必须携带 viewSnapshotID")
func tapInputRequiresViewSnapshotIDForIdentifier() {
    #expect(throws: CommandInputParseError.self) {
        try UITapInput.parse(from: ["accessibilityIdentifier": "checkout.submit"])
    }
}

@Test("UITapInput 拒绝裸坐标 x/y")
func tapInputRejectsCoordinates() {
    #expect(throws: CommandInputParseError.self) {
        try UITapInput.parse(from: ["x": 120, "y": 300])
    }
}

@Test("UITapInput 拒绝 coordinateSpace")
func tapInputRejectsCoordinateSpace() {
    #expect(throws: CommandInputParseError.self) {
        try UITapInput.parse(from: ["x": 1, "y": 2, "coordinateSpace": "window"])
    }
}

@Test("UITapInput 拒绝 path 与 accessibilityIdentifier 同时提供")
func tapInputRejectsMixedPathAndIdentifier() {
    #expect(throws: CommandInputParseError.self) {
        try UITapInput.parse(from: [
            "path": "root/0",
            "accessibilityIdentifier": "checkout.submit",
            "viewSnapshotID": "view_snapshot_test",
        ])
    }
}

@Test("UITapInput 拒绝旧 snapshotID 字段名")
func tapInputRejectsOldSnapshotID() {
    // 旧契约 path + snapshotID 合法；新契约字段改名为 viewSnapshotID，旧名属于未声明字段，
    // 同时 path 必须配 viewSnapshotID，故此组合必须失败。
    #expect(throws: CommandInputParseError.self) {
        try UITapInput.parse(from: ["path": "root/0", "snapshotID": "snap-1"])
    }
}

@Test("UITapInput schema 不再声明坐标字段且使用 viewSnapshotID")
func tapInputSchemaDropsCoordinatesAndUsesViewSnapshotID() {
    #expect(UITapInput.inputSchema.fields.map(\.name) == [
        "accessibilityIdentifier",
        "path",
        "viewSnapshotID",
    ])
}
