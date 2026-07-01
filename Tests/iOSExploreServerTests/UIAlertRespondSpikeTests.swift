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
#endif
