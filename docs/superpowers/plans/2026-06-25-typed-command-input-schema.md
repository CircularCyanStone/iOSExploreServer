# Typed Command Input Schema Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the old `[CommandParameter]` command schema with typed command inputs and `help.inputSchema.properties`.

**Architecture:** Commands become `Command<Input>` style units through an associated `CommandInput`; `Router` stores type-erased `AnyCommand` values and parses typed input before calling handlers. Field definitions are the single source for parsing and schema output; UIKit commands keep Foundation-only input parsing and move UIKit work into execute/collector layers.

**Tech Stack:** Swift Package, Swift 6.2 toolchain, Swift 5 framework language mode, Foundation/Network core, UIKit extension package, Swift Testing.

---

## File Structure

Create these core files:

- `Sources/iOSExploreServer/CommandInput.swift` — `CommandInput`, `EmptyCommandInput`, `RawJSONInput`, and `CommandInputParseError`.
- `Sources/iOSExploreServer/CommandField.swift` — typed `CommandField<Value>`, `AnyCommandField`, `CommandFieldSchema`, `CommandJSONSchemaType`, and `CommandFields` factories.
- `Sources/iOSExploreServer/CommandInputSchema.swift` — `CommandInputSchema`, `CommandInputConstraint`, schema-to-JSON conversion, duplicate-field validation, property order.
- `Sources/iOSExploreServer/CommandInputDecoder.swift` — schema-aware decoder, unknown-field validation, `read(field)` membership enforcement.

Modify these core files:

- `Sources/iOSExploreServer/Command.swift` — replace `ParameterKind`/`CommandParameter`/old `Command` with typed `Command` and `AnyCommand`.
- `Sources/iOSExploreServer/Router.swift` — store `[String: AnyCommand]`, route through type-erased parse/handle, expose metadata with `inputSchema`.
- `Sources/iOSExploreServer/ExploreServer.swift` — replace closure registration with typed input registration.
- `Sources/iOSExploreServer/Handlers/BuiltinHandlers.swift` — migrate `ping`/`echo`/`info`/`help` to typed inputs and `inputSchema` output.
- `Sources/iOSExploreServer/ExploreCommandSupport.swift` — update command extension registration docs/API if it references old parameters.

Create or replace these tests:

- `Tests/iOSExploreServerTests/CommandInputSchemaTests.swift`
- `Tests/iOSExploreServerTests/CommandInputDecoderTests.swift`
- Update `Tests/iOSExploreServerTests/CommandTests.swift`
- Update `Tests/iOSExploreServerTests/RouterTests.swift`
- Update `Tests/iOSExploreServerTests/BuiltinHandlersTests.swift`
- Update `Tests/iOSExploreServerTests/IntegrationTests.swift`

Modify UIKit files:

- `Sources/iOSExploreUIKit/Support/Parsing/QueryDecoder.swift` — delete or leave unused only until final cleanup; final state should use core `CommandInputDecoder`.
- `Sources/iOSExploreUIKit/Support/Parsing/UIKitQueryParsing.swift` — remove old protocol or replace with compatibility typealiases only if needed during migration.
- Create `Sources/iOSExploreUIKit/Support/Parsing/UIKitCommandFields.swift` — `UIKitFilterFields`, `UIKitLocatorFields`, `UIKitLocatorInput`.
- Modify all files under `Sources/iOSExploreUIKit/Commands/TopViewHierarchy/`, `ViewTargets/`, `Tap/`, `ControlAction/` to use `CommandInput`.

Modify docs:

- `README.md`
- `docs/architecture/index.md`
- `docs/tools/network-tools.md`
- `docs/uikit/README.md`
- `docs/uikit/reading-guide.md`
- `docs/uikit/uikit-file-reference.md`

---

### Task 1: Core Input Schema Types

**Files:**
- Create: `Sources/iOSExploreServer/CommandInput.swift`
- Create: `Sources/iOSExploreServer/CommandField.swift`
- Create: `Sources/iOSExploreServer/CommandInputSchema.swift`
- Test: `Tests/iOSExploreServerTests/CommandInputSchemaTests.swift`
- Test: `Tests/iOSExploreServerTests/CommandInputDecoderTests.swift`

- [ ] **Step 1: Write failing schema JSON tests**

Add `Tests/iOSExploreServerTests/CommandInputSchemaTests.swift`:

```swift
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
    guard case .array(let extensions)? = json["x-iosExplore-constraints"] else {
        Issue.record("extensions missing")
        return
    }
    #expect(extensions.map(\.stringValue) == ["snapshotID is valid only with path"])
}
```

- [ ] **Step 2: Write failing decoder tests**

Add `Tests/iOSExploreServerTests/CommandInputDecoderTests.swift`:

```swift
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

    var unknownDecoder = CommandInputDecoder(["unexpected": "x"], schema: schema)
    #expect(throws: CommandInputParseError.self) {
        try unknownDecoder.validateNoUnknownFields()
    }

    var decoder = CommandInputDecoder([:], schema: schema)
    #expect(throws: CommandInputParseError.self) {
        _ = try decoder.read(undeclared)
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
```

- [ ] **Step 3: Run tests and verify they fail**

Run:

```bash
swift test --filter CommandInput
```

Expected: compile fails because `CommandInputSchema`, `CommandFields`, and `CommandInputDecoder` do not exist.

- [ ] **Step 4: Implement core schema/input files**

Create `Sources/iOSExploreServer/CommandInput.swift`:

```swift
import Foundation

/// 命令输入解析失败。
///
/// Router 只把该错误转换为 `invalid_data`；其他错误代表命令实现 bug。
public struct CommandInputParseError: Error, Sendable, Equatable {
    /// 可直接返回给调用方的错误说明。
    public let message: String

    /// 创建输入解析错误。
    ///
    /// - Parameter message: 错误说明。
    public init(_ message: String) {
        self.message = message
    }
}

/// 可从 `ExploreRequest.data` 解析的 typed command input。
public protocol CommandInput: Sendable {
    /// 对外暴露给 `help.inputSchema` 的输入 schema。
    static var inputSchema: CommandInputSchema { get }

    /// 从原始 JSON data 解析输入。
    ///
    /// - Parameter data: 请求中的 `data` 对象。
    /// - Returns: typed input。
    /// - Throws: `CommandInputParseError` 表示调用方输入非法。
    static func parse(from data: JSON) throws -> Self

    /// 从 schema-aware decoder 解析输入。
    ///
    /// - Parameter decoder: 已绑定 schema 的字段读取器。
    /// - Returns: typed input。
    /// - Throws: `CommandInputParseError` 表示调用方输入非法。
    static func parse(decoding decoder: inout CommandInputDecoder) throws -> Self
}

public extension CommandInput {
    /// 默认解析入口：先校验未知字段，再进入领域解析。
    static func parse(from data: JSON) throws -> Self {
        var decoder = CommandInputDecoder(data, schema: inputSchema)
        try decoder.validateNoUnknownFields()
        return try parse(decoding: &decoder)
    }
}

/// 无参数命令输入。
public struct EmptyCommandInput: CommandInput, Equatable {
    /// 空对象 schema。
    public static let inputSchema = CommandInputSchema.empty

    /// 空输入无需读取字段。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> EmptyCommandInput {
        EmptyCommandInput()
    }
}

/// 原始 JSON 输入，用于 echo 或自定义 passthrough 命令。
public struct RawJSONInput: CommandInput, Equatable {
    /// 允许任意字段的 schema。
    public static let inputSchema = CommandInputSchema(additionalProperties: true)

    /// 原始 data。
    public let data: JSON

    /// 创建原始输入。
    public init(data: JSON) {
        self.data = data
    }

    /// Raw input 保留完整 data，刻意绕过 unknown-field 校验。
    public static func parse(from data: JSON) throws -> RawJSONInput {
        RawJSONInput(data: data)
    }

    /// 库内 decoder 入口。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> RawJSONInput {
        RawJSONInput(data: decoder.rawDataForInternalUse)
    }
}
```

Create `Sources/iOSExploreServer/CommandField.swift`:

