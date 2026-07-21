#if canImport(UIKit)
import UIKit
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

/// `ui.input` 的 schema 解析与执行核心测试。
///
/// schema 解析（Foundation-only typed query）与 executor 派发（批量顺序 → locate →
/// first responder → insertText → 委托比对 → 密码脱敏）都在这里覆盖。通过
/// `UIKitTestHost` 注入可控 view 树，真实驱动 `UITextInputExecutor.execute` 的主要成功/失败分支。

// MARK: - UIInputInput schema 解析（Foundation-only typed query）

@Test("UIInputInput: 单字段也必须放入 fields；mode 默认 replace；submit 默认 false")
func inputInputParseDefaults() throws {
    let input = try UIInputInput.parse(from: [
        "fields": [
            [
                "path": "root/0",
                "text": "hi",
            ],
        ],
    ])

    #expect(input.fields.count == 1)
    #expect(input.fields[0].text == "hi")
    #expect(input.fields[0].mode == .replace)
    #expect(input.fields[0].submit == false)
    #expect(input.stopOnFailure == true)
    #expect(input.viewSnapshotID == nil)
}

@Test("UIInputInput: fields 必填且不能为空")
func inputInputRejectsMissingOrEmptyFields() {
    #expect(throws: CommandInputParseError.self) {
        _ = try UIInputInput.parse(from: [:])
    }
    #expect(throws: CommandInputParseError.self) {
        _ = try UIInputInput.parse(from: ["fields": []])
    }
}

@Test("UIInputInput: field 缺 text 抛带下标的解析错误")
func inputInputRejectsMissingFieldText() {
    #expect(throws: CommandInputParseError.self) {
        _ = try UIInputInput.parse(from: ["fields": [["path": "root/0"]]])
    }
}

@Test("UIInputInput: append 模式与 submit=true 可显式传入")
func inputInputParsesAppendAndSubmit() throws {
    let input = try UIInputInput.parse(from: [
        "fields": [
            [
                "accessibilityIdentifier": "field.email",
                "text": "x",
                "mode": "append",
                "submit": true,
            ],
        ],
    ])

    #expect(input.fields[0].mode == .append)
    #expect(input.fields[0].submit == true)
    #expect(input.fields[0].target == .accessibilityIdentifier("field.email"))
}

@Test("UIInputInput: viewSnapshotID 放在顶层并适用于 identifier/path")
func inputInputAcceptsTopLevelViewSnapshotID() throws {
    let input = try UIInputInput.parse(from: [
        "viewSnapshotID": "view_snapshot_test",
        "fields": [
            [
                "accessibilityIdentifier": "field.email",
                "text": "x",
            ],
        ],
    ])

    #expect(input.viewSnapshotID == "view_snapshot_test")
    #expect(input.fields[0].target == .accessibilityIdentifier("field.email"))
}

@Test("UIInputInput: stopOnFailure=false 可继续后续字段")
func inputInputParsesStopOnFailureFalse() throws {
    let input = try UIInputInput.parse(from: [
        "stopOnFailure": false,
        "fields": [
            ["path": "root/0", "text": "x"],
            ["path": "root/1", "text": "y"],
        ],
    ])

    #expect(input.stopOnFailure == false)
    #expect(input.fields.count == 2)
}

@Test("UIInputInput: field 同时传 identifier 和 path 会被拒绝")
func inputInputRejectsAmbiguousFieldLocator() {
    #expect(throws: CommandInputParseError.self) {
        _ = try UIInputInput.parse(from: [
            "fields": [
                [
                    "accessibilityIdentifier": "field.email",
                    "path": "root/0",
                    "text": "x",
                ],
            ],
        ])
    }
}

@Test("UIInputInput: fields 超过上限会被拒绝")
func inputInputRejectsTooManyFields() {
    let fields = (0...UIInputInput.maxFields).map { index in
        JSONValue.object(JSON([
            "path": .string("root/\(index)"),
            "text": .string("x"),
        ]))
    }

    #expect(throws: CommandInputParseError.self) {
        _ = try UIInputInput.parse(from: ["fields": .array(fields)])
    }
}

