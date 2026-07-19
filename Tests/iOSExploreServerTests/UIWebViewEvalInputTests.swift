import Testing
import Foundation
import iOSExploreServer
@testable import iOSExploreUIKit

#if canImport(UIKit)

@Test("解析 script 模式")
func webViewEvalInputParsesScript() throws {
    let input = try UIWebViewEvalInput.parse(from: [
        "accessibilityIdentifier": .string("web_container"),
        "script": .string("document.title")
    ])
    #expect(input.target == .accessibilityIdentifier("web_container"))
    #expect(input.script == "document.title")
    #expect(input.function == nil)
    #expect(input.timeout == 5.0)
}

@Test("解析 function 模式")
func webViewEvalInputParsesFunction() throws {
    let input = try UIWebViewEvalInput.parse(from: [
        "path": .string("root/0/1"),
        "function": .string("return await fetch('/api/user')")
    ])
    #expect(input.target == .path([0, 1]))
    #expect(input.function == "return await fetch('/api/user')")
    #expect(input.script == nil)
}

@Test("解析 arguments")
func webViewEvalInputParsesArguments() throws {
    let input = try UIWebViewEvalInput.parse(from: [
        "accessibilityIdentifier": .string("web"),
        "function": .string("return arguments[0].userId"),
        "arguments": .object(["userId": .double(123)])
    ])
    #expect(input.arguments?["userId"] as? Double == 123)
}

@Test("解析自定义 timeout")
func webViewEvalInputParsesTimeout() throws {
    let input = try UIWebViewEvalInput.parse(from: [
        "accessibilityIdentifier": .string("web"),
        "script": .string("true"),
        "timeout": .double(10)
    ])
    #expect(input.timeout == 10.0)
}

@Test("拒绝 script 与 function 同时提供")
func webViewEvalInputRejectsBothScriptAndFunction() {
    #expect(throws: CommandInputParseError.self) {
        _ = try UIWebViewEvalInput.parse(from: [
            "accessibilityIdentifier": .string("web"),
            "script": .string("true"),
            "function": .string("return true")
        ])
    }
}

@Test("拒绝 script 与 function 都不提供")
func webViewEvalInputRejectsNeitherScriptNorFunction() {
    #expect(throws: CommandInputParseError.self) {
        _ = try UIWebViewEvalInput.parse(from: [
            "accessibilityIdentifier": .string("web")
        ])
    }
}

@Test("拒绝 arguments 没有 function")
func webViewEvalInputRejectsArgumentsWithoutFunction() {
    #expect(throws: CommandInputParseError.self) {
        _ = try UIWebViewEvalInput.parse(from: [
            "accessibilityIdentifier": .string("web"),
            "script": .string("true"),
            "arguments": .object(["key": .string("value")])
        ])
    }
}

@Test("拒绝 timeout 超出范围")
func webViewEvalInputRejectsInvalidTimeout() {
    #expect(throws: CommandInputParseError.self) {
        _ = try UIWebViewEvalInput.parse(from: [
            "accessibilityIdentifier": .string("web"),
            "script": .string("true"),
            "timeout": .double(0)
        ])
    }
    #expect(throws: CommandInputParseError.self) {
        _ = try UIWebViewEvalInput.parse(from: [
            "accessibilityIdentifier": .string("web"),
            "script": .string("true"),
            "timeout": .double(31)
        ])
    }
}

@Test("schema 声明全部字段")
func webViewEvalInputSchemaFields() {
    let fields = UIWebViewEvalInput.inputSchema.fields.map(\.name)
    #expect(fields.contains("accessibilityIdentifier"))
    #expect(fields.contains("path"))
    #expect(fields.contains("viewSnapshotID"))
    #expect(fields.contains("script"))
    #expect(fields.contains("function"))
    #expect(fields.contains("arguments"))
    #expect(fields.contains("timeout"))
}

#endif
