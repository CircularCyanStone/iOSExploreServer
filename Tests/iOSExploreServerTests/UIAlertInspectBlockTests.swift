#if canImport(UIKit)
import UIKit
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

/// `ui.inspect` 与 `ui.topViewHierarchy` 响应中的 `alert` 区块验证。
///
/// 该区块通过 `UIAlertInspector.summarizeForInspect` + 视图树 DFS 将 alert 按钮路径注入
/// 响应。测试覆盖无 alert、一/两/多按钮、相同标题、message-only 等场景。
@MainActor
private func alertContext(
    _ alert: UIAlertController
) -> UIKitContextProvider.Context {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    window.rootViewController = alert
    window.makeKeyAndVisible()
    window.layoutIfNeeded()
    // 需要触发 alert 的 viewDidLoad/layout，使 subviews 树初始化。
    _ = alert.view
    return UIKitContextProvider.Context(
        window: window,
        rootViewController: alert,
        topViewController: alert,
        rootView: alert.view
    )
}

@Test("inspectWithoutAlert 返回 available=false") @MainActor
func inspectWithoutAlertReturnsUnavailable() {
    let context = UIKitTestHost.context { _ in }

    let data = UIViewTargetsCollector.collect(query: .default, context: context)
    let alert = data["alert"]?.objectValue
    #expect(alert?["available"]?.boolValue == false)
}

@Test("inspectWithAlert 包含按钮列表与路径") @MainActor
func inspectWithAlertIncludesButtonsAndPaths() {
    let alert = UIAlertController(title: "确认", message: "是否继续", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "确认", style: .default))
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    let context = alertContext(alert)

    let data = UIViewTargetsCollector.collect(query: .default, context: context)
    let alertData = data["alert"]?.objectValue
    #expect(alertData?["available"]?.boolValue == true)
    #expect(alertData?["title"]?.stringValue == "确认")
    #expect(alertData?["message"]?.stringValue == "是否继续")

    let buttons = try? #require(alertData?["buttons"]?.arrayValue)
    #expect(buttons?.count == 2)

    let first = try? #require(buttons?[0].objectValue)
    #expect(first?["index"]?.doubleValue == 0)
    #expect(first?["title"]?.stringValue == "确认")
    #expect(first?["role"]?.stringValue == "default")
    #expect(first?["path"]?.stringValue != nil)
    // availableActions 包含 ui.alert.respond
    let actions = try? #require(first?["availableActions"]?.arrayValue)
    #expect(actions?.count == 1)
    #expect(actions?[0].stringValue == "ui.alert.respond")

    let second = try? #require(buttons?[1].objectValue)
    #expect(second?["index"]?.doubleValue == 1)
    #expect(second?["title"]?.stringValue == "取消")
    #expect(second?["role"]?.stringValue == "cancel")
    #expect(second?["path"]?.stringValue != nil)
}

@Test("alertButtonPath 在多次 inspect 间稳定") @MainActor
func alertButtonPathIsStableAcrossInspects() {
    let alert = UIAlertController(title: "确认", message: nil, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "确认", style: .default))
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    let context = alertContext(alert)

    let firstData = UIViewTargetsCollector.collect(query: .default, context: context)
    let secondData = UIViewTargetsCollector.collect(query: .default, context: context)

    let firstButtons = firstData["alert"]?.objectValue?["buttons"]?.arrayValue ?? []
    let secondButtons = secondData["alert"]?.objectValue?["buttons"]?.arrayValue ?? []

    let firstConfirmPath = firstButtons[0].objectValue?["path"]?.stringValue
    let secondConfirmPath = secondButtons[0].objectValue?["path"]?.stringValue
    #expect(firstConfirmPath != nil)
    #expect(firstConfirmPath == secondConfirmPath)
}

@Test("alertBlock 出现在 topViewHierarchy") @MainActor
func alertBlockAppearsInTopViewHierarchy() throws {
    let alert = UIAlertController(title: "确认", message: nil, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "确认", style: .default))
    let context = alertContext(alert)

    let data = UIViewHierarchyCollector.collectTopViewHierarchy(
        query: try UIViewHierarchyInput.parse(from: [:]),
        context: context
    )
    let alertData = data["alert"]?.objectValue
    #expect(alertData?["available"]?.boolValue == true)
    let buttons = alertData?["buttons"]?.arrayValue
    #expect(buttons?.count == 1)
}

@Test("duplicateButtonTitles 按 firstUnmatched 规则解析") @MainActor
func duplicateButtonTitlesResolveToFirstMatch() {
    let alert = UIAlertController(title: "选项", message: nil, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "选项", style: .default))
    alert.addAction(UIAlertAction(title: "选项", style: .cancel))
    let context = alertContext(alert)

    let data = UIViewTargetsCollector.collect(query: .default, context: context)
    let buttons = data["alert"]?.objectValue?["buttons"]?.arrayValue ?? []
    #expect(buttons.count == 2)

    let firstPath = buttons[0].objectValue?["path"]?.stringValue
    let secondPath = buttons[1].objectValue?["path"]?.stringValue
    #expect(firstPath != nil)
    #expect(secondPath != nil)
    #expect(firstPath != secondPath, "同标题按钮应解析到各自 _UIAlertControllerActionView，路径不同")
}

@Test("messageOnlyAlert 有 buttons 空数组") @MainActor
func messageOnlyAlertHasEmptyButtonsArray() {
    let alert = UIAlertController(title: "提示", message: "无按钮", preferredStyle: .alert)
    let context = alertContext(alert)

    let data = UIViewTargetsCollector.collect(query: .default, context: context)
    let alertData = data["alert"]?.objectValue
    #expect(alertData?["available"]?.boolValue == true)
    let buttons = alertData?["buttons"]?.arrayValue
    #expect(buttons?.isEmpty == true)
}
#endif