```swift
import Foundation

/// inputSchema 支持的 JSON 类型。
public enum CommandJSONSchemaType: String, Sendable, Equatable {
    case string
    case number
    case integer
    case boolean
    case object
    case array
}

/// 单个字段的 schema 元数据。
public struct CommandFieldSchema: Sendable, Equatable {
    public let type: CommandJSONSchemaType
    public let required: Bool
    public let description: String
    public let defaultValue: JSONValue?
    public let minimum: Double?
    public let maximum: Double?
    public let enumValues: [String]
}

/// 类型擦除后的字段 schema。
public struct AnyCommandField: Sendable, Equatable {
    public let name: String
    public let schema: CommandFieldSchema
}

/// typed 字段定义，是 schema 和解析的单一来源。
public struct CommandField<Value: Sendable>: Sendable {
    public let name: String
    public let schema: CommandFieldSchema
    let decode: @Sendable (JSONValue?) throws -> Value

    public var erased: AnyCommandField {
        AnyCommandField(name: name, schema: schema)
    }
}

/// 常用字段工厂。
public enum CommandFields {
    public static func bool(_ name: String, default defaultValue: Bool, description: String) -> CommandField<Bool> {
        CommandField(name: name,
                     schema: CommandFieldSchema(type: .boolean, required: false, description: description,
                                                defaultValue: .bool(defaultValue), minimum: nil, maximum: nil, enumValues: [])) { value in
            guard let value, value != .null else { return defaultValue }
            guard let parsed = value.boolValue else { throw CommandInputParseError("parameter '\(name)' expects boolean") }
            return parsed
        }
    }

    public static func optionalString(_ name: String, description: String) -> CommandField<String?> {
        CommandField(name: name,
                     schema: CommandFieldSchema(type: .string, required: false, description: description,
                                                defaultValue: nil, minimum: nil, maximum: nil, enumValues: [])) { value in
            guard let value, value != .null else { return nil }
            guard let parsed = value.stringValue else { throw CommandInputParseError("parameter '\(name)' expects string") }
            return parsed
        }
    }

    public static func requiredString(_ name: String, description: String) -> CommandField<String> {
        CommandField(name: name,
                     schema: CommandFieldSchema(type: .string, required: true, description: description,
                                                defaultValue: nil, minimum: nil, maximum: nil, enumValues: [])) { value in
            guard let value, value != .null else { throw CommandInputParseError("missing required parameter '\(name)'") }
            guard let parsed = value.stringValue else { throw CommandInputParseError("parameter '\(name)' expects string") }
            return parsed
        }
    }

    public static func optionalFiniteNumber(_ name: String, description: String) -> CommandField<Double?> {
        CommandField(name: name,
                     schema: CommandFieldSchema(type: .number, required: false, description: description,
                                                defaultValue: nil, minimum: nil, maximum: nil, enumValues: [])) { value in
            guard let value, value != .null else { return nil }
            guard let parsed = value.doubleValue, parsed.isFinite else {
                throw CommandInputParseError("parameter '\(name)' expects number")
            }
            return parsed
        }
    }

    public static func optionalNonNegativeInt(_ name: String, description: String) -> CommandField<Int?> {
        CommandField(name: name,
                     schema: CommandFieldSchema(type: .integer, required: false, description: description,
                                                defaultValue: nil, minimum: 0, maximum: nil, enumValues: [])) { value in
            guard let value, value != .null else { return nil }
            return try integer(name: name, value: value, range: 0...Int.max)
        }
    }

    public static func int(_ name: String, range: ClosedRange<Int>, default defaultValue: Int, description: String) -> CommandField<Int> {
        CommandField(name: name,
                     schema: CommandFieldSchema(type: .integer, required: false, description: description,
                                                defaultValue: .double(Double(defaultValue)),
                                                minimum: Double(range.lowerBound), maximum: Double(range.upperBound), enumValues: [])) { value in
            guard let value, value != .null else { return defaultValue }
            return try integer(name: name, value: value, range: range)
        }
    }

    public static func enumValue<E>(_ name: String, type: E.Type, default defaultValue: E, description: String) -> CommandField<E>
        where E: RawRepresentable & CaseIterable & Sendable, E.RawValue == String {
        let values = E.allCases.map(\.rawValue)
        return CommandField(name: name,
                            schema: CommandFieldSchema(type: .string, required: false, description: description,
                                                       defaultValue: .string(defaultValue.rawValue),
                                                       minimum: nil, maximum: nil, enumValues: values)) { value in
            guard let value, value != .null else { return defaultValue }
            guard let raw = value.stringValue else { throw CommandInputParseError("parameter '\(name)' expects string") }
            guard let parsed = E(rawValue: raw) else {
                throw CommandInputParseError("\(name) must be one of \(values.joined(separator: ", "))")
            }
            return parsed
        }
    }

    public static func requiredEnum<E>(_ name: String, type: E.Type, description: String) -> CommandField<E>
        where E: RawRepresentable & CaseIterable & Sendable, E.RawValue == String {
        let values = E.allCases.map(\.rawValue)
        return CommandField(name: name,
                            schema: CommandFieldSchema(type: .string, required: true, description: description,
                                                       defaultValue: nil, minimum: nil, maximum: nil, enumValues: values)) { value in
            guard let value, value != .null else { throw CommandInputParseError("missing required parameter '\(name)'") }
            guard let raw = value.stringValue else { throw CommandInputParseError("parameter '\(name)' expects string") }
            guard let parsed = E(rawValue: raw) else {
                throw CommandInputParseError("\(name) must be one of \(values.joined(separator: ", "))")
            }
            return parsed
        }
    }

    private static func integer(name: String, value: JSONValue, range: ClosedRange<Int>) throws -> Int {
        guard let raw = value.doubleValue, raw.isFinite, raw.rounded() == raw else {
            throw CommandInputParseError("\(name) must be an integer between \(range.lowerBound) and \(range.upperBound)")
        }
        guard raw >= Double(range.lowerBound), raw <= Double(range.upperBound) else {
            throw CommandInputParseError("\(name) must be an integer between \(range.lowerBound) and \(range.upperBound)")
        }
        return Int(raw)
    }
}
```

Create `Sources/iOSExploreServer/CommandInputSchema.swift`:

```swift
import Foundation

/// 命令 schema 构造错误，代表开发期字段定义非法。
public struct CommandInputSchemaError: Error, Sendable, Equatable {
    public let message: String
}

/// inputSchema 的领域约束。
public enum CommandInputConstraint: Sendable, Equatable {
    case exactlyOneOf([String])
    case extensionMessage(String)
}

/// 命令输入 schema。
public struct CommandInputSchema: Sendable, Equatable {
    public static let empty = CommandInputSchema(fields: [])

    public let fields: [AnyCommandField]
    public let additionalProperties: Bool
    public let constraints: [CommandInputConstraint]

    public init(fields: [AnyCommandField] = [],
                additionalProperties: Bool = false,
                constraints: [CommandInputConstraint] = []) {
        self.fields = fields
        self.additionalProperties = additionalProperties
        self.constraints = constraints
    }

    public static func validated(fields: [AnyCommandField],
                                 additionalProperties: Bool = false,
                                 constraints: [CommandInputConstraint] = []) throws -> CommandInputSchema {
        var seen = Set<String>()
        for field in fields {
            if !seen.insert(field.name).inserted {
                throw CommandInputSchemaError(message: "duplicate input field '\(field.name)'")
            }
        }
        return CommandInputSchema(fields: fields, additionalProperties: additionalProperties, constraints: constraints)
    }

    func containsField(named name: String) -> Bool {
        fields.contains { $0.name == name }
    }

    func fieldNames() -> Set<String> {
        Set(fields.map(\.name))
    }

    public func toJSON() -> JSON {
        var properties = JSON()
        var required: [JSONValue] = []
        for field in fields {
            properties[field.name] = .object(field.schema.toJSON())
            if field.schema.required { required.append(.string(field.name)) }
        }
        var result: JSON = [
            "type": "object",
            "properties": .object(properties),
            "required": .array(required),
            "additionalProperties": .bool(additionalProperties),
            "x-iosExplore-propertyOrder": .array(fields.map { .string($0.name) }),
        ]
        apply(constraints: constraints, to: &result)
        return result
    }

    private func apply(constraints: [CommandInputConstraint], to json: inout JSON) {
        var oneOf: [JSONValue] = []
        var extensions: [JSONValue] = []
        for constraint in constraints {
            switch constraint {
            case .exactlyOneOf(let names):
                for name in names {
                    oneOf.append(.object(["required": .array([.string(name)])]))
                }
            case .extensionMessage(let message):
                extensions.append(.string(message))
            }
        }
        if !oneOf.isEmpty { json["oneOf"] = .array(oneOf) }
        if !extensions.isEmpty { json["x-iosExplore-constraints"] = .array(extensions) }
    }
}

private extension CommandFieldSchema {
    func toJSON() -> JSON {
        var json: JSON = [
            "type": .string(type.rawValue),
            "description": .string(description),
        ]
        if let defaultValue { json["default"] = defaultValue }
        if let minimum { json["minimum"] = .double(minimum) }
        if let maximum { json["maximum"] = .double(maximum) }
        if !enumValues.isEmpty { json["enum"] = .array(enumValues.map { .string($0) }) }
        return json
    }
}
```

