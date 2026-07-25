#if canImport(UIKit)
import UIKit
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

/// `ui.alert.respond` inspector + executor 的 iOS 测试。
/// inspector 直接读 `UIAlertController.actions`，不依赖 present 转场（评审 M7），
/// 因此用构造好的 alert 对象稳定验证。
///
/// `ui.alert.respond` 移除 dryRun 后只负责「触发按钮」；查询 alert 结构（标题/按钮/输入框
/// 含 path/identifier）由 `ui.inspect` 的 alert 区块覆盖，见 `UIAlertInspectBlockTests`。

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

@Test("alert respond 按标题触发 UIAlertAction handler") @MainActor
func alertRespondPerformsButtonByTitle() throws {
    let alert = UIAlertController(title: "确认", message: nil, preferredStyle: .alert)
    var performedTitle: String?
    alert.addAction(UIAlertAction(title: "OK", style: .default) { action in
        performedTitle = action.title
    })
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    let context = UIKitContextProvider.Context(window: window,
                                               rootViewController: alert,
                                               topViewController: alert,
                                               rootView: alert.view)
    let input = UIAlertRespondInput(buttonTitle: "OK")
    let data = try UIAlertRespondExecutor.execute(input: input, context: context)
    #expect(performedTitle == "OK")
    #expect(data["performed"]?.boolValue == true)
    #expect(data["button"]?.objectValue?["title"]?.stringValue == "OK")
    #expect(data["button"]?.objectValue?["index"]?.doubleValue == 0)
    #expect(data["button"]?.objectValue?["role"]?.stringValue == "default")
    // 这里 alert 只被构造、未真正 present（无 presentingViewController、view 未挂 window），
    // dismissed 必须是 false。锁定「未 present 不谎报关闭」契约；真实 present 的 alert 走模拟器集成验证。
    #expect(data["dismissed"]?.boolValue == false)
}

@Test("alert respond 支持按下标和角色选择按钮") @MainActor
func alertRespondSelectsByIndexAndRole() throws {
    let alert = UIAlertController(title: "确认", message: nil, preferredStyle: .alert)
    var performed: [String] = []
    alert.addAction(UIAlertAction(title: "继续", style: .default) { _ in performed.append("default") })
    alert.addAction(UIAlertAction(title: "删除", style: .destructive) { _ in performed.append("destructive") })
    alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in performed.append("cancel") })
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    let context = UIKitContextProvider.Context(window: window,
                                               rootViewController: alert,
                                               topViewController: alert,
                                               rootView: alert.view)

    let byIndex = try UIAlertRespondExecutor.execute(input: UIAlertRespondInput(buttonIndex: 1),
                                                     context: context)
    #expect(performed == ["destructive"])
    #expect(byIndex["button"]?.objectValue?["title"]?.stringValue == "删除")

    let byRole = try UIAlertRespondExecutor.execute(input: UIAlertRespondInput(role: "cancel"),
                                                    context: context)
    #expect(performed == ["destructive", "cancel"])
    #expect(byRole["button"]?.objectValue?["title"]?.stringValue == "取消")
}

@Test("alert respond 多按钮未指定选择器时要求明确按钮") @MainActor
func alertRespondRequiresSelectorForMultipleButtons() {
    let alert = UIAlertController(title: "确认", message: nil, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    let context = UIKitContextProvider.Context(window: window,
                                               rootViewController: alert,
                                               topViewController: alert,
                                               rootView: alert.view)
    do {
        _ = try UIAlertRespondExecutor.execute(input: UIAlertRespondInput(), context: context)
        Issue.record("expected alertButtonRequired, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .alertButtonRequired)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("alert respond 找不到指定按钮时返回 alertButtonNotFound") @MainActor
func alertRespondReturnsNotFoundForMissingButton() {
    let alert = UIAlertController(title: "确认", message: nil, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    let context = UIKitContextProvider.Context(window: window,
                                               rootViewController: alert,
                                               topViewController: alert,
                                               rootView: alert.view)
    do {
        _ = try UIAlertRespondExecutor.execute(input: UIAlertRespondInput(buttonTitle: "不存在"),
                                               context: context)
        Issue.record("expected alertButtonNotFound, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .alertButtonNotFound)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("alert respond alertButtonRequired 表示需要明确按钮")
func alertRespondButtonRequiredExplainsSelectorRequirement() {
    let error = UIKitCommandError.alertButtonRequired(action: "ui.alert.respond")
    let message = error.failure.message.lowercased()
    let logMessage = error.failure.logMessage.lowercased()
    // message / logMessage 不能出现「已点击/已触发/已响应成功」这类肯定词，否则会误导 agent 以为已响应。
    for term in ["clicked", "tapped", "performed", "responded: true", "dismissed: true"] {
        #expect(!message.contains(term), "message 不应暗示已点击: \(term)")
        #expect(!logMessage.contains(term), "logMessage 不应暗示已点击: \(term)")
    }
    // message 必须明确告知需要提供按钮选择条件，不能让 agent 猜测默认按钮。
    #expect(message.contains("button"))
    #expect(message.contains("specify"))
}

/// 验证未 present 的 alert：dismissWaitMs 应该为 0。
@Test("alert respond 未 present 时 dismissWaitMs 为 0") @MainActor
func alertRespondDismissWaitMsIsZeroForUnpresentedAlert() throws {
    let alert = UIAlertController(title: "确认", message: nil, preferredStyle: .alert)
    var performedTitle: String?
    alert.addAction(UIAlertAction(title: "OK", style: .default) { action in
        performedTitle = action.title
    })
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    let context = UIKitContextProvider.Context(window: window,
                                               rootViewController: alert,
                                               topViewController: alert,
                                               rootView: alert.view)
    let input = UIAlertRespondInput(buttonTitle: "OK")
    let data = try UIAlertRespondExecutor.execute(input: input, context: context)
    #expect(performedTitle == "OK")
    #expect(data["performed"]?.boolValue == true)
    // 未 present — 不走 wait 路径
    #expect(data["dismissWaitMs"]?.doubleValue ?? -1 == 0)
}
#endif
