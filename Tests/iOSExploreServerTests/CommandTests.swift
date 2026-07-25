import Testing
@testable import iOSExploreServer

private struct GreetingInput: CommandInput, Equatable {
    static let nameField = CommandFields.requiredString("name")
    static let inputDefinition = CommandInputDefinition(fields: [nameField.erased])

    let name: String

    static func parse(decoding decoder: inout CommandInputDecoder) throws -> GreetingInput {
        GreetingInput(name: try decoder.read(nameField))
    }
}

@Test("AnyCommand 解析 typed input 并转发 handle")
func anyCommandParsesTypedInputAndHandles() async {
    let cmd = AnyCommand(
        action: "greet",
        description: "打招呼",
        input: GreetingInput.self
    ) { input in
        .success(["message": .string("Hello, \(input.name)")])
    }
    #expect(cmd.action == "greet")
    #expect(cmd.description == "打招呼")
    #expect(cmd.inputDefinition.fields.map(\.name) == ["name"])

    let result = await cmd.handle(ExploreRequest(action: "greet", data: ["name": "Claude"]))
    if case .success(let data) = result {
        #expect(data["message"]?.stringValue == "Hello, Claude")
    } else {
        Issue.record("expected success")
    }
}

@Test("AnyCommand 解析失败映射 invalid_data")
func anyCommandParseFailureMapsInvalidData() async {
    let cmd = AnyCommand(action: "greet", description: "打招呼", input: GreetingInput.self) { input in
        .success(["message": .string(input.name)])
    }

    let result = await cmd.handle(ExploreRequest(action: "greet"))
    if case .failure(let code, let message, _) = result {
        #expect(code == .invalidData)
        #expect(message.contains("name"))
    } else {
        Issue.record("expected invalidData")
    }
}