Create `Sources/iOSExploreServer/CommandInputDecoder.swift`:

```swift
import Foundation

/// schema-aware command input decoder。
public struct CommandInputDecoder: Sendable {
    private let data: JSON
    private let schema: CommandInputSchema

    var rawDataForInternalUse: JSON { data }

    public init(_ data: JSON, schema: CommandInputSchema) {
        self.data = data
        self.schema = schema
    }

    public func validateNoUnknownFields() throws {
        guard !schema.additionalProperties else { return }
        let allowed = schema.fieldNames()
        for key in data.storage.keys where !allowed.contains(key) {
            throw CommandInputParseError("unknown parameter '\(key)'")
        }
    }

    public func read<Value>(_ field: CommandField<Value>) throws -> Value {
        guard schema.containsField(named: field.name) else {
            throw CommandInputParseError("parameter '\(field.name)' is not declared in inputSchema")
        }
        return try field.decode(data[field.name])
    }
}
```

- [ ] **Step 5: Run tests and verify task passes**

Run:

```bash
swift test --filter CommandInput
```

Expected: all `CommandInput*` tests pass.

- [ ] **Step 6: Commit Task 1**

```bash
git add Sources/iOSExploreServer/CommandInput.swift Sources/iOSExploreServer/CommandField.swift Sources/iOSExploreServer/CommandInputSchema.swift Sources/iOSExploreServer/CommandInputDecoder.swift Tests/iOSExploreServerTests/CommandInputSchemaTests.swift Tests/iOSExploreServerTests/CommandInputDecoderTests.swift
git commit -m "feat: add typed command input schema"
```

---

### Task 2: Typed Command, AnyCommand, and Router

**Files:**
- Modify: `Sources/iOSExploreServer/Command.swift`
- Modify: `Sources/iOSExploreServer/Router.swift`
- Modify: `Sources/iOSExploreServer/ExploreServer.swift`
- Test: `Tests/iOSExploreServerTests/CommandTests.swift`
- Test: `Tests/iOSExploreServerTests/RouterTests.swift`

- [ ] **Step 1: Replace command tests with typed command expectations**

Update `Tests/iOSExploreServerTests/CommandTests.swift`:

```swift
import Testing
@testable import iOSExploreServer

private struct GreetingInput: CommandInput, Equatable {
    static let name = CommandFields.requiredString("name", description: "名字")
    static let inputSchema = CommandInputSchema(fields: [name.erased])
    let nameValue: String

    static func parse(decoding decoder: inout CommandInputDecoder) throws -> GreetingInput {
        GreetingInput(nameValue: try decoder.read(name))
    }
}

private struct GreetingCommand: Command {
    let action = "greet"
    let description = "问候"

    func handle(_ input: GreetingInput) async throws -> ExploreResult {
        .success(["message": .string("Hello, \(input.nameValue)")])
    }
}

@Test("AnyCommand 解析 typed input 并调用 handler")
func anyCommandParsesTypedInput() async {
    let any = AnyCommand(GreetingCommand())
    let result = await any.handle(ExploreRequest(action: "greet", data: ["name": "Ada"]))
    guard case .success(let data) = result else {
        Issue.record("expected success")
        return
    }
    #expect(data["message"]?.stringValue == "Hello, Ada")
}

@Test("AnyCommand 将 input parse error 转为 invalid_data")
func anyCommandMapsInputParseError() async {
    let any = AnyCommand(GreetingCommand())
    let result = await any.handle(ExploreRequest(action: "greet", data: [:]))
    guard case .failure(let code, let message) = result else {
        Issue.record("expected failure")
        return
    }
    #expect(code == .invalidData)
    #expect(message.contains("missing required parameter 'name'"))
}
```

- [ ] **Step 2: Replace router tests with typed registration**

Update `Tests/iOSExploreServerTests/RouterTests.swift` to use typed commands and typed closure registration:

```swift
import Testing
@testable import iOSExploreServer

private struct AddInput: CommandInput, Equatable {
    static let x = CommandFields.int("x", range: 0...100, default: 0, description: "x")
    static let y = CommandFields.int("y", range: 0...100, default: 0, description: "y")
    static let inputSchema = CommandInputSchema(fields: [x.erased, y.erased])
    let xValue: Int
    let yValue: Int

    static func parse(decoding decoder: inout CommandInputDecoder) throws -> AddInput {
        AddInput(xValue: try decoder.read(x), yValue: try decoder.read(y))
    }
}

@Test("Router 注册 typed closure 并路由")
func routerRoutesTypedClosure() async {
    let router = Router()
    router.register(action: "add", description: "相加", input: AddInput.self) { input in
        .success(["value": .double(Double(input.xValue + input.yValue))])
    }

    let result = await router.route(ExploreRequest(action: "add", data: ["x": 2, "y": 3]))
    guard case .success(let data) = result else {
        Issue.record("expected success")
        return
    }
    #expect(data["value"]?.doubleValue == 5)
}

@Test("Router unknown action 返回 unknown_action")
func routerUnknownAction() async {
    let router = Router()
    let result = await router.route(ExploreRequest(action: "missing"))
    guard case .failure(let code, _) = result else {
        Issue.record("expected failure")
        return
    }
    #expect(code == .unknownAction)
}

@Test("Router inputSchema metadata 包含 action description schema")
func routerMetadataIncludesInputSchema() {
    let router = Router()
    router.register(action: "add", description: "相加", input: AddInput.self) { _ in .success([:]) }
    let metadata = router.commandMetadata()
    let add = metadata.first { $0.action == "add" }
    #expect(add?.description == "相加")
    #expect(add?.inputSchema.fields.map(\.name) == ["x", "y"])
}
```

- [ ] **Step 3: Run tests and verify they fail**

Run:

```bash
swift test --filter CommandTests
swift test --filter RouterTests
```

Expected: compile fails because `Command` still uses `handle(_ request:)` and `Router.register(action:description:parameters:)` still exists.

- [ ] **Step 4: Implement typed Command and AnyCommand**

Replace `Sources/iOSExploreServer/Command.swift` with:

