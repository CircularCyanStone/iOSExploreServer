#if canImport(UIKit)
import Testing
@testable import iOSExploreServer
@testable import iOSExploreUIKit

@Test("ui.inspect 命令 schema 声明 typed input 字段")
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

@Test("ui.navigation.tapBarButton 命令 schema 声明 typed input 字段")
func navigationBarButtonCommandSchemaMatchesInputFields() {
    #expect(NavigationBarButtonCommand.Input.inputSchema.fields.map(\.name) == UINavigationBarButtonInput.inputSchema.fields.map(\.name))
}

@Test("ui.wait 命令 schema 声明 typed input 字段")
func waitCommandSchemaMatchesInputFields() {
    #expect(WaitCommand.Input.inputSchema.fields.map(\.name) == UIWaitInput.inputSchema.fields.map(\.name))
}

@Test("ui.scrollToElement 命令 schema 声明 typed input 字段")
func scrollToElementCommandSchemaMatchesInputFields() {
    #expect(ScrollToElementCommand.Input.inputSchema.fields.map(\.name) == UIScrollToElementInput.inputSchema.fields.map(\.name))
}

@Test("ui.alert.respond 命令 schema 声明 typed input 字段")
func alertRespondCommandSchemaMatchesInputFields() {
    #expect(AlertRespondCommand.Input.inputSchema.fields.map(\.name) == UIAlertRespondInput.inputSchema.fields.map(\.name))
}

@Test("ui.waitAny 命令 schema 声明 typed input 字段")
func waitAnyCommandSchemaMatchesInputFields() {
    #expect(WaitAnyCommand.Input.inputSchema.fields.map(\.name) == UIWaitAnyInput.inputSchema.fields.map(\.name))
}

@Test("ui.controllers 命令 schema 声明 typed input 字段")
func controllersCommandSchemaMatchesInputFields() {
    #expect(ControllersCommand.Input.inputSchema.fields.map(\.name) == UIControllersInput.inputSchema.fields.map(\.name))
}

@Test("ui.input 命令 description 写明 viewSnapshotID 只与 path 搭配")
func inputCommandDescriptionExplainsViewSnapshotPathOnly() {
    let description = InputCommand().description
    #expect(description.contains("accessibilityIdentifier 或 path"))
    #expect(description.contains("viewSnapshotID 仅允许与 path 搭配"))
    #expect(description.contains("identifier 定位不能带 viewSnapshotID"))
    #expect(description.contains("必须先调 ui.inspect") == false)
}
#endif
