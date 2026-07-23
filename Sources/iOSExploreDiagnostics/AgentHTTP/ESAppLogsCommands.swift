import Foundation
import iOSExploreServer

struct ESAppLogsMarkCommand: Command {
    typealias Input = EmptyCommandInput

    let action = "app.logs.mark"
    let description = "建立当前进程日志检查点"

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

    let action = "app.logs.read"
    let description = "读取当前进程内已捕获的日志"

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
    let after: ESAppLogCursor?
    let limit: Int
    let sources: Set<ESAppLogSource>?
    let minimumLevel: ESAppLogLevel?

    static let inputSchema = CommandInputSchema(fields: [
        AnyCommandField(name: "after",
                        schema: CommandFieldSchema(type: .object,
                                                   required: false,
                                                   description: "增量读取起点 cursor；省略时返回当前可见的最近 limit 条。",
                                                   allowsNull: true)),
        AnyCommandField(name: "limit",
                        schema: CommandFieldSchema(type: .integer,
                                                   required: false,
                                                   description: "最多返回 entry 数量。",
                                                   defaultValue: .double(100),
                                                   minimum: 1,
                                                   maximum: 500)),
        AnyCommandField(name: "sources",
                        schema: CommandFieldSchema(type: .array,
                                                   required: false,
                                                   description: "可选日志来源过滤，支持 explore、bridge、stdout、stderr、nslog、oslog。",
                                                   allowsNull: true,
                                                   enumValues: ESAppLogSource.allCases.map(\.rawValue))),
        AnyCommandField(name: "minimumLevel",
                        schema: CommandFieldSchema(type: .string,
                                                   required: false,
                                                   description: "可选最低日志等级过滤。",
                                                   allowsNull: true,
                                                   enumValues: ESAppLogLevel.allCases.map(\.rawValue))),
    ])

    static func parse(from data: JSON) throws -> ESAppLogsReadInput {
        try rejectUnknownFields(data, allowed: ["after", "limit", "sources", "minimumLevel"])
        return ESAppLogsReadInput(after: try parseCursor(data["after"]),
                                limit: try parseLimit(data["limit"]),
                                sources: try parseSources(data["sources"]),
                                minimumLevel: try parseMinimumLevel(data["minimumLevel"]))
    }

    static func parse(decoding decoder: inout CommandInputDecoder) throws -> ESAppLogsReadInput {
        throw CommandInputParseError("app.logs.read uses a custom parser")
    }

    private static func rejectUnknownFields(_ data: JSON, allowed: Set<String>) throws {
        let unknown = data.storage.keys.first { allowed.contains($0) == false }
        if let unknown {
            throw CommandInputParseError("unknown parameter '\(unknown)'")
        }
    }

    private static func parseCursor(_ raw: JSONValue?) throws -> ESAppLogCursor? {
        guard let raw, raw != .null else { return nil }
        guard let object = raw.objectValue,
              let captureSessionID = object["captureSessionID"]?.stringValue,
              let idDouble = object["id"]?.doubleValue,
              idDouble.isFinite,
              idDouble >= 0,
              idDouble.rounded(.towardZero) == idDouble else {
            throw CommandInputParseError("after must be an object with captureSessionID and id")
        }
        return ESAppLogCursor(captureSessionID: captureSessionID, id: UInt64(idDouble))
    }

    private static func parseLimit(_ raw: JSONValue?) throws -> Int {
        guard let raw, raw != .null else { return 100 }
        guard let limit = raw.doubleValue,
              limit.isFinite,
              limit.rounded(.towardZero) == limit,
              limit >= 1,
              limit <= 500 else {
            throw CommandInputParseError("limit must be an integer between 1 and 500")
        }
        return Int(limit)
    }

    private static func parseSources(_ raw: JSONValue?) throws -> Set<ESAppLogSource>? {
        guard let raw, raw != .null else { return nil }
        guard let values = raw.arrayValue else {
            throw CommandInputParseError("sources must be an array")
        }
        var sources = Set<ESAppLogSource>()
        for value in values {
            guard let rawSource = value.stringValue,
                  let source = ESAppLogSource(rawValue: rawSource) else {
                throw CommandInputParseError("sources contains unsupported value")
            }
            sources.insert(source)
        }
        return sources
    }

    private static func parseMinimumLevel(_ raw: JSONValue?) throws -> ESAppLogLevel? {
        guard let raw, raw != .null else { return nil }
        guard let rawLevel = raw.stringValue,
              let level = ESAppLogLevel(rawValue: rawLevel) else {
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
