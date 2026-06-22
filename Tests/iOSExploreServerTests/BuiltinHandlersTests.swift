import Testing
@testable import iOSExploreServer

@Test("PingCommand 返回 pong")
func pingCommandReturns() async throws {
    let r = try await PingCommand().handle(ExploreRequest(action: "ping"))
    if case .success(let data) = r {
        #expect(data["pong"] == .bool(true))
    } else { Issue.record("expected success") }
}

@Test("EchoCommand 原样回显 data")
func echoCommandReturns() async throws {
    let req = ExploreRequest(action: "echo", data: ["a": 1, "b": "x"])
    let r = try await EchoCommand().handle(req)
    if case .success(let data) = r {
        #expect(data["a"] == .double(1))
        #expect(data["b"]?.stringValue == "x")
    } else { Issue.record("expected success") }
}

@Test("InfoCommand 返回 system/app/bundle 字段")
func infoCommandReturns() async throws {
    let r = try await InfoCommand().handle(ExploreRequest(action: "info"))
    if case .success(let data) = r {
        #expect(data["system"]?.stringValue != nil)
        #expect(data["app"]?.stringValue != nil)
        #expect(data["bundle"]?.stringValue != nil)
    } else { Issue.record("expected success") }
}

@Test("registerAll 注册 ping/echo/info/help")
func registerAllRegisters() async {
    let router = Router()
    BuiltinHandlers.registerAll(into: router)
    for action in ["ping", "echo", "info", "help"] {
        let r = await router.route(ExploreRequest(action: action))
        if case .failure = r { Issue.record("\(action) should be registered") }
    }
}

@Test("help 列出全部命令元数据,结构对齐 MCP")
func helpListsAllCommands() async throws {
    let router = Router()
    BuiltinHandlers.registerAll(into: router)
    let r = try await HelpCommand(router: router).handle(ExploreRequest(action: "help"))
    guard case .success(let data) = r else { Issue.record("expected success"); return }
    guard case .array(let entries) = data["commands"] else { Issue.record("commands not array"); return }
    let actions: [String] = entries.compactMap { entry in
        if case .object(let obj) = entry, case .string(let a) = obj["action"] { return a }
        return nil
    }
    #expect(actions.contains("ping"))
    #expect(actions.contains("echo"))
    #expect(actions.contains("info"))
    #expect(actions.contains("help"))
}
