import Testing
@testable import iOSExploreServer

@Suite("GeneratedCommandFieldTests")
struct GeneratedCommandFieldTests {
    @Test("optionalInt 同步输出 nullable 范围 schema 并校验运行时值")
    func optionalIntUsesSharedBoundsForSchemaAndDecode() throws {
        let field = CommandFields.optionalInt(
            "index",
            minimum: 0,
            maximum: 20,
            description: "可选下标"
        )
        let schema = field.schema.toJSON()

        #expect(schemaTypeValues(schema) == ["integer", "null"])
        #expect(schema["minimum"]?.doubleValue == 0)
        #expect(schema["maximum"]?.doubleValue == 20)
        #expect(try field.decode(nil) == nil)
        #expect(try field.decode(.null) == nil)
        #expect(try field.decode(.double(0)) == 0)
        #expect(try field.decode(.double(20)) == 20)
        #expect(throws: CommandInputParseError.self) {
            _ = try field.decode(.double(-1))
        }
        #expect(throws: CommandInputParseError.self) {
            _ = try field.decode(.double(21))
        }
        #expect(throws: CommandInputParseError.self) {
            _ = try field.decode(.double(1.5))
        }
    }

    @Test("raw string enum 的必填、默认和可选语义与 schema 一致")
    func rawStringEnumsDecodeWithoutDomainEnum() throws {
        let values = ["auto", "manual"]
        let required = CommandFields.requiredStringEnum(
            "requiredMode",
            values: values,
            description: "必填模式"
        )
        let defaulted = CommandFields.stringEnum(
            "defaultMode",
            values: values,
            default: "auto",
            description: "默认模式"
        )
        let optional = CommandFields.optionalStringEnum(
            "optionalMode",
            values: values,
            description: "可选模式"
        )

        #expect(required.schema.required)
        #expect(required.schema.toJSON()["type"]?.stringValue == "string")
        #expect(schemaEnumValues(required.schema.toJSON()) == [.string("auto"), .string("manual")])
        #expect(try required.decode(.string("manual")) == "manual")
        #expect(throws: CommandInputParseError.self) { _ = try required.decode(nil) }
        #expect(throws: CommandInputParseError.self) { _ = try required.decode(.null) }
        #expect(throws: CommandInputParseError.self) { _ = try required.decode(.string("other")) }

        #expect(!defaulted.schema.required)
        #expect(defaulted.schema.toJSON()["type"]?.stringValue == "string")
        #expect(defaulted.schema.toJSON()["default"]?.stringValue == "auto")
        #expect(schemaEnumValues(defaulted.schema.toJSON()) == [.string("auto"), .string("manual")])
        #expect(try defaulted.decode(nil) == "auto")
        #expect(try defaulted.decode(.null) == "auto")
        #expect(try defaulted.decode(.string("manual")) == "manual")
        #expect(throws: CommandInputParseError.self) { _ = try defaulted.decode(.string("other")) }

        #expect(schemaTypeValues(optional.schema.toJSON()) == ["string", "null"])
        #expect(schemaEnumValues(optional.schema.toJSON()) == [.string("auto"), .string("manual"), .null])
        #expect(try optional.decode(nil) == nil)
        #expect(try optional.decode(.null) == nil)
        #expect(try optional.decode(.string("manual")) == "manual")
        #expect(throws: CommandInputParseError.self) { _ = try optional.decode(.string("other")) }
    }

    @Test("bounded finite number 同源处理 inclusive 和 exclusive 边界")
    func boundedFiniteNumbersShareSchemaAndRuntimeBounds() throws {
        let optional = CommandFields.optionalFiniteNumber(
            "ratio",
            minimum: 1,
            maximum: 3,
            exclusiveMaximum: true,
            description: "可选比例"
        )
        let defaulted = CommandFields.finiteNumber(
            "duration",
            default: 0.5,
            minimum: 0,
            maximum: 10,
            exclusiveMinimum: true,
            description: "持续时间"
        )

        let optionalSchema = optional.schema.toJSON()
        #expect(schemaTypeValues(optionalSchema) == ["number", "null"])
        #expect(optionalSchema["minimum"]?.doubleValue == 1)
        #expect(optionalSchema["maximum"] == nil)
        #expect(optionalSchema["exclusiveMaximum"]?.doubleValue == 3)
        #expect(try optional.decode(nil) == nil)
        #expect(try optional.decode(.null) == nil)
        #expect(try optional.decode(.double(1)) == 1)
        #expect(try optional.decode(.double(2.5)) == 2.5)
        #expect(throws: CommandInputParseError.self) { _ = try optional.decode(.double(0.99)) }
        #expect(throws: CommandInputParseError.self) { _ = try optional.decode(.double(3)) }
        #expect(throws: CommandInputParseError.self) { _ = try optional.decode(.double(.infinity)) }

        let defaultedSchema = defaulted.schema.toJSON()
        #expect(schemaTypeValues(defaultedSchema) == ["number", "null"])
        #expect(defaultedSchema["default"]?.doubleValue == 0.5)
        #expect(defaultedSchema["minimum"] == nil)
        #expect(defaultedSchema["exclusiveMinimum"]?.doubleValue == 0)
        #expect(defaultedSchema["maximum"]?.doubleValue == 10)
        #expect(defaultedSchema["exclusiveMaximum"] == nil)
        #expect(try defaulted.decode(nil) == 0.5)
        #expect(try defaulted.decode(.null) == 0.5)
        #expect(try defaulted.decode(.double(10)) == 10)
        #expect(throws: CommandInputParseError.self) { _ = try defaulted.decode(.double(0)) }
        #expect(throws: CommandInputParseError.self) { _ = try defaulted.decode(.double(.nan)) }
    }

    @Test("optionalStringEnumArray 校验元素枚举并保留重复值")
    func optionalStringEnumArrayValidatesItemsWithoutUniqueConstraint() throws {
        let field = CommandFields.optionalStringEnumArray(
            "sources",
            values: ["stdout", "stderr"],
            itemDescription: "日志来源项",
            description: "日志来源"
        )
        let schema = field.schema.toJSON()

        #expect(schemaTypeValues(schema) == ["array", "null"])
        #expect(schema["uniqueItems"] == nil)
        guard case .object(let items)? = schema["items"] else {
            Issue.record("items schema missing")
            return
        }
        #expect(items["type"]?.stringValue == "string")
        #expect(items["description"]?.stringValue == "日志来源项")
        #expect(schemaEnumValues(items) == [.string("stdout"), .string("stderr")])

        #expect(try field.decode(nil) == nil)
        #expect(try field.decode(.null) == nil)
        #expect(try field.decode(.array([])) == [])
        #expect(try field.decode(.array([.string("stdout"), .string("stdout")])) == ["stdout", "stdout"])
        #expect(throws: CommandInputParseError.self) {
            _ = try field.decode(.array([.string("other")]))
        }
        #expect(throws: CommandInputParseError.self) {
            _ = try field.decode(.array([.double(1)]))
        }
        #expect(throws: CommandInputParseError.self) {
            _ = try field.decode(.string("stdout"))
        }
    }
}

private func schemaTypeValues(_ schema: JSON) -> [String] {
    guard case .array(let values)? = schema["type"] else { return [] }
    return values.compactMap(\.stringValue)
}

private func schemaEnumValues(_ schema: JSON) -> [JSONValue] {
    guard case .array(let values)? = schema["enum"] else { return [] }
    return values
}
