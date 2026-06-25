import Testing
@testable import iOSExploreServer

@Test("CommandInputDecoder 读取默认值、必填和值类型")
func commandInputDecoderReadsFields() throws {
    let name = CommandFields.requiredString("name", description: "名字")
    let enabled = CommandFields.bool("enabled", default: true, description: "启用")
    let schema = CommandInputSchema(fields: [name.erased, enabled.erased])
    var decoder = CommandInputDecoder(["name": "Ada"], schema: schema)
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

    var decoder = CommandInputDecoder([:], schema: schema)
    #expect(throws: CommandInputParseError.self) {
        _ = try decoder.read(undeclared)
    }
}

@Test("CommandInputDecoder 拒绝同名但 schema 不一致的字段读取")
func commandInputDecoderRejectsSchemaMismatchForSameName() throws {
    let declared = CommandFields.optionalString("value", description: "字符串值")
    let mismatched = CommandFields.int("value", range: 1...10, default: 3, description: "整数值")
    let schema = CommandInputSchema(fields: [declared.erased])
    var decoder = CommandInputDecoder(["value": 5], schema: schema)

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

    var ok = CommandInputDecoder(["x": 3.5, "count": 3, "mode": "window"], schema: schema)
    #expect(try ok.read(x) == 3.5)
    #expect(try ok.read(count) == 3)
    #expect(try ok.read(mode) == .window)

    var nonInteger = CommandInputDecoder(["count": 1.5], schema: schema)
    #expect(throws: CommandInputParseError.self) { _ = try nonInteger.read(count) }

    var outOfRange = CommandInputDecoder(["count": 4], schema: schema)
    #expect(throws: CommandInputParseError.self) { _ = try outOfRange.read(count) }

    var badEnum = CommandInputDecoder(["mode": "screen"], schema: schema)
    #expect(throws: CommandInputParseError.self) { _ = try badEnum.read(mode) }
}

@Test("CommandInputDecoder 默认值字段把显式 null 当作缺失")
func commandInputDecoderTreatsNullAsMissingForDefaultBackedFields() throws {
    enum Mode: String, CaseIterable, Sendable { case window }

    let enabled = CommandFields.bool("enabled", default: true, description: "启用")
    let count = CommandFields.int("count", range: 1...3, default: 2, description: "数量")
    let mode = CommandFields.enumValue("mode", type: Mode.self, default: .window, description: "模式")
    let schema = CommandInputSchema(fields: [enabled.erased, count.erased, mode.erased])

    var nullBool = CommandInputDecoder(["enabled": nil], schema: schema)
    #expect(try nullBool.read(enabled) == true)

    var nullInt = CommandInputDecoder(["count": nil], schema: schema)
    #expect(try nullInt.read(count) == 2)

    var nullEnum = CommandInputDecoder(["mode": nil], schema: schema)
    #expect(try nullEnum.read(mode) == .window)
}

@Test("CommandInputDecoder 拒绝超过 JSON safe integer 的整数")
func commandInputDecoderRejectsUnsafeIntegerValue() throws {
    let count = CommandFields.int("count", range: 0...Int.max, default: 0, description: "数量")
    let limit = CommandFields.optionalNonNegativeInt("limit", description: "限制")
    let schema = CommandInputSchema(fields: [count.erased, limit.erased])

    var decoder = CommandInputDecoder(["count": 9_007_199_254_740_992], schema: schema)
    #expect(throws: CommandInputParseError.self) {
        _ = try decoder.read(count)
    }

    var optionalDecoder = CommandInputDecoder(["limit": 9_007_199_254_740_992], schema: schema)
    #expect(throws: CommandInputParseError.self) {
        _ = try optionalDecoder.read(limit)
    }
}

@Test("CommandFields.int 合法默认值同步用于 schema 和运行时")
func commandFieldsIntAcceptsDefaultInsideRange() throws {
    let count = CommandFields.int("count", range: 1...3, default: 2, description: "数量")
    let schema = CommandInputSchema(fields: [count.erased])
    var decoder = CommandInputDecoder([:], schema: schema)

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

@Test("CommandInputDecoder 全部声明字段读取后通过守卫")
func commandInputDecoderPassesWhenAllDeclaredFieldsRead() throws {
    let a = CommandFields.optionalString("a", description: "a")
    let b = CommandFields.int("b", range: 1...3, default: 2, description: "b")
    let schema = CommandInputSchema(fields: [a.erased, b.erased])
    var decoder = CommandInputDecoder(["a": "x", "b": 2], schema: schema)
    _ = try decoder.read(a)
    _ = try decoder.read(b)
    // 全部声明字段都已读取,守卫不应抛错。
    try decoder.assertAllDeclaredFieldsRead()
}

@Test("CommandInputDecoder 存在声明但未读取字段时守卫抛错")
func commandInputDecoderFailsWhenDeclaredFieldNotRead() throws {
    let a = CommandFields.optionalString("a", description: "a")
    let b = CommandFields.optionalString("b", description: "b")
    let schema = CommandInputSchema(fields: [a.erased, b.erased])
    var decoder = CommandInputDecoder(["a": "x"], schema: schema)
    _ = try decoder.read(a)
    // 故意不读 b,模拟“声明了但 parse 没读”的漂移。
    #expect(throws: CommandInputParseError.self) {
        try decoder.assertAllDeclaredFieldsRead()
    }
}

@Test("CommandInput.parse 守卫:声明字段未读取则整体解析失败")
func commandInputParseFailsWhenDeclaredFieldNotRead() throws {
    struct PartialInput: CommandInput, Equatable {
        static let a = CommandFields.optionalString("a", description: "a")
        static let b = CommandFields.optionalString("b", description: "b")
        static let inputSchema = CommandInputSchema(fields: [a.erased, b.erased])
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