@Test("UIInputInput schema 声明 fields 数组元素是对象")
func inputInputSchemaFieldsAndItems() throws {
    #expect(UIInputInput.inputSchema.fields.map(\.name) == [
        "fields",
        "viewSnapshotID",
        "stopOnFailure",
    ])

    let json = UIInputInput.inputSchema.toJSON()
    let properties = try #require(json["properties"]?.objectValue)
    let fieldsSchema = try #require(properties["fields"]?.objectValue)
    #expect(fieldsSchema["type"]?.stringValue == "array")
    #expect(fieldsSchema["minItems"]?.doubleValue == 1)
    #expect(fieldsSchema["maxItems"]?.doubleValue == Double(UIInputInput.maxFields))

    let itemSchema = try #require(fieldsSchema["items"]?.objectValue)
    #expect(itemSchema["type"]?.stringValue == "object")
    let itemProperties = try #require(itemSchema["properties"]?.objectValue)
    #expect(Set(itemProperties.storage.keys) == ["accessibilityIdentifier", "path", "text", "mode", "submit"])
    #expect(itemSchema["required"]?.arrayValue == [.string("text")])
    #expect(itemSchema["oneOf"]?.arrayValue?.count == 2)
}

// MARK: - UITextInputExecutor 派发

@Test("executor replace 写入中文与 emoji") @MainActor
func executorReplaceWritesChineseAndEmoji() throws {
    let context = UIKitTestHost.context { root in
        let field = UITextField()
        field.text = "old"
        field.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        root.addSubview(field)
    }

    let input = UIInputInput(fields: [
        UIInputField(target: .path([0]), text: "中文🎉", mode: .replace),
    ])
    let data = try UITextInputExecutor.execute(input: input, context: context)
    let result = try singleResult(from: data)

    #expect(data["completed"]?.boolValue == true)
    #expect(result["finalText"]?.stringValue == "中文🎉")
    #expect(result["type"]?.stringValue == "UITextField")
    #expect(result["code"]?.stringValue == "ok")
}

@Test("executor append 在旧文本后拼接") @MainActor
func executorAppendConcatenates() throws {
    let context = UIKitTestHost.context { root in
        let field = UITextField()
        field.text = "old"
        field.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        root.addSubview(field)
    }

    let input = UIInputInput(fields: [
        UIInputField(target: .path([0]), text: "X", mode: .append),
    ])
    let data = try UITextInputExecutor.execute(input: input, context: context)

    #expect(try singleResult(from: data)["finalText"]?.stringValue == "oldX")
}

@Test("executor 两个字段顺序输入成功") @MainActor
func executorWritesTwoFieldsInOrder() throws {
    let context = UIKitTestHost.context { root in
        let first = UITextField()
        first.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        root.addSubview(first)
        let second = UITextField()
        second.frame = CGRect(x: 10, y: 60, width: 200, height: 40)
        root.addSubview(second)
    }

    let input = UIInputInput(fields: [
        UIInputField(target: .path([0]), text: "A"),
        UIInputField(target: .path([1]), text: "B"),
    ])
    let data = try UITextInputExecutor.execute(input: input, context: context)
    let results = try resultObjects(from: data)

    #expect(data["completed"]?.boolValue == true)
    #expect(results.map { $0["finalText"]?.stringValue } == ["A", "B"])
}

@Test("executor 非 text 控件写入失败并按 stopOnFailure 停止") @MainActor
func executorRejectsLabelAndStops() throws {
    let context = UIKitTestHost.context { root in
        let label = UILabel()
        label.text = "hi"
        label.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        root.addSubview(label)
        let field = UITextField()
        field.frame = CGRect(x: 10, y: 60, width: 200, height: 40)
        root.addSubview(field)
    }

    let input = UIInputInput(fields: [
        UIInputField(target: .path([0]), text: "x"),
        UIInputField(target: .path([1]), text: "y"),
    ])
    let data = try UITextInputExecutor.execute(input: input, context: context)
    let results = try resultObjects(from: data)

    #expect(data["completed"]?.boolValue == false)
    #expect(data["failedIndex"]?.doubleValue == 0)
    #expect(results.count == 1)
    #expect(results[0]["code"]?.stringValue == "unsupported_text_input_type")
}

