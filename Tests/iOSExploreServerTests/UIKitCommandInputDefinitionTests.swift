#if canImport(UIKit)
import Testing
@testable import iOSExploreServer
@testable import iOSExploreUIKit

@Test("ui.inspect 命令使用 generated input definition 字段")
func inspectCommandDefinitionMatchesInputFields() {
    #expect(InspectCommand.Input.inputDefinition.fields.map(\.name) == UIInspectInput.inputDefinition.fields.map(\.name))
}

@Test("ui.topViewHierarchy 命令使用 generated input definition 字段")
func topViewHierarchyCommandDefinitionMatchesInputFields() {
    #expect(TopViewHierarchyCommand.Input.inputDefinition.fields.map(\.name) == UIViewHierarchyInput.inputDefinition.fields.map(\.name))
}

@Test("ui.control.sendAction 命令使用 generated input definition 字段")
func controlSendActionCommandDefinitionMatchesInputFields() {
    #expect(UIControlSendActionCommand.Input.inputDefinition.fields.map(\.name) == UIControlSendActionInput.inputDefinition.fields.map(\.name))
}

@Test("ui.tap 命令使用 generated input definition 字段")
func tapCommandDefinitionMatchesInputFields() {
    #expect(UITapCommand.Input.inputDefinition.fields.map(\.name) == UITapInput.inputDefinition.fields.map(\.name))
}

@Test("ui.keyboard.dismiss 命令使用 generated input definition 字段")
func keyboardDismissCommandDefinitionMatchesInputFields() {
    #expect(KeyboardDismissCommand.Input.inputDefinition.fields.map(\.name) == UIKeyboardDismissInput.inputDefinition.fields.map(\.name))
}

@Test("ui.navigation.back 命令使用 generated input definition 字段")
func navigationBackCommandDefinitionMatchesInputFields() {
    #expect(NavigationBackCommand.Input.inputDefinition.fields.map(\.name) == UINavigationBackInput.inputDefinition.fields.map(\.name))
}

@Test("ui.navigation.tapBarButton 命令使用 generated input definition 字段")
func navigationBarButtonCommandDefinitionMatchesInputFields() {
    #expect(NavigationBarButtonCommand.Input.inputDefinition.fields.map(\.name) == UINavigationBarButtonInput.inputDefinition.fields.map(\.name))
}

@Test("ui.wait 命令使用 generated input definition 字段")
func waitCommandDefinitionMatchesInputFields() {
    #expect(WaitCommand.Input.inputDefinition.fields.map(\.name) == UIWaitInput.inputDefinition.fields.map(\.name))
}

@Test("ui.scrollToElement 命令使用 generated input definition 字段")
func scrollToElementCommandDefinitionMatchesInputFields() {
    #expect(ScrollToElementCommand.Input.inputDefinition.fields.map(\.name) == UIScrollToElementInput.inputDefinition.fields.map(\.name))
}

@Test("ui.alert.respond 命令使用 generated input definition 字段")
func alertRespondCommandDefinitionMatchesInputFields() {
    #expect(AlertRespondCommand.Input.inputDefinition.fields.map(\.name) == UIAlertRespondInput.inputDefinition.fields.map(\.name))
}

@Test("ui.waitAny 命令使用 generated input definition 字段")
func waitAnyCommandDefinitionMatchesInputFields() {
    #expect(WaitAnyCommand.Input.inputDefinition.fields.map(\.name) == UIWaitAnyInput.inputDefinition.fields.map(\.name))
}

@Test("ui.controllers 命令使用 generated input definition 字段")
func controllersCommandDefinitionMatchesInputFields() {
    #expect(ControllersCommand.Input.inputDefinition.fields.map(\.name) == UIControllersInput.inputDefinition.fields.map(\.name))
}

@Test("ui.swipe 命令使用 generated input definition 字段")
func swipeCommandDefinitionMatchesInputFields() {
    #expect(SwipeCommand.Input.inputDefinition.fields.map(\.name) == UISwipeInput.inputDefinition.fields.map(\.name))
}

@Test("ui.longPress 命令使用 generated input definition 字段")
func longPressCommandDefinitionMatchesInputFields() {
    #expect(LongPressCommand.Input.inputDefinition.fields.map(\.name) == UILongPressInput.inputDefinition.fields.map(\.name))
}

@Test("ui.longPress duration 超过 10 秒上限被拒绝为 invalid_data")
func longPressDurationUpperLimitRejected() {
    var decoder = CommandInputDecoder(JSON(["duration": 100.0]), definition: UILongPressInput.inputDefinition)
    #expect(throws: CommandInputParseError.self) {
        try UILongPressInput.parse(decoding: &decoder)
    }
}

@Test("ui.longPress duration=10 边界合法，duration>10 非法")
func longPressDurationBoundary() throws {
    // 10.0 是闭区间上界，合法
    var atBoundary = CommandInputDecoder(JSON(["duration": 10.0]), definition: UILongPressInput.inputDefinition)
    let boundaryInput = try UILongPressInput.parse(decoding: &atBoundary)
    #expect(boundaryInput.duration == 10.0)

    // 略超上界即拒绝
    var overBoundary = CommandInputDecoder(JSON(["duration": 10.1]), definition: UILongPressInput.inputDefinition)
    #expect(throws: CommandInputParseError.self) {
        try UILongPressInput.parse(decoding: &overBoundary)
    }
}

@Test("ui.longPress duration<=0 仍被拒绝（回归保护）")
func longPressDurationNonPositiveRejected() {
    var zeroDecoder = CommandInputDecoder(JSON(["duration": 0.0]), definition: UILongPressInput.inputDefinition)
    #expect(throws: CommandInputParseError.self) {
        try UILongPressInput.parse(decoding: &zeroDecoder)
    }
    var negativeDecoder = CommandInputDecoder(JSON(["duration": -1.0]), definition: UILongPressInput.inputDefinition)
    #expect(throws: CommandInputParseError.self) {
        try UILongPressInput.parse(decoding: &negativeDecoder)
    }
}

@Test("ui.input 命令 description 来自 generated contract")
func inputCommandDescriptionMatchesContract() {
    #expect(InputCommand().description == UIKitActionContracts.uiInputContract.description)
}
#endif
