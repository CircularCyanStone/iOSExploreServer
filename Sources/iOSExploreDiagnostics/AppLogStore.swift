import Foundation
import iOSExploreServer

private struct AppLogStoreState: Sendable {
    var nextID: UInt64 = 1
    var entries: [AppLogEntry] = []
}

/// 有界进程日志存储。
///
/// `AppLogStore` 是 Diagnostics Runtime 的内存事实来源：所有日志先完成脱敏和截断，再在锁内
/// 分配物理 id、写入 ring buffer。锁内不执行 IO、不 await，适合被日志高频路径调用。
public final class AppLogStore: Sendable {
    private let captureSessionID: String
    private let capacity: Int
    private let maximumEntryBytes: Int
    private let maximumMetadataEntries: Int
    private let maximumMetadataKeyBytes: Int
    private let maximumMetadataValueBytes: Int
    private let redactor: LogRedactor
    private let state = Mutex(AppLogStoreState())

    /// 创建日志 store。
    ///
    /// - Parameters:
    ///   - captureSessionID: 当前进程级 Diagnostics Runtime 标识。
    ///   - capacity: 最多保留的 entry 数量，至少为 1。
    ///   - maximumEntryBytes: 单条 message 最大 UTF-8 字节数，至少为 1。
    ///   - maximumMetadataEntries: 单条 entry 最多保留的 metadata 数量，0 表示不保留。
    ///   - maximumMetadataKeyBytes: 单个 metadata key 最大 UTF-8 字节数，至少为 1。
    ///   - maximumMetadataValueBytes: 单个 metadata value 最大 UTF-8 字节数，至少为 1。
    ///   - redactor: 写入前使用的脱敏器。
    public init(captureSessionID: String,
                capacity: Int,
                maximumEntryBytes: Int,
                maximumMetadataEntries: Int = 32,
                maximumMetadataKeyBytes: Int = 128,
                maximumMetadataValueBytes: Int = 1024,
                redactor: LogRedactor = .standard) {
        self.captureSessionID = captureSessionID
        self.capacity = max(1, capacity)
        self.maximumEntryBytes = max(1, maximumEntryBytes)
        self.maximumMetadataEntries = max(0, maximumMetadataEntries)
        self.maximumMetadataKeyBytes = max(1, maximumMetadataKeyBytes)
        self.maximumMetadataValueBytes = max(1, maximumMetadataValueBytes)
        self.redactor = redactor
    }

    /// 追加一条日志。
    ///
    /// - Parameters:
    ///   - source: 日志来源。
    ///   - level: 日志等级。
    ///   - category: 来源内分类。
    ///   - message: 原始日志正文，写入前会脱敏和截断。
    ///   - metadata: 原始轻量上下文，写入前会脱敏。
    /// - Returns: store 分配的物理日志 id。
    @discardableResult
    public func append(source: AppLogSource,
                       level: AppLogLevel,
                       category: String?,
                       message: String,
                       metadata: [String: String]? = nil) -> UInt64 {
        let redactedMessage = redactor.redactMessage(message)
        let truncated = Self.truncate(redactedMessage, maximumBytes: maximumEntryBytes)
        let boundedMetadata = boundedMetadata(metadata)
        return state.withLock { state in
            let id = state.nextID
            state.nextID += 1
            let entry = AppLogEntry(id: id,
                                    timestamp: Date(),
                                    source: source,
                                    level: level,
                                    category: category,
                                    message: truncated.value,
                                    messageTruncated: truncated.truncated,
                                    metadata: boundedMetadata)
            state.entries.append(entry)
            if state.entries.count > capacity {
                state.entries.removeFirst(state.entries.count - capacity)
            }
            return id
        }
    }

    /// 建立当前日志检查点。
    ///
    /// - Returns: 最新 cursor 与当前可用 id 范围。
    public func mark() -> AppLogMarkSnapshot {
        state.withLock { state in
            AppLogMarkSnapshot(cursor: AppLogCursor(captureSessionID: captureSessionID, id: state.nextID - 1),
                               oldestAvailableID: state.entries.first?.id,
                               latestAvailableID: state.nextID - 1)
        }
    }

