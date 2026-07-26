import Testing
@testable import iOSExploreServer

@Suite("CommandInputDefinitionTests")
struct CommandInputDefinitionTests {
    @Test("definition 拒绝顶层未知字段")
    func rejectsUnknownTopLevelField() {
        let field = CommandFields.optionalString("name")
        let definition = CommandInputDefinition(fields: [field.erased])

        #expect(throws: CommandInputParseError.self) {
            _ = try definition.makeDecoder(for: ["unexpected": true])
        }
    }

    @Test("wire validation 区分缺失、null 和合同类型")
    func validatesRequiredAndNullableTypes() throws {
        let definition = CommandInputDefinition(
            fields: [AnyCommandField(name: "name"), AnyCommandField(name: "note")],
            validate: { data in
                try CommandWireValidation.value(
                    data["name"], path: "name", required: true, types: [.string]
                )
                try CommandWireValidation.value(
                    data["note"], path: "note", required: false, types: [.string, .null]
                )
            }
        )

        _ = try definition.makeDecoder(for: ["name": "Ada", "note": nil])
        #expect(throws: CommandInputParseError.self) {
            _ = try definition.makeDecoder(for: [:])
        }
        #expect(throws: CommandInputParseError.self) {
            _ = try definition.makeDecoder(for: ["name": nil])
        }
        #expect(throws: CommandInputParseError.self) {
            _ = try definition.makeDecoder(for: ["name": 1])
        }
    }

    @Test("wire validation 校验 safe integer、范围和数组长度")
    func validatesNumberAndArrayConstraints() throws {
        try CommandWireValidation.value(
            .double(10), path: "count", required: true, types: [.integer], minimum: 1, maximum: 10
        )
        #expect(throws: CommandInputParseError.self) {
            try CommandWireValidation.value(
                .double(10.5), path: "count", required: true, types: [.integer]
            )
        }
        #expect(throws: CommandInputParseError.self) {
            try CommandWireValidation.value(
                .double(9_007_199_254_740_992), path: "count", required: true, types: [.integer]
            )
        }
        #expect(throws: CommandInputParseError.self) {
            try CommandWireValidation.value(
                .array([]), path: "items", required: true, types: [.array], minimumItems: 1
            )
        }
    }
}
