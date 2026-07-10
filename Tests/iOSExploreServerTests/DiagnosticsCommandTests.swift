import Darwin
import Foundation
import OSLog
import Testing
@testable import iOSExploreServer
@testable import iOSExploreDiagnostics

@Suite(.serialized)
struct DiagnosticsCommandTests {
    @Test("默认不会自动注册 app.logs action")
    func coreDoesNotAutoRegisterDiagnosticsCommands() async {
        let server = ExploreServer()

        let result = await server.routerSnapshotRoute(ExploreRequest(action: "help"))

        #expect(result.commandActions.contains("app.logs.mark") == false)
        #expect(result.commandActions.contains("app.logs.read") == false)
    }

    @Test("显式注册后 help 包含 app.logs action")
    func explicitRegistrationAddsDiagnosticsCommands() async {
        await withProcessDiagnosticsTestIsolation {
            ProcessDiagnosticsRuntime.shared.resetForTesting()
            defer { ProcessDiagnosticsRuntime.shared.resetForTesting() }
            let server = ExploreServer()
            _ = server.registerDiagnosticsCommands(.init(captureExploreLogs: false,
                                                         captureStdout: false,
                                                         captureStderr: false))

            let result = await server.routerSnapshotRoute(ExploreRequest(action: "help"))

            #expect(result.commandActions.contains("app.logs.mark"))
            #expect(result.commandActions.contains("app.logs.read"))
        }
    }

    @Test("app.logs.read help 暴露可查询字段")
    func readHelpIncludesInputSchemaFields() async throws {
        try await withProcessDiagnosticsTestIsolation {
            ProcessDiagnosticsRuntime.shared.resetForTesting()
            defer { ProcessDiagnosticsRuntime.shared.resetForTesting() }
            let server = ExploreServer()
            _ = server.registerDiagnosticsCommands(.init(captureExploreLogs: false,
                                                         captureStdout: false,
                                                         captureStderr: false))

            let result = await server.routerSnapshotRoute(ExploreRequest(action: "help"))

            let schema = try inputSchema(for: "app.logs.read", from: result)
            let properties = schema["properties"]?.objectValue ?? [:]
            #expect(Set(properties.storage.keys) == ["after", "limit", "sources", "minimumLevel"])
            #expect(schema["additionalProperties"]?.boolValue == false)
            #expect(properties["after"]?.objectValue?["type"]?.arrayValue?.contains(.string("object")) == true)
            #expect(properties["limit"]?.objectValue?["minimum"]?.doubleValue == 1)
            #expect(properties["limit"]?.objectValue?["maximum"]?.doubleValue == 500)
            #expect(properties["sources"]?.objectValue?["type"]?.arrayValue?.contains(.string("array")) == true)
            #expect(properties["minimumLevel"]?.objectValue?["enum"]?.arrayValue?.contains(.string("error")) == true)
        }
    }

    @Test("mark 响应包含各日志来源捕获状态")
    func markReturnsCaptureStatus() async throws {
        try await withProcessDiagnosticsTestIsolation {
            ProcessDiagnosticsRuntime.shared.resetForTesting()
            defer { ProcessDiagnosticsRuntime.shared.resetForTesting() }
            let server = ExploreServer()
            _ = server.registerDiagnosticsCommands(.init(captureExploreLogs: false,
                                                         captureStdout: false,
                                                         captureStderr: false))

            let result = await server.routerSnapshotRoute(ExploreRequest(action: "app.logs.mark"))

            guard case .success(let data) = result,
                  let capture = data["capture"]?.objectValue else {
                throw TestFailure("missing capture status")
            }
            #expect(capture["explore"]?.objectValue?["state"]?.stringValue == "notCaptured")
            #expect(capture["bridge"]?.objectValue?["state"]?.stringValue == "enabled")
            #expect(capture["stdout"]?.objectValue?["state"]?.stringValue == "notCaptured")
            #expect(capture["stderr"]?.objectValue?["state"]?.stringValue == "notCaptured")
            #expect(capture["nslog"]?.objectValue?["state"]?.stringValue == "notCaptured")
            #expect(capture["oslog"]?.objectValue?["state"]?.stringValue == "notCaptured")
        }
    }

