import Testing
@testable import iOSExploreDiagnostics

@Suite("Diagnostics 日志存储")
struct DiagnosticsStoreTests {
    @Test("mark 返回当前最大 cursor,read 只读取 cursor 之后的记录")
    func markAndReadIncrementalEntries() {
        let store = AppLogStore(captureSessionID: "session-a", capacity: 10, maximumEntryBytes: 1024)
        _ = store.append(source: .bridge, level: .info, category: "auth", message: "before mark")
        let mark = store.mark()
        _ = store.append(source: .bridge, level: .error, category: "auth", message: "after mark")

        let result = store.read(after: mark.cursor, limit: 100, sources: nil, minimumLevel: nil)

        #expect(result.entries.map(\.message) == ["after mark"])
        #expect(result.nextCursor.id == result.capturedThrough.id)
        #expect(result.hasMore == false)
        #expect(result.gap == nil)
    }

    @Test("read 使用最后扫描的物理 id 推进 cursor,不是最后返回的 entry id")
    func readAdvancesCursorByLastScannedID() {
        let store = AppLogStore(captureSessionID: "session-a", capacity: 10, maximumEntryBytes: 1024)
        _ = store.append(source: .stdout, level: .unknown, category: nil, message: "stdout-1")
        _ = store.append(source: .bridge, level: .info, category: "auth", message: "bridge-1")
        _ = store.append(source: .stderr, level: .unknown, category: nil, message: "stderr-1")

        let result = store.read(after: AppLogCursor(captureSessionID: "session-a", id: 0),
                                limit: 10,
                                sources: [.bridge],
                                minimumLevel: nil)

        #expect(result.entries.map(\.message) == ["bridge-1"])
        #expect(result.nextCursor.id == 3)
        #expect(result.capturedThrough.id == 3)
        #expect(result.hasMore == false)
    }

    @Test("read 达到 limit 时返回 hasMore 并停在最后扫描 id")
    func readPaginatesWithHasMore() {
        let store = AppLogStore(captureSessionID: "session-a", capacity: 10, maximumEntryBytes: 1024)
        _ = store.append(source: .bridge, level: .info, category: "auth", message: "one")
        _ = store.append(source: .bridge, level: .info, category: "auth", message: "two")
        _ = store.append(source: .bridge, level: .info, category: "auth", message: "three")

        let firstPage = store.read(after: AppLogCursor(captureSessionID: "session-a", id: 0),
                                   limit: 2,
                                   sources: [.bridge],
                                   minimumLevel: nil)
        let secondPage = store.read(after: firstPage.nextCursor,
                                    limit: 2,
                                    sources: [.bridge],
                                    minimumLevel: nil)

        #expect(firstPage.entries.map(\.message) == ["one", "two"])
        #expect(firstPage.nextCursor.id == 2)
        #expect(firstPage.hasMore == true)
        #expect(secondPage.entries.map(\.message) == ["three"])
        #expect(secondPage.hasMore == false)
    }

    @Test("read 未传 after 时返回最近记录且不暗示可向旧记录翻页")
    func initialReadDoesNotReportOlderPages() {
        let store = AppLogStore(captureSessionID: "session-a", capacity: 10, maximumEntryBytes: 1024)
        _ = store.append(source: .bridge, level: .info, category: "auth", message: "one")
        _ = store.append(source: .bridge, level: .info, category: "auth", message: "two")
        _ = store.append(source: .bridge, level: .info, category: "auth", message: "three")

        let result = store.read(after: nil, limit: 2, sources: [.bridge], minimumLevel: nil)

        #expect(result.entries.map(\.message) == ["two", "three"])
        #expect(result.nextCursor.id == 3)
        #expect(result.capturedThrough.id == 3)
        #expect(result.hasMore == false)
    }

    @Test("ring buffer 覆盖时 read 返回明确 gap")
    func readReportsBufferOverrunGap() {
        let store = AppLogStore(captureSessionID: "session-a", capacity: 2, maximumEntryBytes: 1024)
        _ = store.append(source: .bridge, level: .info, category: nil, message: "one")
        _ = store.append(source: .bridge, level: .info, category: nil, message: "two")
        _ = store.append(source: .bridge, level: .info, category: nil, message: "three")

        let result = store.read(after: AppLogCursor(captureSessionID: "session-a", id: 0),
                                limit: 10,
                                sources: nil,
                                minimumLevel: nil)

        #expect(result.entries.map(\.message) == ["two", "three"])
        #expect(result.gap == .bufferOverrun(requestedAfterID: 0,
                                            oldestAvailableID: 2,
                                            lostRange: 1...1))
    }

    @Test("capture session 不匹配时 read 返回 stale cursor")
    func readRejectsStaleCaptureSession() {
        let store = AppLogStore(captureSessionID: "session-b", capacity: 10, maximumEntryBytes: 1024)
        _ = store.append(source: .bridge, level: .info, category: nil, message: "current")

        let result = store.read(after: AppLogCursor(captureSessionID: "session-a", id: 0),
                                limit: 10,
                                sources: nil,
                                minimumLevel: nil)

        #expect(result.staleCursorCurrentSessionID == "session-b")
        #expect(result.entries.isEmpty)
    }

    @Test("写入前先脱敏再截断")
    func appendRedactsBeforeTruncating() {
        let store = AppLogStore(captureSessionID: "session-a", capacity: 10, maximumEntryBytes: 64)

        _ = store.append(source: .bridge,
                         level: .error,
                         category: "auth",
                         message: "Authorization: Bearer secret-token " + String(repeating: "x", count: 120),
                         metadata: ["token": "secret-token"])

        let result = store.read(after: nil, limit: 10, sources: nil, minimumLevel: nil)

        #expect(result.entries.count == 1)
        #expect(result.entries[0].message.contains("secret-token") == false)
        #expect(result.entries[0].message.contains("[REDACTED]"))
        #expect(result.entries[0].messageTruncated == true)
        #expect(result.entries[0].metadata == ["token": "[REDACTED]"])
    }

    @Test("metadata 写入前会限制数量和 key/value 长度并保持脱敏")
    func appendBoundsMetadataSizeAfterRedaction() {
        let store = AppLogStore(captureSessionID: "session-a",
                                capacity: 10,
                                maximumEntryBytes: 1024,
                                maximumMetadataEntries: 2,
                                maximumMetadataKeyBytes: 4,
                                maximumMetadataValueBytes: 10)

        _ = store.append(source: .bridge,
                         level: .error,
                         category: "auth",
                         message: "login",
                         metadata: [
                             "zzzz-long-key": "Authorization: Bearer secret-token",
                             "aaaa-long-key": "value-1234567890",
                             "token": "secret-token",
                         ])

        let result = store.read(after: nil, limit: 10, sources: nil, minimumLevel: nil)

        let metadata = result.entries[0].metadata ?? [:]
        #expect(metadata.count == 2)
        #expect(metadata["aaaa"] == "value-1234")
        #expect(metadata["toke"] == "[REDACTED]")
        #expect(metadata.values.contains { $0.contains("secret-token") } == false)
    }
}
