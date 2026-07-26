import Testing
@testable import iOSExploreServer

@Test("CommandInputDecoder 读取默认值、必填和值类型")
func commandInputDecoderReadsFields() throws {
    let name = CommandFields.requiredString("name")
    let enabled = CommandFields.bool("enabled", default: true)
    let definition = CommandInputDefinition(fields: [name.erased, enabled.erased])
    var decoder = try definition.makeDecoder(for: ["name": "Ada"])

    #expect(try decoder.read(name) == "Ada")
    #expect(try decoder.read(enabled) == true)
}

@Test("CommandInputDecoder 原样读取类型擦除字段")
func commandInputDecoderReadsRawField() throws {
    let payload = AnyCommandField(name: "payload")
    let definition = CommandInputDefinition(fields: [payload])
    var decoder = try definition.makeDecoder(for: ["payload": .object(["nested": .string("value")])])

    #expect(try decoder.readRaw(payload) == .object(["nested": .string("value")]))
    try decoder.assertAllDeclaredFieldsRead()
}

@Test("CommandInputDecoder 拒绝未知字段和未声明字段读取")
func commandInputDecoderRejectsUnknownAndUndeclaredFields() throws {
    let declared = CommandFields.optionalString("declared")
    let undeclared = CommandFields.optionalString("other")
    let definition = CommandInputDefinition(fields: [declared.erased])

    #expect(throws: CommandInputParseError.self) {
        _ = try definition.makeDecoder(for: ["unexpected": "x"])
    }

    var decoder = CommandInputDecoder([:], definition: definition)
    #expect(throws: CommandInputParseError.self) {
        _ = try decoder.read(undeclared)
    }
}

@Test("CommandInputDecoder 校验 finite number integer enum")
func commandInputDecoderValidatesNumberIntegerEnum() throws {
    enum Mode: String, CaseIterable, Sendable { case window }

    let x = CommandFields.optionalFiniteNumber("x")
    let count = CommandFields.int("count", range: 1...3, default: 2)
    let mode = CommandFields.enumValue("mode", type: Mode.self, default: .window)
    let definition = CommandInputDefinition(fields: [x.erased, count.erased, mode.erased])

    var ok = CommandInputDecoder(["x": 3.5, "count": 3, "mode": "window"], definition: definition)
    #expect(try ok.read(x) == 3.5)
    #expect(try ok.read(count) == 3)
    #expect(try ok.read(mode) == .window)

    var nonInteger = CommandInputDecoder(["count": 1.5], definition: definition)
    #expect(throws: CommandInputParseError.self) { _ = try nonInteger.read(count) }

    var outOfRange = CommandInputDecoder(["count": 4], definition: definition)
    #expect(throws: CommandInputParseError.self) { _ = try outOfRange.read(count) }

    var badEnum = CommandInputDecoder(["mode": "screen"], definition: definition)
    #expect(throws: CommandInputParseError.self) { _ = try badEnum.read(mode) }
}

@Test("CommandInputDecoder 默认值字段只在缺失时使用默认值并拒绝显式 null")
func commandInputDecoderRejectsNullForNonNullableDefaultBackedFields() throws {
    enum Mode: String, CaseIterable, Sendable { case window }

    let enabled = CommandFields.bool("enabled", default: true)
    let count = CommandFields.int("count", range: 1...3, default: 2)
    let mode = CommandFields.enumValue("mode", type: Mode.self, default: .window)
    let definition = CommandInputDefinition(fields: [enabled.erased, count.erased, mode.erased])

    var missing = CommandInputDecoder([:], definition: definition)
    #expect(try missing.read(enabled) == true)
    #expect(try missing.read(count) == 2)
    #expect(try missing.read(mode) == .window)

    var nullBool = CommandInputDecoder(["enabled": nil], definition: definition)
    #expect(throws: CommandInputParseError.self) { _ = try nullBool.read(enabled) }

    var nullInt = CommandInputDecoder(["count": nil], definition: definition)
    #expect(throws: CommandInputParseError.self) { _ = try nullInt.read(count) }

    var nullEnum = CommandInputDecoder(["mode": nil], definition: definition)
    #expect(throws: CommandInputParseError.self) { _ = try nullEnum.read(mode) }
}

@Test("CommandInputDecoder 拒绝超过 JSON safe integer 的整数")
func commandInputDecoderRejectsUnsafeIntegerValue() throws {
    let count = CommandFields.int("count", range: 0...Int.max, default: 0)
    let limit = CommandFields.optionalNonNegativeInt("limit")
    let definition = CommandInputDefinition(fields: [count.erased, limit.erased])

    var decoder = CommandInputDecoder(["count": 9_007_199_254_740_992], definition: definition)
    #expect(throws: CommandInputParseError.self) {
        _ = try decoder.read(count)
    }

    var optionalDecoder = CommandInputDecoder(["limit": 9_007_199_254_740_992], definition: definition)
    #expect(throws: CommandInputParseError.self) {
        _ = try optionalDecoder.read(limit)
    }
}

@Test("CommandFields.int 合法默认值用于运行时转换")
func commandFieldsIntAcceptsDefaultInsideRange() throws {
    let count = CommandFields.int("count", range: 1...3, default: 2)
    let definition = CommandInputDefinition(fields: [count.erased])
    var decoder = CommandInputDecoder([:], definition: definition)

    #expect(try decoder.read(count) == 2)
}

@Test("CommandInputDecoder 全部声明字段读取后通过守卫")
func commandInputDecoderPassesWhenAllDeclaredFieldsRead() throws {
    let a = CommandFields.optionalString("a")
    let b = CommandFields.int("b", range: 1...3, default: 2)
    let definition = CommandInputDefinition(fields: [a.erased, b.erased])
    var decoder = CommandInputDecoder(["a": "x", "b": 2], definition: definition)
    _ = try decoder.read(a)
    _ = try decoder.read(b)
    // 全部声明字段都已读取,守卫不应抛错。
    try decoder.assertAllDeclaredFieldsRead()
}

@Test("CommandInputDecoder 存在声明但未读取字段时守卫抛错")
func commandInputDecoderFailsWhenDeclaredFieldNotRead() throws {
    let a = CommandFields.optionalString("a")
    let b = CommandFields.optionalString("b")
    let definition = CommandInputDefinition(fields: [a.erased, b.erased])
    var decoder = CommandInputDecoder(["a": "x"], definition: definition)
    _ = try decoder.read(a)
    // 故意不读 b,模拟“声明了但 parse 没读”的漂移。
    #expect(throws: CommandInputParseError.self) {
        try decoder.assertAllDeclaredFieldsRead()
    }
}

@Test("CommandInput.parse 守卫:声明字段未读取则整体解析失败")
func commandInputParseFailsWhenDeclaredFieldNotRead() throws {
    struct PartialInput: CommandInput, Equatable {
        static let a = CommandFields.optionalString("a")
        static let b = CommandFields.optionalString("b")
        static let inputDefinition = CommandInputDefinition(fields: [a.erased, b.erased])
        let a: String?

        static func parse(decoding decoder: inout CommandInputDecoder) throws -> PartialInput {
            // 故意只读 a,漏读 b。默认 parse(from:) 入口的守卫必须捕获这种漂移。
            PartialInput(a: try decoder.read(a))
        }
    }

    #expect(throws: CommandInputParseError.self) {
        _ = try PartialInput.parse(from: ["a": "x", "b": "y"])
    }
}