    @Test("ExploreAppLog 写入 bridge 日志并可被 read 读取")
    func readReturnsBridgeLogs() async throws {
        try await withProcessDiagnosticsTestIsolation {
            ProcessDiagnosticsRuntime.shared.resetForTesting()
            defer { ProcessDiagnosticsRuntime.shared.resetForTesting() }
            let server = ExploreServer()
            _ = server.registerDiagnosticsCommands(.init(captureExploreLogs: false,
                                                         captureStdout: false,
                                                         captureStderr: false))
            let mark = try cursor(from: await server.routerSnapshotRoute(ExploreRequest(action: "app.logs.mark")))

            ExploreAppLog.emit(.error,
                               category: "auth",
                               message: "login failed token=secret-token",
                               metadata: ["route": "login", "token": "secret-token"])

            let result = await server.routerSnapshotRoute(ExploreRequest(action: "app.logs.read",
                                                                        data: ["after": .object(mark.toJSON()),
                                                                               "sources": .array([.string("bridge")])]))
            let entries = try entries(from: result)
            #expect(entries.count == 1)
            #expect(entries[0]["source"]?.stringValue == "bridge")
            #expect(entries[0]["level"]?.stringValue == "error")
            #expect(entries[0]["category"]?.stringValue == "auth")
            #expect(entries[0]["message"]?.stringValue?.contains("secret-token") == false)
            #expect(entries[0]["message"]?.stringValue?.contains("[REDACTED]") == true)
            #expect(entries[0]["metadata"]?.objectValue?["token"]?.stringValue == "[REDACTED]")
        }
    }

