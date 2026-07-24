import Testing
@testable import iOSExploreServer
import iOSExploreUIKit
@testable import iOSExploreDiagnostics

@Suite("HelpContractTests", .serialized)
struct HelpContractTests {
    @Test("help 暴露公共合同版本、哈希和 commands")
    func helpExposesPublicContractBundleMetadata() async throws {
        let data = try await helpData(from: ExploreServer())
        let contractHash = data["contractHash"]?.stringValue ?? ""
        let hexadecimalCharacters = Set("0123456789abcdef")

        #expect(data["protocolVersion"]?.stringValue == "1")
        #expect(data["contractVersion"]?.stringValue == "1.0.0")
        #expect(contractHash.hasPrefix("sha256:"))
        #expect(contractHash.count == 71)
        #expect(contractHash.dropFirst("sha256:".count).allSatisfy { hexadecimalCharacters.contains($0) })
        #expect(data["commands"]?.arrayValue != nil)

        let commands = try helpCommands(from: data)
        let ping = try command(named: "ping", in: commands)
        #expect(ping["result"]?.objectValue?["kind"]?.stringValue == "json")
        #expect(ping["resultKind"] == nil)
        #expect(ping["errors"]?.arrayValue?.contains(.string("internal_error")) == true)
    }

    @Test("help 只列出当前 Router 已注册的 action")
    func helpOnlyListsCurrentlyRegisteredActions() async throws {
        let commands = try await helpCommands(from: ExploreServer())
        let actions = Set(commands.compactMap { $0["action"]?.stringValue })

        #expect(actions == ["echo", "help", "info", "ping"])
        #expect(actions.contains(where: { $0.hasPrefix("ui.") }) == false)
        #expect(actions.contains("app.logs.mark") == false)
        #expect(actions.contains("app.logs.read") == false)
    }

    @Test("Diagnostics 注册后 help 暴露 generated 公共 metadata")
    func diagnosticsRegistrationExposesGeneratedMetadata() async throws {
        try await withProcessDiagnosticsTestIsolation {
            ESDiagnosticsRuntime.shared.resetForTesting()
            defer { ESDiagnosticsRuntime.shared.resetForTesting() }

            let server = ExploreServer()
            _ = server.registerDiagnosticsCommands(.init(captureExploreLogs: false,
                                                         captureStdout: false,
                                                         captureStderr: false))
            let commands = try await helpCommands(from: server)

            for action in ["app.logs.mark", "app.logs.read"] {
                let command = try command(named: action, in: commands)
                #expect(command["provider"]?.stringValue == "diagnostics")
                #expect(command["stability"]?.stringValue == "public")
                #expect(command["contractSource"]?.stringValue == "generated")
            }
        }
    }

#if canImport(UIKit)
    @Test("UIKit 注册后 help 暴露 generated 公共 metadata")
    func uikitRegistrationExposesGeneratedMetadata() async throws {
        let server = ExploreServer()
        server.registerUIKitCommands()
        let commands = try await helpCommands(from: server)
        let uikitCommands = commands.filter { $0["action"]?.stringValue?.hasPrefix("ui.") == true }

        #expect(uikitCommands.count == 21)
        for command in uikitCommands {
            #expect(command["provider"]?.stringValue == "uikit")
            #expect(command["stability"]?.stringValue == "public")
            #expect(command["contractSource"]?.stringValue == "generated")
        }
    }
#endif

    @Test("旧 closure 注册入口产生 runtime extension metadata 且不改变公共合同哈希")
    func closureRegistrationUsesRuntimeExtensionMetadataWithoutChangingBundleHash() async throws {
        let server = ExploreServer()
        let beforeRegistration = try await helpData(from: server)

        server.register(action: "runtime.echo",
                        description: "运行时扩展",
                        input: EmptyCommandInput.self) { _ in
            .success([:])
        }

        let afterRegistration = try await helpData(from: server)
        let commands = try helpCommands(from: afterRegistration)
        let runtimeCommand = try command(named: "runtime.echo", in: commands)

        #expect(runtimeCommand["provider"]?.stringValue == "extension")
        #expect(runtimeCommand["stability"]?.stringValue == "internal")
        #expect(runtimeCommand["contractSource"]?.stringValue == "runtime")

        let beforeHash = try requiredString("contractHash", in: beforeRegistration)
        let afterHash = try requiredString("contractHash", in: afterRegistration)
        #expect(afterHash == beforeHash)
    }
}

private func helpData(from server: ExploreServer) async throws -> JSON {
    let result = await server.routerSnapshotRoute(ExploreRequest(action: "help"))
    guard case .success(let data) = result else {
        throw HelpContractTestError("help did not return success")
    }
    return data
}

private func helpCommands(from server: ExploreServer) async throws -> [JSON] {
    try helpCommands(from: await helpData(from: server))
}

private func helpCommands(from data: JSON) throws -> [JSON] {
    guard let values = data["commands"]?.arrayValue else {
        throw HelpContractTestError("help commands missing or not an array")
    }
    let commands = values.compactMap(\.objectValue)
    guard commands.count == values.count else {
        throw HelpContractTestError("help commands contains a non-object entry")
    }
    return commands
}

private func command(named action: String, in commands: [JSON]) throws -> JSON {
    guard let command = commands.first(where: { $0["action"]?.stringValue == action }) else {
        throw HelpContractTestError("help command missing: \(action)")
    }
    return command
}

private func requiredString(_ key: String, in data: JSON) throws -> String {
    guard let value = data[key]?.stringValue else {
        throw HelpContractTestError("help field missing or not a string: \(key)")
    }
    return value
}

private struct HelpContractTestError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
