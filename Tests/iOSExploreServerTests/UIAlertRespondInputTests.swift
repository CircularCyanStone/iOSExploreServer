import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

@Test("alert respond 默认 dryRun true 且无 selector")
func alertRespondDefaults() throws {
    let input = try UIAlertRespondInput.parse(from: [:])
    #expect(input.dryRun == true)
    #expect(input.buttonTitle == nil)
    #expect(input.buttonIndex == nil)
    #expect(input.role == nil)
}

@Test("alert respond 选择器互斥")
func alertRespondRejectsMultipleSelectors() {
    #expect(throws: Error.self) {
        try UIAlertRespondInput.parse(from: ["buttonTitle": "确定", "buttonIndex": 0])
    }
}

@Test("alert respond 接受单个 selector")
func alertRespondAcceptsSingleSelector() throws {
    let input = try UIAlertRespondInput.parse(from: ["buttonTitle": "确定"])
    #expect(input.buttonTitle == "确定")
}
