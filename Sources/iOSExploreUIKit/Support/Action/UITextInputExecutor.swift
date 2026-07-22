#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.input` 的执行核心。
///
/// 在 `MainActor` 上按顺序完成批量字段输入。每个字段独立经历：定位 → 陈旧校验 → 文本控件白名单
/// → 成为 first responder → （replace 模式先清空）`insertText` → 比对实际文本 → 可选
/// resignFirstResponder。单条字段失败不会回滚已成功字段；调用方可通过 `stopOnFailure` 决定是否继续。
///
/// 设计要点（codex 审过）：
/// - **responder 与 textInput 分离**：`UIResponder` 提供 `becomeFirstResponder` /
///   `isFirstResponder` / `resignFirstResponder` / `selectAll(_:)`，而 `UITextInput` 协议
///   只有 `insertText` / `deleteBackward` / `selectedTextRange`。两类方法分别通过对应类型调用。
/// - **selectAll 按具体类型**：`selectAll(_:)` 是 `UIResponder` 方法但只有具体文本控件
///   实现了"全选当前文本"语义，故按 `UITextField` / `UITextView` 分别调用。
/// - **append expected = 旧文本 + field.text**：append 模式下最终文本必然包含旧内容，
///   比对期望须含旧文本，否则会误判为 `inputRejected`。
/// - **secure 脱敏**：`isSecureTextEntry` 为 true 时，所有响应（含失败响应）只回长度和 masked
///   值，绝不回原文或期望文本。
@MainActor
enum UITextInputExecutor {
    /// 执行一次批量文本注入。
    ///
    /// - Parameters:
    ///   - input: 已通过 typed schema 校验的 input 参数。
    ///   - context: 由调用方在 MainActor 上取好的查询上下文（持有真实 window / rootView）。
    /// - Returns: 成功时返回 `completed`、`results`，失败时额外返回 `failedIndex`。
    /// - Throws: `UIKitCommandError`——仅在执行器内部出现无法转为逐项结果的异常时抛出。
    static func execute(input: UIInputInput, context: UIKitContextProvider.Context) throws -> JSON {
        let action = InputCommand.actionName

        var results: [JSONValue] = []
        var failedIndex: Int?
        for (index, field) in input.fields.enumerated() {
            UIKitCommandLogging.info("command", "command \(action) field[\(index)] start target=\(field.target.logSummary) mode=\(field.mode.rawValue) submit=\(field.submit) textLen=\(field.text.count)")
            do {
                let data = try execute(field: field, viewSnapshotID: input.viewSnapshotID, context: context)
                var payload = data.storage
                payload["index"] = .double(Double(index))
                payload["completed"] = .bool(true)
                payload["code"] = .string("ok")
                payload["target"] = .string(field.target.logSummary)
                results.append(.object(JSON(payload)))
                UIKitCommandLogging.info("command", "command \(action) field[\(index)] completed target=\(field.target.logSummary)")
            } catch let error as UIKitCommandError {
                if failedIndex == nil {
                    failedIndex = index
                }
                var payload: JSON = [
                    "index": .double(Double(index)),
                    "completed": .bool(false),
                    "code": .string(error.failure.code.rawValue),
                    "message": .string(error.failure.message),
                    "target": .string(field.target.logSummary)
                ]
                if let data = error.failure.data {
                    payload["data"] = .object(data)
                }
                results.append(.object(payload))
                UIKitCommandLogging.error("command", "command \(action) field[\(index)] failed code=\(error.failure.code.rawValue) target=\(field.target.logSummary)")
                if input.stopOnFailure {
                    break
                }
            }
        }

        var response: JSON = [
            "completed": .bool(failedIndex == nil),
            "results": .array(results),
        ]
        if let failedIndex {
            response["failedIndex"] = .double(Double(failedIndex))
        }
        return response
    }

