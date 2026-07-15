#if canImport(UIKit)
import UIKit
import Testing
@testable import iOSExploreServer
@testable import iOSExploreUIKit

/// F-16 / F-01 安全回归测试：secure UITextField（密码框）的明文密码不得经
/// `ui.topViewHierarchy` 的 `text.value` 或 `ui.inspect` 的子节点 value/semanticText/text 泄露。
///
/// #### 背景
/// - **F-16**：`UIViewHierarchyCollector.textInfo` 直接读 `textField.text`（UITextField.text 总持有明文，
///   `isSecureTextEntry` 只控制圆点渲染），导致 `ui.topViewHierarchy` 节点的 `text.value` 字段泄露密码。
/// - **F-01**：secure UITextField 成为 firstResponder 后，UIKit 插入 `UIFieldEditor` 子节点承载编辑态
///   文本，该子节点的 accessibilityValue / 文本属性返回明文。`UIInspectCollector` 的 value / semanticText /
///   textualValue 三个取值点未检查祖先链，把子节点明文透传到响应。
///
/// 两条路径共用同一个 helper（`explore_secureTextEntryAncestor`）保证保护口径一致。

/// 把 JSON 序列化为字符串，用于断言整个响应不含敏感原文。
private func describe(_ json: JSON) -> String {
    "\(json.storage)"
}

// MARK: - F-16: ui.topViewHierarchy text.value 泄露

@Test("F-16: topViewHierarchy secure UITextField 的 text.value 不泄露明文密码") @MainActor
func topViewHierarchySecureFieldDoesNotLeakPassword() throws {
    let secret = "mySecretPass123"
    let context = UIKitTestHost.context { root in
        let field = UITextField()
        field.isSecureTextEntry = true
        field.text = secret
        field.accessibilityIdentifier = "test.password"
        field.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        root.addSubview(field)
    }

    let data = try UIViewHierarchyCollector.collectTopViewHierarchy(
        query: try UIViewHierarchyInput.parse(from: [:]),
        context: context
    )

    // 整个响应序列化后不得出现明文密码。
    let serialized = describe(data)
    #expect(serialized.contains(secret) == false,
            "topViewHierarchy response must not contain plaintext password")
}

@Test("F-16: topViewHierarchy 非 secure UITextField 的 text.value 正常返回") @MainActor
func topViewHierarchyNonSecureFieldReturnsText() throws {
    let plainText = "hello@example.com"
    let context = UIKitTestHost.context { root in
        let field = UITextField()
        field.isSecureTextEntry = false
        field.text = plainText
        field.accessibilityIdentifier = "test.email"
        field.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        root.addSubview(field)
    }

    let data = try UIViewHierarchyCollector.collectTopViewHierarchy(
        query: try UIViewHierarchyInput.parse(from: [:]),
        context: context
    )

    // 非 secure 字段的明文应正常出现在响应中。
    let serialized = describe(data)
    #expect(serialized.contains(plainText) == true,
            "non-secure field text should appear in topViewHierarchy")
}

// MARK: - F-01: ui.inspect 子节点（secure 祖先链）不泄露

@Test("F-01: inspect secure UITextField 本体 text/value 为 nil") @MainActor
func inspectSecureFieldBodyDoesNotLeak() {
    let secret = "p@ssw0rd"
    let context = UIKitTestHost.context { root in
        let field = UITextField()
        field.isSecureTextEntry = true
        field.text = secret
        field.accessibilityIdentifier = "test.password"
        field.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        root.addSubview(field)
    }

    let data = UIInspectCollector.collect(query: .default, context: context)
    let serialized = describe(data)
    #expect(serialized.contains(secret) == false,
            "inspect response must not contain plaintext password")
}

@Test("F-01: explore_secureTextEntryAncestor 正确识别 secure 祖先") @MainActor
func secureTextEntryAncestorHelper() {
    let secureField = UITextField()
    secureField.isSecureTextEntry = true
    secureField.frame = CGRect(x: 0, y: 0, width: 200, height: 40)

    let child = UIView()
    child.frame = CGRect(x: 0, y: 0, width: 100, height: 20)
    secureField.addSubview(child)

    let grandchild = UIView()
    grandchild.frame = CGRect(x: 0, y: 0, width: 50, height: 10)
    child.addSubview(grandchild)

    // 子节点和孙节点都应找到 secure 祖先。
    #expect(child.explore_secureTextEntryAncestor != nil)
    #expect(grandchild.explore_secureTextEntryAncestor != nil)
    #expect(child.explore_secureTextEntryAncestor === secureField)

    // 非 secure 字段的子节点不应找到 secure 祖先。
    let plainField = UITextField()
    plainField.isSecureTextEntry = false
    let plainChild = UIView()
    plainField.addSubview(plainChild)
    #expect(plainChild.explore_secureTextEntryAncestor == nil)

    // 无父节点的 view 也不应找到。
    let orphan = UIView()
    #expect(orphan.explore_secureTextEntryAncestor == nil)
}

@Test("F-01: inspect secure UITextField 的 scroll 子节点不泄露明文") @MainActor
func inspectSecureFieldScrollSubtreeDoesNotLeak() {
    // 模拟 F-01 场景：secure UITextField 内部有 UIScrollView 子节点（UIFieldEditor 是
    // UITextView 子类→UIScrollView），该子节点因 isScrollView 命中 full，其文本/value
    // 可能泄露。修复后 explore_secureTextEntryAncestor 应屏蔽它。
    let secret = "leakedFromSubnode"
    let context = UIKitTestHost.context { root in
        let field = UITextField()
        field.isSecureTextEntry = true
        field.text = secret
        field.accessibilityIdentifier = "test.password"
        field.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        root.addSubview(field)

        // 在 secure field 内部塞一个带文本的 UIScrollView（模拟 UIFieldEditor 的结构）。
        let editorLikeScroll = UIScrollView()
        editorLikeScroll.frame = CGRect(x: 0, y: 0, width: 180, height: 30)
        editorLikeScroll.accessibilityValue = secret
        field.addSubview(editorLikeScroll)
    }

    // includeHidden=true 确保 UITextField 内部子节点也被遍历。
    let query = UIInspectInput(includeHidden: true)
    let data = UIInspectCollector.collect(query: query, context: context)
    let serialized = describe(data)

    // 整个 inspect 响应不得出现明文密码——即使子节点自身 accessibilityValue 持有明文。
    #expect(serialized.contains(secret) == false,
            "inspect response must not contain plaintext from secure field subnode")
}

@Test("F-01: inspect secure UITextField 的 UILabel 子节点不泄露明文") @MainActor
func inspectSecureFieldLabelSubtreeDoesNotLeak() {
    let secret = "labelLeakSecret"
    let context = UIKitTestHost.context { root in
        let field = UITextField()
        field.isSecureTextEntry = true
        field.text = secret
        field.accessibilityIdentifier = "test.password"
        field.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        root.addSubview(field)

        // 在 secure field 内部塞一个带明文的 UILabel。
        let innerLabel = UILabel()
        innerLabel.text = secret
        innerLabel.frame = CGRect(x: 0, y: 0, width: 100, height: 20)
        field.addSubview(innerLabel)
    }

    let query = UIInspectInput(includeHidden: true)
    let data = UIInspectCollector.collect(query: query, context: context)
    let serialized = describe(data)

    #expect(serialized.contains(secret) == false,
            "inspect response must not contain plaintext from secure field UILabel subnode")
}
#endif
