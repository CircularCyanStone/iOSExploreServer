# Command Input Parser Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 降低命令输入解析模块的阅读和维护成本，同时保持 HTTP 行为、public Swift API、generated contracts 输出和 typed parse 语义不变。

**Architecture:** 保留 `CommandInput.parse(from:) -> CommandInputDecoder -> CommandField.decode` 这条 seam，不改变调用方使用方式。第一轮只做行为锁定、文件拆分和内部 helper 提取；`CommandInputConstraint` 仍是 schema-only contract hint，不升级为运行时 validator。

**Tech Stack:** Swift Package Manager, Swift Testing, iOSExploreServer core, generated Swift contracts from `iOSDriver/src/contracts/generator/emitSwift.ts`.

---

### Task 1: Add HTTP Invalid Data Characterization Test

**Files:**
- Modify: `Tests/iOSExploreServerTests/IntegrationTests.swift`

- [x] **Step 1: Add the characterization test**

Add this test after `endToEndCustom()` in `IntegrationTests`:

```swift
@Test("typed input 缺必填字段经 HTTP 返回 invalid_data envelope")
func endToEndTypedInputMissingRequiredFieldReturnsInvalidData() async throws {
    let server = ExploreServer(port: testPort)
    server.register(action: "greet", input: IntegrationGreetingInput.self) { input in
        .success(["message": .string("Hello, \(input.name)")])
    }
    try await startWithPortRetry(server)
    defer { server.stop() }

    let text = try await send(action: "greet")
    #expect(text.contains("200 OK"))
    #expect(text.contains(#""code":"invalid_data""#))
    #expect(text.contains("name"))
    #expect(!text.contains(#""ok":"#))
    #expect(!text.contains(#""error":"#))
}
```

- [x] **Step 2: Run the focused test**

Run:

```bash
swift test --filter IntegrationTests/endToEndTypedInputMissingRequiredFieldReturnsInvalidData
```

Expected: PASS. This is a characterization test for existing behavior, not a new behavior change; if it fails, fix the production behavior only after reporting the failure details.

- [x] **Step 3: Run adjacent existing HTTP tests**

Run:

```bash
swift test --filter IntegrationTests
```

Expected: PASS for the serialized HTTP integration suite.

### Task 2: Split CommandField.swift Without API or Behavior Changes

**Files:**
- Modify: `Sources/iOSExploreServer/Commands/CommandField.swift`
- Create: `Sources/iOSExploreServer/Commands/CommandFieldSchema.swift`
- Create: `Sources/iOSExploreServer/Commands/CommandFields+String.swift`
- Create: `Sources/iOSExploreServer/Commands/CommandFields+Array.swift`
- Create: `Sources/iOSExploreServer/Commands/CommandFields+Number.swift`

- [x] **Step 1: Move schema-only declarations**

Move these declarations verbatim from `CommandField.swift` to `CommandFieldSchema.swift`:

Move the complete current declarations whose headers are:

```swift
public enum CommandJSONSchemaType: String, Sendable, Equatable
public struct CommandFieldSchema: Sendable, Equatable
public struct AnyCommandField: Sendable, Equatable
```

Keep each declaration body, documentation comments, access levels, initializer signatures, stored properties, and `toJSON()` behavior unchanged.

- [x] **Step 2: Keep the typed field in CommandField.swift**

Leave only this declaration in `CommandField.swift`:

Keep the complete current declaration whose header is:

```swift
public struct CommandField<Value: Sendable>: Sendable
```

Keep `name`, `schema`, internal `decode`, `.erased`, and the internal initializer unchanged.

- [x] **Step 3: Split string and enum factories**

Create `CommandFields+String.swift` containing:

```swift
public extension CommandFields {
    // Move the complete current implementations of these factories:
    // optionalString(_:description:)
    // requiredString(_:description:)
    // requiredStringEnum(_:values:description:)
    // stringEnum(_:values:default:description:)
    // optionalStringEnum(_:values:description:)
    // enumValue(_:type:default:description:)
    // requiredEnum(_:type:description:)
}
```

Do not redeclare `public enum CommandFields` in this file; it must have exactly one declaration in the module.

- [x] **Step 4: Split array factories**

Create `CommandFields+Array.swift` containing:

```swift
public extension CommandFields {
    // Move the complete current implementations of these factories:
    // requiredArray(_:description:itemsSchema:minimumCount:maximumCount:)
    // optionalStringEnumArray(_:values:itemDescription:description:)
}
```

Keep schema output and decode behavior unchanged.

- [x] **Step 5: Split boolean and numeric factories**

Create `CommandFields+Number.swift` containing:

```swift
public enum CommandFields {
    private static let jsonSafeIntegerLimit = 9_007_199_254_740_991
}

public extension CommandFields {
    // Move the complete current implementations of these factories:
    // bool(_:default:description:)
    // optionalFiniteNumber(_:minimum:maximum:exclusiveMinimum:exclusiveMaximum:description:)
    // finiteNumber(_:default:minimum:maximum:exclusiveMinimum:exclusiveMaximum:description:)
    // number(_:required:description:)
    // optionalNonNegativeInt(_:description:)
    // optionalInt(_:minimum:maximum:description:)
    // requiredInt(_:range:description:)
    // int(_:range:default:description:)
}
```

