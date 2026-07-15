#if canImport(UIKit)
import UIKit
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

/// `ui.input` 的 schema 解析与执行核心测试。
///
/// schema 解析（Foundation-only typed query）与 executor 派发（locate → first responder
/// → insertText → 委托比对 → 密码脱敏）都在这里覆盖。通过 `UIKitTestHost` 注入可控 view
/// 树，真实驱动 `UITextInputExecutor.execute` 的全部成功/失败分支。
///
/// executor 已 throw 化：成功路径用 `try` 直取 JSON，失败路径用 do/catch 断言
/// `error.failure.code`。secure 路径额外断言响应不含原文。

// MARK: - UIInputInput schema 解析（Foundation-only typed query）

@Test("UIInputInput: text 必填；mode 默认 replace；submit 默认 true")
func inputInputParseDefaults() throws {
    let input = try UIInputInput.parse(from: ["path": "root/0", "text": "hi"])
    #expect(input.text == "hi")
    #expect(input.mode == .replace)
    #expect(input.submit == true)
    #expect(input.viewSnapshotID == nil)
}

@Test("UIInputInput: 缺 text 抛解析错误")
func inputInputRejectsMissingText() {
    #expect(throws: CommandInputParseError.self) {
        _ = try UIInputInput.parse(from: ["path": "root/0"])
    }
}

@Test("UIInputInput: append 模式与 submit=false 可显式传入")
func inputInputParsesAppendAndNoSubmit() throws {
    let input = try UIInputInput.parse(from: [
        "accessibilityIdentifier": "field.email",
        "text": "x",
        "mode": "append",
        "submit": false,
    ])
    #expect(input.mode == .append)
    #expect(input.submit == false)
    #expect(input.target == .accessibilityIdentifier("field.email"))
}

@Test("UIInputInput: viewSnapshotID 搭配 identifier 合法（与 ui.tap 一致）")
func inputInputAcceptsViewSnapshotIDWithIdentifier() throws {
    let input = try UIInputInput.parse(from: [
        "accessibilityIdentifier": "field.email",
        "text": "x",
        "viewSnapshotID": "view_snapshot_test",
    ])
    #expect(input.viewSnapshotID == "view_snapshot_test")
    #expect(input.target == .accessibilityIdentifier("field.email"))
}

@Test("UIInputInput schema 声明字段顺序与互斥约束")
func inputInputSchemaFieldsAndConstraints() {
    #expect(UIInputInput.inputSchema.fields.map(\.name) == [
        "accessibilityIdentifier",
        "path",
        "viewSnapshotID",
        "text",
        "mode",
        "submit",
    ])

    let json = UIInputInput.inputSchema.toJSON()
    guard case .array(let oneOf)? = json["oneOf"] else {
        Issue.record("oneOf not found")
        return
    }
    // exactlyOneOf(["accessibilityIdentifier", "path"]) 展开为每个字段一个 oneOf 条目。
    #expect(oneOf.count == 2)

    // P0-2 后 viewSnapshotID 校验迁移到 executor 内（identifier/path 都走 validateViewSnapshot），
    // schema 不再声明 viewSnapshotID-only-path 约束；x-iosExplore-constraints key 可能整体不存在，
    // 此时应视为符合（无旧约束），不应 Issue.record。
    let constraints = json["x-iosExplore-constraints"]?.arrayValue ?? []
    #expect(constraints.map(\.stringValue).contains("viewSnapshotID is valid only with path") == false)
}

// MARK: - UITextInputExecutor 派发
//
// 说明：executor 的 inputRejected 比对路径（finalText != expected）在纯 logic test 下难以
// 稳定触发——`UITextField`/`UITextView` 的程序化 `insertText`（UITextInput 协议）会直接写入
// 文本，委托（shouldChangeCharactersIn / shouldChangeTextIn）仅对真实键盘/输入会话生效，在
// logic test 中不被咨询。故 inputRejected 工厂与比对逻辑由 `UIKitCommandErrorTests` 在
// 工厂级覆盖（码/message/logMessage 契约），此处不再构造不可靠的委托 fixture。

@Test("executor replace 写入中文与 emoji") @MainActor
func executorReplaceWritesChineseAndEmoji() throws {
    let context = UIKitTestHost.context { root in
        let field = UITextField()
        field.text = "old"
        field.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        root.addSubview(field)
    }

    let input = UIInputInput(target: .path([0]), text: "中文🎉", mode: .replace)
    let data = try UITextInputExecutor.execute(input: input, context: context)

    #expect(data["finalText"]?.stringValue == "中文🎉")
    #expect(data["type"]?.stringValue == "UITextField")
}

@Test("executor append 在旧文本后拼接") @MainActor
func executorAppendConcatenates() throws {
    let context = UIKitTestHost.context { root in
        let field = UITextField()
        field.text = "old"
        field.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        root.addSubview(field)
    }

    let input = UIInputInput(target: .path([0]), text: "X", mode: .append)
    let data = try UITextInputExecutor.execute(input: input, context: context)

    #expect(data["finalText"]?.stringValue == "oldX")
}