    @Test("app.logs.read 不等待 pending capture flush 完成")
    func readDoesNotWaitForPendingCaptureFlush() async throws {
        try await withProcessDiagnosticsTestIsolation {
            ProcessDiagnosticsRuntime.shared.resetForTesting()
            defer { ProcessDiagnosticsRuntime.shared.resetForTesting() }
            let server = ExploreServer()
            _ = server.registerDiagnosticsCommands(.init(captureExploreLogs: false,
                                                         captureStdout: false,
                                                         captureStderr: false,
                                                         captureOSLog: false))
            let mark = try cursor(from: await server.routerSnapshotRoute(ExploreRequest(action: "app.logs.mark")))

            ExploreAppLog.emit(.info,
                               category: "test.flush",
                               message: "flush should not block read")
            ProcessDiagnosticsRuntime.shared.setPendingCaptureFlushOverrideForTesting {
                Thread.sleep(forTimeInterval: 2)
            }

            let start = Date()
            let result = await server.routerSnapshotRoute(ExploreRequest(action: "app.logs.read",
                                                                        data: ["after": .object(mark.toJSON()),
                                                                               "sources": .array([.string("bridge")])]))
            let elapsed = Date().timeIntervalSince(start)
            let entries = try entries(from: result)

            #expect(elapsed < 1.0)
            #expect(entries.contains { entry in
                entry["source"]?.stringValue == "bridge" &&
                entry["category"]?.stringValue == "test.flush"
            })
        }
    }

    @Test("captureSessionID 不匹配时 read 返回 stale_cursor")
    func readReturnsStaleCursorForDifferentCaptureSession() async {
        await withProcessDiagnosticsTestIsolation {
            ProcessDiagnosticsRuntime.shared.resetForTesting()
            defer { ProcessDiagnosticsRuntime.shared.resetForTesting() }
            let server = ExploreServer()
            _ = server.registerDiagnosticsCommands(.init(captureExploreLogs: false,
                                                         captureStdout: false,
                                                         captureStderr: false))

            let result = await server.routerSnapshotRoute(ExploreRequest(action: "app.logs.read",
                                                                        data: ["after": .object([
                                                                            "captureSessionID": .string("other-session"),
                                                                            "id": 0,
                                                                        ])]))

            #expect(result == .failure(code: .staleCursor,
                                      message: "The log capture session changed; call app.logs.mark to begin a new stream."))
        }
    }

    @Test("stdout capture 打开后可按 stdout 来源读取到整行日志")
    func stdoutCaptureWritesLineIntoDiagnosticsStore() async throws {
        try await withProcessDiagnosticsTestIsolation {
            ProcessDiagnosticsRuntime.shared.resetForTesting()
            defer { ProcessDiagnosticsRuntime.shared.resetForTesting() }
            let token = "stdout-capture-\(UUID().uuidString)"
            let server = ExploreServer()
            _ = server.registerDiagnosticsCommands(.init(captureExploreLogs: false,
                                                         captureStdout: true,
                                                         captureStderr: false,
                                                         teeToOriginalStreams: false))
            let mark = try cursor(from: await server.routerSnapshotRoute(ExploreRequest(action: "app.logs.mark")))

            writeLine(token, to: .standardOutput)

            let entries = try await waitForEntry(after: mark, source: "stdout", token: token, server: server)
            #expect(entries.contains { entry in
                entry["source"]?.stringValue == "stdout" &&
                entry["level"]?.stringValue == "info" &&
                entry["category"]?.stringValue == "stdio" &&
                entry["message"]?.stringValue == token
            })
        }
    }

    @Test("stdout capture 打开后可捕获 Swift print 输出")
    func stdoutCaptureRecordsSwiftPrintOutput() async throws {
        try await withProcessDiagnosticsTestIsolation {
            ProcessDiagnosticsRuntime.shared.resetForTesting()
            defer {
                ProcessDiagnosticsRuntime.shared.resetForTesting()
                setvbuf(stdout, nil, _IOLBF, 0)
            }
            let token = "stdout-print-capture-\(UUID().uuidString)"
            let server = ExploreServer()
            setvbuf(stdout, nil, _IOFBF, 0)
            _ = server.registerDiagnosticsCommands(.init(captureExploreLogs: false,
                                                         captureStdout: true,
                                                         captureStderr: false,
                                                         teeToOriginalStreams: false))
            let mark = try cursor(from: await server.routerSnapshotRoute(ExploreRequest(action: "app.logs.mark")))

            print(token)

            let entries = try await waitForEntry(after: mark, source: "stdout", token: token, server: server)
            #expect(entries.contains { entry in
                entry["source"]?.stringValue == "stdout" &&
                entry["level"]?.stringValue == "info" &&
                entry["category"]?.stringValue == "stdio" &&
                entry["message"]?.stringValue == token
            })
        }
    }

    @Test("stderr capture 打开后可按 stderr 来源读取到 error 日志")
    func stderrCaptureWritesLineIntoDiagnosticsStore() async throws {
        try await withProcessDiagnosticsTestIsolation {
            ProcessDiagnosticsRuntime.shared.resetForTesting()
            defer { ProcessDiagnosticsRuntime.shared.resetForTesting() }
            let token = "stderr-capture-\(UUID().uuidString)"
            let server = ExploreServer()
            _ = server.registerDiagnosticsCommands(.init(captureExploreLogs: false,
                                                         captureStdout: false,
                                                         captureStderr: true,
                                                         teeToOriginalStreams: false))
            let mark = try cursor(from: await server.routerSnapshotRoute(ExploreRequest(action: "app.logs.mark")))

            writeLine(token, to: .standardError)

            let entries = try await waitForEntry(after: mark, source: "stderr", token: token, server: server)
            #expect(entries.contains { entry in
                entry["source"]?.stringValue == "stderr" &&
                entry["level"]?.stringValue == "error" &&
                entry["category"]?.stringValue == "stdio" &&
                entry["message"]?.stringValue == token
            })
        }
    }

    @Test("NSLog capture 打开后可按 nslog 来源读取到日志")
    func nslogCaptureWritesLineIntoDiagnosticsStore() async throws {
        try await withProcessDiagnosticsTestIsolation {
            ProcessDiagnosticsRuntime.shared.resetForTesting()
            defer { ProcessDiagnosticsRuntime.shared.resetForTesting() }
            let token = "nslog-capture-\(UUID().uuidString)"
            let server = ExploreServer()
            _ = server.registerDiagnosticsCommands(.init(captureExploreLogs: false,
                                                         captureStdout: false,
                                                         captureStderr: false,
                                                         captureNSLog: true,
                                                         teeToOriginalStreams: false))
            let mark = try cursor(from: await server.routerSnapshotRoute(ExploreRequest(action: "app.logs.mark")))

            NSLog("%@", token)

            let entries = try await waitForEntry(after: mark, source: "nslog", token: token, server: server)
            #expect(entries.contains { entry in
                entry["source"]?.stringValue == "nslog" &&
                entry["level"]?.stringValue == "info" &&
                entry["category"]?.stringValue == "nslog" &&
                (entry["message"]?.stringValue ?? "").contains(token)
            })
        }
    }

    @Test("NSLog capture 关闭时不会捕获 NSLog")
    func disabledNSLogCaptureDoesNotRecordOutput() async throws {
        try await withProcessDiagnosticsTestIsolation {
            ProcessDiagnosticsRuntime.shared.resetForTesting()
            defer { ProcessDiagnosticsRuntime.shared.resetForTesting() }
            let token = "nslog-disabled-\(UUID().uuidString)"
            let server = ExploreServer()
            _ = server.registerDiagnosticsCommands(.init(captureExploreLogs: false,
                                                         captureStdout: false,
                                                         captureStderr: false,
                                                         captureNSLog: false,
                                                         teeToOriginalStreams: false))
            let mark = try cursor(from: await server.routerSnapshotRoute(ExploreRequest(action: "app.logs.mark")))

            NSLog("%@", token)
            try await Task.sleep(nanoseconds: 100_000_000)

            let result = await server.routerSnapshotRoute(ExploreRequest(action: "app.logs.read",
                                                                        data: ["after": .object(mark.toJSON()),
                                                                               "sources": .array([.string("nslog")])]))
            let entries = try entries(from: result)
            #expect(entries.contains { ($0["message"]?.stringValue ?? "").contains(token) } == false)
        }
    }

    @Test("stdout capture 关闭时不会捕获标准输出")
    func disabledStdoutCaptureDoesNotRecordOutput() async throws {
        try await withProcessDiagnosticsTestIsolation {
            ProcessDiagnosticsRuntime.shared.resetForTesting()
            defer { ProcessDiagnosticsRuntime.shared.resetForTesting() }
            let token = "stdout-disabled-\(UUID().uuidString)"
            let server = ExploreServer()
            _ = server.registerDiagnosticsCommands(.init(captureExploreLogs: false,
                                                         captureStdout: false,
                                                         captureStderr: false,
                                                         teeToOriginalStreams: false))
            let mark = try cursor(from: await server.routerSnapshotRoute(ExploreRequest(action: "app.logs.mark")))

            writeLine(token, to: .standardOutput)
            try await Task.sleep(nanoseconds: 100_000_000)

            let result = await server.routerSnapshotRoute(ExploreRequest(action: "app.logs.read",
                                                                        data: ["after": .object(mark.toJSON()),
                                                                               "sources": .array([.string("stdout")])]))
            let entries = try entries(from: result)
            #expect(entries.contains { ($0["message"]?.stringValue ?? "").contains(token) } == false)
        }
    }

    @Test("mark 响应在 stdout/stderr capture 安装成功时返回 enabled")
    func markReportsEnabledStatusForInstalledStdIOCapture() async throws {
        try await withProcessDiagnosticsTestIsolation {
            ProcessDiagnosticsRuntime.shared.resetForTesting()
            defer { ProcessDiagnosticsRuntime.shared.resetForTesting() }
            let server = ExploreServer()
            _ = server.registerDiagnosticsCommands(.init(captureExploreLogs: false,
                                                         captureStdout: true,
                                                         captureStderr: true,
                                                         teeToOriginalStreams: false))

            let result = await server.routerSnapshotRoute(ExploreRequest(action: "app.logs.mark"))

            guard case .success(let data) = result,
                  let capture = data["capture"]?.objectValue else {
                throw TestFailure("missing capture status")
            }
            #expect(capture["stdout"]?.objectValue?["state"]?.stringValue == "enabled")
            #expect(capture["stderr"]?.objectValue?["state"]?.stringValue == "enabled")
        }
    }

    @Test("mark 响应在 NSLog capture 安装成功时返回 enabled")
    func markReportsEnabledStatusForInstalledNSLogCapture() async throws {
        try await withProcessDiagnosticsTestIsolation {
            ProcessDiagnosticsRuntime.shared.resetForTesting()
            defer { ProcessDiagnosticsRuntime.shared.resetForTesting() }
            let server = ExploreServer()
            _ = server.registerDiagnosticsCommands(.init(captureExploreLogs: false,
                                                         captureStdout: false,
                                                         captureStderr: false,
                                                         captureNSLog: true,
                                                         teeToOriginalStreams: false))

            let result = await server.routerSnapshotRoute(ExploreRequest(action: "app.logs.mark"))

            guard case .success(let data) = result,
                  let capture = data["capture"]?.objectValue else {
                throw TestFailure("missing capture status")
            }
            #expect(capture["nslog"]?.objectValue?["state"]?.stringValue == "enabled")
            #expect(capture["stderr"]?.objectValue?["state"]?.stringValue == "notCaptured")
        }
    }

    @Test("os_log/Logger capture 打开后可按 oslog 来源读取日志")
    func osLogCaptureWritesEntriesIntoDiagnosticsStore() async throws {
        guard #available(macOS 11.0, iOS 15.0, *) else { return }
        try await withProcessDiagnosticsTestIsolation {
            ProcessDiagnosticsRuntime.shared.resetForTesting()
            defer { ProcessDiagnosticsRuntime.shared.resetForTesting() }
            let token = "oslog-capture-\(UUID().uuidString)"
            let server = ExploreServer()
            _ = server.registerDiagnosticsCommands(.init(captureExploreLogs: false,
                                                         captureStdout: false,
                                                         captureStderr: false,
                                                         captureOSLog: true,
                                                         teeToOriginalStreams: false))
            let mark = try cursor(from: await server.routerSnapshotRoute(ExploreRequest(action: "app.logs.mark")))

            let logger = Logger(subsystem: "com.coo.iOSExploreDiagnosticsTests", category: "diagnostics")
            logger.error("\(token, privacy: .public)")
            os_log("%{public}@", log: OSLog(subsystem: "com.coo.iOSExploreDiagnosticsTests",
                                            category: "legacy"),
                   type: .error,
                   token)

            let entries = try await waitForEntry(after: mark,
                                                 source: "oslog",
                                                 token: token,
                                                 server: server,
                                                 attempts: 80)
            #expect(entries.contains { entry in
                entry["source"]?.stringValue == "oslog" &&
                (entry["message"]?.stringValue ?? "").contains(token)
            })
        }
    }

    @Test("os_log 捕获会过滤 com.apple. 系统来源")
    func osLogCaptureFiltersAppleSystemSubsystem() async throws {
        guard #available(macOS 11.0, iOS 15.0, *) else { return }
        try await withProcessDiagnosticsTestIsolation {
            ProcessDiagnosticsRuntime.shared.resetForTesting()
            defer { ProcessDiagnosticsRuntime.shared.resetForTesting() }
            let systemToken = "apple-system-\(UUID().uuidString)"
            let appToken = "app-custom-\(UUID().uuidString)"
            let server = ExploreServer()
            _ = server.registerDiagnosticsCommands(.init(captureExploreLogs: false,
                                                         captureStdout: false,
                                                         captureStderr: false,
                                                         captureNSLog: false,
                                                         captureOSLog: true,
                                                         teeToOriginalStreams: false))
            let mark = try cursor(from: await server.routerSnapshotRoute(ExploreRequest(action: "app.logs.mark")))

            // 模拟系统框架日志（subsystem 以 com.apple. 开头）—— 不应被捕获
            os_log("%{public}@", log: OSLog(subsystem: "com.apple.Foundation",
                                            category: "nslog"),
                   type: .info,
                   systemToken)
            // 模拟宿主 App 自己的日志 —— 应被捕获
            os_log("%{public}@", log: OSLog(subsystem: "com.coo.SPMExample",
                                            category: "test"),
                   type: .info,
                   appToken)

            let entries = try await waitForEntry(after: mark,
                                                 source: "oslog",
                                                 token: appToken,
                                                 server: server,
                                                 attempts: 80)
            #expect(entries.contains { entry in
                entry["source"]?.stringValue == "oslog" &&
                (entry["message"]?.stringValue ?? "").contains(appToken)
            })
            #expect(entries.contains { entry in
                (entry["message"]?.stringValue ?? "").contains(systemToken)
            } == false)
        }
    }

    @Test("stdout 无换行尾部会在 reset 停止捕获时 flush 成一条日志")
    func stdoutCaptureFlushesPendingLineOnReset() async throws {
        try await withProcessDiagnosticsTestIsolation {
            ProcessDiagnosticsRuntime.shared.resetForTesting()
            defer { ProcessDiagnosticsRuntime.shared.resetForTesting() }
            let token = "stdout-tail-\(UUID().uuidString)"
            let server = ExploreServer()
            _ = server.registerDiagnosticsCommands(.init(captureExploreLogs: false,
                                                         captureStdout: true,
                                                         captureStderr: false,
                                                         teeToOriginalStreams: false))
            guard let store = ProcessDiagnosticsRuntime.shared.currentStore() else {
                throw TestFailure("missing diagnostics store")
            }
            let mark = store.mark()

            FileHandle.standardOutput.write(Data(token.utf8))
            ProcessDiagnosticsRuntime.shared.resetForTesting()

            let result = store.read(after: mark.cursor, limit: 20, sources: [.stdout], minimumLevel: nil)
            #expect(result.entries.contains { $0.message == token && $0.source == .stdout })
        }
    }

    @Test("reset 后 stdout capture 不再写入旧 store")
    func resetStopsStdoutCaptureFromAppendingToPreviousStore() async throws {
        try await withProcessDiagnosticsTestIsolation {
            ProcessDiagnosticsRuntime.shared.resetForTesting()
            defer { ProcessDiagnosticsRuntime.shared.resetForTesting() }
            let token = "stdout-after-reset-\(UUID().uuidString)"
            let server = ExploreServer()
            _ = server.registerDiagnosticsCommands(.init(captureExploreLogs: false,
                                                         captureStdout: true,
                                                         captureStderr: false,
                                                         teeToOriginalStreams: false))
            guard let store = ProcessDiagnosticsRuntime.shared.currentStore() else {
                throw TestFailure("missing diagnostics store")
            }
            let mark = store.mark()

            ProcessDiagnosticsRuntime.shared.resetForTesting()
            writeLine(token, to: .standardOutput)
            try await Task.sleep(nanoseconds: 100_000_000)

            let result = store.read(after: mark.cursor, limit: 20, sources: [.stdout], minimumLevel: nil)
            #expect(result.entries.contains { $0.message == token } == false)
        }
    }
}