```swift
import Foundation

/// 命令日志通道。
public enum CommandLogCategory: Sendable, Equatable {
    case core
    case extensionCommand(category: String)
}

/// 可被 `ExploreServer` 注册和路由的 typed 命令协议。
public protocol Command: Sendable {
    associatedtype Input: CommandInput

    /// 命令名，也是 HTTP body 中 `action` 字段的匹配键。
    var action: String { get }

    /// 命令人类可读描述，由 `help` 输出给调用方。
    var description: String { get }

    /// 执行命令。
    ///
    /// - Parameter input: 已解析和校验的 typed 输入。
    /// - Returns: 业务结果。
    func handle(_ input: Input) async throws -> ExploreResult
}

/// type-erased command，用于 Router 保存不同 Input 类型的命令。
public struct AnyCommand: Sendable {
    public let action: String
    public let description: String
    public let inputSchema: CommandInputSchema
    public let logCategory: CommandLogCategory
    private let handler: @Sendable (ExploreRequest) async -> ExploreResult

    /// 包装协议命令。
    public init<C: Command>(_ command: C, logCategory: CommandLogCategory = .core) {
        self.action = command.action
        self.description = command.description
        self.inputSchema = C.Input.inputSchema
        self.logCategory = logCategory
        self.handler = { request in
            do {
                Self.log(.debug, logCategory, "command \(command.action) input parse start payloadKeys=\(request.data.storage.count)")
                let input = try C.Input.parse(from: request.data)
                Self.log(.debug, logCategory, "command \(command.action) input parse success")
                let result = try await command.handle(input)
                return result
            } catch let error as CommandInputParseError {
                let serverError = ExploreServerError.invalidData(action: command.action, message: error.message)
                Self.log(.error, logCategory, serverError.logMessage)
                return .failure(code: serverError.code, message: serverError.message)
            } catch {
                let serverError = ExploreServerError.handlerThrown(action: command.action, error: error)
                Self.log(.error, logCategory, serverError.logMessage)
                return .failure(code: serverError.code, message: serverError.message)
            }
        }
    }

    /// 包装 typed closure。
    public init<Input: CommandInput>(action: String,
                                     description: String,
                                     input: Input.Type,
                                     logCategory: CommandLogCategory = .core,
                                     handler: @escaping @Sendable (Input) async throws -> ExploreResult) {
        self.action = action
        self.description = description
        self.inputSchema = Input.inputSchema
        self.logCategory = logCategory
        self.handler = { request in
            do {
                Self.log(.debug, logCategory, "command \(action) input parse start payloadKeys=\(request.data.storage.count)")
                let typedInput = try Input.parse(from: request.data)
                Self.log(.debug, logCategory, "command \(action) input parse success")
                return try await handler(typedInput)
            } catch let error as CommandInputParseError {
                let serverError = ExploreServerError.invalidData(action: action, message: error.message)
                Self.log(.error, logCategory, serverError.logMessage)
                return .failure(code: serverError.code, message: serverError.message)
            } catch {
                let serverError = ExploreServerError.handlerThrown(action: action, error: error)
                Self.log(.error, logCategory, serverError.logMessage)
                return .failure(code: serverError.code, message: serverError.message)
            }
        }
    }

    /// 执行 type-erased 命令。
    func handle(_ request: ExploreRequest) async -> ExploreResult {
        await handler(request)
    }

    private static func log(_ level: ExploreLogLevel, _ category: CommandLogCategory, _ message: String) {
        switch category {
        case .core:
            switch level {
            case .debug: ExploreLogger.debug(.command, message)
            case .info: ExploreLogger.info(.command, message)
            case .error: ExploreLogger.error(.command, message)
            }
        case .extensionCommand(let category):
            ExploreLogging.emitExtension(level: level, category: category, message)
        }
    }
}
```

- [ ] **Step 5: Update Router**

Modify `Sources/iOSExploreServer/Router.swift`:

```swift
private let handlers = Mutex<[String: AnyCommand]>([:])

public func register<C: Command>(_ command: C, logCategory: CommandLogCategory = .core) {
    register(AnyCommand(command, logCategory: logCategory))
}

public func register(_ command: AnyCommand) {
    handlers.withLock { $0[command.action] = command }
    ExploreLogger.info(.router, "router registered action=\(command.action) schemaFields=\(command.inputSchema.fields.count) constraints=\(command.inputSchema.constraints.count)")
}

public func register<Input: CommandInput>(action: String,
                                          description: String = "",
                                          input: Input.Type,
                                          logCategory: CommandLogCategory = .core,
                                          _ handler: @escaping @Sendable (Input) async throws -> ExploreResult) {
    register(AnyCommand(action: action, description: description, input: input, logCategory: logCategory, handler: handler))
}

func commandMetadata() -> [(action: String, description: String, inputSchema: CommandInputSchema)] {
    let metadata = handlers.withLock { dict in
        dict.values.map { ($0.action, $0.description, $0.inputSchema) }
    }
    ExploreLogger.debug(.router, "router metadata snapshot count=\(metadata.count)")
    return metadata
}
```

Remove the old `validate(_:against:)` and `typeMatches` methods; validation now lives in `CommandInputDecoder`.

- [ ] **Step 6: Update ExploreServer registration**

Modify `Sources/iOSExploreServer/ExploreServer.swift`:

```swift
public func register<C: Command>(_ command: C, logCategory: CommandLogCategory = .core) {
    ExploreLogger.info(.server, "server register command action=\(command.action)")
    router.register(command, logCategory: logCategory)
}

public func register<Input: CommandInput>(action: String,
                                          description: String = "",
                                          input: Input.Type,
                                          logCategory: CommandLogCategory = .core,
                                          _ handler: @escaping @Sendable (Input) async throws -> ExploreResult) {
    ExploreLogger.info(.server, "server register closure action=\(action)")
    router.register(action: action, description: description, input: input, logCategory: logCategory, handler)
}
```

- [ ] **Step 7: Run tests and verify task passes**

Run:

```bash
swift test --filter CommandTests
swift test --filter RouterTests
```

Expected: tests pass after updating any old call sites in these two test files.

- [ ] **Step 8: Commit Task 2**

```bash
git add Sources/iOSExploreServer/Command.swift Sources/iOSExploreServer/Router.swift Sources/iOSExploreServer/ExploreServer.swift Tests/iOSExploreServerTests/CommandTests.swift Tests/iOSExploreServerTests/RouterTests.swift
git commit -m "refactor: route typed command inputs"
```

---

### Task 3: Builtin Commands and Help inputSchema

**Files:**
- Modify: `Sources/iOSExploreServer/Handlers/BuiltinHandlers.swift`
- Modify: `Tests/iOSExploreServerTests/BuiltinHandlersTests.swift`
- Modify: `Tests/iOSExploreServerTests/IntegrationTests.swift`

- [ ] **Step 1: Update help tests to expect inputSchema**

In `BuiltinHandlersTests.swift`, replace the old `parameters` assertions with:

```swift
@Test("help 列出全部命令元数据和 inputSchema")
func helpListsAllCommandsWithInputSchema() async throws {
    let router = Router()
    BuiltinHandlers.registerAll(into: router)
    router.register(action: "greet2",
                    description: "测试用",
                    input: GreetingInput.self) { _ in .success([:]) }

    let r = try await HelpCommand(router: router).handle(EmptyCommandInput())
    guard case .success(let data) = r else { Issue.record("expected success"); return }
    guard case .array(let entries) = data["commands"] else { Issue.record("commands not array"); return }
    guard let greet2 = entries.first(where: { entry in
        if case .object(let obj) = entry, case .string(let a) = obj["action"] { return a == "greet2" }
        return false
    }) else { Issue.record("greet2 not found"); return }
    guard case .object(let obj2) = greet2 else { Issue.record("greet2 not object"); return }
    #expect(obj2["parameters"] == nil)
    guard case .object(let schema)? = obj2["inputSchema"] else { Issue.record("inputSchema not object"); return }
    guard case .object(let properties)? = schema["properties"] else { Issue.record("properties not object"); return }
    #expect(properties["name"] != nil)
}
```

Add `GreetingInput` test helper in the same file:

```swift
private struct GreetingInput: CommandInput, Equatable {
    static let name = CommandFields.requiredString("name", description: "名字")
    static let inputSchema = CommandInputSchema(fields: [name.erased])
    let nameValue: String

    static func parse(decoding decoder: inout CommandInputDecoder) throws -> GreetingInput {
        GreetingInput(nameValue: try decoder.read(name))
    }
}
```

- [ ] **Step 2: Run help tests and verify they fail**

Run:

```bash
swift test --filter BuiltinHandlersTests
```

Expected: compile fails because builtin commands still use `ExploreRequest`.

- [ ] **Step 3: Migrate builtin commands**

Modify `Sources/iOSExploreServer/Handlers/BuiltinHandlers.swift`:

