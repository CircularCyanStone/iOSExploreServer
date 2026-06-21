import Testing
@testable import iOSExploreServer

@Test("ping 返回 pong")
func pingReturns() {
    let result = BuiltinHandlers.ping(ExploreRequest(action: "ping"))
    if case .success(let data) = result {
        #expect(data["pong"] == .bool(true))
    } else { Issue.record("expected success") }
}

@Test("echo 原样回显 data")
func echoReturns() {
    let req = ExploreRequest(action: "echo", data: ["a": 1, "b": "x"])
    let result = BuiltinHandlers.echo(req)
    if case .success(let data) = result {
        #expect(data["a"] == .double(1))
        #expect(data["b"]?.stringValue == "x")
    } else { Issue.record("expected success") }
}

@Test("info 返回 system/app/bundle 字段")
func infoReturns() {
    let result = BuiltinHandlers.info(ExploreRequest(action: "info"))
    if case .success(let data) = result {
        #expect(data["system"]?.stringValue != nil)
        #expect(data["app"]?.stringValue != nil)
        #expect(data["bundle"]?.stringValue != nil)
    } else { Issue.record("expected success") }
}

@Test("registerAll 注册三个命令")
func registerAllRegisters() async {
    let router = Router()
    BuiltinHandlers.registerAll(into: router)
    for action in ["ping", "echo", "info"] {
        let r = await router.route(ExploreRequest(action: action))
        if case .failure = r { Issue.record("\(action) should be registered") }
    }
}