    /// 执行单个字段输入。
    ///
    /// - Parameters:
    ///   - field: 已解析的单字段输入。
    ///   - viewSnapshotID: 顶层批量输入携带的快照标识。
    ///   - context: 当前 UIKit 查询上下文。
    /// - Returns: 单字段成功结果 JSON。
    /// - Throws: `UIKitCommandError`——定位失败、陈旧、非文本控件、first responder 失败或委托拒绝。
    private static func execute(field: UIInputField,
                                viewSnapshotID: String?,
                                context: UIKitContextProvider.Context) throws -> JSON {
        let action = InputCommand.actionName

        // 1. 定位。notFound 用 target_not_found（与 tap/control/scroll/scrollToElement/swipe/
        // longPress 同款 code + 恢复指引），不再用 invalid_data。ambiguous 保持 invalid_data。
        let located = try UIKitLocatorResolver.locate(
            locator: field.target.locator,
            in: context.rootView,
            notFound: { UIKitCommandError.targetNotFound(
                action: action,
                message: "input target not found — the page view tree may have changed; call ui.inspect first, then retry with a fresh target",
                logMessage: "ui input target not found action=\(action) target=\(field.target.logSummary)") },
            ambiguous: { n in UIKitCommandError.invalidData(action: action, message: "input target ambiguous count=\(n)") }
        )

        // 2. 陈旧校验。identifier / path 都按 located view 的 pathString 比对指纹，与 ui.tap 对齐。
        if let viewSnapshotID {
            try UIKitActionExecutor.validateViewSnapshot(
                located: located,
                viewSnapshotID: viewSnapshotID,
                context: context,
                action: action
            )
        }

        // 3. 白名单：只接受 UITextField / UITextView / UISearchTextField。
        let view = located.view
        guard (view is UITextField) || (view is UITextView) || (view is UISearchTextField) else {
            throw UIKitCommandError.unsupportedTextInputType(action: action, type: String(describing: type(of: view)))
        }

        let responder = view as! UIResponder
        let textInput = view as! UITextInput
        let oldText = (view as? UITextField)?.text ?? (view as? UITextView)?.text ?? ""

        // 4. 成为 first responder；失败立即抛错。
        guard responder.becomeFirstResponder() else {
            throw UIKitCommandError.becomeFirstResponderFailed(action: action, target: field.target.logSummary)
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        guard responder.isFirstResponder, textInput.selectedTextRange != nil else {
            throw UIKitCommandError.becomeFirstResponderFailed(action: action, target: field.target.logSummary)
        }

        // 5. replace 模式先清空原内容：selectAll(_:) 按具体控件调用，再 deleteBackward。
        if field.mode == .replace {
            if let fieldView = view as? UITextField {
                fieldView.selectAll(nil)
            } else if let textView = view as? UITextView {
                textView.selectAll(nil)
            }
            textInput.deleteBackward()
        }

        // 6. 注入文本。
        // 设计特性 F-27（勿当 bug 重提）: ui.input 的文本经 UIKit `insertText` 字面量写入
        // UITextField/UITextView。不做转义、不求值、不做注入防护；宿主若把文本拼进 SQL /
        // HTML / Shell / 模板，必须自行参数化或转义。
        textInput.insertText(field.text)

        // 7. 读取最终文本并比对（append 期望含旧文本）。
        let finalText = (view as? UITextField)?.text ?? (view as? UITextView)?.text ?? ""
        let expected = (field.mode == .append) ? oldText + field.text : field.text
        let secure = (view as? UITextField)?.isSecureTextEntry ?? false
        if finalText != expected {
            throw UIKitCommandError.inputRejected(action: action,
                                                  expectedLen: expected.count,
                                                  finalLen: finalText.count,
                                                  secure: secure,
                                                  singleLineField: view is UITextField)
        }

        // 8. 可选 resignFirstResponder。
        if field.submit {
            responder.resignFirstResponder()
        }

        UIKitCommandLogging.info("command", "ui input completed type=\(String(describing: type(of: view))) mode=\(field.mode.rawValue) finalLen=\(finalText.count) secure=\(secure)")

        let masked = String(repeating: "•", count: finalText.count)
        if secure {
            return [
                "type": .string(String(describing: type(of: view))),
                "masked": .string(masked),
                "length": .double(Double(finalText.count)),
                "textLength": .double(Double(finalText.count)),
                "maskedText": .string(masked),
            ]
        }
        return [
            "type": .string(String(describing: type(of: view))),
            "finalText": .string(finalText),
            "textLength": .double(Double(finalText.count)),
            "maskedText": .string(masked),
        ]
    }
}
#endif
