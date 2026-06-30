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

@Test("parseOptional: 都缺返回 nil；identifier 或 path 单值解析成功；互斥抛错")
func parseOptionalLocator() throws {
    let schema = CommandInputSchema(fields: [
        UIKitLocatorFields.accessibilityIdentifier.erased,
        UIKitLocatorFields.path.erased,
    ])
    // 都缺 → nil
    var d1 = CommandInputDecoder(JSON([:]), schema: schema)
    #expect(try UIKitLocatorInput.parseOptional(decoder: &d1) == nil)
    // 单 identifier → 解析成功
    var d2 = CommandInputDecoder(JSON(["accessibilityIdentifier": "home.submit"]), schema: schema)
    let identifierTarget = try UIKitLocatorInput.parseOptional(decoder: &d2)
    #expect(identifierTarget == .accessibilityIdentifier("home.submit"))
    // 单 path → 解析成功
    var d3 = CommandInputDecoder(JSON(["path": "root/0"]), schema: schema)
    let pathTarget = try UIKitLocatorInput.parseOptional(decoder: &d3)
    #expect(pathTarget != nil)
    // 两者都给 → 互斥抛错
    #expect(throws: CommandInputParseError.self) {
        var d4 = CommandInputDecoder(JSON(["accessibilityIdentifier": "x", "path": "root/0"]), schema: schema)
        _ = try UIKitLocatorInput.parseOptional(decoder: &d4)
    }
}