@Test("executor stopOnFailure=false 时失败后继续执行") @MainActor
func executorContinuesWhenStopOnFailureFalse() throws {
    let context = UIKitTestHost.context { root in
        let label = UILabel()
        label.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        root.addSubview(label)
        let field = UITextField()
        field.frame = CGRect(x: 10, y: 60, width: 200, height: 40)
        root.addSubview(field)
    }

    let input = UIInputInput(fields: [
        UIInputField(target: .path([0]), text: "x"),
        UIInputField(target: .path([1]), text: "y"),
    ], stopOnFailure: false)
    let data = try UITextInputExecutor.execute(input: input, context: context)
    let results = try resultObjects(from: data)

    #expect(data["completed"]?.boolValue == false)
    #expect(data["failedIndex"]?.doubleValue == 0)
    #expect(results.count == 2)
    #expect(results[0]["code"]?.stringValue == "unsupported_text_input_type")
    #expect(results[1]["code"]?.stringValue == "ok")
    #expect(results[1]["finalText"]?.stringValue == "y")
}

@Test("executor secure 字段只回 masked/length，不回原文") @MainActor
func executorSecureFieldMasksResponse() throws {
    let context = UIKitTestHost.context { root in
        let field = UITextField()
        field.text = ""
        field.isSecureTextEntry = true
        field.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        root.addSubview(field)
    }

    let secret = "p@ssw0rd"
    let input = UIInputInput(fields: [
        UIInputField(target: .path([0]), text: secret, mode: .replace),
    ])
    let data = try UITextInputExecutor.execute(input: input, context: context)
    let result = try singleResult(from: data)

    #expect(result["masked"]?.stringValue == String(repeating: "•", count: secret.count))
    #expect(result["length"]?.doubleValue == Double(secret.count))
    #expect(result["finalText"] == nil)
    let serialized = describe(data)
    #expect(serialized.contains(secret) == false)
}

@Test("executor 带 viewSnapshotID 且陈旧时返回 staleLocator 字段结果") @MainActor
func executorStaleViewSnapshotReturnsFieldFailure() throws {
    let context = UIKitTestHost.context { root in
        let field = UITextField()
        field.text = ""
        field.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        root.addSubview(field)
    }

    let input = UIInputInput(fields: [
        UIInputField(target: .path([0]), text: "x"),
    ], viewSnapshotID: "snap-nonexistent")
    let data = try UITextInputExecutor.execute(input: input, context: context)
    let result = try singleResult(from: data)

    #expect(data["completed"]?.boolValue == false)
    #expect(data["failedIndex"]?.doubleValue == 0)
    #expect(result["code"]?.stringValue == "stale_locator")
    #expect(result["message"]?.stringValue?.contains("view snapshot expired") == true)
}

@Test("executor identifier 定位带 viewSnapshotID 且陈旧时返回 staleLocator 字段结果") @MainActor
func executorIdentifierWithStaleViewSnapshotReturnsFieldFailure() throws {
    let context = UIKitTestHost.context { root in
        let field = UITextField()
        field.text = ""
        field.accessibilityIdentifier = "field.test"
        field.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        root.addSubview(field)
    }

    let input = UIInputInput(fields: [
        UIInputField(target: .accessibilityIdentifier("field.test"), text: "x"),
    ], viewSnapshotID: "snap-nonexistent")
    let data = try UITextInputExecutor.execute(input: input, context: context)
    let result = try singleResult(from: data)

    #expect(data["completed"]?.boolValue == false)
    #expect(result["code"]?.stringValue == "stale_locator")
}

@Test("F-03: executor 目标未找到返回 target_not_found（非 invalid_data）") @MainActor
func executorTargetNotFoundUsesTargetNotFoundCode() throws {
    let context = UIKitTestHost.context { root in
        let field = UITextField()
        field.text = ""
        field.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        root.addSubview(field)
    }

    let input = UIInputInput(fields: [
        UIInputField(target: .path([99]), text: "x"),
    ])
    let data = try UITextInputExecutor.execute(input: input, context: context)
    let result = try singleResult(from: data)

    #expect(result["code"]?.stringValue == "target_not_found")
    #expect(result["message"]?.stringValue?.contains("not found") == true)
    #expect(result["message"]?.stringValue?.contains("call ui.inspect first") == true)
    #expect(result["message"]?.stringValue?.contains("invalid_data") == false)
}

/// 取单字段结果对象。
private func singleResult(from data: JSON) throws -> JSON {
    let results = try resultObjects(from: data)
    return try #require(results.first)
}

/// 取批量结果对象数组。
private func resultObjects(from data: JSON) throws -> [JSON] {
    try #require(data["results"]?.arrayValue).map { value in
        try #require(value.objectValue)
    }
}

/// 把 JSON 序列化为字符串用于断言不含敏感原文。
private func describe(_ json: JSON) -> String {
    "\(json.storage)"
}
#endif
