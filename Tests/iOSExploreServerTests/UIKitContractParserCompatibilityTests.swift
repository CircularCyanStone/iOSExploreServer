import Foundation
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

@Suite("UIKitContractParserCompatibilityTests")
struct UIKitContractParserCompatibilityTests {
    private struct SchemaExpectation {
        let action: String
        let inputSchema: CommandInputSchema
    }

    @Test("Foundation-only UIKit Input 使用对应的 generated schema")
    func foundationInputSchemasMatchGeneratedContracts() throws {
        let expectations = [
            SchemaExpectation(action: "ui.alert.respond", inputSchema: UIAlertRespondInput.inputSchema),
            SchemaExpectation(action: "ui.control.sendAction", inputSchema: UIControlSendActionInput.inputSchema),
            SchemaExpectation(action: "ui.controllers", inputSchema: UIControllersInput.inputSchema),
            SchemaExpectation(action: "ui.input", inputSchema: UIInputInput.inputSchema),
            SchemaExpectation(action: "ui.inspect", inputSchema: UIInspectInput.inputSchema),
            SchemaExpectation(action: "ui.keyboard.dismiss", inputSchema: UIKeyboardDismissInput.inputSchema),
            SchemaExpectation(action: "ui.longPress", inputSchema: UILongPressInput.inputSchema),
            SchemaExpectation(action: "ui.navigation.back", inputSchema: UINavigationBackInput.inputSchema),
            SchemaExpectation(action: "ui.navigation.tapBarButton", inputSchema: UINavigationBarButtonInput.inputSchema),
            SchemaExpectation(action: "ui.screenshot", inputSchema: UIScreenshotInput.inputSchema),
            SchemaExpectation(action: "ui.scroll", inputSchema: UIScrollInput.inputSchema),
            SchemaExpectation(action: "ui.scrollToElement", inputSchema: UIScrollToElementInput.inputSchema),
            SchemaExpectation(action: "ui.swipe", inputSchema: UISwipeInput.inputSchema),
            SchemaExpectation(action: "ui.tap", inputSchema: UITapInput.inputSchema),
            SchemaExpectation(action: "ui.topViewHierarchy", inputSchema: UIViewHierarchyInput.inputSchema),
            SchemaExpectation(action: "ui.wait", inputSchema: UIWaitInput.inputSchema),
            SchemaExpectation(action: "ui.waitAny", inputSchema: UIWaitAnyInput.inputSchema),
        ]

        try assertSchemasMatchGenerated(expectations)
    }

    @Test("ui.input 拒绝空 fields 数组")
    func inputRejectsEmptyFields() {
        #expect(throws: CommandInputParseError.self) {
            try UIInputInput.parse(from: ["fields": .array([])])
        }
    }

    @Test("UIInputField 只使用 generated item schema 与字段")
    func inputFieldUsesGeneratedItemContract() throws {
        #expect(UIInputField.inputSchema == UIKitActionContracts.uiInputFieldsItemInputSchema)
        #expect(UIInputField.inputSchema.fields.map(\.name) == [
            "accessibilityIdentifier", "mode", "path", "submit", "text",
        ])

        let topLevelFields = try #require(UIInputInput.inputSchema.toJSON()["properties"]?.objectValue?["fields"]?.objectValue)
        let itemSchema = try #require(topLevelFields["items"]?.objectValue)
        #expect(itemSchema["description"]?.stringValue == "单个字段输入。")
        #expect(itemSchema["x-iosExplore-constraints"]?.objectValue?["note"]?.stringValue?.contains("path 文法") == true)

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
    @Test("UIKit-only Input 使用对应的 generated schema")
    func uikitOnlyInputSchemasMatchGeneratedContracts() throws {
        let expectations = [
            SchemaExpectation(action: "ui.datePicker.setDate", inputSchema: UIDatePickerSetDateInput.inputSchema),
            SchemaExpectation(action: "ui.picker.selectRow", inputSchema: UIPickerSelectRowInput.inputSchema),
            SchemaExpectation(action: "ui.tabBar.selectTab", inputSchema: UITabBarSelectInput.inputSchema),
            SchemaExpectation(action: "ui.webView.eval", inputSchema: UIWebViewEvalInput.inputSchema),
        ]

        try assertSchemasMatchGenerated(expectations)
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

    private func assertSchemasMatchGenerated(_ expectations: [SchemaExpectation]) throws {
        for expectation in expectations {
            let generatedSchema = try #require(UIKitActionContracts.inputSchemas[expectation.action])
            #expect(
                expectation.inputSchema == generatedSchema,
                "\(expectation.action) Input.inputSchema 必须使用对应的 generated schema"
            )
        }
    }
}
