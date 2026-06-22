import Testing
@testable import iOSExploreServer

@Suite(.serialized)
struct ExploreLoggingTests {
    @Test("日志默认关闭,不会输出到 sink")
    func loggingDisabledByDefaultSuppressesOutput() {
        ExploreLogging.resetForTesting()
        let records = Mutex<[ExploreLogRecord]>([])
        ExploreLogging.setSinkForTesting { record in
            records.withLock { $0.append(record) }
        }
        defer { ExploreLogging.resetForTesting() }

        ExploreLogger.info(.server, "server started")

        #expect(records.withLock { $0.isEmpty })
    }

    @Test("开启日志后输出记录")
    func loggingEnabledEmitsRecord() {
        ExploreLogging.resetForTesting()
        let records = Mutex<[ExploreLogRecord]>([])
        ExploreLogging.setSinkForTesting { record in
            records.withLock { $0.append(record) }
        }
        defer { ExploreLogging.resetForTesting() }

        ExploreLogging.setEnabled(true)
        ExploreLogger.info(.server, "server started")

        let snapshot = records.withLock { $0 }
        #expect(snapshot.count == 1)
        #expect(snapshot.first?.level == .info)
        #expect(snapshot.first?.category == "server")
        #expect(snapshot.first?.message == "server started")
    }

    @Test("最小等级会过滤更低等级日志")
    func loggingMinimumLevelFiltersLowerPriorityRecords() {
        ExploreLogging.resetForTesting()
        let records = Mutex<[ExploreLogRecord]>([])
        ExploreLogging.setSinkForTesting { record in
            records.withLock { $0.append(record) }
        }
        defer { ExploreLogging.resetForTesting() }

        ExploreLogging.setEnabled(true)
        ExploreLogging.setMinimumLevel(.error)
        ExploreLogger.debug(.router, "route entered")
        ExploreLogger.error(.router, "route failed")

        let snapshot = records.withLock { $0 }
        #expect(snapshot.count == 1)
        #expect(snapshot.first?.level == .error)
        #expect(snapshot.first?.message == "route failed")
    }

    @Test("Router 输出命中、未知 action 和异常日志")
    func routeEmitsDiagnosticLogs() async {
        ExploreLogging.resetForTesting()
        let records = Mutex<[ExploreLogRecord]>([])
        ExploreLogging.setSinkForTesting { record in
            records.withLock { $0.append(record) }
        }
        ExploreLogging.setEnabled(true)
        defer { ExploreLogging.resetForTesting() }

        let router = Router()
        struct Boom: Error {}
        router.register(action: "ok") { _ in .success([:]) }
        router.register(action: "boom") { _ in throw Boom() }

        _ = await router.route(ExploreRequest(action: "ok"))
        _ = await router.route(ExploreRequest(action: "missing"))
        _ = await router.route(ExploreRequest(action: "boom"))

        let messages = records.withLock { $0.map(\.message) }
        #expect(messages.contains("router registered action=ok"))
        #expect(messages.contains("router registered action=boom"))
        #expect(messages.contains("router route start action=ok"))
        #expect(messages.contains("router route success action=ok"))
        #expect(messages.contains("router route failed category=command message=unknown action=missing"))
        #expect(messages.contains { $0.hasPrefix("router route failed category=command message=handler threw action=boom") })
    }
}
