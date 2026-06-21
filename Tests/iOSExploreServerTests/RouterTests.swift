import Testing
@testable import iOSExploreServer

@Test("注册的 action 被命中并返回 success")
func routeHitsRegistered() async {
    let router = Router()
    router.register(action: "hello") { _ in .success(["msg": "hi"]) }
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
    router.register(action: "boom") { _ in throw Boom() }
    let result = await router.route(ExploreRequest(action: "boom"))
    if case .failure(let code, _) = result {
        #expect(code == .internalError)
    } else {
        Issue.record("expected failure")
    }
}

@Test("缺必填参数返回 invalid_data")
func routeMissingRequiredParam() async {
    let router = Router()
    router.register(action: "greet",
                    parameters: [CommandParameter(name: "name", kind: .string, required: true, description: "")]) { _ in
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

@Test("参数类型不匹配返回 invalid_data")
func routeTypeMismatch() async {
    let router = Router()
    router.register(action: "add",
                    parameters: [CommandParameter(name: "x", kind: .number, required: true, description: "")]) { _ in
        .success([:])
    }
    let result = await router.route(ExploreRequest(action: "add", data: ["x": "not-a-number"]))
    if case .failure(let code, _) = result {
        #expect(code == .invalidData)
    } else {
        Issue.record("expected invalidData")
    }
}

@Test("参数合法时不拦截,正常进入 handler")
func routeValidParamsPassThrough() async {
    let router = Router()
    router.register(action: "add",
                    parameters: [CommandParameter(name: "x", kind: .number, required: true, description: "")]) { req in
        .success(["doubled": req.data["x"] ?? .null])
    }
    let result = await router.route(ExploreRequest(action: "add", data: ["x": 21]))
    if case .success(let data) = result {
        #expect(data["doubled"] == .double(21))
    } else {
        Issue.record("expected success")
    }
}

@Test("协议对象注册与闭包注册等价可达")
func routeProtocolRegistration() async {
    let router = Router()
    struct Ping: Command {
        let action = "ping2"
        let description = ""
        func handle(_ request: ExploreRequest) async throws -> ExploreResult { .success(["ok": .bool(true)]) }
    }
    router.register(Ping())
    let result = await router.route(ExploreRequest(action: "ping2"))
    if case .success(let data) = result {
        #expect(data["ok"] == .bool(true))
    } else {
        Issue.record("expected success")
    }
}