```swift
struct PingCommand: Command {
    typealias Input = EmptyCommandInput
    let action = "ping"
    let description = "健康检查,返回 pong"

    func handle(_ input: EmptyCommandInput) async throws -> ExploreResult {
        ExploreLogger.debug(.command, "command ping handled")
        return .success(["pong": .bool(true)])
    }
}

struct EchoCommand: Command {
    typealias Input = RawJSONInput
    let action = "echo"
    let description = "原样回显 data"

    func handle(_ input: RawJSONInput) async throws -> ExploreResult {
        ExploreLogger.debug(.command, "command echo handled keys=\(input.data.storage.count)")
        return .success(input.data)
    }
}

struct InfoCommand: Command {
    typealias Input = EmptyCommandInput
    let action = "info"
    let description = "返回系统/应用/Bundle 信息"

    func handle(_ input: EmptyCommandInput) async throws -> ExploreResult {
        ExploreLogger.debug(.command, "command info handled")
        let processInfo = ProcessInfo.processInfo
        let bundle = Bundle.main
        return .success([
            "system": .string(processInfo.operatingSystemVersionString),
            "app": .string((bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"),
            "bundle": .string(bundle.bundleIdentifier ?? "unknown"),
        ])
    }
}

struct HelpCommand: Command {
    typealias Input = EmptyCommandInput
    let action = "help"
    let description = "列出所有已注册命令及其输入 schema"
    private let router: Router

    init(router: Router) { self.router = router }

    func handle(_ input: EmptyCommandInput) async throws -> ExploreResult {
        ExploreLogger.debug(.command, "command help handled")
        let entries: [JSONValue] = router.commandMetadata().map { entry in
            .object(JSON([
                "action": .string(entry.action),
                "description": .string(entry.description),
                "inputSchema": .object(entry.inputSchema.toJSON()),
            ]))
        }
        ExploreLogger.info(.command, "command help completed count=\(entries.count)")
        return .success(JSON(["commands": .array(entries)]))
    }
}
```

- [ ] **Step 4: Update integration tests and old direct calls**

Search:

```bash
rg -n "handle\\(ExploreRequest|parameters:|CommandParameter|ParameterKind" Tests Sources
```

For tests directly calling builtin handlers, replace:

```swift
try await PingCommand().handle(ExploreRequest(action: "ping"))
```

with:

```swift
try await PingCommand().handle(EmptyCommandInput())
```

For `IntegrationTests`, update `help` assertions from `"parameters"` to `"inputSchema"`.

- [ ] **Step 5: Run tests and verify task passes**

Run:

```bash
swift test --filter BuiltinHandlersTests
swift test --filter IntegrationTests
```

Expected: both pass.

- [ ] **Step 6: Commit Task 3**

```bash
git add Sources/iOSExploreServer/Handlers/BuiltinHandlers.swift Tests/iOSExploreServerTests/BuiltinHandlersTests.swift Tests/iOSExploreServerTests/IntegrationTests.swift
git commit -m "refactor: expose help input schemas"
```

---

### Task 4: UIKit Shared Fields and Locator Input

**Files:**
- Create: `Sources/iOSExploreUIKit/Support/Parsing/UIKitCommandFields.swift`
- Test: `Tests/iOSExploreServerTests/UIKitLocatorInputTests.swift`
- Modify if needed: `Sources/iOSExploreUIKit/Support/Locator/UIKitViewLookupModels.swift`

- [ ] **Step 1: Write locator input tests**

Create `Tests/iOSExploreServerTests/UIKitLocatorInputTests.swift`:

```swift
import Testing
@testable import iOSExploreServer
@testable import iOSExploreUIKit

@Test("UIKitLocatorInput 通过字段读取 identifier")
func locatorInputParsesIdentifier() throws {
    var decoder = CommandInputDecoder(["accessibilityIdentifier": "home.submit"],
                                      schema: CommandInputSchema(fields: [
                                          UIKitLocatorFields.accessibilityIdentifier.erased,
                                          UIKitLocatorFields.path.erased,
                                      ]))
    let target = try UIKitLocatorInput.parse(decoder: &decoder,
                                             identifierField: UIKitLocatorFields.accessibilityIdentifier,
                                             pathField: UIKitLocatorFields.path)
    #expect(target.description.contains("home.submit"))
}

@Test("UIKitLocatorInput 拒绝 identifier path 同时存在")
func locatorInputRejectsAmbiguousTarget() throws {
    var decoder = CommandInputDecoder(["accessibilityIdentifier": "home.submit", "path": "root/0"],
                                      schema: CommandInputSchema(fields: [
                                          UIKitLocatorFields.accessibilityIdentifier.erased,
                                          UIKitLocatorFields.path.erased,
                                      ]))
    #expect(throws: CommandInputParseError.self) {
        _ = try UIKitLocatorInput.parse(decoder: &decoder,
                                        identifierField: UIKitLocatorFields.accessibilityIdentifier,
                                        pathField: UIKitLocatorFields.path)
    }
}
```

- [ ] **Step 2: Run locator tests and verify they fail**

Run:

```bash
swift test --filter UIKitLocatorInputTests
```

Expected: compile fails because `UIKitCommandFields.swift` does not exist.

- [ ] **Step 3: Implement UIKit shared fields**

Create `Sources/iOSExploreUIKit/Support/Parsing/UIKitCommandFields.swift`:

```swift
import Foundation
import iOSExploreServer

/// UIKit 查询命令使用的筛选字段。
public enum UIKitFilterFields {
    public static let accessibilityIdentifier = CommandFields.optionalString("accessibilityIdentifier", description: "按 accessibilityIdentifier 精确筛选")
    public static let accessibilityIdentifierPrefix = CommandFields.optionalString("accessibilityIdentifierPrefix", description: "按 accessibilityIdentifier 前缀筛选")
    public static let maxDepth = CommandFields.optionalNonNegativeInt("maxDepth", description: "最大递归深度, 0 表示仅根 view")
    public static let includeHidden = CommandFields.bool("includeHidden", default: false, description: "是否包含隐藏 view")
}

/// UIKit 交互命令使用的定位字段。
public enum UIKitLocatorFields {
    public static let accessibilityIdentifier = CommandFields.optionalString("accessibilityIdentifier", description: "按 accessibilityIdentifier 精确定位目标 view")
    public static let path = CommandFields.optionalString("path", description: "按 ui.viewTargets 或 ui.topViewHierarchy 返回的 root/0/1 路径定位目标 view")
    public static let snapshotID = CommandFields.optionalString("snapshotID", description: "快照标识, 仅用于 path 定位的陈旧校验")
}

/// UIKit 定位输入解析 helper。
public enum UIKitLocatorInput {
    public static func parse(decoder: inout CommandInputDecoder,
                             identifierField: CommandField<String?>,
                             pathField: CommandField<String?>) throws -> UIKitViewLookupTarget {
        let identifier = try decoder.read(identifierField)
        let path = try decoder.read(pathField)
        do {
            return try UIKitViewLookupTarget.parse(identifier: identifier, rawPath: path)
        } catch let error as QueryParseError {
            throw CommandInputParseError(error.message)
        }
    }
}
```

- [ ] **Step 4: Run locator tests and verify task passes**

Run:

```bash
swift test --filter UIKitLocatorInputTests
```

Expected: tests pass. If `UIKitViewLookupTarget.parse` currently throws `QueryParseError` only, keep the translation here until Task 8 removes old parsing types.

- [ ] **Step 5: Commit Task 4**

```bash
git add Sources/iOSExploreUIKit/Support/Parsing/UIKitCommandFields.swift Tests/iOSExploreServerTests/UIKitLocatorInputTests.swift
git commit -m "feat: add UIKit command input fields"
```

---

### Task 5: Migrate ViewTargets and TopViewHierarchy Inputs

**Files:**
- Modify: `Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsModels.swift`
- Modify: `Sources/iOSExploreUIKit/Commands/ViewTargets/ViewTargetsCommand.swift`
- Modify: `Sources/iOSExploreUIKit/Commands/TopViewHierarchy/UIViewHierarchyModels.swift`
- Modify: `Sources/iOSExploreUIKit/Commands/TopViewHierarchy/TopViewHierarchyCommand.swift`
- Modify: `Tests/iOSExploreServerTests/UIKitViewTargetsTests.swift`
- Modify: `Tests/iOSExploreServerTests/UIKitViewHierarchyTests.swift`
- Delete/replace: `Tests/iOSExploreServerTests/UIKitQueryKeyConsistencyTests.swift`

- [ ] **Step 1: Update ViewTargets tests for CommandInput**

