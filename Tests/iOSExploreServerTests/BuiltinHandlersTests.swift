import Testing
@testable import iOSExploreServer

private struct BuiltinGreetingInput: CommandInput, Equatable {
    static let nameField = CommandFields.requiredString("name", description: "名字")
    static let inputSchema = CommandInputSchema(fields: [nameField.erased])

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

@Test("help 列出全部命令元数据,结构对齐 MCP")
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

    // 验证 greet2 的 inputSchema 映射逻辑。
    guard let greet2 = entries.first(where: { entry in
        if case .object(let obj) = entry, case .string(let a) = obj["action"] { return a == "greet2" }
        return false
    }) else { Issue.record("greet2 not found"); return }
    guard case .object(let obj2) = greet2 else { Issue.record("greet2 not object"); return }
    #expect(obj2["parameters"] == nil)
    guard case .object(let inputSchema) = obj2["inputSchema"] else { Issue.record("inputSchema not object"); return }
    guard case .object(let properties) = inputSchema["properties"] else { Issue.record("properties not object"); return }
    guard case .object(let nameSchema) = properties["name"] else { Issue.record("name schema missing"); return }
    if case .string(let type) = nameSchema["type"] { #expect(type == "string") } else { Issue.record("type mismatch") }
    if case .string(let d) = nameSchema["description"] { #expect(d == "名字") } else { Issue.record("description mismatch") }
    guard case .array(let required) = inputSchema["required"] else { Issue.record("required missing"); return }
    #expect(required == [JSONValue.string("name")])
    guard case .array(let order) = inputSchema["x-iosExplore-propertyOrder"] else { Issue.record("property order missing"); return }
    #expect(order == [JSONValue.string("name")])
}
