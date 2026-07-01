#if canImport(UIKit)
import UIKit
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

/// `ui.keyboard.dismiss` 执行核心的 iOS 测试。
///
/// 通过 `UIKitTestHost` 注入可控 window，覆盖无 first responder 的 no-op 成功路径和
/// text field first responder 的收起路径。失败路径由错误工厂测试覆盖 code/message/logMessage。

@Test("没有 first responder 时返回 dismissed false") @MainActor
func dismissWithoutFirstResponderIsSuccessNoop() throws {
    let context = UIKitTestHost.context { _ in }
    let data = try UIKeyboardDismissExecutor.execute(input: UIKeyboardDismissInput(), context: context)
    #expect(data["dismissed"]?.boolValue == false)
}

@Test("auto 策略收起当前 first responder") @MainActor
func autoDismissesCurrentFirstResponder() throws {
    var field: UITextField!
    let context = UIKitTestHost.context { root in
        field = UITextField()
        field.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        root.addSubview(field)
    }
    #expect(field.becomeFirstResponder())
    let data = try UIKeyboardDismissExecutor.execute(input: UIKeyboardDismissInput(waitAfterMs: 0), context: context)
    #expect(data["dismissed"]?.boolValue == true)
    #expect(data["strategy"]?.stringValue == "auto")
    #expect(field.isFirstResponder == false)
}

@Test("resignFirstResponder 策略收起 first responder") @MainActor
func resignFirstResponderStrategyDismisses() throws {
    var field: UITextField!
    let context = UIKitTestHost.context { root in
        field = UITextField()
        field.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        root.addSubview(field)
    }
    #expect(field.becomeFirstResponder())
    let input = UIKeyboardDismissInput(strategy: .resignFirstResponder, waitAfterMs: 0)
    let data = try UIKeyboardDismissExecutor.execute(input: input, context: context)
    #expect(data["dismissed"]?.boolValue == true)
    #expect(data["strategy"]?.stringValue == "resignFirstResponder")
    #expect(field.isFirstResponder == false)
}

@Test("endEditing 策略收起 first responder") @MainActor
func endEditingStrategyDismisses() throws {
    var field: UITextField!
    let context = UIKitTestHost.context { root in
        field = UITextField()
        field.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        root.addSubview(field)
    }
    #expect(field.becomeFirstResponder())
    let input = UIKeyboardDismissInput(strategy: .endEditing, waitAfterMs: 0)
    let data = try UIKeyboardDismissExecutor.execute(input: input, context: context)
    #expect(data["dismissed"]?.boolValue == true)
    #expect(data["strategy"]?.stringValue == "endEditing")
    #expect(field.isFirstResponder == false)
}
#endif