In `UIKitViewTargetsTests.swift`, rename parsing test references from `UIViewTargetsQuery.parse(from:)` to `UIViewTargetsInput.parse(from:)` and add:

```swift
@Test("UIViewTargetsInput schema 字段覆盖解析字段")
func viewTargetsInputSchemaCoversFields() throws {
    #expect(UIViewTargetsInput.inputSchema.fields.map(\.name) == [
        "includeHidden",
        "includeDisabled",
        "includeStaticText",
        "includeContainers",
        "maxDepth",
        "accessibilityIdentifier",
        "accessibilityIdentifierPrefix",
        "textLimit",
        "maxTargets",
    ])
}
```

- [ ] **Step 2: Update hierarchy tests for CommandInput**

In `UIKitViewHierarchyTests.swift`, add:

```swift
@Test("UIViewHierarchyInput schema 字段覆盖解析字段")
func hierarchyInputSchemaCoversFields() throws {
    #expect(UIViewHierarchyInput.inputSchema.fields.map(\.name) == [
        "detailLevel",
        "maxDepth",
        "includeHidden",
        "accessibilityIdentifier",
        "accessibilityIdentifierPrefix",
    ])
}
```

- [ ] **Step 3: Run tests and verify they fail**

Run:

```bash
swift test --filter UIKitViewTargetsTests
swift test --filter UIKitViewHierarchyTests
```

Expected: compile fails until inputs are migrated.

- [ ] **Step 4: Migrate `UIViewTargetsQuery` to `UIViewTargetsInput`**

In `UIViewTargetsModels.swift`, rename the query type or add a typealias during migration:

```swift
public struct UIViewTargetsInput: CommandInput, Sendable, Equatable {
    public let includeHidden: Bool
    public let includeDisabled: Bool
    public let includeStaticText: Bool
    public let includeContainers: Bool
    public let maxDepth: Int?
    public let accessibilityIdentifier: String?
    public let accessibilityIdentifierPrefix: String?
    public let textLimit: Int
    public let maxTargets: Int

    enum Fields {
        static let includeHidden = CommandFields.bool("includeHidden", default: false, description: "是否包含隐藏 view")
        static let includeDisabled = CommandFields.bool("includeDisabled", default: true, description: "是否包含 disabled control")
        static let includeStaticText = CommandFields.bool("includeStaticText", default: false, description: "是否包含仅展示文本的节点")
        static let includeContainers = CommandFields.bool("includeContainers", default: false, description: "是否包含普通容器 view")
        static let maxDepth = UIKitFilterFields.maxDepth
        static let accessibilityIdentifier = UIKitFilterFields.accessibilityIdentifier
        static let accessibilityIdentifierPrefix = UIKitFilterFields.accessibilityIdentifierPrefix
        static let textLimit = CommandFields.int("textLimit", range: 1...200, default: 80, description: "title/text/placeholder/value 最大字符数")
        static let maxTargets = CommandFields.int("maxTargets", range: 1...UIKitSnapshotLimits.maxFingerprints, default: 200, description: "单次响应最多返回的目标数")
        static let all = [includeHidden.erased, includeDisabled.erased, includeStaticText.erased, includeContainers.erased, maxDepth.erased, accessibilityIdentifier.erased, accessibilityIdentifierPrefix.erased, textLimit.erased, maxTargets.erased]
    }

    public static let inputSchema = CommandInputSchema(fields: Fields.all)
    public static let `default` = UIViewTargetsInput()

    public init(includeHidden: Bool = false,
                includeDisabled: Bool = true,
                includeStaticText: Bool = false,
                includeContainers: Bool = false,
                maxDepth: Int? = nil,
                accessibilityIdentifier: String? = nil,
                accessibilityIdentifierPrefix: String? = nil,
                textLimit: Int = 80,
                maxTargets: Int = 200) {
        self.includeHidden = includeHidden
        self.includeDisabled = includeDisabled
        self.includeStaticText = includeStaticText
        self.includeContainers = includeContainers
        self.maxDepth = maxDepth
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessibilityIdentifierPrefix = accessibilityIdentifierPrefix
        self.textLimit = textLimit
        self.maxTargets = maxTargets
    }

    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIViewTargetsInput {
        UIViewTargetsInput(includeHidden: try decoder.read(Fields.includeHidden),
                           includeDisabled: try decoder.read(Fields.includeDisabled),
                           includeStaticText: try decoder.read(Fields.includeStaticText),
                           includeContainers: try decoder.read(Fields.includeContainers),
                           maxDepth: try decoder.read(Fields.maxDepth),
                           accessibilityIdentifier: try decoder.read(Fields.accessibilityIdentifier),
                           accessibilityIdentifierPrefix: try decoder.read(Fields.accessibilityIdentifierPrefix),
                           textLimit: try decoder.read(Fields.textLimit),
                           maxTargets: try decoder.read(Fields.maxTargets))
    }
}

public typealias UIViewTargetsQuery = UIViewTargetsInput
```

Keep the typealias only until all references are updated; remove it in Task 8.

- [ ] **Step 5: Migrate ViewTargetsCommand**

In `ViewTargetsCommand.swift`:

```swift
struct ViewTargetsCommand: Command {
    typealias Input = UIViewTargetsInput
    static let actionName = "ui.viewTargets"
    let action = ViewTargetsCommand.actionName
    let description = "返回当前顶部控制器中可用于事件下发的轻量 UI 目标列表"

    func handle(_ input: UIViewTargetsInput) async throws -> ExploreResult {
        UIKitCommandLogging.info("command", "command \(action) execute start includeHidden=\(input.includeHidden) maxTargets=\(input.maxTargets)")
        do {
            let data = try await UIViewTargetsCollector.collect(query: input)
            let targetCount = data["targetCount"]?.doubleValue ?? 0
            let visitedCount = data["visitedNodeCount"]?.doubleValue ?? 0
            UIKitCommandLogging.info("command", "command \(action) execute completed targetCount=\(targetCount) visitedNodeCount=\(visitedCount)")
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        }
    }
}
```

- [ ] **Step 6: Migrate hierarchy input and command**

Repeat the same pattern for `UIViewHierarchyInput`, using fields:

```swift
static let detailLevel = CommandFields.enumValue("detailLevel", type: UIViewHierarchyDetailLevel.self, default: .appearance, description: "详情级别: basic / appearance / full, 默认 appearance")
static let maxDepth = UIKitFilterFields.maxDepth
static let includeHidden = UIKitFilterFields.includeHidden
static let accessibilityIdentifier = UIKitFilterFields.accessibilityIdentifier
static let accessibilityIdentifierPrefix = UIKitFilterFields.accessibilityIdentifierPrefix
```

`TopViewHierarchyCommand.handle(_:)` should accept `UIViewHierarchyInput`, log `execute start`, call `UIViewHierarchyCollector.collectTopViewHierarchy(query:)`, and catch only `UIKitCommandError`.

- [ ] **Step 7: Run tests and verify task passes**

Run:

```bash
swift test --filter UIKitViewTargetsTests
swift test --filter UIKitViewHierarchyTests
```

Expected: both pass.

- [ ] **Step 8: Commit Task 5**

```bash
git add Sources/iOSExploreUIKit/Commands/ViewTargets Sources/iOSExploreUIKit/Commands/TopViewHierarchy Tests/iOSExploreServerTests/UIKitViewTargetsTests.swift Tests/iOSExploreServerTests/UIKitViewHierarchyTests.swift
git commit -m "refactor: migrate UIKit query commands to typed inputs"
```

---

### Task 6: Migrate Tap and ControlAction Inputs

**Files:**
- Modify: `Sources/iOSExploreUIKit/Commands/Tap/UITapModels.swift`
- Modify: `Sources/iOSExploreUIKit/Commands/Tap/UITapCommand.swift`
- Modify: `Sources/iOSExploreUIKit/Commands/ControlAction/UIControlSendActionModels.swift`
- Modify: `Sources/iOSExploreUIKit/Commands/ControlAction/UIControlSendActionCommand.swift`
- Modify: `Tests/iOSExploreServerTests/UIKitTapTests.swift`
- Modify: `Tests/iOSExploreServerTests/UIKitControlActionTests.swift`

