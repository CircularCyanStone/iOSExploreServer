import Testing
@testable import iOSExploreServer

@Test("ClosureCommand 暴露元数据并转发 handle")
func closureCommandMetadataAndHandle() async throws {
    let cmd = ClosureCommand(
        action: "greet",
        description: "打招呼",
        parameters: [CommandParameter(name: "name", kind: .string, required: true, description: "名字")]
    ) { req in
        let name = req.data["name"]?.stringValue ?? "world"
        return .success(["message": .string("Hello, \(name)")])
    }
    #expect(cmd.action == "greet")
    #expect(cmd.description == "打招呼")
    #expect(cmd.parameters.count == 1)
    #expect(cmd.parameters[0].name == "name")

    let result = try await cmd.handle(ExploreRequest(action: "greet", data: ["name": "Claude"]))
    if case .success(let data) = result {
        #expect(data["message"]?.stringValue == "Hello, Claude")
    } else {
        Issue.record("expected success")
    }
}

@Test("Command 协议默认 parameters 为空")
func defaultParametersEmpty() {
    let cmd = ClosureCommand(action: "noop", description: "") { _ in .success([:]) }
    #expect(cmd.parameters.isEmpty)
}
