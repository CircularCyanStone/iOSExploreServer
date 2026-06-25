import Testing
@testable import iOSExploreServer

/// 所有 touch `ExploreLogging` 全局 sink 的测试集中在本 suite 并标 `.serialized`。
///
/// `ExploreLogging` 的 sink / enable / level 是进程级全局可变状态。Swift Testing 默认跨
/// suite 并行,若 touch-sink 的测试分散在多个 suite,会互相覆盖 sink 导致偶发失败(约 1/10)。
/// `.serialized` 保证本 suite 内测试串行;把所有 touch-sink 测试(含原 `ExploreCommandSupportTests`
/// 的 `extensionLogUsesCoreSink`)收拢到此,即可在不加全局锁的前提下彻底消除竞态。
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
        router.register(action: "ok", input: EmptyCommandInput.self) { _ in .success([:]) }
        router.register(action: "boom", input: EmptyCommandInput.self) { _ in throw Boom() }

        _ = await router.route(ExploreRequest(action: "ok"))
        _ = await router.route(ExploreRequest(action: "missing"))
        _ = await router.route(ExploreRequest(action: "boom"))

        let messages = records.withLock { $0.map(\.message) }
        #expect(messages.contains("router registered action=ok schemaFields=0 constraints=0"))
        #expect(messages.contains("router registered action=boom schemaFields=0 constraints=0"))
        #expect(messages.contains("router route start action=ok payloadKeys=0"))
        #expect(messages.contains("router route success action=ok"))
        #expect(messages.contains("router route failed category=command message=unknown action=missing"))
        #expect(messages.contains { $0.hasPrefix("command boom failed code=internal_error message=handler threw action=boom") })
        #expect(messages.contains { $0.hasPrefix("router route business failure action=boom code=internal_error") })
    }

    @Test("AnyCommand 解析失败日志走统一错误工厂语义")
    func commandParseFailuresUseErrorFactoryDiagnostics() async {
        ExploreLogging.resetForTesting()
        let records = Mutex<[ExploreLogRecord]>([])
        ExploreLogging.setSinkForTesting { record in
            records.withLock { $0.append(record) }
        }
        ExploreLogging.setEnabled(true)
        defer { ExploreLogging.resetForTesting() }

        struct NameInput: CommandInput {
            static let name = CommandFields.requiredString("name", description: "名字")
            static let inputSchema = CommandInputSchema(fields: [name.erased])

            static func parse(decoding decoder: inout CommandInputDecoder) throws -> NameInput {
                _ = try decoder.read(name)
                return NameInput()
            }
        }
        struct BrokenInput: CommandInput {
            struct Boom: Error {}
            static let inputSchema = CommandInputSchema.empty

            static func parse(from data: JSON) throws -> BrokenInput { throw Boom() }
            static func parse(decoding decoder: inout CommandInputDecoder) throws -> BrokenInput {
                BrokenInput()
            }
        }

        let router = Router()
        router.register(action: "needsName", input: NameInput.self) { _ in .success([:]) }
        router.register(action: "brokenParse", input: BrokenInput.self) { _ in .success([:]) }

        _ = await router.route(ExploreRequest(action: "needsName"))
        _ = await router.route(ExploreRequest(action: "brokenParse"))

        let messages = records.withLock { $0.map(\.message) }
        #expect(messages.contains {
            $0.hasPrefix("command needsName parse failed code=invalid_data message=invalid data action=needsName")
        })
        #expect(messages.contains {
            $0.hasPrefix("command brokenParse parse unexpected code=internal_error message=unexpected parse error action=brokenParse")
        })
    }

    @Test("扩展日志进入既有 sink")
    func extensionLogUsesCoreSink() {
        defer { ExploreLogging.resetForTesting() }
        let records = Mutex<[ExploreLogRecord]>([])
        ExploreLogging.setEnabled(true)
        ExploreLogging.setSinkForTesting { record in
            records.withLock { $0.append(record) }
        }
        ExploreLogging.emitExtension(level: .info, category: "uikit.action", message: "tap completed")
        #expect(records.withLock { $0.map(\.category) } == ["uikit.action"])
    }
}
