#if canImport(UIKit)
import Testing
@testable import iOSExploreServer
@testable import iOSExploreUIKit

@Test("ui.inspect 命令 schema 声明 typed input 字段")
func inspectCommandSchemaMatchesInputFields() {
    #expect(InspectCommand.Input.inputSchema.fields.map(\.name) == UIInspectInput.inputSchema.fields.map(\.name))
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

@Test("ui.swipe 命令 schema 声明 typed input 字段")
func swipeCommandSchemaMatchesInputFields() {
    #expect(SwipeCommand.Input.inputSchema.fields.map(\.name) == UISwipeInput.inputSchema.fields.map(\.name))
}

@Test("ui.longPress 命令 schema 声明 typed input 字段")
func longPressCommandSchemaMatchesInputFields() {
    #expect(LongPressCommand.Input.inputSchema.fields.map(\.name) == UILongPressInput.inputSchema.fields.map(\.name))
}

@Test("ui.longPress duration 超过 10 秒上限被拒绝为 invalid_data")
func longPressDurationUpperLimitRejected() {
    var decoder = CommandInputDecoder(JSON(["duration": 100.0]), schema: UILongPressInput.inputSchema)
    #expect(throws: CommandInputParseError.self) {
        try UILongPressInput.parse(decoding: &decoder)
    }
}

@Test("ui.longPress duration=10 边界合法，duration>10 非法")
func longPressDurationBoundary() throws {
    // 10.0 是闭区间上界，合法
    var atBoundary = CommandInputDecoder(JSON(["duration": 10.0]), schema: UILongPressInput.inputSchema)
    let boundaryInput = try UILongPressInput.parse(decoding: &atBoundary)
    #expect(boundaryInput.duration == 10.0)

    // 略超上界即拒绝
    var overBoundary = CommandInputDecoder(JSON(["duration": 10.1]), schema: UILongPressInput.inputSchema)
    #expect(throws: CommandInputParseError.self) {
        try UILongPressInput.parse(decoding: &overBoundary)
    }
}

@Test("ui.longPress duration<=0 仍被拒绝（回归保护）")
func longPressDurationNonPositiveRejected() {
    var zeroDecoder = CommandInputDecoder(JSON(["duration": 0.0]), schema: UILongPressInput.inputSchema)
    #expect(throws: CommandInputParseError.self) {
        try UILongPressInput.parse(decoding: &zeroDecoder)
    }
    var negativeDecoder = CommandInputDecoder(JSON(["duration": -1.0]), schema: UILongPressInput.inputSchema)
    #expect(throws: CommandInputParseError.self) {
        try UILongPressInput.parse(decoding: &negativeDecoder)
    }
}

@Test("ui.input 命令 description 写明 fields 批量形态")
func inputCommandDescriptionExplainsBatchShape() {
    let description = InputCommand().description
    #expect(description.contains("fields 数组"))
    #expect(description.contains("单字段输入也必须放进数组"))
    #expect(description.contains("stopOnFailure 默认 true"))
    #expect(description.contains("text 字段必填") == false)
}
#endif
