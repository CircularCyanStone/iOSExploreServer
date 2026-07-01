#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.input` 的执行核心。
///
/// 在 `MainActor` 上完成：定位 → 陈旧校验 → 文本控件白名单 → 成为 first responder
/// → （replace 模式先清空）`insertText` → 比对实际文本 → 可选 resignFirstResponder。
/// 成功返回纯 `JSON`，失败 `throw UIKitCommandError`，由命令 handler 顶层 catch 转
/// `ExploreResult` envelope（业务码不丢），失败日志在 handler 顶层一处记。
///
/// 设计要点（codex 审过）：
/// - **responder 与 textInput 分离**：`UIResponder` 提供 `becomeFirstResponder` /
///   `isFirstResponder` / `resignFirstResponder` / `selectAll(_:)`，而 `UITextInput` 协议
///   只有 `insertText` / `deleteBackward` / `selectedTextRange`。两类方法分别通过对应类型
///   调用，不能混到一个协议引用上。
/// - **selectAll 按具体类型**：`selectAll(_:)` 是 `UIResponder` 方法但只有具体文本控件
///   实现了"全选当前文本"语义，故按 `UITextField` / `UITextView` 分别调用。
/// - **append expected = 旧文本 + input.text**：append 模式下最终文本必然包含旧内容，
///   比对期望须含旧文本，否则会误判为 `inputRejected`。
/// - **secure 脱敏**：`isSecureTextEntry` 为 true 时，所有响应（含 `inputRejected` 失败
///   响应）只回 `{masked, length}`，绝不回原文或期望文本。
@MainActor
enum UITextInputExecutor {
    /// 执行一次文本注入。
    ///
    /// - Parameters:
    ///   - input: 已通过 typed schema 校验的 input 参数。
    ///   - context: 由调用方在 MainActor 上取好的查询上下文（持有真实 window / rootView）。
    /// - Returns: 成功时返回 `type` 与 `finalText`（secure 时返回 `masked` + `length`）。
    /// - Throws: `UIKitCommandError`——定位失败 / 陈旧 / 非文本控件 / first responder 失败 / 委托拒绝。
    static func execute(input: UIInputInput, context: UIKitContextProvider.Context) throws -> JSON {
        let action = InputCommand.actionName

        // 1. 定位（真实签名：ambiguous 单参闭包）。
        let located = try UIKitLocatorResolver.locate(
            locator: input.target.locator,
            in: context.rootView,
            notFound: { UIKitCommandError.invalidData(action: action, message: "input target not found") },
            ambiguous: { n in UIKitCommandError.invalidData(action: action, message: "input target ambiguous count=\(n)") }
        )

        // 2. 陈旧校验：仅 path 定位 + 带 snapshotID 时执行。
        if let snapshotID = input.snapshotID, case .path = input.target {
            let cur = UIKitFingerprintCollector.fingerprint(
                for: located.view,
                path: located.pathString,
                rootView: context.rootView,
                digest: UIKitFingerprintCollector.digest(topViewController: context.topViewController)
            )
            let snapCtx = UIKitFingerprintCollector.context(
                window: context.window,
                topViewController: context.topViewController
            )
            if UIKitSnapshotStore.shared.isStale(snapshotID: snapshotID,
                                                 path: located.pathString,
                                                 context: snapCtx,
                                                 current: cur) {
                throw UIKitCommandError.staleLocator(action: action, snapshotID: snapshotID)
            }
        }

        // 3. 白名单：只接受 UITextField / UITextView / UISearchTextField。
        let view = located.view
        guard (view is UITextField) || (view is UITextView) || (view is UISearchTextField) else {
            throw UIKitCommandError.unsupportedTextInputType(action: action, type: String(describing: type(of: view)))
        }

        // responder（焦点/选区控制）与 textInput（文本写入）分离引用。
        // 注：UISearchTextField 是 UITextField 子类，下方 UITextField 分支会覆盖它。
        let responder = view as! UIResponder
        let textInput = view as! UITextInput

        // 4. 记录旧文本：append 模式的期望值 = 旧文本 + 输入文本。
        let oldText = (view as? UITextField)?.text ?? (view as? UITextView)?.text ?? ""

        // 5. 成为 first responder；失败立即抛错。
        guard responder.becomeFirstResponder() else {
            throw UIKitCommandError.becomeFirstResponderFailed(action: action, target: input.target.logSummary)
        }
        // 等一帧，让 first responder / selectedTextRange 在没有真实事件循环时也生效。
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        guard responder.isFirstResponder, textInput.selectedTextRange != nil else {
            throw UIKitCommandError.becomeFirstResponderFailed(action: action, target: input.target.logSummary)
        }

        // 6. replace 模式先清空原内容：selectAll(_:) 按具体控件调用，再 deleteBackward。
        if input.mode == .replace {
            if let field = view as? UITextField {
                field.selectAll(nil)
            } else if let textView = view as? UITextView {
                textView.selectAll(nil)
            }
            textInput.deleteBackward()
        }

        // 7. 注入文本。
        textInput.insertText(input.text)

        // 8. 读取最终文本并比对（append 期望含旧文本）。
        let finalText = (view as? UITextField)?.text ?? (view as? UITextView)?.text ?? ""
        let expected = (input.mode == .append) ? oldText + input.text : input.text
        let secure = (view as? UITextField)?.isSecureTextEntry ?? false
        if finalText != expected {
            throw UIKitCommandError.inputRejected(action: action,
                                                  expectedLen: expected.count,
                                                  finalLen: finalText.count,
                                                  secure: secure)
        }

        // 9. 可选 resignFirstResponder。
        if input.submit {
            responder.resignFirstResponder()
        }

        UIKitCommandLogging.info("command", "ui input completed type=\(String(describing: type(of: view))) mode=\(input.mode.rawValue) finalLen=\(finalText.count) secure=\(secure)")

        // 10. 响应：secure 时只回 masked + length，绝不回原文。
        if secure {
            return [
                "type": .string(String(describing: type(of: view))),
                "masked": .string(String(repeating: "•", count: finalText.count)),
                "length": .double(Double(finalText.count)),
            ]
        }
        return [
            "type": .string(String(describing: type(of: view))),
            "finalText": .string(finalText),
        ]
    }
}
#endif
