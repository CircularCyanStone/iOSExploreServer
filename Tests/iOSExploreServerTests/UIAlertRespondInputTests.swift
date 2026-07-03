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

@Test("alert respond 拒绝 buttonTitle 与 role 同时提供")
func alertRespondRejectsTitleAndRole() {
    #expect(throws: Error.self) {
        try UIAlertRespondInput.parse(from: ["buttonTitle": "确定", "role": "default"])
    }
}

@Test("alert respond 拒绝 buttonIndex 与 role 同时提供")
func alertRespondRejectsIndexAndRole() {
    #expect(throws: Error.self) {
        try UIAlertRespondInput.parse(from: ["buttonIndex": 0, "role": "cancel"])
    }
}

@Test("alert respond 拒绝三个 selector 同时提供")
func alertRespondRejectsAllThreeSelectors() {
    #expect(throws: Error.self) {
        try UIAlertRespondInput.parse(from: ["buttonTitle": "确定", "buttonIndex": 0, "role": "default"])
    }
}

@Test("alert respond 接受单独 buttonIndex")
func alertRespondAcceptsSingleIndex() throws {
    let input = try UIAlertRespondInput.parse(from: ["buttonIndex": 1])
    #expect(input.buttonIndex == 1)
    #expect(input.buttonTitle == nil)
    #expect(input.role == nil)
}

@Test("alert respond 接受单独 role")
func alertRespondAcceptsSingleRole() throws {
    let input = try UIAlertRespondInput.parse(from: ["role": "destructive"])
    #expect(input.role == "destructive")
    #expect(input.buttonTitle == nil)
    #expect(input.buttonIndex == nil)
}
