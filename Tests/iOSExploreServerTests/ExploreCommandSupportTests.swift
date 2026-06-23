import Testing
@testable import iOSExploreServer

@Suite(.serialized)
struct ExploreCommandSupportTests {
    @Test("扩展 command failure 保留 envelope 与日志语义")
    func commandFailureMapsToResult() {
        let failure = ExploreCommandFailure(code: .invalidData,
                                            message: "target not found",
                                            logMessage: "uikit locator missing kind=path")
        #expect(failure.result == .failure(code: .invalidData, message: "target not found"))
    }

    @Test("扩展日志进入既有 sink")
    func extensionLogUsesCoreSink() {
        let records = Mutex<[ExploreLogRecord]>([])
        ExploreLogging.setEnabled(true)
        ExploreLogging.setSinkForTesting { record in records.withLock { $0.append(record) } }
        ExploreLogging.emitExtension(level: .info, category: "uikit.action", message: "tap completed")
        #expect(records.withLock { $0.map(\.category) } == ["uikit.action"])
        ExploreLogging.resetForTesting()
    }
}
