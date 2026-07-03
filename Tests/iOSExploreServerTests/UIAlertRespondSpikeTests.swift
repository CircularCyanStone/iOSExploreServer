#if canImport(UIKit)
import UIKit
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

/// `ui.alert.respond` inspector + executor 的 iOS 测试。
/// inspector 直接读 `UIAlertController.actions`，不依赖 present 转场（评审 M7），
/// 因此用构造好的 alert 对象稳定验证。

@Test("alert inspector 列出 UIAlertController actions") @MainActor
func alertInspectorListsActions() throws {
    let alert = UIAlertController(title: "确认", message: "是否继续", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "继续", style: .default))
    let summary = UIAlertInspector.summarize(alert)
    #expect(summary.title == "确认")
    #expect(summary.message == "是否继续")
    #expect(summary.buttons.count == 2)
    #expect(summary.buttons[0].title == "取消")
    #expect(summary.buttons[0].role == .cancel)
    #expect(summary.buttons[1].title == "继续")
    #expect(summary.buttons[1].role == .default)
}

@Test("alert respond 无 alert 抛 alertUnavailable") @MainActor
func alertRespondUnavailableThrows() {
    let context = UIKitTestHost.context { _ in }
    let input = UIAlertRespondInput()
    do {
        _ = try UIAlertRespondExecutor.execute(input: input, context: context)
        Issue.record("expected failure, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .alertUnavailable)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("alert respond dryRun=true 返回 alert 信息") @MainActor
func alertRespondDryRunReturnsInfo() throws {
    let alert = UIAlertController(title: "确认", message: "继续?", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "继续", style: .default))
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    let context = UIKitContextProvider.Context(window: window,
                                               rootViewController: alert,
                                               topViewController: alert,
                                               rootView: alert.view)
    let input = UIAlertRespondInput()
    let data = try UIAlertRespondExecutor.execute(input: input, context: context)
    #expect(data["dryRun"]?.boolValue == true)
    #expect(data["title"]?.stringValue == "确认")
}

@Test("alert respond dryRun=false 抛 alertButtonRequired（点击未实现）") @MainActor
func alertRespondDryRunFalseThrowsButtonRequired() {
    let alert = UIAlertController(title: "确认", message: nil, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    let context = UIKitContextProvider.Context(window: window,
                                               rootViewController: alert,
                                               topViewController: alert,
                                               rootView: alert.view)
    let input = UIAlertRespondInput(dryRun: false, buttonTitle: "OK")
    do {
        _ = try UIAlertRespondExecutor.execute(input: input, context: context)
        Issue.record("expected failure, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .alertButtonRequired)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("alert respond dryRun=false 对任意 selector 都抛 alertButtonRequired") @MainActor
func alertRespondDryRunFalseRejectsAllSelectors() throws {
    let alert = UIAlertController(title: "确认", message: nil, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    let context = UIKitContextProvider.Context(window: window,
                                               rootViewController: alert,
                                               topViewController: alert,
                                               rootView: alert.view)
    // 当前版本点击未实现：无论用 buttonTitle / buttonIndex / role（或不传 selector），
    // 都稳定命中同一类错误，不进入选按钮逻辑。
    let inputs: [UIAlertRespondInput] = [
        UIAlertRespondInput(dryRun: false, buttonTitle: "OK"),
        UIAlertRespondInput(dryRun: false, buttonIndex: 0),
        UIAlertRespondInput(dryRun: false, role: "default"),
        UIAlertRespondInput(dryRun: false),
    ]
    for input in inputs {
        do {
            _ = try UIAlertRespondExecutor.execute(input: input, context: context)
            Issue.record("expected alertButtonRequired, got success for \(input)")
        } catch let error as UIKitCommandError {
            #expect(error.failure.code == .alertButtonRequired)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
}

@Test("alert respond alertButtonRequired 不暗示已点击或已关闭")
func alertRespondButtonRequiredDoesNotImplyClick() {
    let error = UIKitCommandError.alertButtonRequired(action: "ui.alert.respond")
    let message = error.failure.message.lowercased()
    let logMessage = error.failure.logMessage.lowercased()
    // message / logMessage 不能出现「已点击/已触发/已响应成功」这类肯定词，否则会误导 agent 以为已响应。
    for term in ["clicked", "tapped", "performed", "responded: true", "dismissed: true"] {
        #expect(!message.contains(term), "message 不应暗示已点击: \(term)")
        #expect(!logMessage.contains(term), "logMessage 不应暗示已点击: \(term)")
    }
    // message 必须明确告知当前 query-only 且无法关闭 alert，并指引下一步（宿主/后续版本）。
    #expect(message.contains("query-only"))
    #expect(message.contains("cannot dismiss"))
}

@Test("alert respond 暴露输入框 placeholder 与 secure 标记") @MainActor
func alertRespondExposesTextFields() throws {
    let alert = UIAlertController(title: "登录", message: nil, preferredStyle: .alert)
    alert.addTextField { tf in tf.placeholder = "用户名" }
    alert.addTextField { tf in
        tf.placeholder = "密码"
        tf.isSecureTextEntry = true
    }
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    let context = UIKitContextProvider.Context(window: window,
                                               rootViewController: alert,
                                               topViewController: alert,
                                               rootView: alert.view)
    let input = UIAlertRespondInput()
    let data = try UIAlertRespondExecutor.execute(input: input, context: context)
    // 输入型 alert 必须暴露 textFields，让 agent 识别「需先填输入框」；原文不回（防泄露密码）。
    let textFields = try #require(data["textFields"]?.arrayValue)
    #expect(textFields.count == 2)
    #expect(textFields[0].objectValue?["placeholder"]?.stringValue == "用户名")
    #expect(textFields[0].objectValue?["isSecure"]?.boolValue == false)
    #expect(textFields[1].objectValue?["placeholder"]?.stringValue == "密码")
    #expect(textFields[1].objectValue?["isSecure"]?.boolValue == true)
}
#endif
