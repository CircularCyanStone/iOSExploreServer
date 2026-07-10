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

/// 把 `alert.textFields` 的 UITextField 手工加入 alert.view 子树。
///
/// UIAlertController 在非 present 的测试环境（rootViewController=alert）只创建 textField
/// 对象并存入 `alert.textFields` 数组，但**不**把它们 addSubview 到视图树——textField 容器
/// 需要完整 present 流程才入树（实测 alert.view 子树 28 个 view 但 0 个 UITextField）。
/// button 的 `_UIAlertControllerActionView` 在 viewDidLoad 就入树，故 button 测试无需此处理。
/// 这里手工建立 textField 的视图位置驱动 resolver 解析；真实 present 场景由 SPMExample
/// 闭环覆盖（见 N3 任务）。
@MainActor
private func embedAlertTextFields(_ alert: UIAlertController) {
    guard let textFields = alert.textFields, !textFields.isEmpty else { return }
    let container = UIView()
    for textField in textFields { container.addSubview(textField) }
    alert.view.addSubview(container)
}

@Test("inspectWithoutAlert 返回 available=false") @MainActor
func inspectWithoutAlertReturnsUnavailable() {
    let context = UIKitTestHost.context { _ in }

    let data = UIInspectCollector.collect(query: .default, context: context)
    let alert = data["alert"]?.objectValue
    #expect(alert?["available"]?.boolValue == false)
}

@Test("inspectWithAlert 包含按钮列表") @MainActor
func inspectWithAlertIncludesButtons() {
    let alert = UIAlertController(title: "确认", message: "是否继续", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "确认", style: .default))
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    let context = alertContext(alert)

    let data = UIInspectCollector.collect(query: .default, context: context)
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
    // availableActions 含 ui.alert.respond（button 不带 path——用 index/title/role 调 respond）
    let actions = try? #require(first?["availableActions"]?.arrayValue)
    #expect(actions?.count == 1)
    #expect(actions?[0].stringValue == "ui.alert.respond")

    let second = try? #require(buttons?[1].objectValue)
    #expect(second?["index"]?.doubleValue == 1)
    #expect(second?["title"]?.stringValue == "取消")
    #expect(second?["role"]?.stringValue == "cancel")
}

@Test("alertBlock 出现在 topViewHierarchy") @MainActor
func alertBlockAppearsInTopViewHierarchy() throws {
    let alert = UIAlertController(title: "确认", message: nil, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "确认", style: .default))
    let context = alertContext(alert)

    let data = try UIViewHierarchyCollector.collectTopViewHierarchy(
        query: try UIViewHierarchyInput.parse(from: [:]),
        context: context
    )
    let alertData = data["alert"]?.objectValue
    #expect(alertData?["available"]?.boolValue == true)
    let buttons = alertData?["buttons"]?.arrayValue
    #expect(buttons?.count == 1)
}

@Test("messageOnlyAlert 有 buttons 空数组") @MainActor
func messageOnlyAlertHasEmptyButtonsArray() {
    let alert = UIAlertController(title: "提示", message: "无按钮", preferredStyle: .alert)
    let context = alertContext(alert)

    let data = UIInspectCollector.collect(query: .default, context: context)
    let alertData = data["alert"]?.objectValue
    #expect(alertData?["available"]?.boolValue == true)
    let buttons = alertData?["buttons"]?.arrayValue
    #expect(buttons?.isEmpty == true)
    // 无 addTextField 的 alert，textFields 也应为空数组。
    let textFields = alertData?["textFields"]?.arrayValue
    #expect(textFields?.isEmpty == true)
}