@Test("executor 非 text 控件抛 unsupportedTextInputType") @MainActor
func executorRejectsLabel() {
    let context = UIKitTestHost.context { root in
        let label = UILabel()
        label.text = "hi"
        label.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        root.addSubview(label)
    }

    let input = UIInputInput(target: .path([0]), text: "x")
    do {
        _ = try UITextInputExecutor.execute(input: input, context: context)
        Issue.record("expected failure, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .unsupportedTextInputType)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
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
    let input = UIInputInput(target: .path([0]), text: secret, mode: .replace)
    let data = try UITextInputExecutor.execute(input: input, context: context)

    // 成功响应只含 type/masked/length，绝不回 finalText。
    #expect(data["masked"]?.stringValue == String(repeating: "•", count: secret.count))
    #expect(data["length"]?.doubleValue == Double(secret.count))
    #expect(data["finalText"] == nil)
    // 整个响应序列化后不得出现明文密码。
    let serialized = describe(data)
    #expect(serialized.contains(secret) == false)
}

@Test("executor 带 viewSnapshotID 且陈旧时抛 staleLocator") @MainActor
func executorStaleViewSnapshotThrows() {
    let context = UIKitTestHost.context { root in
        let field = UITextField()
        field.text = ""
        field.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        root.addSubview(field)
    }

    // 用一个 store 里不存在的 viewSnapshotID 触发 stale（unknown id → isStale 返回 true）。
    let input = UIInputInput(target: .path([0]), text: "x", viewSnapshotID: "snap-nonexistent")
    do {
        _ = try UITextInputExecutor.execute(input: input, context: context)
        Issue.record("expected failure, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .staleLocator)
        // 消息含 TTL 插值（UIKitSnapshotStore.ttlSeconds，当前 120s），用 contains 验证关键短语，
        // 避免 TTL 值调整时（如 10ca9a1 加 TTL、P1-6 调秒数）绑死全文。
        let staleMessage = error.failure.message
        #expect(staleMessage.contains("view snapshot expired"))
        #expect(staleMessage.contains("or target changed"))
        #expect(staleMessage.contains("call ui.inspect first"))
        #expect(error.failure.logMessage == "uikit locator stale action=ui.input viewSnapshot=snap-nonexistent")
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("executor identifier 定位带 viewSnapshotID 且陈旧时抛 staleLocator") @MainActor
func executorIdentifierWithStaleViewSnapshotThrows() {
    let context = UIKitTestHost.context { root in
        let field = UITextField()
        field.text = ""
        field.accessibilityIdentifier = "field.test"
        field.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        root.addSubview(field)
    }

    // 用一个 store 里不存在的 viewSnapshotID 触发 stale（unknown id → isStale 返回 true）。
    let input = UIInputInput(target: .accessibilityIdentifier("field.test"), text: "x", viewSnapshotID: "snap-nonexistent")
    do {
        _ = try UITextInputExecutor.execute(input: input, context: context)
        Issue.record("expected failure, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .staleLocator)
        // 消息含 TTL 插值（UIKitSnapshotStore.ttlSeconds，当前 120s），用 contains 验证关键短语，
        // 避免 TTL 值调整时（如 10ca9a1 加 TTL、P1-6 调秒数）绑死全文。
        let staleMessage = error.failure.message
        #expect(staleMessage.contains("view snapshot expired"))
        #expect(staleMessage.contains("or target changed"))
        #expect(staleMessage.contains("call ui.inspect first"))
        #expect(error.failure.logMessage == "uikit locator stale action=ui.input viewSnapshot=snap-nonexistent")
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("F-03: executor 目标未找到抛 target_not_found（非 invalid_data）") @MainActor
func executorTargetNotFoundUsesTargetNotFoundCode() {
    // 不存在的 path → UIKitLocatorResolver.locate 的 notFound 闭包应抛 target_not_found，
    // 不再是 invalid_data（旧码与 message "input target not_found" 自相矛盾，且是 6 个命令里唯一离群点）。
    let context = UIKitTestHost.context { root in
        let field = UITextField()
        field.text = ""
        field.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        root.addSubview(field)
    }

    let input = UIInputInput(target: .path([99]), text: "x")
    do {
        _ = try UITextInputExecutor.execute(input: input, context: context)
        Issue.record("expected failure, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .targetNotFound)
        // message 应含恢复指引（与 tap 同款），不再是旧 "input target not_found"。
        let message = error.failure.message
        #expect(message.contains("not found"))
        #expect(message.contains("call ui.inspect first"))
        #expect(message.contains("invalid_data") == false)
        // logMessage 应标注 action 和 target。
        #expect(error.failure.logMessage.contains("action=ui.input"))
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

/// 把 JSON 序列化为字符串用于断言不含敏感原文。
private func describe(_ json: JSON) -> String {
    "\(json.storage)"
}
#endif
