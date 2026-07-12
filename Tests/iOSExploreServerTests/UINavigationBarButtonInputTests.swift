import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

@Test("navigation bar button 解析 right index title identifier waitAfterMs")
func navigationBarButtonParsesSelector() throws {
    let input = try UINavigationBarButtonInput.parse(from: [
        "placement": "right",
        "index": 0,
        "title": "控件测试",
        "accessibilityIdentifier": "example.controlTest",
        "waitAfterMs": 120,
    ])

    #expect(input.placement == .right)
    #expect(input.index == 0)
    #expect(input.title == "控件测试")
    #expect(input.accessibilityIdentifier == "example.controlTest")
    #expect(input.waitAfterMs == 120)
}

@Test("navigation bar button 默认 waitAfterMs 300")
func navigationBarButtonDefaultsWaitAfter() throws {
    let input = try UINavigationBarButtonInput.parse(from: [
        "placement": "left",
        "index": 1,
    ])

    #expect(input.placement == .left)
    #expect(input.index == 1)
    #expect(input.waitAfterMs == 300)
}

@Test("navigation bar button 拒绝非法 placement")
func navigationBarButtonRejectsInvalidPlacement() {
    #expect(throws: Error.self) {
        try UINavigationBarButtonInput.parse(from: [
            "placement": "center",
            "index": 0,
        ])
    }
}

@Test("navigation bar button 拒绝非法 index")
func navigationBarButtonRejectsNegativeIndex() {
    #expect(throws: Error.self) {
        try UINavigationBarButtonInput.parse(from: [
            "placement": "right",
            "index": -1,
        ])
    }
}

@Test("navigation bar button 允许只提供 accessibilityIdentifier 全局搜索")
func navigationBarButtonAllowsAccessibilityIdentifierOnly() throws {
    let input = try UINavigationBarButtonInput.parse(from: [
        "accessibilityIdentifier": "example.controlTest",
    ])

    #expect(input.placement == nil)
    #expect(input.index == nil)
    #expect(input.accessibilityIdentifier == "example.controlTest")
    #expect(input.waitAfterMs == 300)
}

@Test("navigation bar button 允许 placement + accessibilityIdentifier 组合")
func navigationBarButtonAllowsPlacementWithAccessibilityIdentifier() throws {
    let input = try UINavigationBarButtonInput.parse(from: [
        "placement": "right",
        "accessibilityIdentifier": "example.controlTest",
    ])

    #expect(input.placement == .right)
    #expect(input.index == nil)
    #expect(input.accessibilityIdentifier == "example.controlTest")
}

@Test("navigation bar button 允许只提供 placement + index")
func navigationBarButtonAllowsPlacementAndIndex() throws {
    let input = try UINavigationBarButtonInput.parse(from: [
        "placement": "right",
        "index": 0,
    ])

    #expect(input.placement == .right)
    #expect(input.index == 0)
    #expect(input.accessibilityIdentifier == nil)
}