- [ ] **Step 1: Add tap input matrix tests**

In `UIKitTapTests.swift`, add parse tests:

```swift
@Test("UITapInput 拒绝坐标缺半和目标混用")
func tapInputRejectsInvalidTargets() throws {
    #expect(throws: CommandInputParseError.self) { try UITapInput.parse(from: ["x": 1]) }
    #expect(throws: CommandInputParseError.self) { try UITapInput.parse(from: ["y": 1]) }
    #expect(throws: CommandInputParseError.self) { try UITapInput.parse(from: ["accessibilityIdentifier": "a", "path": "root/0"]) }
    #expect(throws: CommandInputParseError.self) { try UITapInput.parse(from: ["accessibilityIdentifier": "a", "x": 1, "y": 2]) }
    #expect(throws: CommandInputParseError.self) { try UITapInput.parse(from: ["accessibilityIdentifier": "a", "snapshotID": "s1"]) }
    #expect(throws: CommandInputParseError.self) { try UITapInput.parse(from: ["x": 1, "y": 2, "snapshotID": "s1"]) }
    #expect(throws: CommandInputParseError.self) { try UITapInput.parse(from: ["path": "root/0", "coordinateSpace": "screen"]) }
}

@Test("UITapInput 接受 identifier path 和 window point")
func tapInputAcceptsValidTargets() throws {
    _ = try UITapInput.parse(from: ["accessibilityIdentifier": "home.submit"])
    _ = try UITapInput.parse(from: ["path": "root/0", "snapshotID": "snap"])
    _ = try UITapInput.parse(from: ["x": 1.5, "y": 2.5])
}
```

- [ ] **Step 2: Add control input matrix tests**

In `UIKitControlActionTests.swift`, add:

```swift
@Test("UIControlSendActionInput 拒绝非法事件和目标")
func controlInputRejectsInvalidData() throws {
    #expect(throws: CommandInputParseError.self) { try UIControlSendActionInput.parse(from: ["path": "root/0"]) }
    #expect(throws: CommandInputParseError.self) { try UIControlSendActionInput.parse(from: ["event": "bad", "path": "root/0"]) }
    #expect(throws: CommandInputParseError.self) { try UIControlSendActionInput.parse(from: ["event": "touchUpInside"]) }
    #expect(throws: CommandInputParseError.self) { try UIControlSendActionInput.parse(from: ["event": "touchUpInside", "accessibilityIdentifier": "a", "path": "root/0"]) }
    #expect(throws: CommandInputParseError.self) { try UIControlSendActionInput.parse(from: ["event": "touchUpInside", "accessibilityIdentifier": "a", "snapshotID": "s"]) }
}

@Test("UIControlSendActionInput 接受 identifier 和 path")
func controlInputAcceptsValidTargets() throws {
    _ = try UIControlSendActionInput.parse(from: ["event": "touchUpInside", "accessibilityIdentifier": "home.submit"])
    _ = try UIControlSendActionInput.parse(from: ["event": "touchUpInside", "path": "root/0", "snapshotID": "snap"])
}
```

- [ ] **Step 3: Run tests and verify they fail**

Run:

```bash
swift test --filter UIKitTapTests
swift test --filter UIKitControlActionTests
```

Expected: compile fails until input types are migrated.

- [ ] **Step 4: Implement `UITapInput`**

In `UITapModels.swift`, rename `UITapQuery` to `UITapInput` and add fields:

```swift
public enum UITapCoordinateSpace: String, CaseIterable, Sendable {
    case window
}

public struct UITapInput: CommandInput, Sendable, Equatable {
    enum Fields {
        static let accessibilityIdentifier = UIKitLocatorFields.accessibilityIdentifier
        static let path = UIKitLocatorFields.path
        static let snapshotID = UIKitLocatorFields.snapshotID
        static let x = CommandFields.optionalFiniteNumber("x", description: "window 坐标 x, 需要与 y 同时提供")
        static let y = CommandFields.optionalFiniteNumber("y", description: "window 坐标 y, 需要与 x 同时提供")
        static let coordinateSpace = CommandFields.enumValue("coordinateSpace", type: UITapCoordinateSpace.self, default: .window, description: "坐标空间, 第一版仅支持 window")
        static let all = [accessibilityIdentifier.erased, path.erased, snapshotID.erased, x.erased, y.erased, coordinateSpace.erased]
    }

    public static let inputSchema = CommandInputSchema(fields: Fields.all, constraints: [
        .extensionMessage("snapshotID is valid only with path"),
        .extensionMessage("coordinateSpace currently supports only window"),
    ])

    public let target: UITapTarget
    public let snapshotID: String?

    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UITapInput {
        let identifier = try decoder.read(Fields.accessibilityIdentifier)
        let path = try decoder.read(Fields.path)
        let snapshotID = try decoder.read(Fields.snapshotID)
        let x = try decoder.read(Fields.x)
        let y = try decoder.read(Fields.y)
        _ = try decoder.read(Fields.coordinateSpace)

        let hasViewTarget = identifier != nil || path != nil
        let hasPointTarget = x != nil || y != nil
        if hasViewTarget, hasPointTarget { throw CommandInputParseError("view target and coordinate target are mutually exclusive") }
        if let snapshotID, path == nil { throw CommandInputParseError("snapshotID is valid only with path") }
        if hasPointTarget {
            guard let x, let y else { throw CommandInputParseError("x and y must be provided together") }
            return UITapInput(target: .windowPoint(x: x, y: y), snapshotID: nil)
        }
        let target = try UIKitLocatorInput.parse(decoder: &decoder, identifierField: Fields.accessibilityIdentifier, pathField: Fields.path)
        return UITapInput(target: .view(target), snapshotID: snapshotID)
    }
}

public typealias UITapQuery = UITapInput
```

- [ ] **Step 5: Implement `UIControlSendActionInput`**

In `UIControlSendActionModels.swift`, rename query to input:

```swift
public struct UIControlSendActionInput: CommandInput, Sendable, Equatable {
    enum Fields {
        static let accessibilityIdentifier = UIKitLocatorFields.accessibilityIdentifier
        static let path = UIKitLocatorFields.path
        static let snapshotID = UIKitLocatorFields.snapshotID
        static let event = CommandFields.requiredEnum("event", type: UIControlSendActionEvent.self, description: "事件名")
        static let all = [accessibilityIdentifier.erased, path.erased, snapshotID.erased, event.erased]
    }

    public static let inputSchema = CommandInputSchema(fields: Fields.all, constraints: [
        .exactlyOneOf(["accessibilityIdentifier", "path"]),
        .extensionMessage("snapshotID is valid only with path"),
    ])

    public let target: UIControlSendActionTarget
    public let event: UIControlSendActionEvent
    public let snapshotID: String?

    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIControlSendActionInput {
        let snapshotID = try decoder.read(Fields.snapshotID)
        let identifier = try decoder.read(Fields.accessibilityIdentifier)
        let path = try decoder.read(Fields.path)
        if let snapshotID, path == nil { throw CommandInputParseError("snapshotID is valid only with path") }
        let event = try decoder.read(Fields.event)
        let target = try UIKitViewLookupTarget.parse(identifier: identifier, rawPath: path)
        return UIControlSendActionInput(target: target, event: event, snapshotID: snapshotID)
    }
}

public typealias UIControlSendActionQuery = UIControlSendActionInput
```

If `UIKitViewLookupTarget.parse` still throws `QueryParseError`, catch and translate to `CommandInputParseError` here.

- [ ] **Step 6: Migrate command handlers**

Change `UITapCommand.handle` to:

```swift
func handle(_ input: UITapInput) async throws -> ExploreResult {
    UIKitCommandLogging.info("command", "command \(action) execute start target=\(input.target.description)")
    do {
        let plan = UIKitActionPlan.tap(locator: input.target.locator, snapshotID: input.snapshotID)
        let data = try await UIKitActionExecutor.execute(plan)
        UIKitCommandLogging.info("command", "command \(action) execute completed target=\(input.target.description) dispatchMode=\(data["dispatchMode"]?.stringValue ?? "unknown")")
        return .success(data)
    } catch let error as UIKitCommandError {
        UIKitCommandLogging.error("command", error.failure.logMessage)
        return error.result
    }
}
```

