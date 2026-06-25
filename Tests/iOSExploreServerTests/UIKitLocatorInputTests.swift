import Testing
@testable import iOSExploreServer
@testable import iOSExploreUIKit

@Test("UIKitLocatorInput 从 accessibilityIdentifier 解析定位目标")
func uikitLocatorInputParsesIdentifierTarget() throws {
    let decoder = CommandInputDecoder(
        ["accessibilityIdentifier": "home.submit"],
        schema: CommandInputSchema(fields: [
            UIKitLocatorFields.accessibilityIdentifier.erased,
            UIKitLocatorFields.path.erased,
        ])
    )
    var mutableDecoder = decoder

    let target = try UIKitLocatorInput.parse(decoder: &mutableDecoder)

    #expect(target == .accessibilityIdentifier("home.submit"))
}

@Test("UIKitLocatorInput 将 identifier/path 互斥错误转为 CommandInputParseError")
func uikitLocatorInputRejectsAmbiguousTargetsAsCommandInputError() {
    var decoder = CommandInputDecoder(
        [
            "accessibilityIdentifier": "home.submit",
            "path": "root/0",
        ],
        schema: CommandInputSchema(fields: [
            UIKitLocatorFields.accessibilityIdentifier.erased,
            UIKitLocatorFields.path.erased,
        ])
    )

    #expect(throws: CommandInputParseError.self) {
        try UIKitLocatorInput.parse(decoder: &decoder)
    }
}
