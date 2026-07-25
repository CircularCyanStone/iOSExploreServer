import Testing
@testable import iOSExploreServer

private struct BuiltinGreetingInput: CommandInput, Equatable {
    static let nameField = CommandFields.requiredString("name")
    static let inputDefinition = CommandInputDefinition(fields: [nameField.erased])

    let name: String

    static func parse(decoding decoder: inout CommandInputDecoder) throws -> BuiltinGreetingInput {
        BuiltinGreetingInput(name: try decoder.read(nameField))
    }
}

@Test("PingCommand 返回 pong")
func pingCommandReturns() async {
    let r = await AnyCommand(PingCommand()).handle(ExploreRequest(action: "ping"))
    if case .success(let data) = r {
        #expect(data["pong"] == .bool(true))
    } else { Issue.record("expected success") }
}

@Test("EchoCommand 原样回显 data")
func echoCommandReturns() async {
    let req = ExploreRequest(action: "echo", data: ["a": 1, "b": "x"])
    let r = await AnyCommand(EchoCommand()).handle(req)
    if case .success(let data) = r {
        #expect(data["a"] == .double(1))
        #expect(data["b"]?.stringValue == "x")
    } else { Issue.record("expected success") }
}

@Test("InfoCommand 返回 system/app/bundle 字段")
func infoCommandReturns() async {
    let r = await AnyCommand(InfoCommand()).handle(ExploreRequest(action: "info"))
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

@Test("help 列出运行时命令元数据且不携带 inputSchema")
func helpListsAllCommands() async throws {
    let router = Router()
    BuiltinHandlers.registerAll(into: router)
    router.register(action: "greet2", description: "测试用", input: BuiltinGreetingInput.self) { _ in .success([:]) }
    let r = try await HelpCommand(router: router).handle(EmptyCommandInput())
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

    // runtime extension 也只返回运行时 metadata，输入字段由 Swift parser 自己持有。
    guard let greet2 = entries.first(where: { entry in
        if case .object(let obj) = entry, case .string(let a) = obj["action"] { return a == "greet2" }
        return false
    }) else { Issue.record("greet2 not found"); return }
    guard case .object(let obj2) = greet2 else { Issue.record("greet2 not object"); return }
    #expect(obj2["parameters"] == nil)
    #expect(obj2["inputSchema"] == nil)
    #expect(obj2["inputDefinition"] == nil)
    #expect(obj2["provider"]?.stringValue == "extension")
}
