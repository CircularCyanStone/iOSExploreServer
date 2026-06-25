import Testing
@testable import iOSExploreServer

private struct RouterGreetingInput: CommandInput, Equatable {
    static let nameField = CommandFields.requiredString("name", description: "名字")
    static let inputSchema = CommandInputSchema(fields: [nameField.erased])

    let name: String

    static func parse(decoding decoder: inout CommandInputDecoder) throws -> RouterGreetingInput {
        RouterGreetingInput(name: try decoder.read(nameField))
    }
}

@Test("注册的 action 被命中并返回 success")
func routeHitsRegistered() async {
    let router = Router()
    router.register(action: "hello", input: EmptyCommandInput.self) { _ in .success(["msg": "hi"]) }
    let result = await router.route(ExploreRequest(action: "hello"))
    if case .success(let data) = result {
        #expect(data["msg"]?.stringValue == "hi")
    } else {
        Issue.record("expected success")
    }
}

@Test("未注册的 action 返回 unknown_action")
func routeUnknown() async {
    let router = Router()
    let result = await router.route(ExploreRequest(action: "nope"))
    if case .failure(let code, _) = result {
        #expect(code == .unknownAction)
    } else {
        Issue.record("expected failure")
    }
}

@Test("handler 抛异常转为 internal_error")
func routeThrowing() async {
    let router = Router()
    struct Boom: Error {}
    router.register(action: "boom", input: EmptyCommandInput.self) { _ in throw Boom() }
    let result = await router.route(ExploreRequest(action: "boom"))
    if case .failure(let code, _) = result {
        #expect(code == .internalError)
    } else {
        Issue.record("expected failure")
    }
}

@Test("typed input 缺必填字段返回 invalid_data")
func routeMissingRequiredInputField() async {
    let router = Router()
    router.register(action: "greet", input: RouterGreetingInput.self) { _ in
        .success([:])
    }
    let result = await router.route(ExploreRequest(action: "greet"))
    if case .failure(let code, let msg) = result {
        #expect(code == .invalidData)
        #expect(msg.contains("name"))
    } else {
        Issue.record("expected invalidData")
    }
}

@Test("typed input 字段类型不匹配返回 invalid_data")
func routeInputTypeMismatch() async {
    let router = Router()
    router.register(action: "greet", input: RouterGreetingInput.self) { _ in
        .success([:])
    }
    let result = await router.route(ExploreRequest(action: "greet", data: ["name": 42]))
    if case .failure(let code, _) = result {
        #expect(code == .invalidData)
    } else {
        Issue.record("expected invalidData")
    }
}

@Test("typed input 合法时进入 handler")
func routeValidTypedInputPassesThrough() async {
    let router = Router()
    router.register(action: "greet", input: RouterGreetingInput.self) { input in
        .success(["message": .string(input.name)])
    }
    let result = await router.route(ExploreRequest(action: "greet", data: ["name": "Claude"]))
    if case .success(let data) = result {
        #expect(data["message"] == .string("Claude"))
    } else {
        Issue.record("expected success")
    }
}

@Test("协议对象注册与闭包注册等价可达")
func routeProtocolRegistration() async {
    let router = Router()
    struct Ping: Command {
        typealias Input = EmptyCommandInput
        let action = "ping2"
        let description = ""
        func handle(_ input: EmptyCommandInput) async throws -> ExploreResult { .success(["ok": .bool(true)]) }
    }
    router.register(Ping())
    let result = await router.route(ExploreRequest(action: "ping2"))
    if case .success(let data) = result {
        #expect(data["ok"] == .bool(true))
    } else {
        Issue.record("expected success")
    }
}

@Test("metadata 暴露 typed inputSchema properties")
func commandMetadataIncludesInputSchemaProperties() {
    let router = Router()
    router.register(action: "greet", description: "打招呼", input: RouterGreetingInput.self) { _ in
        .success([:])
    }

    let metadata = router.commandMetadata()
    guard let greet = metadata.first(where: { $0.action == "greet" }) else {
        Issue.record("greet metadata missing")
        return
    }
    #expect(greet.description == "打招呼")
    let schemaJSON = greet.inputSchema.toJSON()
    guard case .object(let properties) = schemaJSON["properties"] else {
        Issue.record("properties not object")
        return
    }
    #expect(properties["name"] != nil)
    guard case .array(let order) = schemaJSON["x-iosExplore-propertyOrder"] else {
        Issue.record("property order missing")
        return
    }
    #expect(order == [JSONValue.string("name")])
}
