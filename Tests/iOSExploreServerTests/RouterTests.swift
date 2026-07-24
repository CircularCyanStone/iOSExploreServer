import Testing
@testable import iOSExploreServer

private let thirtySecondCommandTimeoutNanoseconds: UInt64 = 30 * 1_000_000_000

private struct RouterGreetingInput: CommandInput, Equatable {
    static let nameField = CommandFields.requiredString("name", description: "名字")
    static let inputSchema = CommandInputSchema(fields: [nameField.erased])

    let name: String

    static func parse(decoding decoder: inout CommandInputDecoder) throws -> RouterGreetingInput {
        RouterGreetingInput(name: try decoder.read(nameField))
    }
}

private func routerTestContract(action: String,
                                description: String = "",
                                inputSchema: CommandInputSchema = .empty) -> CommandContract {
    CommandContract(action: action,
                    description: description,
                    inputSchema: inputSchema,
                    provider: .extension,
                    stability: .`internal`,
                    resultKind: .json,
                    declaredErrors: [],
                    idempotency: .sideEffecting,
                    timeoutClass: .standard,
                    contractVersion: CoreActionContracts.contractVersion,
                    contractHash: CoreActionContracts.contractHash,
                    contractSource: .runtime)
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
    if case .failure(let code, _, _) = result {
        #expect(code == .unknownAction)
    } else {
        Issue.record("expected failure")
    }
}

@Test("注册拒绝非法 action 且不污染 metadata")
func registrationRejectsInvalidAction() async {
    let router = Router()
    router.register(action: "bad action", input: EmptyCommandInput.self) { _ in .success([:]) }

    #expect(router.commandMetadata().isEmpty)
    let result = await router.route(ExploreRequest(action: "bad action"))
    guard case .failure(let code, _, _) = result else {
        Issue.record("expected unknown action")
        return
    }
    #expect(code == .unknownAction)
}

@Test("handler 抛异常转为 internal_error")
func routeThrowing() async {
    let router = Router()
    struct Boom: Error {}
    router.register(action: "boom", input: EmptyCommandInput.self) { _ in throw Boom() }
    let result = await router.route(ExploreRequest(action: "boom"))
    if case .failure(let code, _, _) = result {
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
    if case .failure(let code, let msg, _) = result {
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
    if case .failure(let code, _, _) = result {
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
        let contract = routerTestContract(action: "ping2")
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
    #expect(greet.provider == .extension)
    #expect(greet.stability == .`internal`)
    #expect(greet.resultKind == .json)
    #expect(greet.declaredErrors.isEmpty)
    #expect(greet.idempotency == .sideEffecting)
    #expect(greet.timeoutClass == .standard)
    #expect(greet.contractVersion == CoreActionContracts.contractVersion)
    #expect(greet.contractHash == CoreActionContracts.contractHash)
    #expect(greet.contractSource == .runtime)
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

@Test("显式合同注册保留 metadata 且执行仍使用 typed parser")
func explicitContractRegistrationPreservesMetadataAndTypedParser() async {
    let contract = CommandContract(action: "contract.greet",
                                   description: "显式合同问候",
                                   inputSchema: .empty,
                                   provider: .extension,
                                   stability: .experimental,
                                   resultKind: .text,
                                   declaredErrors: ["invalid_data"],
                                   idempotency: .idempotent,
                                   timeoutClass: .wait,
                                   contractVersion: "2.0.0",
                                   contractHash: "sha256:" + String(repeating: "a", count: 64),
                                   contractSource: .generated)
    let router = Router()
    router.register(contract: contract, input: RouterGreetingInput.self) { input in
        .success(["message": .string(input.name)])
    }

    #expect(router.commandMetadata() == [contract])

    let missingName = await router.route(ExploreRequest(action: contract.action))
    guard case .failure(let code, _, _) = missingName else {
        Issue.record("expected typed parser failure")
        return
    }
    #expect(code == .invalidData)

    let success = await router.route(ExploreRequest(action: contract.action, data: ["name": "Ada"]))
    guard case .success(let data) = success else {
        Issue.record("expected explicit contract command success")
        return
    }
    #expect(data["message"] == .string("Ada"))
}

@Test("Router.commandTimeout 返回命令自声明 timeoutNanoseconds，缺省 nil")
func commandTimeoutLookup() async {
    let router = Router()
    router.register(action: "defaultTimeout", input: EmptyCommandInput.self) { _ in .success([:]) }
    #expect(router.commandTimeout(for: "defaultTimeout") == nil)
    #expect(router.commandTimeout(for: "unregistered") == nil)
}

@Test("协议命令自声明 timeoutNanoseconds 透传到 Router.commandTimeout")
func commandTimeoutLookupForProtocolCommand() async {
    struct SlowCommand: Command {
        typealias Input = EmptyCommandInput
        let contract = routerTestContract(action: "slow")
        var timeoutNanoseconds: UInt64? { thirtySecondCommandTimeoutNanoseconds }
        func handle(_ input: EmptyCommandInput) async throws -> ExploreResult { .success([:]) }
    }
    let router = Router()
    router.register(SlowCommand())
    #expect(router.commandTimeout(for: "slow") == thirtySecondCommandTimeoutNanoseconds)
}

@Test("闭包命令默认 timeoutNanoseconds 为 nil（无自声明超时）")
func commandTimeoutLookupForClosureCommand() async {
    let router = Router()
    router.register(action: "closureCmd", input: EmptyCommandInput.self) { _ in .success([:]) }
    #expect(router.commandTimeout(for: "closureCmd") == nil)
}

@Test("metadata 按 action 稳定排序")
func commandMetadataSortsByAction() {
    let router = Router()
    router.register(action: "z.last", input: EmptyCommandInput.self) { _ in .success([:]) }
    router.register(action: "a.first", input: EmptyCommandInput.self) { _ in .success([:]) }

    let actions = router.commandMetadata().map(\.action)

    #expect(actions == ["a.first", "z.last"])
}