Change `UIControlSendActionCommand.handle` to:

```swift
func handle(_ input: UIControlSendActionInput) async throws -> ExploreResult {
    UIKitCommandLogging.info("command", "command \(action) execute start target=\(input.target.description) event=\(input.event.rawValue)")
    do {
        let plan = UIKitActionPlan.controlEvent(locator: input.target.locator,
                                                event: input.event,
                                                snapshotID: input.snapshotID)
        let data = try await UIKitActionExecutor.execute(plan)
        UIKitCommandLogging.info("command", "command \(action) execute completed target=\(input.target.description) event=\(input.event.rawValue) type=\(data["type"]?.stringValue ?? "unknown")")
        return .success(data)
    } catch let error as UIKitCommandError {
        UIKitCommandLogging.error("command", error.failure.logMessage)
        return error.result
    }
}
```

- [ ] **Step 7: Run tests and verify task passes**

Run:

```bash
swift test --filter UIKitTapTests
swift test --filter UIKitControlActionTests
```

Expected: both pass.

- [ ] **Step 8: Commit Task 6**

```bash
git add Sources/iOSExploreUIKit/Commands/Tap Sources/iOSExploreUIKit/Commands/ControlAction Tests/iOSExploreServerTests/UIKitTapTests.swift Tests/iOSExploreServerTests/UIKitControlActionTests.swift
git commit -m "refactor: migrate UIKit action commands to typed inputs"
```

---

### Task 7: Registration, Example App, and Cleanup

**Files:**
- Modify: `Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift`
- Modify: `Examples/SPMExample/SPMExample/ViewController.swift`
- Modify: `Sources/iOSExploreServer/ExploreCommandSupport.swift`
- Delete or simplify: `Sources/iOSExploreUIKit/Support/Parsing/QueryDecoder.swift`
- Delete or simplify: `Sources/iOSExploreUIKit/Support/Parsing/UIKitQueryParsing.swift`
- Delete: `Tests/iOSExploreServerTests/UIKitQueryKeyConsistencyTests.swift`
- Modify tests with old API references.

- [ ] **Step 1: Search old API references**

Run:

```bash
rg -n "CommandParameter|ParameterKind|parameters:|UIKitQueryParsing|QueryDecoder|QueryParseError|handle\\(ExploreRequest|register\\(action:.*description:.*parameters" Sources Tests Examples README.md docs
```

Expected: many hits before cleanup.

- [ ] **Step 2: Update UIKit registrar logging category**

Modify `UIKitCommandRegistrar.swift`:

```swift
public extension ExploreServer {
    func registerUIKitCommands() {
        UIKitCommandLogging.info("uikit.registrar", "registration started")
        register(TopViewHierarchyCommand(), logCategory: .extensionCommand(category: "command"))
        register(ViewTargetsCommand(), logCategory: .extensionCommand(category: "command"))
        register(UIControlSendActionCommand(), logCategory: .extensionCommand(category: "command"))
        register(UITapCommand(), logCategory: .extensionCommand(category: "command"))
        UIKitCommandLogging.info("uikit.registrar", "registration completed count=4")
    }
}
```

- [ ] **Step 3: Update Example App typed custom commands**

In `Examples/SPMExample/SPMExample/ViewController.swift`, add a local input:

```swift
private struct GreetInput: CommandInput, Equatable {
    static let name = CommandFields.optionalString("name", description: "姓名")
    static let inputSchema = CommandInputSchema(fields: [name.erased])
    let nameValue: String

    static func parse(decoding decoder: inout CommandInputDecoder) throws -> GreetInput {
        GreetInput(nameValue: try decoder.read(name) ?? "world")
    }
}
```

Replace custom registration:

```swift
server.register(action: "greet", description: "按 name 打招呼", input: GreetInput.self) { input in
    .success(["message": .string("Hello, \(input.nameValue)")])
}
server.register(action: "device", description: "返回设备机型与名称(UIKit 注入)", input: EmptyCommandInput.self) { _ in
    await MainActor.run {
        .success(["model": .string(UIDevice.current.model),
                  "name": .string(UIDevice.current.name)])
    }
}
```

- [ ] **Step 4: Remove old parsing infrastructure**

Delete `Tests/iOSExploreServerTests/UIKitQueryKeyConsistencyTests.swift`.

If no references remain, delete:

```bash
git rm Sources/iOSExploreUIKit/Support/Parsing/QueryDecoder.swift
git rm Sources/iOSExploreUIKit/Support/Parsing/UIKitQueryParsing.swift
git rm Tests/iOSExploreServerTests/UIKitQueryKeyConsistencyTests.swift
```

If `QueryParseError` is still used by locator helpers, keep only that error type in a small file or migrate it to `CommandInputParseError`.

- [ ] **Step 5: Run cleanup search**

Run:

```bash
rg -n "CommandParameter|ParameterKind|parameters:|UIKitQueryParsing|QueryDecoder|handle\\(ExploreRequest|register\\(action:.*description:.*parameters" Sources Tests Examples
```

Expected: no results except documentation files that are intentionally updated in Task 8.

- [ ] **Step 6: Run focused tests**

Run:

```bash
swift test --filter UIKitCommandRegistrationTests
swift test --filter ExploreCommandSupportTests
```

Expected: pass.

- [ ] **Step 7: Commit Task 7**

```bash
git add Sources Tests Examples
git commit -m "chore: remove legacy command parameter APIs"
```

---

### Task 8: Documentation and Full Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/architecture/index.md`
- Modify: `docs/tools/network-tools.md`
- Modify: `docs/uikit/README.md`
- Modify: `docs/uikit/reading-guide.md`
- Modify: `docs/uikit/uikit-file-reference.md`

- [ ] **Step 1: Update docs examples**

Search:

```bash
rg -n "parameters|CommandParameter|register\\(action|help|inputSchema" README.md docs
```

Replace old command registration examples with:

```swift
struct GreetInput: CommandInput {
    static let name = CommandFields.optionalString("name", description: "姓名")
    static let inputSchema = CommandInputSchema(fields: [name.erased])
    let nameValue: String

    static func parse(decoding decoder: inout CommandInputDecoder) throws -> GreetInput {
        GreetInput(nameValue: try decoder.read(name) ?? "world")
    }
}

server.register(action: "greet", description: "按 name 打招呼", input: GreetInput.self) { input in
    .success(["message": .string("Hello, \(input.nameValue)")])
}
```

Replace help examples with `inputSchema`:

```json
{
  "action": "ui.viewTargets",
  "description": "返回当前顶部控制器中可用于事件下发的轻量 UI 目标列表",
  "inputSchema": {
    "type": "object",
    "properties": {
      "maxTargets": {
        "type": "integer",
        "minimum": 1,
        "maximum": 512,
        "default": 200,
        "description": "单次响应最多返回的目标数"
      }
    },
    "required": [],
    "additionalProperties": false
  }
}
```

- [ ] **Step 2: Run full SwiftPM tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 3: Run framework build**

Run:

```bash
xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator build
```

Expected: build succeeds under framework Swift 5 language mode.

- [ ] **Step 4: Run final old API search**

Run:

```bash
rg -n "CommandParameter|ParameterKind|parameters: \\[|UIKitQueryParsing|QueryDecoder" Sources Tests Examples README.md docs
```

Expected: no old API references except historical spec/plan docs under `docs/superpowers/`.

- [ ] **Step 5: Commit Task 8**

```bash
git add README.md docs
git commit -m "docs: document typed command input schemas"
```

---

## Self-Review Checklist

- [ ] Spec coverage: typed input protocol, AnyCommand, field schema, `inputSchema`, UIKit tap/control constraints, UIKit logging responsibility, tests, docs, and validation gates all map to tasks above.
- [ ] Placeholder scan: no unresolved placeholders and no "write tests" without named test cases.
- [ ] Type consistency: use `CommandInput`, `CommandInputSchema`, `CommandField`, `AnyCommandField`, `CommandInputDecoder`, `CommandInputParseError`, `AnyCommand`, `CommandLogCategory` consistently.
- [ ] Verification: every task includes at least one focused test command; final task includes `swift test` and framework `xcodebuild`.
