import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

@Test("keyboard dismiss 默认 auto 和 waitAfterMs")
func keyboardDismissDefaults() throws {
    let input = try UIKeyboardDismissInput.parse(from: [:])
    #expect(input.strategy == .auto)
    #expect(input.waitAfterMs == 200)
}

@Test("keyboard dismiss 拒绝非法 strategy")
func keyboardDismissRejectsInvalidStrategy() {
    #expect(throws: Error.self) {
        try UIKeyboardDismissInput.parse(from: ["strategy": "force"])
    }
}

@Test("keyboard dismiss 限制 waitAfterMs 范围")
func keyboardDismissRejectsInvalidWait() {
    #expect(throws: Error.self) {
        try UIKeyboardDismissInput.parse(from: ["waitAfterMs": 3001])
    }
}
