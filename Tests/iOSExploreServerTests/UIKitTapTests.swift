import Testing
@testable import iOSExploreServer

@Test("UIKitViewLookupTarget 解析 path 并生成一致路径描述")
func viewLookupTargetParsesPath() {
    let result = UIKitViewLookupTarget.parse(identifier: nil, rawPath: "root/0/2/1")

    switch result {
    case .success(let target):
        #expect(target == .path([0, 2, 1]))
        #expect(target.description == "path=root/0/2/1")
        #expect(UIKitViewLookupTarget.pathString(from: [0, 2, 1]) == "root/0/2/1")
    case .failure(let message):
        Issue.record("unexpected failure: \(message)")
    }
}

@Test("UITapQuery 从 accessibilityIdentifier 解析 view 目标")
func tapQueryParsesIdentifierTarget() {
    let result = UITapQuery.parse(from: [
        "accessibilityIdentifier": "mine.header.avatar",
    ])

    switch result {
    case .success(let query):
        #expect(query.target == .view(.accessibilityIdentifier("mine.header.avatar")))
    case .failure(let message):
        Issue.record("unexpected failure: \(message)")
    }
}

@Test("UITapQuery 从 window 坐标解析点击目标")
func tapQueryParsesWindowPointTarget() {
    let result = UITapQuery.parse(from: [
        "x": 120,
        "y": 300,
        "coordinateSpace": "window",
    ])

    switch result {
    case .success(let query):
        #expect(query.target == .windowPoint(x: 120, y: 300))
    case .failure(let message):
        Issue.record("unexpected failure: \(message)")
    }
}

@Test("UITapQuery 拒绝 view 定位和坐标混用")
func tapQueryRejectsMixedTargets() {
    if case .success = UITapQuery.parse(from: [
        "accessibilityIdentifier": "mine.header.avatar",
        "x": 120,
        "y": 300,
    ]) {
        Issue.record("view target and coordinate target should be mutually exclusive")
    }
}
