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
    #expect(throws: CommandInputParseError.self) {
        try UITapQuery.parse(from: [
            "accessibilityIdentifier": "mine.header.avatar",
            "x": 120,
            "y": 300,
        ])
    }
}

@Test("UITapInput schema 声明字段顺序和扩展约束")
func tapInputSchemaUsesExpectedFieldsAndConstraints() {
    #expect(UITapInput.inputSchema.fields.map(\.name) == [
        "accessibilityIdentifier",
        "path",
        "snapshotID",
        "x",
        "y",
        "coordinateSpace",
    ])

    let json = UITapInput.inputSchema.toJSON()
    guard case .array(let constraints)? = json["x-iosExplore-constraints"] else {
        Issue.record("x-iosExplore-constraints not found")
        return
    }
    #expect(constraints.map(\.stringValue).contains("snapshotID is valid only with path"))
    #expect(constraints.map(\.stringValue).contains("coordinateSpace currently supports only window"))
}

@Test("UITapInput 接受 identifier、path+snapshotID、window 坐标三类合法输入")
func tapInputParsesValidMatrix() throws {
    let identifier = try UITapInput.parse(from: ["accessibilityIdentifier": "home.submit"])
    #expect(identifier.target == .view(.accessibilityIdentifier("home.submit")))
    #expect(identifier.snapshotID == nil)

    let path = try UITapInput.parse(from: ["path": "root/0/1", "snapshotID": "snap-1"])
    #expect(path.target == .view(.path([0, 1])))
    #expect(path.snapshotID == "snap-1")

    let point = try UITapInput.parse(from: ["x": 10.5, "y": 20, "coordinateSpace": "window"])
    #expect(point.target == .windowPoint(x: 10.5, y: 20))
}

@Test("UITapInput 拒绝互斥、成对和 snapshotID 非法组合")
func tapInputRejectsInvalidMatrixAsCommandInputError() {
    let invalidCases: [JSON] = [
        ["x": 10],
        ["y": 20],
        ["accessibilityIdentifier": "home.submit", "path": "root/0"],
        ["accessibilityIdentifier": "home.submit", "x": 10, "y": 20],
        ["path": "root/0", "coordinateSpace": "window"],
        ["snapshotID": "snap-1", "accessibilityIdentifier": "home.submit"],
        ["snapshotID": "snap-1", "x": 10, "y": 20],
        ["x": 10, "y": 20, "coordinateSpace": "screen"],
    ]

    for data in invalidCases {
        #expect(throws: CommandInputParseError.self) {
            try UITapInput.parse(from: data)
        }
    }
}
