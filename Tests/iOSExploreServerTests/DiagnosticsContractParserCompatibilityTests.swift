import Testing
@testable import iOSExploreDiagnostics
@testable import iOSExploreServer

@Suite("DiagnosticsContractParserCompatibilityTests")
struct DiagnosticsContractParserCompatibilityTests {
    @Test("mark/read 使用 generated 输入字段")
    func commandInputsUseGeneratedDefinitions() {
        #expect(EmptyCommandInput.inputDefinition.fields.isEmpty)
        #expect(ESAppLogsReadInput.inputDefinition.fields.map(\.name) ==
                DiagnosticsActionContracts.appLogsReadInput.fields.map(\.name))
    }

    @Test("read 空输入使用默认值")
    func emptyInputUsesDefaults() throws {
        let input = try ESAppLogsReadInput.parse(from: [:])

        #expect(input.after == nil)
        #expect(input.limit == 100)
        #expect(input.sources == nil)
        #expect(input.minimumLevel == nil)
    }

    @Test("read cursor 接受合法值并拒绝缺失或非法 id")
    func cursorValidationMatchesExistingParser() throws {
        let input = try ESAppLogsReadInput.parse(from: [
            "after": .object([
                "captureSessionID": "capture-1",
                "id": 42,
            ]),
        ])

        #expect(input.after == ESAppLogCursor(captureSessionID: "capture-1", id: 42))
        let boundaryInput = try ESAppLogsReadInput.parse(from: [
            "after": .object([
                "captureSessionID": "capture-1",
                "id": .double(9_007_199_254_740_991),
            ]),
        ])
        #expect(boundaryInput.after == ESAppLogCursor(captureSessionID: "capture-1",
                                                      id: 9_007_199_254_740_991))
        #expect(throws: CommandInputParseError.self) {
            _ = try ESAppLogsReadInput.parse(from: [
                "after": .object(["id": 42]),
            ])
        }
        #expect(throws: CommandInputParseError.self) {
            _ = try ESAppLogsReadInput.parse(from: [
                "after": .object([
                    "captureSessionID": "capture-1",
                    "id": -1,
                ]),
            ])
        }
        #expect(throws: CommandInputParseError.self) {
            _ = try ESAppLogsReadInput.parse(from: [
                "after": .object([
                    "captureSessionID": "capture-1",
                    "id": 1.5,
                ]),
            ])
        }
        #expect(throws: CommandInputParseError.self) {
            _ = try ESAppLogsReadInput.parse(from: [
                "after": .object([
                    "captureSessionID": "capture-1",
                    "id": .double(9_007_199_254_740_992),
                ]),
            ])
        }
        #expect(throws: CommandInputParseError.self) {
            _ = try ESAppLogsReadInput.parse(from: [
                "after": .object([
                    "captureSessionID": "capture-1",
                    "id": .double(Double.greatestFiniteMagnitude),
                ]),
            ])
        }
    }

    @Test("read limit 接受边界并拒绝越界或非整数")
    func limitValidationMatchesExistingParser() throws {
        #expect(try ESAppLogsReadInput.parse(from: ["limit": 1]).limit == 1)
        #expect(try ESAppLogsReadInput.parse(from: ["limit": 500]).limit == 500)

        for invalidLimit: JSONValue in [0, 501, 1.5, "100"] {
            #expect(throws: CommandInputParseError.self) {
                _ = try ESAppLogsReadInput.parse(from: ["limit": invalidLimit])
            }
        }
    }

    @Test("read sources 接受合法来源并拒绝非法来源或类型")
    func sourcesValidationMatchesExistingParser() throws {
        let input = try ESAppLogsReadInput.parse(from: [
            "sources": .array(["bridge", "stderr", "bridge"]),
        ])

        #expect(input.sources == [.bridge, .stderr])
        #expect(throws: CommandInputParseError.self) {
            _ = try ESAppLogsReadInput.parse(from: [
                "sources": .array(["bridge", "unsupported"]),
            ])
        }
        #expect(throws: CommandInputParseError.self) {
            _ = try ESAppLogsReadInput.parse(from: ["sources": "bridge"])
        }
    }

    @Test("read minimumLevel 接受合法等级并拒绝非法等级或类型")
    func minimumLevelValidationMatchesExistingParser() throws {
        let input = try ESAppLogsReadInput.parse(from: ["minimumLevel": "error"])

        #expect(input.minimumLevel == .error)
        #expect(try ESAppLogsReadInput.parse(from: ["minimumLevel": nil]).minimumLevel == nil)
        #expect(throws: CommandInputParseError.self) {
            _ = try ESAppLogsReadInput.parse(from: ["minimumLevel": "warning"])
        }
        #expect(throws: CommandInputParseError.self) {
            _ = try ESAppLogsReadInput.parse(from: ["minimumLevel": 3])
        }
    }

    @Test("read 拒绝顶层未知字段")
    func unknownTopLevelFieldIsRejected() {
        #expect(throws: CommandInputParseError.self) {
            _ = try ESAppLogsReadInput.parse(from: ["unexpected": true])
        }
    }

    @Test("generated definition 中声明但未读取的字段触发守卫")
    func generatedDefinitionRejectsUnreadFields() {
        do {
            _ = try IncompleteGeneratedDiagnosticsInput.parse(from: [:])
            Issue.record("expected generated definition unread-field guard to fail")
        } catch let error as CommandInputParseError {
            #expect(error.message.contains("declared but not read"))
        } catch {
            Issue.record("expected CommandInputParseError, got \(error)")
        }
    }
}

private struct IncompleteGeneratedDiagnosticsInput: CommandInput {
    static let inputDefinition = DiagnosticsActionContracts.appLogsReadInput

    let limit: Int

    static func parse(decoding decoder: inout CommandInputDecoder) throws -> Self {
        Self(limit: try decoder.read(DiagnosticsActionContracts.appLogsReadLimitField))
    }
}
