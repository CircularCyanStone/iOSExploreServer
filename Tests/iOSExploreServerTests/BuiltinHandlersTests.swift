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
    router.register(action: "greet2",
                    description: "测试用",
                    parameters: [CommandParameter(name: "name", kind: .string, required: true, description: "名字")]) { _ in .success([:]) }
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

    // 验证 greet2 的 parameters 映射逻辑(HelpCommand 参数子结构)
    guard let greet2 = entries.first(where: { entry in
        if case .object(let obj) = entry, case .string(let a) = obj["action"] { return a == "greet2" }
        return false
    }) else { Issue.record("greet2 not found"); return }
    guard case .object(let obj2) = greet2 else { Issue.record("greet2 not object"); return }
    guard case .array(let params) = obj2["parameters"] else { Issue.record("parameters not array"); return }
    #expect(params.count == 1)
    guard let firstParam = params.first else { Issue.record("parameters empty"); return }
    guard case .object(let p) = firstParam else { Issue.record("param not object"); return }
    if case .string(let n) = p["name"] { #expect(n == "name") } else { Issue.record("name mismatch") }
    if case .string(let k) = p["kind"] { #expect(k == "string") } else { Issue.record("kind mismatch") }
    if case .bool(let req) = p["required"] { #expect(req == true) } else { Issue.record("required mismatch") }
    if case .string(let d) = p["description"] { #expect(d == "名字") } else { Issue.record("description mismatch") }
}