private extension AppLogCursor {
    func toJSON() -> JSON {
        [
            "captureSessionID": .string(captureSessionID),
            "id": .double(Double(id)),
        ]
    }
}

private func cursor(from result: ExploreResult) throws -> AppLogCursor {
    guard case .success(let data) = result,
          let cursorObject = data["cursor"]?.objectValue,
          let session = cursorObject["captureSessionID"]?.stringValue,
          let id = cursorObject["id"]?.doubleValue else {
        throw TestFailure("missing cursor")
    }
    return AppLogCursor(captureSessionID: session, id: UInt64(id))
}

private func entries(from result: ExploreResult) throws -> [JSON] {
    guard case .success(let data) = result,
          let values = data["entries"]?.arrayValue else {
        throw TestFailure("missing entries")
    }
    return values.compactMap(\.objectValue)
}

private func nextCursor(from result: ExploreResult) throws -> AppLogCursor {
    guard case .success(let data) = result,
          let cursorObject = data["nextCursor"]?.objectValue,
          let session = cursorObject["captureSessionID"]?.stringValue,
          let id = cursorObject["id"]?.doubleValue else {
        throw TestFailure("missing nextCursor")
    }
    return AppLogCursor(captureSessionID: session, id: UInt64(id))
}

private func hasMore(from result: ExploreResult) throws -> Bool {
    guard case .success(let data) = result,
          let hasMore = data["hasMore"]?.boolValue else {
        throw TestFailure("missing hasMore")
    }
    return hasMore
}

