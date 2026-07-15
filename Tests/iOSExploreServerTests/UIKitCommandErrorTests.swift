import Foundation
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

@Suite
struct UIKitCommandErrorTests {
    @Test("staleLocator 使用 stale_locator code")
    func staleLocatorUsesDedicatedCode() {
        let error = UIKitCommandError.staleLocator(action: "ui.tap", viewSnapshotID: "snap-1")
        #expect(error.failure.code == .staleLocator)
        #expect(error.failure.message.contains("ui.inspect"))
        #expect(error.failure.logMessage.contains("action=ui.tap"))
        #expect(error.failure.logMessage.contains("viewSnapshot=snap-1"))
    }

    @Test("F-24: staleLocator message 提示 snapshot 不跟踪文本变化")
    func staleLocatorMessageWarnsAboutTextTracking() {
        let error = UIKitCommandError.staleLocator(action: "ui.tap", viewSnapshotID: "snap-1")
        // message 应含文本追踪限制提示，让 agent 知晓异步文本变化不触发 stale。
        #expect(error.failure.message.contains("do not track label/text content changes"))
        #expect(error.failure.message.contains("re-inspect"))
    }

    @Test("notActionable 工厂生成 not_actionable 业务码并引导 ui.inspect")
    func notActionableMapsToCode() {
        let error = UIKitCommandError.notActionable(action: "ui.tap", path: "root/5/0")
        #expect(error.failure.code == .notActionable)
        #expect(error.failure.message.contains("ui.inspect"))
        #expect(error.failure.message.contains("root/5/0"))
        #expect(error.failure.logMessage.contains("action=ui.tap"))
        #expect(error.failure.logMessage.contains("path=root/5/0"))
    }

    @Test("agent common command error code raw values")
    func agentCommonCommandErrorCodes() {
        #expect(ExploreError.waitTimeout.rawValue == "wait_timeout")
        #expect(ExploreError.navigationBackUnavailable.rawValue == "navigation_back_unavailable")
        #expect(ExploreError.alertUnavailable.rawValue == "alert_unavailable")
        #expect(ExploreError.alertButtonNotFound.rawValue == "alert_button_not_found")
        #expect(ExploreError.alertButtonRequired.rawValue == "alert_button_required")
        #expect(ExploreError.keyboardDismissFailed.rawValue == "keyboard_dismiss_failed")
        #expect(ExploreError.targetNotFound.rawValue == "target_not_found")
    }

    @Test("UIKit 上下文不可用映射为 internal_error")
    func hierarchyUnavailableMapsToInternalError() {
        let error = UIKitCommandError.hierarchyUnavailable(action: "ui.tap", reason: "active window not found")
        #expect(error.result == .failure(code: .internalError, message: "UI hierarchy unavailable: active window not found"))
        #expect(error.failure.logMessage.contains("action=ui.tap"))
        #expect(error.failure.logMessage.contains("reason=active window not found"))
    }

    @Test("目标未找到使用 target_not_found")
    func targetNotFoundMapsToDedicatedCode() {
        let error = UIKitCommandError.targetNotFound(action: "ui.tap", targetDescription: "accessibilityIdentifier=home")
        #expect(error.result == .failure(code: .targetNotFound, message: "tap target not found — the page view tree may have changed; call ui.inspect first, then retry with a fresh target"))
        #expect(error.failure.logMessage.contains("target=accessibilityIdentifier=home"))
    }

    @Test("目标歧义使用 invalid_data 并记录 count")
    func targetAmbiguousMapsToInvalidData() {
        let error = UIKitCommandError.targetAmbiguous(action: "ui.tap", targetDescription: "home", count: 3)
        #expect(error.result == .failure(code: .invalidData, message: "tap target is ambiguous"))
        #expect(error.failure.logMessage.contains("count=3"))
    }

    @Test("无默认激活路由目标使用 unsupported_target")
    func unsupportedTargetMapsToUnsupportedTarget() {
        let error = UIKitCommandError.unsupportedTarget(action: "ui.tap", targetDescription: "root/0", type: "UILabel")
        #expect(error.result == .failure(code: .unsupportedTarget, message: "target has no default activation route (UIButton / UISwitch / text input only)"))
        #expect(error.failure.logMessage.contains("type=UILabel"))
    }

    @Test("unsupportedTarget 支持按命令定制 message（swipe/longPress 不再用 tap 文案）")
    func unsupportedTargetAcceptsCustomMessage() {
        // tap 不传 message：保持默认文案（回归保护，不能因加参数破坏 ui.tap 行为）
        let tapError = UIKitCommandError.unsupportedTarget(action: "ui.tap", targetDescription: "root/0", type: "UILabel")
        #expect(tapError.failure.message == "target has no default activation route (UIButton / UISwitch / text input only)")

        // swipe 传专用 message，不应再提到 UIButton/UISwitch/text input
        let swipeError = UIKitCommandError.unsupportedTarget(
            action: "ui.swipe", targetDescription: "root/1", type: "UILabel",
            message: "no matching swipe gesture recognizer found on target")
        #expect(swipeError.failure.code == .unsupportedTarget)
        #expect(swipeError.failure.message == "no matching swipe gesture recognizer found on target")
        #expect(swipeError.failure.message.contains("UIButton") == false)
        #expect(swipeError.failure.logMessage.contains("action=ui.swipe"))

        // longPress 传专用 message
        let longPressError = UIKitCommandError.unsupportedTarget(
            action: "ui.longPress", targetDescription: "root/2", type: "UILabel",
            message: "no UILongPressGestureRecognizer found on target")
        #expect(longPressError.failure.message == "no UILongPressGestureRecognizer found on target")
        #expect(longPressError.failure.message.contains("UISwitch") == false)
    }

