import Foundation
import iOSExploreServer

struct ESAppLogsMarkCommand: Command {
    typealias Input = EmptyCommandInput

    let contract = DiagnosticsActionContracts.appLogsMarkContract

    private let runtime: ESDiagnosticsRuntime

    init(runtime: ESDiagnosticsRuntime) {
        self.runtime = runtime
    }

    func handle(_ input: EmptyCommandInput) async throws -> ExploreResult {
        guard let store = runtime.currentStore() else {
            return ESDiagnosticsCommandError.runtimeNotInstalled(action: action).result
        }
        return .success(Self.toJSON(store.mark(), capture: runtime.captureStatusJSON()))
    }

    private static func toJSON(_ snapshot: ESAppLogMarkSnapshot, capture: JSON) -> JSON {
        [
            "cursor": .object(snapshot.cursor.toJSON()),
            "oldestAvailableID": snapshot.oldestAvailableID.map { .double(Double($0)) } ?? .null,
            "latestAvailableID": .double(Double(snapshot.latestAvailableID)),
            "capture": .object(capture),
        ]
    }
}

struct ESAppLogsReadCommand: Command {
    typealias Input = ESAppLogsReadInput

    let contract = DiagnosticsActionContracts.appLogsReadContract

    private let runtime: ESDiagnosticsRuntime

    init(runtime: ESDiagnosticsRuntime) {
        self.runtime = runtime
    }

    func handle(_ input: ESAppLogsReadInput) async throws -> ExploreResult {
        guard let store = runtime.currentStore() else {
            return ESDiagnosticsCommandError.runtimeNotInstalled(action: action).result
        }
        runtime.flushPendingCaptures()
        let result = store.read(after: input.after,
                                limit: input.limit,
                                sources: input.sources,
                                minimumLevel: input.minimumLevel)
        if result.staleCursorCurrentSessionID != nil {
            return ESDiagnosticsCommandError.staleCursor(action: action,
                                                       currentSessionID: result.staleCursorCurrentSessionID).result
        }
        return .success(Self.toJSON(result, capture: runtime.captureStatusJSON()))
    }

    private static func toJSON(_ result: ESAppLogReadResult, capture: JSON) -> JSON {
        [
            "entries": .array(result.entries.map { .object($0.toJSON()) }),
            "nextCursor": .object(result.nextCursor.toJSON()),
            "capturedThrough": .object(result.capturedThrough.toJSON()),
            "hasMore": .bool(result.hasMore),
            "gap": result.gap.map { .object($0.toJSON()) } ?? .null,
            "oldestAvailableID": result.oldestAvailableID.map { .double(Double($0)) } ?? .null,
            "capture": .object(capture),
        ]
    }
}

struct ESAppLogsReadInput: CommandInput {
    private static let maximumCursorID = 9_007_199_254_740_991

    let after: ESAppLogCursor?
    let limit: Int
    let sources: Set<ESAppLogSource>?
    let minimumLevel: ESAppLogLevel?

    static let inputSchema = DiagnosticsActionContracts.appLogsReadInputSchema

    static func parse(from data: JSON) throws -> ESAppLogsReadInput {
        var decoder = CommandInputDecoder(data, schema: inputSchema)
        try decoder.validateNoUnknownFields()

        let after = try parseCursor(decoder.readRaw(DiagnosticsActionContracts.appLogsReadAfterField))
        let limit = try decoder.read(DiagnosticsActionContracts.appLogsReadLimitField)
        let rawSources = try decoder.read(DiagnosticsActionContracts.appLogsReadSourcesField)
        let rawMinimumLevel = try decoder.read(DiagnosticsActionContracts.appLogsReadMinimumLevelField)
        let sources = try parseSources(rawSources)
        let minimumLevel = try parseMinimumLevel(rawMinimumLevel)

        try decoder.assertAllDeclaredFieldsRead()
        return ESAppLogsReadInput(after: after,
                                  limit: limit,
                                  sources: sources,
                                  minimumLevel: minimumLevel)
    }

    static func parse(decoding decoder: inout CommandInputDecoder) throws -> ESAppLogsReadInput {
        throw CommandInputParseError("app.logs.read uses a custom parser")
    }

    private static func parseCursor(_ raw: JSONValue?) throws -> ESAppLogCursor? {
        guard let raw, raw != .null else { return nil }
        guard let object = raw.objectValue,
              let captureSessionID = object["captureSessionID"]?.stringValue,
              let idDouble = object["id"]?.doubleValue,
              idDouble.isFinite,
              idDouble >= 0,
              idDouble <= Double(maximumCursorID),
              idDouble.rounded(.towardZero) == idDouble,
              let id = UInt64(exactly: idDouble) else {
            throw CommandInputParseError("after must be an object with captureSessionID and id")
        }
        return ESAppLogCursor(captureSessionID: captureSessionID, id: id)
    }

    private static func parseSources(_ values: [String]?) throws -> Set<ESAppLogSource>? {
        guard let values else { return nil }
        var sources = Set<ESAppLogSource>()
        for value in values {
            guard let source = ESAppLogSource(rawValue: value) else {
                throw CommandInputParseError("sources contains unsupported value")
            }
            sources.insert(source)
        }
        return sources
    }

    private static func parseMinimumLevel(_ rawLevel: String?) throws -> ESAppLogLevel? {
        guard let rawLevel else { return nil }
        guard let level = ESAppLogLevel(rawValue: rawLevel) else {
            throw CommandInputParseError("minimumLevel must be a valid log level")
        }
        return level
    }
}

private extension ESAppLogCursor {
    func toJSON() -> JSON {
        [
            "captureSessionID": .string(captureSessionID),
            "id": .double(Double(id)),
        ]
    }
}

private extension ESAppLogEntry {
    func toJSON() -> JSON {
        [
            "id": .double(Double(id)),
            "timestamp": .string(ISO8601DateFormatter().string(from: timestamp)),
            "source": .string(source.rawValue),
            "level": .string(level.rawValue),
            "category": category.map { .string($0) } ?? .null,
            "message": .string(message),
            "messageTruncated": .bool(messageTruncated),
            "metadata": metadata.map { metadata in .object(JSON(metadata.mapValues { .string($0) })) } ?? .null,
        ]
    }
}

private extension ESAppLogGap {
    func toJSON() -> JSON {
        switch self {
        case .bufferOverrun(let requestedAfterID, let oldestAvailableID, let lostRange):
            return [
                "kind": .string("bufferOverrun"),
                "requestedAfterID": .double(Double(requestedAfterID)),
                "oldestAvailableID": .double(Double(oldestAvailableID)),
                "lostIDRange": .object([
                    "from": .double(Double(lostRange.lowerBound)),
                    "to": .double(Double(lostRange.upperBound)),
                ]),
            ]
        }
    }
}