Also move these private helpers into the same enum/extension file:

```swift
private static func parseInteger(_ raw: JSONValue, name: String) throws -> Int?
private static func finiteNumberSchema(description: String, defaultValue: Double?, minimum: Double?, maximum: Double?, exclusiveMinimum: Bool, exclusiveMaximum: Bool) -> CommandFieldSchema
private static func validateFiniteNumberBounds(name: String, minimum: Double?, maximum: Double?, exclusiveMinimum: Bool, exclusiveMaximum: Bool)
private static func finiteNumberIsWithinBounds(_ value: Double, minimum: Double?, maximum: Double?, exclusiveMinimum: Bool, exclusiveMaximum: Bool) -> Bool
private static func isJSONSafeInteger(_ value: Int) -> Bool
```

If Swift rejects private static helpers from an extension because of placement, keep `jsonSafeIntegerLimit` and helpers in the base `public enum CommandFields` body and factories in extensions.

- [x] **Step 6: Run focused core parser tests**

Run:

```bash
swift test --filter CommandInputDecoderTests
swift test --filter CommandInputSchemaTests
swift test --filter GeneratedCommandFieldTests
```

Expected: all PASS.

### Task 3: Extract CommandInputDecoder Declaration Matching Helper

**Files:**
- Modify: `Sources/iOSExploreServer/Commands/CommandInputDecoder.swift`
- Test: `Tests/iOSExploreServerTests/CommandInputDecoderTests.swift`

- [x] **Step 1: Confirm existing tests cover the behavior**

Run:

```bash
swift test --filter CommandInputDecoderTests
```

Expected: PASS before refactor.

- [x] **Step 2: Add a private helper**

Inside `CommandInputDecoder`, add:

```swift
private mutating func declaredField(matching field: AnyCommandField) throws -> AnyCommandField {
    guard let declaredField = schema.fields.first(where: { $0.name == field.name }) else {
        throw CommandInputParseError("command input field '\(field.name)' is not declared in schema")
    }
    guard declaredField.schema == field.schema else {
        throw CommandInputParseError("command input field '\(field.name)' schema does not match declaration")
    }
    readFieldNames.insert(field.name)
    return declaredField
}
```

Use it from `read(_:)`, `readRaw(_:)`, and `contains(_:)`. For typed fields, call it with `field.erased` and then run `field.decode(data[field.name])`.

- [x] **Step 3: Run focused tests**

Run:

```bash
swift test --filter CommandInputDecoderTests
```

Expected: PASS.

### Task 4: Clarify Schema-Only Constraints Without Changing Runtime Semantics

**Files:**
- Modify: `Sources/iOSExploreServer/Commands/CommandInputSchema.swift`
- Test: `Tests/iOSExploreServerTests/CommandInputSchemaTests.swift`

- [x] **Step 1: Rename comments, not public symbols**

Keep `CommandInputConstraint` public symbol unchanged. Update comments around `CommandInputConstraint` and `CommandInputSchema.toJSON()` to consistently call these "schema-only constraints" or "schema-only hints". Do not imply runtime enforcement.

- [x] **Step 2: Add a small schema-only documentation test if missing**

If there is no test proving `exactlyOneOf` only affects schema JSON, add a test to `CommandInputSchemaTests.swift` that builds a schema with `.exactlyOneOf(["a", "b"])`, calls `toJSON()`, and asserts the output contains `oneOf`. Do not add runtime parser enforcement.

- [x] **Step 3: Run focused tests**

Run:

```bash
swift test --filter CommandInputSchemaTests
```

Expected: PASS.

### Task 5: Final Verification

**Files:**
- No additional source changes.

- [x] **Step 1: Run parser and contract compatibility tests**

Run:

```bash
swift test --filter CommandInputDecoderTests
swift test --filter CommandInputSchemaTests
swift test --filter GeneratedCommandFieldTests
swift test --filter CommandTests
swift test --filter RouterTests
swift test --filter UIKitContractParserCompatibilityTests
swift test --filter DiagnosticsContractParserCompatibilityTests
swift test --filter UIKitCommandInputSchemaTests
swift test --filter IntegrationTests
```

Expected: all PASS. If one of these filters cannot run in the current platform because UIKit is unavailable, report the exact command and output instead of claiming it passed.

- [x] **Step 2: Confirm no generated output drift**

Run:

```bash
git diff -- Sources/iOSExploreServer/Generated Sources/iOSExploreUIKit/Generated Sources/iOSExploreDiagnostics/Generated iOSDriver/src/contracts/generator/emitSwift.ts
```

Expected: no diff. This first refactor must not hand-edit generated contracts or alter the Swift generator.
