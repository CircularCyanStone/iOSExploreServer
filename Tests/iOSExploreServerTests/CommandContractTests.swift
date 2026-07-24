import Testing
@testable import iOSExploreServer

@Test("CommandContract 接受合法 action 名")
func commandContractAcceptsValidActions() throws {
    for action in ["ping", "ui.tap", "core_v2", "read-logs", "A1.b2_c3-d4"] {
        try CommandContract.validateAction(action)
    }
}

@Test("CommandContract 拒绝非法 action 名")
func commandContractRejectsInvalidActions() {
    for action in ["", "1ping", "bad action", "bad/route", "bad.", "bad_", "bad-", "bad..name", "bad__name", "中文"] {
        #expect(throws: CommandContractError.self) {
            try CommandContract.validateAction(action)
        }
    }
}

@Test("CommandContract 保存完整合同字段")
func commandContractStoresContractFields() {
    let schema = CommandInputSchema(fields: [
        CommandFields.requiredString("name", description: "名称").erased,
    ])
    let contract = CommandContract(
        action: "example.read",
        description: "读取示例",
        inputSchema: schema,
        provider: .core,
        stability: .public,
        resultKind: .json,
        declaredErrors: ["internal_error"],
        idempotency: .readOnly,
        timeoutClass: .standard,
        contractVersion: "1.0.0",
        contractHash: "sha256:" + String(repeating: "0", count: 64)
    )

    #expect(contract.action == "example.read")
    #expect(contract.description == "读取示例")
    #expect(contract.inputSchema == schema)
    #expect(contract.provider == .core)
    #expect(contract.stability == .public)
    #expect(contract.resultKind == .json)
    #expect(contract.declaredErrors == ["internal_error"])
    #expect(contract.idempotency == .readOnly)
    #expect(contract.timeoutClass == .standard)
    #expect(contract.contractVersion == "1.0.0")
    #expect(contract.contractHash == "sha256:" + String(repeating: "0", count: 64))
}

@Test("CommandContract 区分 generated 和 runtime 来源")
func commandContractStoresSource() {
    let common: (CommandContractSource) -> CommandContract = { source in
        CommandContract(
            action: "example.read",
            description: "读取示例",
            inputSchema: .empty,
            provider: .extension,
            stability: .`internal`,
            resultKind: .json,
            declaredErrors: [],
            idempotency: .readOnly,
            timeoutClass: .standard,
            contractVersion: "1.0.0",
            contractHash: "sha256:" + String(repeating: "a", count: 64),
            contractSource: source
        )
    }

    #expect(common(.generated).contractSource == .generated)
    #expect(common(.runtime).contractSource == .runtime)
    #expect(common(.generated) != common(.runtime))
}

@Test("CommandContract 保留 version 和 hash")
func commandContractPreservesVersionAndHash() {
    let contract = CommandContract(
        action: "example.read",
        description: "读取示例",
        inputSchema: .empty,
        provider: .core,
        stability: .public,
        resultKind: .json,
        declaredErrors: [],
        idempotency: .readOnly,
        timeoutClass: .standard,
        contractVersion: "2.4.7",
        contractHash: "sha256:" + String(repeating: "f", count: 64)
    )

    #expect(contract.contractVersion == "2.4.7")
    #expect(contract.contractHash == "sha256:" + String(repeating: "f", count: 64))
}
