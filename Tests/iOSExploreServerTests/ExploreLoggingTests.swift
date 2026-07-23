import Testing
import Foundation
@testable import iOSExploreServer
@testable import iOSExploreDiagnostics
#if canImport(UIKit)
import UIKit
@testable import iOSExploreUIKit
#endif

/// 所有 touch `ESLogger` 全局 sink 的测试集中在本 suite 并标 `.serialized`。
///
/// `ESLogger` 的 sink / enable / level 是进程级全局可变状态。Swift Testing 默认跨
/// suite 并行,若 touch-sink 的测试分散在多个 suite,会互相覆盖 sink 导致偶发失败(约 1/10)。
/// `.serialized` 保证本 suite 内测试串行;把所有 touch-sink 测试(含原 `ExploreCommandSupportTests`
/// 的 `extensionLogUsesCoreSink`)收拢到此,即可在不加全局锁的前提下彻底消除竞态。
@Suite(.serialized)
struct ESLoggerTests {
#if canImport(UIKit)
    @Test("ui.input 顶层批量生命周期 start 只记录一次")
    @MainActor
    func inputCommandLogsBatchLifecycleOnce() throws {
        ESLogger.resetForTesting()
        let records = Mutex<[ESLogRecord]>([])
        ESLogger.setEnabled(true)
        ESLogger.setSinkForTesting { record in
            records.withLock { $0.append(record) }
        }
        defer { ESLogger.resetForTesting() }

        let context = UIKitTestHost.context { root in
            let field = UITextField()
            field.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
            root.addSubview(field)
        }
        let input = UIInputInput(fields: [
            UIInputField(target: .path([0]), text: "x"),
        ])

        let result = InputCommand.execute(input: input, context: context)
        guard case .success = result else {
            Issue.record("ui.input test execution should return success envelope")
            return
        }

        let messages = records.withLock { $0.map(\.message) }
        let starts = messages.filter {
            $0.hasPrefix("command ui.input start fields=1 stopOnFailure=true viewSnapshot=nil")
        }
        let completions = messages.filter {
            $0.hasPrefix("command ui.input completed fields=1 completed=true failedIndex=nil")
        }
        #expect(starts.count == 1)
        #expect(completions.count == 1)
    }
#endif

    @Test("日志默认关闭,不会输出到 sink")
    func loggingDisabledByDefaultSuppressesOutput() {
        ESLogger.resetForTesting()
        let records = Mutex<[ESLogRecord]>([])
        ESLogger.setSinkForTesting { record in
            records.withLock { $0.append(record) }
        }
        defer { ESLogger.resetForTesting() }

        ESLogger.info(.server, "server started")

        #expect(records.withLock { $0.isEmpty })
    }

    @Test("开启日志后输出记录")
    func loggingEnabledEmitsRecord() {
        ESLogger.resetForTesting()
        let token = "logging-enabled-\(UUID().uuidString)"
        let records = Mutex<[ESLogRecord]>([])
        ESLogger.setSinkForTesting { record in
            records.withLock { $0.append(record) }
        }
        defer { ESLogger.resetForTesting() }

        ESLogger.setEnabled(true)
        ESLogger.info(.server, token)

        let snapshot = records.withLock { $0 }
        let matches = snapshot.filter { $0.message == token }
        #expect(matches.count == 1)
        #expect(matches.first?.level == .info)
        #expect(matches.first?.category == "server")
    }

    @Test("最小等级会过滤更低等级日志")
    func loggingMinimumLevelFiltersLowerPriorityRecords() {
        ESLogger.resetForTesting()
        let debugToken = "filtered-debug-\(UUID().uuidString)"
        let errorToken = "filtered-error-\(UUID().uuidString)"
        let records = Mutex<[ESLogRecord]>([])
        ESLogger.setSinkForTesting { record in
            records.withLock { $0.append(record) }
        }
        defer { ESLogger.resetForTesting() }

        ESLogger.setEnabled(true)
        ESLogger.setMinimumLevel(.error)
        ESLogger.debug(.router, debugToken)
        ESLogger.error(.router, errorToken)

        let snapshot = records.withLock { $0 }
        #expect(snapshot.contains { $0.message == debugToken } == false)
        let matches = snapshot.filter { $0.message == errorToken }
        #expect(matches.count == 1)
        #expect(matches.first?.level == .error)
    }

