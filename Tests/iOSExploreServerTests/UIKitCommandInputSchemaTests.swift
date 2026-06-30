#if canImport(UIKit)
import Testing
@testable import iOSExploreServer
@testable import iOSExploreUIKit

@Test("ui.viewTargets 命令 schema 声明 typed input 字段")
func viewTargetsCommandSchemaMatchesInputFields() {
    #expect(ViewTargetsCommand.Input.inputSchema.fields.map(\.name) == UIViewTargetsInput.inputSchema.fields.map(\.name))
}

@Test("ui.topViewHierarchy 命令 schema 声明 typed input 字段")
func topViewHierarchyCommandSchemaMatchesInputFields() {
    #expect(TopViewHierarchyCommand.Input.inputSchema.fields.map(\.name) == UIViewHierarchyInput.inputSchema.fields.map(\.name))
}

@Test("ui.control.sendAction 命令 schema 声明 typed input 字段")
func controlSendActionCommandSchemaMatchesInputFields() {
    #expect(UIControlSendActionCommand.Input.inputSchema.fields.map(\.name) == UIControlSendActionInput.inputSchema.fields.map(\.name))
}

@Test("ui.tap 命令 schema 声明 typed input 字段")
func tapCommandSchemaMatchesInputFields() {
    #expect(UITapCommand.Input.inputSchema.fields.map(\.name) == UITapInput.inputSchema.fields.map(\.name))
}

@Test("parseOptional: 都缺 nil；互斥抛错；单 path 解析")
func parseOptionalLocator() throws {
    let schema = CommandInputSchema(fields: [
        UIKitLocatorFields.accessibilityIdentifier.erased,
        UIKitLocatorFields.path.erased,
    ])
    // 都缺 → nil
    var d1 = CommandInputDecoder(JSON([:]), schema: schema)
    #expect(try UIKitLocatorInput.parseOptional(decoder: &d1) == nil)
    // 两者都给 → 互斥抛错
    #expect(throws: CommandInputParseError.self) {
        var d2 = CommandInputDecoder(JSON(["accessibilityIdentifier": "x", "path": "root/0"]), schema: schema)
        _ = try UIKitLocatorInput.parseOptional(decoder: &d2)
    }
    // 单 path → 解析成功
    var d3 = CommandInputDecoder(JSON(["path": "root/0"]), schema: schema)
    let t = try UIKitLocatorInput.parseOptional(decoder: &d3)
    #expect(t != nil)
}
#endif
