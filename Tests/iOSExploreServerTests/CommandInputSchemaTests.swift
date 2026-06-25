import Testing
@testable import iOSExploreServer

@Test("CommandInputSchema 输出 properties object 和 propertyOrder")
func commandInputSchemaOutputsPropertiesObject() throws {
    let name = CommandFields.requiredString("name", description: "名字")
    let age = CommandFields.int("age", range: 1...120, default: 18, description: "年龄")
    let schema = CommandInputSchema(fields: [name.erased, age.erased])
    let json = schema.toJSON()

    #expect(json["type"]?.stringValue == "object")
    guard case .object(let properties)? = json["properties"] else {
        Issue.record("properties not object")
        return
    }
    #expect(properties["name"] != nil)
    #expect(properties["age"] != nil)
    guard case .array(let required)? = json["required"] else {
        Issue.record("required not array")
        return
    }
    #expect(required.map(\.stringValue) == ["name"])
    guard case .array(let order)? = json["x-iosExplore-propertyOrder"] else {
        Issue.record("property order not array")
        return
    }
    #expect(order.map(\.stringValue) == ["name", "age"])
}

@Test("CommandInputSchema 拒绝重复字段名")
func commandInputSchemaRejectsDuplicateFields() {
    let first = CommandFields.optionalString("name", description: "姓名")
    let second = CommandFields.optionalString("name", description: "重复姓名")
    #expect(throws: CommandInputSchemaError.self) {
        _ = try CommandInputSchema.validated(fields: [first.erased, second.erased])
    }
}

@Test("CommandInputConstraint 输出 oneOf 与扩展约束")
func commandInputConstraintJSON() throws {
    let schema = CommandInputSchema(fields: [
        CommandFields.optionalString("path", description: "路径").erased,
        CommandFields.optionalString("accessibilityIdentifier", description: "标识").erased,
    ], constraints: [
        .exactlyOneOf(["path", "accessibilityIdentifier"]),
        .extensionMessage("snapshotID is valid only with path"),
    ])
    let json = schema.toJSON()
    guard case .array(let oneOf)? = json["oneOf"] else {
        Issue.record("oneOf missing")
        return
    }
    #expect(oneOf.count == 2)
    guard case .object(let firstBranch) = oneOf[0],
          case .array(let firstRequired)? = firstBranch["required"],
          case .object(let secondBranch) = oneOf[1],
          case .array(let secondRequired)? = secondBranch["required"] else {
        Issue.record("oneOf branches malformed")
        return
    }
    #expect(firstRequired.map(\.stringValue) == ["path"])
    #expect(secondRequired.map(\.stringValue) == ["accessibilityIdentifier"])
    guard case .array(let extensions)? = json["x-iosExplore-constraints"] else {
        Issue.record("extensions missing")
        return
    }
    #expect(extensions.map(\.stringValue) == ["snapshotID is valid only with path"])
}

@Test("CommandInputConstraint 多个 exactlyOneOf 使用 allOf 分组")
func commandInputConstraintMultipleExactlyOneOfGroupsJSON() throws {
    let schema = CommandInputSchema(fields: [
        CommandFields.optionalString("path", description: "路径").erased,
        CommandFields.optionalString("identifier", description: "标识").erased,
        CommandFields.optionalString("x", description: "x 坐标").erased,
        CommandFields.optionalString("y", description: "y 坐标").erased,
    ], constraints: [
        .exactlyOneOf(["path", "identifier"]),
        .exactlyOneOf(["x", "y"]),
    ])

    let json = schema.toJSON()
    guard case .array(let allOf)? = json["allOf"] else {
        Issue.record("allOf missing")
        return
    }
    #expect(allOf.count == 2)
    let expectedRequiredGroups = [[["path"], ["identifier"]], [["x"], ["y"]]]
    for (index, group) in allOf.enumerated() {
        guard case .object(let groupObject) = group,
              case .array(let oneOf)? = groupObject["oneOf"] else {
            Issue.record("allOf group missing oneOf")
            return
        }
        #expect(oneOf.count == 2)
        let requiredFields = oneOf.compactMap { branch -> [String]? in
            guard case .object(let branchObject) = branch,
                  case .array(let required)? = branchObject["required"] else {
                return nil
            }
            return required.compactMap(\.stringValue)
        }
        #expect(requiredFields == expectedRequiredGroups[index])
    }
}

@Test("optional 字段 schema type 明确允许 null")
func optionalFieldsSchemaAllowsNull() throws {
    let schema = CommandInputSchema(fields: [
        CommandFields.optionalString("name", description: "姓名").erased,
        CommandFields.optionalFiniteNumber("x", description: "x 坐标").erased,
        CommandFields.optionalNonNegativeInt("limit", description: "限制").erased,
    ])
    let properties = try schemaProperties(schema.toJSON())

    #expect(try schemaTypeArray(properties, "name") == ["string", "null"])
    #expect(try schemaTypeArray(properties, "x") == ["number", "null"])
    #expect(try schemaTypeArray(properties, "limit") == ["integer", "null"])
}

@Test("默认值字段 schema 保持单一非 null type")
func defaultBackedFieldsSchemaKeepsSingleType() throws {
    enum Mode: String, CaseIterable, Sendable { case window }

    let schema = CommandInputSchema(fields: [
        CommandFields.bool("enabled", default: true, description: "启用").erased,
        CommandFields.int("count", range: 1...3, default: 2, description: "数量").erased,
        CommandFields.enumValue("mode", type: Mode.self, default: .window, description: "模式").erased,
    ])
    let properties = try schemaProperties(schema.toJSON())

    #expect(try schemaTypeString(properties, "enabled") == "boolean")
    #expect(try schemaTypeString(properties, "count") == "integer")
    #expect(try schemaTypeString(properties, "mode") == "string")
}

@Test("optionalNonNegativeInt schema 输出 JSON safe integer 上界")
func optionalNonNegativeIntSchemaOutputsSafeIntegerMaximum() throws {
    let schema = CommandInputSchema(fields: [
        CommandFields.optionalNonNegativeInt("limit", description: "限制").erased,
    ])
    let properties = try schemaProperties(schema.toJSON())
    guard case .object(let limit)? = properties["limit"] else {
        Issue.record("limit property missing")
        return
    }

    #expect(limit["maximum"]?.doubleValue == 9_007_199_254_740_991)
}

private func schemaProperties(_ json: JSON) throws -> JSON {
    guard case .object(let properties)? = json["properties"] else {
        throw CommandInputSchemaError("properties not object")
    }
    return properties
}

private func schemaTypeArray(_ properties: JSON, _ name: String) throws -> [String] {
    guard case .object(let field)? = properties[name],
          case .array(let typeValues)? = field["type"] else {
        throw CommandInputSchemaError("\(name) type not array")
    }
    return typeValues.compactMap(\.stringValue)
}

private func schemaTypeString(_ properties: JSON, _ name: String) throws -> String? {
    guard case .object(let field)? = properties[name] else {
        throw CommandInputSchemaError("\(name) property missing")
    }
    return field["type"]?.stringValue
}