@Test("inspectWithAlert 包含输入框 path 与 accessibilityIdentifier") @MainActor
func inspectWithAlertIncludesTextFieldPaths() {
    let alert = UIAlertController(title: "登录", message: "请输入账号密码", preferredStyle: .alert)
    alert.addTextField { tf in
        tf.placeholder = "用户名"
        tf.accessibilityIdentifier = "alert.input.username"
    }
    alert.addTextField { tf in
        tf.placeholder = "密码"
        tf.isSecureTextEntry = true
        tf.accessibilityIdentifier = "alert.input.password"
    }
    alert.addAction(UIAlertAction(title: "登录", style: .default))
    let context = alertContext(alert)
    embedAlertTextFields(alert)

    let data = UIInspectCollector.collect(query: .default, context: context)
    let alertData = data["alert"]?.objectValue
    let textFields = try? #require(alertData?["textFields"]?.arrayValue)
    #expect(textFields?.count == 2)

    let username = try? #require(textFields?[0].objectValue)
    #expect(username?["placeholder"]?.stringValue == "用户名")
    #expect(username?["isSecure"]?.boolValue == false)
    #expect(username?["accessibilityIdentifier"]?.stringValue == "alert.input.username")
    let usernamePath = username?["path"]?.stringValue
    #expect(usernamePath != nil, "用户名输入框应解析出 path")
    #expect(usernamePath?.hasPrefix("root/") == true, "path 应为 root/<indexes> 格式")
    let usernameActions = try? #require(username?["availableActions"]?.arrayValue)
    #expect(usernameActions?.count == 1)
    #expect(usernameActions?[0].stringValue == "ui.input")

    let password = try? #require(textFields?[1].objectValue)
    #expect(password?["placeholder"]?.stringValue == "密码")
    #expect(password?["isSecure"]?.boolValue == true)
    #expect(password?["accessibilityIdentifier"]?.stringValue == "alert.input.password")
    let passwordPath = password?["path"]?.stringValue
    #expect(passwordPath != nil, "密码输入框应解析出 path")
    // 两个输入框是不同对象，path 必须不同（对象身份 DFS 不会撞同一目标）。
    #expect(usernamePath != passwordPath, "两个输入框 path 应不同")
}

@Test("alertTextFieldPath 在多次 inspect 间稳定") @MainActor
func alertTextFieldPathIsStableAcrossInspects() {
    let alert = UIAlertController(title: "登录", message: nil, preferredStyle: .alert)
    alert.addTextField { tf in
        tf.placeholder = "用户名"
        tf.accessibilityIdentifier = "alert.input.username"
    }
    let context = alertContext(alert)
    embedAlertTextFields(alert)

    let firstData = UIInspectCollector.collect(query: .default, context: context)
    let secondData = UIInspectCollector.collect(query: .default, context: context)

    let firstTextFields = firstData["alert"]?.objectValue?["textFields"]?.arrayValue ?? []
    let secondTextFields = secondData["alert"]?.objectValue?["textFields"]?.arrayValue ?? []

    let firstPath = firstTextFields[0].objectValue?["path"]?.stringValue
    let secondPath = secondTextFields[0].objectValue?["path"]?.stringValue
    #expect(firstPath != nil)
    #expect(firstPath == secondPath, "同一输入框多次 inspect 的 path 应稳定")
}

@Test("alertBlock 输入框出现在 topViewHierarchy") @MainActor
func alertTextFieldsAppearInTopViewHierarchy() throws {
    let alert = UIAlertController(title: "登录", message: nil, preferredStyle: .alert)
    alert.addTextField { tf in
        tf.placeholder = "密码"
        tf.isSecureTextEntry = true
        tf.accessibilityIdentifier = "alert.input.password"
    }
    let context = alertContext(alert)
    embedAlertTextFields(alert)

    let data = try UIViewHierarchyCollector.collectTopViewHierarchy(
        query: try UIViewHierarchyInput.parse(from: [:]),
        context: context
    )
    let alertData = data["alert"]?.objectValue
    #expect(alertData?["available"]?.boolValue == true)
    let textFields = alertData?["textFields"]?.arrayValue
    #expect(textFields?.count == 1)
    let textField = try? #require(textFields?[0].objectValue)
    #expect(textField?["accessibilityIdentifier"]?.stringValue == "alert.input.password")
    #expect(textField?["isSecure"]?.boolValue == true)
    #expect(textField?["path"]?.stringValue != nil)
    #expect(textField?["availableActions"]?.arrayValue?.first?.stringValue == "ui.input")
}
#endif
