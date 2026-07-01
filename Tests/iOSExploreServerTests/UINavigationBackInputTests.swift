import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

@Test("navigation back 默认 auto animated false waitAfterMs 300")
func navigationBackDefaults() throws {
    let input = try UINavigationBackInput.parse(from: [:])
    #expect(input.strategy == .auto)
    #expect(input.animated == false)
    #expect(input.waitAfterMs == 300)
}

@Test("navigation back 拒绝非法 waitAfterMs")
func navigationBackRejectsWaitAfterOutOfRange() {
    #expect(throws: Error.self) {
        try UINavigationBackInput.parse(from: ["waitAfterMs": -1])
    }
}

@Test("navigation back 拒绝非法 strategy")
func navigationBackRejectsInvalidStrategy() {
    #expect(throws: Error.self) {
        try UINavigationBackInput.parse(from: ["strategy": "sideways"])
    }
}