    @Test("control 目标未找到使用 target_not_found")
    func controlTargetNotFoundMapsToDedicatedCode() {
        let error = UIKitCommandError.controlTargetNotFound(action: "ui.control.sendAction",
                                                             targetDescription: "accessibilityIdentifier=submit")
        #expect(error.result == .failure(code: .targetNotFound, message: "UIControl target not found"))
    }

    @Test("control 目标歧义使用 invalid_data")
    func controlTargetAmbiguousMapsToInvalidData() {
        let error = UIKitCommandError.controlTargetAmbiguous(action: "ui.control.sendAction",
                                                              targetDescription: "submit",
                                                              count: 2)
        #expect(error.result == .failure(code: .invalidData, message: "UIControl target is ambiguous"))
    }

    @Test("control 目标非 UIControl 使用 invalid_data")
    func controlTargetNotControlMapsToInvalidData() {
        let error = UIKitCommandError.controlTargetNotControl(action: "ui.control.sendAction",
                                                               targetDescription: "root/0",
                                                               type: "UILabel")
        #expect(error.result == .failure(code: .invalidData, message: "target view is not UIControl"))
    }

    @Test("UIKitCommandError 可作为 Error 抛出与捕获")
    func errorIsThrowableAndCatchable() {
        #expect(throws: UIKitCommandError.self) {
            throw UIKitCommandError.targetNotFound(action: "ui.tap", targetDescription: "root/0")
        }
    }

    @Test("ui.input 非文本控件映射为 unsupported_text_input_type")
    func unsupportedTextInputTypeMapsToCode() {
        let error = UIKitCommandError.unsupportedTextInputType(action: "ui.input", type: "UILabel")
        #expect(error.result == .failure(code: .unsupportedTextInputType,
                                        message: "target is not a supported text input"))
        #expect(error.failure.logMessage.contains("action=ui.input"))
        #expect(error.failure.logMessage.contains("type=UILabel"))
    }

    @Test("ui.input first responder 失败映射为 become_first_responder_failed")
    func becomeFirstResponderFailedMapsToCode() {
        let error = UIKitCommandError.becomeFirstResponderFailed(action: "ui.input", target: "path=root/0")
        #expect(error.result == .failure(code: .becomeFirstResponderFailed,
                                        message: "failed to become first responder"))
        #expect(error.failure.logMessage.contains("target=path=root/0"))
    }

    @Test("ui.input 委托拒绝映射为 input_rejected 且不回原文")
    func inputRejectedMapsToCodeWithoutPlaintext() {
        let error = UIKitCommandError.inputRejected(action: "ui.input", expectedLen: 8, finalLen: 0, secure: true)
        #expect(error.result == .failure(code: .inputRejected,
                                        message: "text input was rejected or altered by delegate"))
        // message 与 logMessage 都不得含期望长度之外的明文输入；只回长度与 secure 标记。
        let log = error.failure.logMessage
        #expect(log.contains("expectedLen=8"))
        #expect(log.contains("finalLen=0"))
        #expect(log.contains("secure=true"))
    }

    @Test("F-23: inputRejected 对 UITextField 且 finalLen<expectedLen 追加换行符提示")
    func inputRejectedSingleLineFieldAppendsNewlineHint() {
        // 模拟向 UITextField 输入含 \n 的文本被 UIKit 截断：expectedLen > finalLen。
        let error = UIKitCommandError.inputRejected(action: "ui.input",
                                                     expectedLen: 12,
                                                     finalLen: 5,
                                                     secure: false,
                                                     singleLineField: true)
        #expect(error.failure.code == .inputRejected)
        // message 应追加换行符/控制字符拒绝提示和 UITextView 建议。
        let message = error.failure.message
        #expect(message.contains("rejected or altered by delegate"))
        #expect(message.contains("UITextField"))
        #expect(message.contains("UITextView"))
        #expect(message.contains("multiline"))
        // logMessage 应记录 singleLineField 标记。
        #expect(error.failure.logMessage.contains("singleLineField=true"))
        // message 仍不含明文输入。
        #expect(message.contains("invalid_data") == false)
    }

    @Test("F-23: inputRejected 对 UITextView（非单行）不追加换行符提示")
    func inputRejectedMultilineFieldDoesNotAppendHint() {
        // UITextView 接受换行，不应追加 UITextField 特有的提示。
        let error = UIKitCommandError.inputRejected(action: "ui.input",
                                                     expectedLen: 12,
                                                     finalLen: 5,
                                                     secure: false,
                                                     singleLineField: false)
        let message = error.failure.message
        // 只有基础 message，无换行符提示。
        #expect(message == "text input was rejected or altered by delegate")
        #expect(error.failure.logMessage.contains("singleLineField=false"))
    }

    @Test("F-23: inputRejected 对 UITextField 但 finalLen==expectedLen 不追加提示")
    func inputRejectedSingleLineFieldEqualLengthDoesNotAppendHint() {
        // finalLen == expectedLen 时差异不是长度截断（可能是字符替换），不追加换行符提示。
        let error = UIKitCommandError.inputRejected(action: "ui.input",
                                                     expectedLen: 5,
                                                     finalLen: 5,
                                                     secure: false,
                                                     singleLineField: true)
        let message = error.failure.message
        #expect(message == "text input was rejected or altered by delegate")
    }
}
