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

@Test("UITapQuery 从 accessibilityIdentifier 解析 view 目标")
func tapQueryParsesIdentifierTarget() throws {
    let query = try UITapQuery.parse(from: [
        "accessibilityIdentifier": "mine.header.avatar",
    ])

    #expect(query.target == .view(.accessibilityIdentifier("mine.header.avatar")))
}

@Test("UITapQuery 从 window 坐标解析点击目标")
func tapQueryParsesWindowPointTarget() throws {
    let query = try UITapQuery.parse(from: [
        "x": 120,
        "y": 300,
        "coordinateSpace": "window",
    ])

    #expect(query.target == .windowPoint(x: 120, y: 300))
}

@Test("UITapQuery 拒绝 view 定位和坐标混用")
func tapQueryRejectsMixedTargets() {
    #expect(throws: QueryParseError.self) {
        try UITapQuery.parse(from: [
            "accessibilityIdentifier": "mine.header.avatar",
            "x": 120,
            "y": 300,
        ])
    }
}
