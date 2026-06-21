import Testing
@testable import iOSExploreServer

@Test("注册的 action 被命中并返回 success")
func routeHitsRegistered() async {
    let router = Router()
    await router.register(action: "hello") { _ in .success(["msg": "hi"]) }
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
    await router.register(action: "boom") { _ in throw Boom() }
    let result = await router.route(ExploreRequest(action: "boom"))
    if case .failure(let code, _) = result {
        #expect(code == .internalError)
    } else {
        Issue.record("expected failure")
    }
}
