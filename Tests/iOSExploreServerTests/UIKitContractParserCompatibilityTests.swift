import Foundation
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

@Suite("UIKitContractParserCompatibilityTests")
struct UIKitContractParserCompatibilityTests {
    private struct InputExpectation {
        let action: String
        let inputDefinition: CommandInputDefinition
    }

    @Test("Foundation-only UIKit Input 使用对应的 generated definition")
    func foundationInputsMatchGeneratedContracts() throws {
        let expectations = [
            InputExpectation(action: "ui.alert.respond", inputDefinition: UIAlertRespondInput.inputDefinition),
            InputExpectation(action: "ui.control.sendAction", inputDefinition: UIControlSendActionInput.inputDefinition),
            InputExpectation(action: "ui.controllers", inputDefinition: UIControllersInput.inputDefinition),
            InputExpectation(action: "ui.input", inputDefinition: UIInputInput.inputDefinition),
            InputExpectation(action: "ui.inspect", inputDefinition: UIInspectInput.inputDefinition),
            InputExpectation(action: "ui.keyboard.dismiss", inputDefinition: UIKeyboardDismissInput.inputDefinition),
            InputExpectation(action: "ui.longPress", inputDefinition: UILongPressInput.inputDefinition),
            InputExpectation(action: "ui.navigation.back", inputDefinition: UINavigationBackInput.inputDefinition),
            InputExpectation(action: "ui.navigation.tapBarButton", inputDefinition: UINavigationBarButtonInput.inputDefinition),
            InputExpectation(action: "ui.screenshot", inputDefinition: UIScreenshotInput.inputDefinition),
            InputExpectation(action: "ui.scroll", inputDefinition: UIScrollInput.inputDefinition),
            InputExpectation(action: "ui.scrollToElement", inputDefinition: UIScrollToElementInput.inputDefinition),
            InputExpectation(action: "ui.swipe", inputDefinition: UISwipeInput.inputDefinition),
            InputExpectation(action: "ui.tap", inputDefinition: UITapInput.inputDefinition),
            InputExpectation(action: "ui.topViewHierarchy", inputDefinition: UIViewHierarchyInput.inputDefinition),
            InputExpectation(action: "ui.wait", inputDefinition: UIWaitInput.inputDefinition),
            InputExpectation(action: "ui.waitAny", inputDefinition: UIWaitAnyInput.inputDefinition),
        ]

        try assertInputsMatchGenerated(expectations)
    }

    @Test("ui.input 拒绝空 fields 数组")
    func inputRejectsEmptyFields() {
        #expect(throws: CommandInputParseError.self) {
            try UIInputInput.parse(from: ["fields": .array([])])
        }
    }

    @Test("UIInputField 只使用 generated item definition 与字段")
    func inputFieldUsesGeneratedItemContract() throws {
        #expect(UIInputField.inputDefinition.fields.map(\.name) == [
            "accessibilityIdentifier", "path", "text", "mode", "submit",
        ])

        let input = try UIInputField.parse(from: [
            "path": .string("root/0"),
            "text": .string("hello"),
        ])
        #expect(input.target == .path([0]))
        #expect(input.mode == .replace)
        #expect(input.submit == false)
    }

    @Test("UIInputField 保留 generated enum、未知字段和 locator 约束")
    func inputFieldPreservesGeneratedValidation() {
        #expect(throws: CommandInputParseError.self) {
            try UIInputField.parse(from: [
                "path": .string("root/0"),
                "text": .string("hello"),
                "mode": .string("unknown"),
            ])
        }
        #expect(throws: CommandInputParseError.self) {
            try UIInputField.parse(from: [
                "path": .string("root/0"),
                "text": .string("hello"),
                "unexpected": .bool(true),
            ])
        }
        #expect(throws: CommandInputParseError.self) {
            try UIInputField.parse(from: [
                "accessibilityIdentifier": .string("field"),
                "path": .string("root/0"),
                "text": .string("hello"),
            ])
        }
        #expect(throws: CommandInputParseError.self) {
            try UIInputField.parse(from: [
                "text": .string("hello"),
            ])
        }
    }

    @Test("ui.waitAny 拒绝空 conditions 数组")
    func waitAnyRejectsEmptyConditions() {
        #expect(throws: CommandInputParseError.self) {
            try UIWaitAnyInput.parse(from: ["conditions": .array([])])
        }
    }

#if canImport(UIKit)
    @Test("UIKit-only Input 使用对应的 generated definition")
    func uikitOnlyInputsMatchGeneratedContracts() throws {
        let expectations = [
            InputExpectation(action: "ui.datePicker.setDate", inputDefinition: UIDatePickerSetDateInput.inputDefinition),
            InputExpectation(action: "ui.picker.selectRow", inputDefinition: UIPickerSelectRowInput.inputDefinition),
            InputExpectation(action: "ui.tabBar.selectTab", inputDefinition: UITabBarSelectInput.inputDefinition),
            InputExpectation(action: "ui.webView.eval", inputDefinition: UIWebViewEvalInput.inputDefinition),
        ]

        try assertInputsMatchGenerated(expectations)
    }

    @Test("ui.datePicker.setDate 接受 ISO 8601 date")
    func datePickerAcceptsISO8601Date() throws {
        let input = try UIDatePickerSetDateInput.parse(from: [
            "path": .string("root/0/1"),
            "date": .string("2026-07-24T10:00:00Z"),
        ])

        #expect(input.target == .path([0, 1]))
        #expect(input.date != nil)
        #expect(input.components == nil)
    }

    @Test("ui.webView.eval 保留 script/function 模式约束")
    func webViewPreservesScriptFunctionConstraints() throws {
        let scriptInput = try UIWebViewEvalInput.parse(from: [
            "accessibilityIdentifier": .string("web"),
            "script": .string("document.title"),
        ])
        #expect(scriptInput.script == "document.title")
        #expect(scriptInput.function == nil)

        let functionInput = try UIWebViewEvalInput.parse(from: [
            "path": .string("root/0"),
            "function": .string("return arguments[0].value"),
            "arguments": .object(["value": .string("ok")]),
        ])
        #expect(functionInput.script == nil)
        #expect(functionInput.function == "return arguments[0].value")

        #expect(throws: CommandInputParseError.self) {
            try UIWebViewEvalInput.parse(from: [
                "accessibilityIdentifier": .string("web"),
                "script": .string("document.title"),
                "function": .string("return document.title"),
            ])
        }
    }
#endif

    private func assertInputsMatchGenerated(_ expectations: [InputExpectation]) throws {
        for expectation in expectations {
            let generated = try #require(UIKitActionContracts.inputs[expectation.action])
            #expect(expectation.inputDefinition.fields.map(\.name) == generated.fields.map(\.name))
            #expect(expectation.inputDefinition.additionalProperties == generated.additionalProperties)
        }
    }
}
