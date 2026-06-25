import Testing
@testable import iOSExploreServer

@Test("CommandInputDecoder 读取默认值、必填和值类型")
func commandInputDecoderReadsFields() throws {
    let name = CommandFields.requiredString("name", description: "名字")
    let enabled = CommandFields.bool("enabled", default: true, description: "启用")
    let schema = CommandInputSchema(fields: [name.erased, enabled.erased])
    let decoder = CommandInputDecoder(["name": "Ada"], schema: schema)
    try decoder.validateNoUnknownFields()

    #expect(try decoder.read(name) == "Ada")
    #expect(try decoder.read(enabled) == true)
}

@Test("CommandInputDecoder 拒绝未知字段和未声明字段读取")
func commandInputDecoderRejectsUnknownAndUndeclaredFields() throws {
    let declared = CommandFields.optionalString("declared", description: "声明字段")
    let undeclared = CommandFields.optionalString("other", description: "未声明字段")
    let schema = CommandInputSchema(fields: [declared.erased])

    let unknownDecoder = CommandInputDecoder(["unexpected": "x"], schema: schema)
    #expect(throws: CommandInputParseError.self) {
        try unknownDecoder.validateNoUnknownFields()
    }

    let decoder = CommandInputDecoder([:], schema: schema)
    #expect(throws: CommandInputParseError.self) {
        _ = try decoder.read(undeclared)
    }
}

@Test("CommandInputDecoder 拒绝同名但 schema 不一致的字段读取")
func commandInputDecoderRejectsSchemaMismatchForSameName() throws {
    let declared = CommandFields.optionalString("value", description: "字符串值")
    let mismatched = CommandFields.int("value", range: 1...10, default: 3, description: "整数值")
    let schema = CommandInputSchema(fields: [declared.erased])
    let decoder = CommandInputDecoder(["value": 5], schema: schema)

    #expect(throws: CommandInputParseError.self) {
        _ = try decoder.read(mismatched)
    }
}

@Test("CommandInputDecoder 校验 finite number integer enum")
func commandInputDecoderValidatesNumberIntegerEnum() throws {
    enum Mode: String, CaseIterable, Sendable { case window }

    let x = CommandFields.optionalFiniteNumber("x", description: "x 坐标")
    let count = CommandFields.int("count", range: 1...3, default: 2, description: "数量")
    let mode = CommandFields.enumValue("mode", type: Mode.self, default: .window, description: "模式")
    let schema = CommandInputSchema(fields: [x.erased, count.erased, mode.erased])

    let ok = CommandInputDecoder(["x": 3.5, "count": 3, "mode": "window"], schema: schema)
    #expect(try ok.read(x) == 3.5)
    #expect(try ok.read(count) == 3)
    #expect(try ok.read(mode) == .window)

    let nonInteger = CommandInputDecoder(["count": 1.5], schema: schema)
    #expect(throws: CommandInputParseError.self) { _ = try nonInteger.read(count) }

    let outOfRange = CommandInputDecoder(["count": 4], schema: schema)
    #expect(throws: CommandInputParseError.self) { _ = try outOfRange.read(count) }

    let badEnum = CommandInputDecoder(["mode": "screen"], schema: schema)
    #expect(throws: CommandInputParseError.self) { _ = try badEnum.read(mode) }
}

@Test("CommandInputDecoder 默认值字段拒绝显式 null")
func commandInputDecoderRejectsNullForDefaultBackedFields() throws {
    enum Mode: String, CaseIterable, Sendable { case window }

    let enabled = CommandFields.bool("enabled", default: true, description: "启用")
    let count = CommandFields.int("count", range: 1...3, default: 2, description: "数量")
    let mode = CommandFields.enumValue("mode", type: Mode.self, default: .window, description: "模式")
    let schema = CommandInputSchema(fields: [enabled.erased, count.erased, mode.erased])

    let nullBool = CommandInputDecoder(["enabled": nil], schema: schema)
    #expect(throws: CommandInputParseError.self) { _ = try nullBool.read(enabled) }

    let nullInt = CommandInputDecoder(["count": nil], schema: schema)
    #expect(throws: CommandInputParseError.self) { _ = try nullInt.read(count) }

    let nullEnum = CommandInputDecoder(["mode": nil], schema: schema)
    #expect(throws: CommandInputParseError.self) { _ = try nullEnum.read(mode) }
}

@Test("CommandInputDecoder 拒绝超过 JSON safe integer 的整数")
func commandInputDecoderRejectsUnsafeIntegerValue() throws {
    let count = CommandFields.int("count", range: 0...Int.max, default: 0, description: "数量")
    let limit = CommandFields.optionalNonNegativeInt("limit", description: "限制")
    let schema = CommandInputSchema(fields: [count.erased, limit.erased])
    let decoder = CommandInputDecoder(["count": 9_007_199_254_740_992], schema: schema)

    #expect(throws: CommandInputParseError.self) {
        _ = try decoder.read(count)
    }

    let optionalDecoder = CommandInputDecoder(["limit": 9_007_199_254_740_992], schema: schema)
    #expect(throws: CommandInputParseError.self) {
        _ = try optionalDecoder.read(limit)
    }
}

@Test("CommandFields.int 合法默认值同步用于 schema 和运行时")
func commandFieldsIntAcceptsDefaultInsideRange() throws {
    let count = CommandFields.int("count", range: 1...3, default: 2, description: "数量")
    let schema = CommandInputSchema(fields: [count.erased])
    let decoder = CommandInputDecoder([:], schema: schema)

    #expect(try decoder.read(count) == 2)
    guard case .object(let properties)? = schema.toJSON()["properties"],
          case .object(let countSchema)? = properties["count"] else {
        Issue.record("count schema missing")
        return
    }
    #expect(countSchema["default"]?.doubleValue == 2)
    #expect(countSchema["minimum"]?.doubleValue == 1)
    #expect(countSchema["maximum"]?.doubleValue == 3)
}