    /// 读取日志。
    ///
    /// - Parameters:
    ///   - after: 增量读取起点；为 nil 时读取当前 ring buffer 中最近的记录。
    ///   - limit: 最多返回 entry 数量。
    ///   - sources: 可选来源过滤。
    ///   - minimumLevel: 可选等级过滤；`.unknown` 仅在调用方显式传入 `.unknown` 时参与比较。
    /// - Returns: 读取结果，包含分页 cursor、gap 与 stale cursor 状态。
    public func read(after: AppLogCursor?,
                     limit: Int,
                     sources: Set<AppLogSource>?,
                     minimumLevel: AppLogLevel?) -> AppLogReadResult {
        state.withLock { state in
            let latestID = state.nextID - 1
            let capturedThrough = AppLogCursor(captureSessionID: captureSessionID, id: latestID)
            let boundedLimit = max(1, limit)
            let oldestID = state.entries.first?.id

            if let after, after.captureSessionID != captureSessionID {
                return AppLogReadResult(entries: [],
                                        nextCursor: capturedThrough,
                                        capturedThrough: capturedThrough,
                                        hasMore: false,
                                        gap: nil,
                                        oldestAvailableID: oldestID,
                                        staleCursorCurrentSessionID: captureSessionID)
            }

            if after == nil {
                let filtered = state.entries.filter { Self.matches($0, sources: sources, minimumLevel: minimumLevel) }
                let suffix = Array(filtered.suffix(boundedLimit))
                let nextID = suffix.last?.id ?? latestID
                return AppLogReadResult(entries: suffix,
                                        nextCursor: AppLogCursor(captureSessionID: captureSessionID, id: nextID),
                                        capturedThrough: capturedThrough,
                                        hasMore: false,
                                        gap: nil,
                                        oldestAvailableID: oldestID,
                                        staleCursorCurrentSessionID: nil)
            }

            let afterID = after?.id ?? 0
            let gap = Self.gap(afterID: afterID, oldestID: oldestID)
            var entries: [AppLogEntry] = []
            var lastScannedID = afterID
            var hasMore = false

            for entry in state.entries where entry.id > afterID {
                lastScannedID = entry.id
                if Self.matches(entry, sources: sources, minimumLevel: minimumLevel) {
                    entries.append(entry)
                    if entries.count == boundedLimit {
                        hasMore = entry.id < latestID
                        break
                    }
                }
            }

            if entries.count < boundedLimit {
                lastScannedID = latestID
                hasMore = false
            }

            return AppLogReadResult(entries: entries,
                                    nextCursor: AppLogCursor(captureSessionID: captureSessionID, id: lastScannedID),
                                    capturedThrough: capturedThrough,
                                    hasMore: hasMore,
                                    gap: gap,
                                    oldestAvailableID: oldestID,
                                    staleCursorCurrentSessionID: nil)
        }
    }

    private static func matches(_ entry: AppLogEntry,
                                sources: Set<AppLogSource>?,
                                minimumLevel: AppLogLevel?) -> Bool {
        if let sources, sources.contains(entry.source) == false { return false }
        if let minimumLevel, entry.level < minimumLevel { return false }
        return true
    }

    private static func gap(afterID: UInt64, oldestID: UInt64?) -> AppLogGap? {
        guard let oldestID, afterID + 1 < oldestID else { return nil }
        return .bufferOverrun(requestedAfterID: afterID,
                              oldestAvailableID: oldestID,
                              lostRange: (afterID + 1)...(oldestID - 1))
    }

    private func boundedMetadata(_ metadata: [String: String]?) -> [String: String]? {
        guard maximumMetadataEntries > 0,
              let redacted = redactor.redactMetadata(metadata),
              redacted.isEmpty == false else { return nil }
        var bounded: [String: String] = [:]
        for key in redacted.keys.sorted() {
            guard bounded.count < maximumMetadataEntries else { break }
            let boundedKey = Self.truncate(key, maximumBytes: maximumMetadataKeyBytes).value
            guard boundedKey.isEmpty == false, bounded[boundedKey] == nil else { continue }
            bounded[boundedKey] = Self.truncate(redacted[key] ?? "", maximumBytes: maximumMetadataValueBytes).value
        }
        return bounded.isEmpty ? nil : bounded
    }

    private static func truncate(_ message: String, maximumBytes: Int) -> (value: String, truncated: Bool) {
        let bytes = Array(message.utf8)
        guard bytes.count > maximumBytes else { return (message, false) }
        var prefix = Array(bytes.prefix(maximumBytes))
        while String(bytes: prefix, encoding: .utf8) == nil, prefix.isEmpty == false {
            prefix.removeLast()
        }
        return (String(bytes: prefix, encoding: .utf8) ?? "", true)
    }
}
