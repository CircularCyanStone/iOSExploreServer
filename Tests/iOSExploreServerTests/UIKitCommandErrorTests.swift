import Foundation
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

@Suite
struct UIKitCommandErrorTests {
    @Test("陈旧 locator 使用既有 invalid_data")
    func staleLocatorUsesExistingErrorCode() {
        let error = UIKitCommandError.staleLocator(action: "ui.tap", snapshotID: "s")
        #expect(error.result == .failure(code: .invalidData, message: "locator is stale; re-query"))
        #expect(error.failure.logMessage.contains("action=ui.tap"))
        #expect(error.failure.logMessage.contains("snapshot=s"))
    }

    @Test("UIKit 上下文不可用映射为 internal_error")
    func hierarchyUnavailableMapsToInternalError() {
        let error = UIKitCommandError.hierarchyUnavailable(action: "ui.tap", reason: "active window not found")
        #expect(error.result == .failure(code: .internalError, message: "UI hierarchy unavailable: active window not found"))
        #expect(error.failure.logMessage.contains("action=ui.tap"))
        #expect(error.failure.logMessage.contains("reason=active window not found"))
    }

    @Test("目标未找到使用 invalid_data")
    func targetNotFoundMapsToInvalidData() {
        let error = UIKitCommandError.targetNotFound(action: "ui.tap", targetDescription: "accessibilityIdentifier=home")
        #expect(error.result == .failure(code: .invalidData, message: "tap target not found"))
        #expect(error.failure.logMessage.contains("target=accessibilityIdentifier=home"))
    }

    @Test("目标歧义使用 invalid_data 并记录 count")
    func targetAmbiguousMapsToInvalidData() {
        let error = UIKitCommandError.targetAmbiguous(action: "ui.tap", targetDescription: "home", count: 3)
        #expect(error.result == .failure(code: .invalidData, message: "tap target is ambiguous"))
        #expect(error.failure.logMessage.contains("count=3"))
    }

    @Test("命中测试失败使用 invalid_data 并记录坐标")
    func hitTestFailedMapsToInvalidData() {
        let error = UIKitCommandError.hitTestFailed(action: "ui.tap", targetDescription: "root/0", x: 10, y: 20)
        #expect(error.result == .failure(code: .invalidData, message: "tap point did not hit any view"))
        #expect(error.failure.logMessage.contains("x=10.0"))
        #expect(error.failure.logMessage.contains("y=20.0"))
    }

    @Test("命中目标不一致使用 invalid_data")
    func hitMismatchMapsToInvalidData() {
        let error = UIKitCommandError.hitMismatch(action: "ui.tap", targetDescription: "root/0", hitType: "UILabel")
        #expect(error.result == .failure(code: .invalidData, message: "tap point hit a different view"))
        #expect(error.failure.logMessage.contains("hitType=UILabel"))
    }

    @Test("非 UIControl 目标使用 invalid_data")
    func unsupportedTargetMapsToInvalidData() {
        let error = UIKitCommandError.unsupportedTarget(action: "ui.tap", targetDescription: "root/0", type: "UILabel")
        #expect(error.result == .failure(code: .invalidData, message: "tap dispatch is only supported for UIControl in this version"))
        #expect(error.failure.logMessage.contains("type=UILabel"))
    }

    @Test("control 目标未找到使用 invalid_data")
    func controlTargetNotFoundMapsToInvalidData() {
        let error = UIKitCommandError.controlTargetNotFound(action: "ui.control.sendAction",
                                                             targetDescription: "accessibilityIdentifier=submit")
        #expect(error.result == .failure(code: .invalidData, message: "UIControl target not found"))
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
}
