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

@Test("ui.keyboard.dismiss 命令 schema 声明 typed input 字段")
func keyboardDismissCommandSchemaMatchesInputFields() {
    #expect(KeyboardDismissCommand.Input.inputSchema.fields.map(\.name) == UIKeyboardDismissInput.inputSchema.fields.map(\.name))
}

@Test("ui.navigation.back 命令 schema 声明 typed input 字段")
func navigationBackCommandSchemaMatchesInputFields() {
    #expect(NavigationBackCommand.Input.inputSchema.fields.map(\.name) == UINavigationBackInput.inputSchema.fields.map(\.name))
}
#endif