    @Test("Router 输出命中、未知 action 和异常日志")
    func routeEmitsDiagnosticLogs() async {
        ESLogger.resetForTesting()
        let records = Mutex<[ESLogRecord]>([])
        ESLogger.setSinkForTesting { record in
            records.withLock { $0.append(record) }
        }
        ESLogger.setEnabled(true)
        defer { ESLogger.resetForTesting() }

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
        ESLogger.resetForTesting()
        let records = Mutex<[ESLogRecord]>([])
        ESLogger.setSinkForTesting { record in
            records.withLock { $0.append(record) }
        }
        ESLogger.setEnabled(true)
        defer { ESLogger.resetForTesting() }

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
        defer { ESLogger.resetForTesting() }
        let token = "extension-log-\(UUID().uuidString)"
        let records = Mutex<[ESLogRecord]>([])
        ESLogger.setEnabled(true)
        ESLogger.setSinkForTesting { record in
            records.withLock { $0.append(record) }
        }
        ESLogger.emitExtension(level: .info, category: "uikit.action", message: token)
        #expect(records.withLock { records in
            records.filter { $0.message == token }.map(\.category) == ["uikit.action"]
        })
    }

    @Test("output 关闭时 observer 仍收到日志")
    func observerReceivesRecordWhenOutputDisabled() {
        ESLogger.resetForTesting()
        defer { ESLogger.resetForTesting() }
        let token = "observer-output-disabled-\(UUID().uuidString)"
        let outputRecords = Mutex<[ESLogRecord]>([])
        let observedRecords = Mutex<[ESLogRecord]>([])
        ESLogger.setSinkForTesting { record in
            outputRecords.withLock { $0.append(record) }
        }
        _ = ESLogger.addObserver { record in
            observedRecords.withLock { $0.append(record) }
        }

        ESLogger.info(.server, token)

        #expect(outputRecords.withLock { records in
            records.contains { $0.message == token } == false
        })
        #expect(observedRecords.withLock { records in
            records.filter { $0.message == token }.count == 1
        })
    }

    @Test("removeObserver 后不再收到日志")
    func removedObserverStopsReceivingRecords() {
        ESLogger.resetForTesting()
        defer { ESLogger.resetForTesting() }
        let observedRecords = Mutex<[ESLogRecord]>([])
        let token = "removed-observer-\(UUID().uuidString)"
        let observation = ESLogger.addObserver { record in
            observedRecords.withLock { $0.append(record) }
        }

        ESLogger.removeObserver(observation)
        ESLogger.info(.server, token)

        #expect(observedRecords.withLock { records in
            records.contains { $0.message == token } == false
        })
    }

    @Test("没有 observer 且 output 关闭时不构造 message")
    func disabledLoggingWithoutObserversDoesNotBuildMessage() {
        ESLogger.resetForTesting()
        defer { ESLogger.resetForTesting() }
        let didBuildMessage = Mutex(false)

        ESLogger.debug(.server, expensiveMessage(didBuildMessage))

        #expect(didBuildMessage.withLock { $0 } == false)
    }

    @Test("有 observer 时只构造一次 message 并同时投递 output")
    func observerAndOutputShareSingleBuiltMessage() {
        ESLogger.resetForTesting()
        defer { ESLogger.resetForTesting() }
        let buildCount = Mutex(0)
        let outputRecords = Mutex<[ESLogRecord]>([])
        let observedRecords = Mutex<[ESLogRecord]>([])
        ESLogger.setEnabled(true)
        ESLogger.setSinkForTesting { record in
            outputRecords.withLock { $0.append(record) }
        }
        _ = ESLogger.addObserver { record in
            observedRecords.withLock { $0.append(record) }
        }

        ESLogger.info(.server, countedMessage(buildCount))

        #expect(buildCount.withLock { $0 } == 1)
        #expect(outputRecords.withLock { records in
            records.filter { $0.message == "built once" }.count == 1
        })
        #expect(observedRecords.withLock { records in
            records.filter { $0.message == "built once" }.count == 1
        })
    }

    @Test("Diagnostics 注册后 output 关闭时 read 仍能读到 explore 日志")
    func diagnosticsReadReturnsExploreLogsWhenOutputDisabled() async throws {
        try await withProcessDiagnosticsTestIsolation {
            ESLogger.resetForTesting()
            ESDiagnosticsRuntime.shared.resetForTesting()
            defer { ESLogger.resetForTesting() }
            defer { ESDiagnosticsRuntime.shared.resetForTesting() }
            let server = ExploreServer()
            _ = server.registerDiagnosticsCommands(.init(captureStdout: false, captureStderr: false))
            let mark = try cursor(from: await server.routerSnapshotRoute(ExploreRequest(action: "app.logs.mark")))

            _ = await server.routerSnapshotRoute(ExploreRequest(action: "ping"))

            let result = await server.routerSnapshotRoute(ExploreRequest(action: "app.logs.read",
                                                                        data: ["after": .object(mark.toJSON())]))
            let entries = try entries(from: result)
            #expect(entries.contains { $0["source"]?.stringValue == "explore" &&
                ($0["message"]?.stringValue ?? "").contains("router route start action=ping")
            })
        }
    }

    @Test("ESAppLogger runtime 未安装时不构造 message")
    func appLogDoesNotBuildMessageWhenRuntimeIsMissing() async {
        await withProcessDiagnosticsTestIsolation {
            ESDiagnosticsRuntime.shared.resetForTesting()
            defer { ESDiagnosticsRuntime.shared.resetForTesting() }
            let didBuildMessage = Mutex(false)

            ESAppLogger.emit(.info, category: "auth", message: expensiveMessage(didBuildMessage))

            #expect(didBuildMessage.withLock { $0 } == false)
        }
    }

    @Test("ESAppLogger bridge 关闭时不构造 message")
    func appLogDoesNotBuildMessageWhenBridgeIsDisabled() async {
        await withProcessDiagnosticsTestIsolation {
            ESDiagnosticsRuntime.shared.resetForTesting()
            defer { ESDiagnosticsRuntime.shared.resetForTesting() }
            let server = ExploreServer()
            _ = server.registerDiagnosticsCommands(.init(captureExploreLogs: false,
                                                         enableBridge: false,
                                                         captureStdout: false,
                                                         captureStderr: false))
            let didBuildMessage = Mutex(false)

            ESAppLogger.emit(.info, category: "auth", message: expensiveMessage(didBuildMessage))

            #expect(didBuildMessage.withLock { $0 } == false)
        }
    }

    private func expensiveMessage(_ flag: Mutex<Bool>) -> String {
        flag.withLock { $0 = true }
        return "expensive"
    }

    private func countedMessage(_ count: Mutex<Int>) -> String {
        count.withLock { $0 += 1 }
        return "built once"
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

private func cursor(from result: ExploreResult) throws -> ESAppLogCursor {
    guard case .success(let data) = result,
          let cursorObject = data["cursor"]?.objectValue,
          let session = cursorObject["captureSessionID"]?.stringValue,
          let id = cursorObject["id"]?.doubleValue else {
        throw ESLoggerTestFailure("missing cursor")
    }
    return ESAppLogCursor(captureSessionID: session, id: UInt64(id))
}

private func entries(from result: ExploreResult) throws -> [JSON] {
    guard case .success(let data) = result,
          let values = data["entries"]?.arrayValue else {
        throw ESLoggerTestFailure("missing entries")
    }
    return values.compactMap(\.objectValue)
}

private struct ESLoggerTestFailure: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