private func inputSchema(for action: String, from result: ExploreResult) throws -> JSON {
    guard case .success(let data) = result,
          let commands = data["commands"]?.arrayValue else {
        throw TestFailure("missing commands")
    }
    for commandValue in commands {
        guard let command = commandValue.objectValue else { continue }
        if command["action"]?.stringValue == action,
           let schema = command["inputSchema"]?.objectValue {
            return schema
        }
    }
    throw TestFailure("missing schema")
}

private func writeLine(_ line: String, to handle: FileHandle) {
    // 前置换行：全套测试并发跑时，其他来源（测试框架/系统）可能向 stderr 写入不带 \n 的字节，
    // 若与 line 拼在同一行，capture 按 \n 切分会把残余字节拼到 line 前（message != line，
    // 导致严格的 message == token 断言偶发失败）。前导 \n 先把残余 pending 终结成独立行，
    // 确保 line 自身成行；无残余时仅多一个空行 entry，不影响检测。
    handle.write(Data(("\n" + line + "\n").utf8))
}

private func waitForEntry(after mark: AppLogCursor,
                          source: String,
                          token: String,
                          server: ExploreServer,
                          attempts: Int = 60) async throws -> [JSON] {
    for _ in 0..<attempts {
        let values = try await pagedEntries(after: mark, source: source, token: token, server: server)
        if values.contains(where: { ($0["message"]?.stringValue ?? "").contains(token) }) {
            return values
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    return try await pagedEntries(after: mark, source: source, token: token, server: server)
}

private func pagedEntries(after mark: AppLogCursor,
                          source: String,
                          token: String,
                          server: ExploreServer) async throws -> [JSON] {
    var cursor = mark
    var collected: [JSON] = []
    for _ in 0..<50 {
        let result = await server.routerSnapshotRoute(ExploreRequest(action: "app.logs.read",
                                                                    data: ["after": .object(cursor.toJSON()),
                                                                           "limit": .double(500),
                                                                           "sources": .array([.string(source)])]))
        let pageEntries = try entries(from: result)
        collected.append(contentsOf: pageEntries)
        if pageEntries.contains(where: { ($0["message"]?.stringValue ?? "").contains(token) }) {
            break
        }
        guard try hasMore(from: result) else { break }
        cursor = try nextCursor(from: result)
    }
    return collected
}

private struct TestFailure: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

private extension ExploreResult {
    var commandActions: [String] {
        guard case .success(let data) = self,
              case .array(let commands)? = data["commands"] else { return [] }
        return commands.compactMap {
            guard case .object(let command) = $0 else { return nil }
            return command["action"]?.stringValue
        }
    }
}
