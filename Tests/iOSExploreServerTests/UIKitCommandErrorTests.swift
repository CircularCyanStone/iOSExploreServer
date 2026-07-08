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
        #expect(error.result == .failure(code: .targetNotFound, message: "tap target not found"))
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
}
