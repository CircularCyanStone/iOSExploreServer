#if canImport(UIKit)
import UIKit
import Testing
@testable import iOSExploreServer
@testable import iOSExploreUIKit

/// Task 6 测试：collector 全节点输出 + full/minimal 分档 + 签发只 full + 截断只数 full
/// + maxVisitedNodes + matchesIdentifier 语义。
///
/// 这些测试通过 `collect(query:context:)` 注入入口驱动真实 UIView 树，锁定 collector 的
/// 可观察行为：minimal 节点维持层级但不签发（toJSON 只输出 path+type）；full 节点签发
/// fingerprint 并带完整字段；minimal 不占 `maxTargets` 配额；identifier 筛选只过滤 full。
///
/// full/minimal 在 JSON 层面的区分依据：minimal 的 `toJSON()` 因 `isMinimal=true` 短路，
/// 只输出 `{path, type}`；full 输出含 `role` 字段。故 `target["role"] != nil` 即 full。

/// 从 collect 结果提取所有 target summary JSON 对象。
@MainActor
private func allTargetSummaries(from data: JSON) -> [JSON] {
    guard case .array(let targets)? = data["targets"] else {
        Issue.record("targets is not an array")
        return []
    }
    return targets.compactMap { json -> JSON? in
        if case .object(let obj) = json { return obj }
        return nil
    }
}

/// 判断 target 是否为 full 档（含 `role` 字段；minimal 的 toJSON 只输出 path+type）。
private func isFullTarget(_ target: JSON) -> Bool {
    target["role"] != nil
}

@Test("minimal 节点进 collected（只 path+type），full 节点带完整字段") @MainActor
func collectEmitsMinimalAndFullNodes() {
    // root(minimal) - UILabel(full,text=A) - container(minimal) - UILabel(full,text=B)
    let context = UIKitTestHost.context { root in
        let label1 = UILabel()
        label1.text = "A"
        label1.frame = CGRect(x: 10, y: 10, width: 100, height: 20)
        root.addSubview(label1)

        let container = UIView()
        container.frame = CGRect(x: 0, y: 40, width: 320, height: 40)
        root.addSubview(container)

        let label2 = UILabel()
        label2.text = "B"
        label2.frame = CGRect(x: 10, y: 0, width: 100, height: 20)
        container.addSubview(label2)
    }

    let data = UIViewTargetsCollector.collect(query: .default, context: context)
    let targets = allTargetSummaries(from: data)

    // 两个 label（full）+ container（minimal）。root 也是 minimal。
    let full = targets.filter { isFullTarget($0) }
    let minimal = targets.filter { !isFullTarget($0) }
    #expect(full.contains { $0["type"]?.stringValue == "UILabel" && $0["text"]?.stringValue == "A" })
    #expect(full.contains { $0["type"]?.stringValue == "UILabel" && $0["text"]?.stringValue == "B" })
    // container 是 UIView 且 minimal（无 role 字段）。
    #expect(minimal.contains { $0["type"]?.stringValue == "UIView" })
    // minimal 节点的 toJSON 只输出 path + type（强制精简，不输出 availableActions/frame/role 等）。
    #expect(minimal.allSatisfy {
        $0["availableActions"] == nil && $0["frame"] == nil && $0["role"] == nil
    })

    // 响应字段：fullCount/minimalCount 与分类一致。
    #expect(data["fullCount"]?.doubleValue == Double(full.count))
    #expect(data["minimalCount"]?.doubleValue == Double(minimal.count))
    #expect(data["targetCount"]?.doubleValue == Double(targets.count))
}

@Test("minimal 节点强制 availableActions 为空（toJSON 不输出该字段）") @MainActor
func minimalNodesOmitAvailableActions() {
    // 纯容器 UIView（无识别信息/不可操作）→ minimal，其 toJSON 不应含 availableActions/role。
    let context = UIKitTestHost.context { root in
        let container = UIView()
        container.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        root.addSubview(container)
    }

    let data = UIViewTargetsCollector.collect(query: .default, context: context)
    let minimal = allTargetSummaries(from: data).filter { !isFullTarget($0) }
    #expect(!minimal.isEmpty)
    // minimal toJSON 短路：只有 path/type，不可能出现 availableActions（避免引诱 agent 操作）。
    #expect(minimal.allSatisfy { $0["availableActions"] == nil })
}

@Test("cell 内 UILabel 进 full（hasStaticText 且 isInControlSubtree=false，spec §3.4 核心）") @MainActor
func cellInternalLabelIsFullTarget() {
    // UITableViewCell 不是 UIControl，cell 内 label 的祖先链无 UIControl → isInControlSubtree=false
    // → hasStaticText 命中 → full。这是 spec §3.4「cell 内 UILabel 可被 agent 直接 tap 选中行」
    // 的核心，rollup 不得误伤 cell 子树。
    let context = UIKitTestHost.context { root in
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        let label = UILabel()
        label.text = "Row Title"
        label.frame = CGRect(x: 10, y: 10, width: 200, height: 20)
        cell.contentView.addSubview(label)
        cell.frame = CGRect(x: 0, y: 0, width: 320, height: 44)
        root.addSubview(cell)
    }

    let data = UIViewTargetsCollector.collect(query: .default, context: context)
    let full = allTargetSummaries(from: data).filter { isFullTarget($0) }
    // cell 内 label 必须作为 full target 出现，且带 text。
    let cellLabel = full.first { $0["type"]?.stringValue == "UILabel" }
    #expect(cellLabel != nil)
    #expect(cellLabel?["text"]?.stringValue == "Row Title")
}

@Test("截断只数 full：minimal 不占 maxTargets 配额，深层 full 不被提前丢弃") @MainActor
func truncationCountsOnlyFullNodes() {
    // root - wrapper0(minimal) - btn0(full) - wrapper1(minimal) - btn1(full)
    //   - wrapper2(minimal) - btn2(full) - wrapper3(minimal) - btn3(full)
    // 设 maxTargets=2：若 minimal 也占配额（旧 collected.count 逻辑），会在 root+wrapper0
    // 后即截断，btn0 永不收集；新逻辑只数 full，btn0/btn1 都应被收集。
    let context = UIKitTestHost.context { root in
        for i in 0..<4 {
            let wrapper = UIView()
            wrapper.frame = CGRect(x: 0, y: CGFloat(i) * 50, width: 320, height: 40)
            let btn = UIButton(type: .system)
            btn.accessibilityIdentifier = "btn\(i)"
            btn.frame = CGRect(x: 10, y: 10, width: 100, height: 30)
            wrapper.addSubview(btn)
            root.addSubview(wrapper)
        }
    }

    let query = UIViewTargetsInput(maxTargets: 2)
    let data = UIViewTargetsCollector.collect(query: query, context: context)
    let full = allTargetSummaries(from: data).filter { isFullTarget($0) }
    let fullIds = Set(full.compactMap { $0["accessibilityIdentifier"]?.stringValue })

    // btn0 必须在 full targets——证明 wrapper0(minimal) 没有占掉它的配额。
    #expect(fullIds.contains("btn0"))
    // btn1 触发 fullCount=2 截断，也应收集（截断发生在 append 之后）。
    #expect(fullIds.contains("btn1"))
    #expect(data["fullCount"]?.doubleValue == 2)
    #expect(data["truncated"]?.boolValue == true)
    // maxTargets 触顶时 reason 必须是 "maxTargets"（防 truncationReason 误报回归）。
    #expect(data["truncationReason"]?.stringValue == "maxTargets")
    // minimal 节点（root + 已访问的 wrapper）也应出现在结果里（维持层级）。
    #expect(data["minimalCount"]?.doubleValue ?? 0 > 0)
}

@Test("maxVisitedNodes 触顶时停止遍历并标记截断") @MainActor
func maxVisitedNodesStopsDeepTree() {
    // 构造 10 层嵌套 UIView 链（全部 minimal）。设 maxVisitedNodes=5，应在第 6 个节点停止。
    let context = UIKitTestHost.context { root in
        var current = root
        for _ in 0..<9 {
            let next = UIView()
            next.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
            current.addSubview(next)
            current = next
        }
    }

    let query = UIViewTargetsInput(maxVisitedNodes: 5)
    let data = UIViewTargetsCollector.collect(query: query, context: context)

    // 第 6 次访问（visitedNodeCount=6 > 5）触发返回；不会继续深入到第 7 层。
    let visited = Int(data["visitedNodeCount"]?.doubleValue ?? -1)
    #expect(visited == 6)
    #expect(data["truncated"]?.boolValue == true)
    // 全是 minimal（纯 UIView 无内容），fullCount 必须为 0。
    #expect(data["fullCount"]?.doubleValue == 0)
    // maxVisitedNodes 触顶时 reason 必须是 "maxVisitedNodes"——而非误导 agent 去调 maxTargets。
    #expect(data["truncationReason"]?.stringValue == "maxVisitedNodes")
}

@Test("matchesIdentifier：full 受筛选过滤，minimal 维持层级") @MainActor
func identifierFilterAffectsOnlyFull() {
    // root(minimal) - btn_keep(full,id=keep) - wrapper(minimal) - btn_drop(full,id=drop)
    let context = UIKitTestHost.context { root in
        let keep = UIButton(type: .system)
        keep.accessibilityIdentifier = "keep"
        keep.frame = CGRect(x: 10, y: 10, width: 100, height: 30)
        root.addSubview(keep)

        let wrapper = UIView()
        wrapper.frame = CGRect(x: 0, y: 50, width: 320, height: 40)
        root.addSubview(wrapper)

        let drop = UIButton(type: .system)
        drop.accessibilityIdentifier = "drop"
        drop.frame = CGRect(x: 10, y: 10, width: 100, height: 30)
        wrapper.addSubview(drop)
    }

    let query = UIViewTargetsInput(accessibilityIdentifier: "keep")
    let data = UIViewTargetsCollector.collect(query: query, context: context)
    let targets = allTargetSummaries(from: data)
    let full = targets.filter { isFullTarget($0) }
    let minimal = targets.filter { !isFullTarget($0) }

    // 只有 id=keep 的 full target；btn_drop 不匹配筛选，不作为 full 输出。
    let fullIds = Set(full.compactMap { $0["accessibilityIdentifier"]?.stringValue })
    #expect(fullIds == ["keep"])
    // minimal 节点不受 identifier 筛选，root + wrapper 都在（维持父子层级）。
    #expect(minimal.contains { $0["type"]?.stringValue == "UIView" })
    #expect(data["fullCount"]?.doubleValue == 1)
    #expect(data["minimalCount"]?.doubleValue == 2)
}

@Test("non-secure UITextField exposes text in collect output") @MainActor
func nonSecureTextFieldExposesText() {
    let context = UIKitTestHost.context { root in
        let textField = UITextField()
        textField.text = "AgentName42"
        textField.placeholder = "用户名"
        textField.isSecureTextEntry = false
        textField.frame = CGRect(x: 10, y: 10, width: 200, height: 30)
        root.addSubview(textField)
    }

    let data = UIViewTargetsCollector.collect(query: .default, context: context)
    let targets = allTargetSummaries(from: data)

    let tfTarget = targets.first { $0["type"]?.stringValue == "UITextField" }
    #expect(tfTarget != nil, "UITextField should appear as a target")
    #expect(tfTarget?["text"]?.stringValue == "AgentName42")
    #expect(tfTarget?["placeholder"]?.stringValue == "用户名")
}

@Test("secure UITextField suppresses text in collect output") @MainActor
func secureTextFieldSuppressesText() {
    let context = UIKitTestHost.context { root in
        let secureField = UITextField()
        secureField.text = "secret123"
        secureField.isSecureTextEntry = true
        secureField.frame = CGRect(x: 10, y: 10, width: 200, height: 30)
        root.addSubview(secureField)
    }

    let data = UIViewTargetsCollector.collect(query: .default, context: context)
    let targets = allTargetSummaries(from: data)

    // collector 不输出 `isSecure` 字段，按 type 找到目标后断言 text 字段不可读。
    // 注意 full 节点的 toJSON 把 nil text 序列化为 "text": .null，故需排除 .string("secret123")
    // 同时允许 .null（缺省值）——不可等同于明文。
    let secureTarget = targets.first { $0["type"]?.stringValue == "UITextField" }
    #expect(secureTarget != nil, "secure UITextField should appear as a target")
    let textValue = secureTarget?["text"]
    #expect(textValue?.stringValue != "secret123",
            "secure field must NOT expose plaintext secret123")
    // 进一步收紧：textValue 必须不是任何 .string(...)
    if case .string(let s)? = textValue {
        Issue.record("secure field leaked text via .string: \"\(s)\"")
    }
}

@Test("non-secure UITextView exposes text in collect output") @MainActor
func nonSecureTextViewExposesText() {
    let context = UIKitTestHost.context { root in
        let textView = UITextView()
        textView.text = "Hello World"
        textView.frame = CGRect(x: 10, y: 10, width: 200, height: 100)
        root.addSubview(textView)
    }

    let data = UIViewTargetsCollector.collect(query: .default, context: context)
    let targets = allTargetSummaries(from: data)

    #expect(targets.contains { $0["type"]?.stringValue == "UITextView" && $0["text"]?.stringValue == "Hello World" })
}

@Test("UITextField 与 UITextView 混合场景：secure 不暴露，non-secure 正常") @MainActor
func mixedTextFieldsSecureVsNonSecure() {
    let context = UIKitTestHost.context { root in
        let nameField = UITextField()
        nameField.text = "Alice"
        nameField.isSecureTextEntry = false
        nameField.frame = CGRect(x: 10, y: 10, width: 200, height: 30)
        root.addSubview(nameField)

        let pwField = UITextField()
        pwField.text = "secret"
        pwField.isSecureTextEntry = true
        pwField.frame = CGRect(x: 10, y: 50, width: 200, height: 30)
        root.addSubview(pwField)

        let bioView = UITextView()
        bioView.text = "Hello!"
        bioView.frame = CGRect(x: 10, y: 90, width: 200, height: 100)
        root.addSubview(bioView)
    }

    let data = UIViewTargetsCollector.collect(query: .default, context: context)
    let targets = allTargetSummaries(from: data)

    let nameTarget = targets.first { $0["type"]?.stringValue == "UITextField" && $0["text"]?.stringValue == "Alice" }
    #expect(nameTarget != nil, "non-secure UITextField must expose text")

    let pwTarget = targets.first { $0["type"]?.stringValue == "UITextField" && $0["text"]?.stringValue == "secret" }
    #expect(pwTarget == nil, "secure UITextField must NOT expose text")

    let bioTarget = targets.first { $0["type"]?.stringValue == "UITextView" && $0["text"]?.stringValue == "Hello!" }
    #expect(bioTarget != nil, "UITextView must expose text")
}

@Test("UITextView.isSecureTextEntry 默认 false，仍暴露 text") @MainActor
func textViewDefaultNotSecureExposesText() {
    let context = UIKitTestHost.context { root in
        let tv = UITextView()
        tv.text = "visible"
        tv.isSecureTextEntry = false // 默认值，显式写以确保
        tv.frame = CGRect(x: 10, y: 10, width: 200, height: 100)
        root.addSubview(tv)
    }

    let data = UIViewTargetsCollector.collect(query: .default, context: context)
    let targets = allTargetSummaries(from: data)

    #expect(targets.contains { $0["type"]?.stringValue == "UITextView" && $0["text"]?.stringValue == "visible" })
}

@Test("UITextField placeholder 仍然从 collector 正常返回") @MainActor
func textFieldPlaceholderStillReturned() {
    let context = UIKitTestHost.context { root in
        let tf = UITextField()
        tf.placeholder = "Password"
        tf.isSecureTextEntry = true
        tf.frame = CGRect(x: 10, y: 10, width: 200, height: 30)
        root.addSubview(tf)
    }

    let data = UIViewTargetsCollector.collect(query: .default, context: context)
    let targets = allTargetSummaries(from: data)

    let tfTarget = targets.first { $0["type"]?.stringValue == "UITextField" }
    #expect(tfTarget != nil, "secure UITextField should appear as a target")
    let textValue = tfTarget?["text"]
    if case .string(let s)? = textValue {
        Issue.record("secure field leaked text via .string: \"\(s)\"")
    }
    #expect(textValue?.stringValue != "secret", "secure field must NOT expose plaintext secret")
    #expect(tfTarget?["placeholder"]?.stringValue == "Password",
            "placeholder 仍应正常返回，不受 secure 影响")
}

@Test("UISwitch/UISlider/UISegmentedControl 的 value 不受 change 影响") @MainActor
func valueFromForNonTextFieldStillWorks() {
    // 验证修改 textualValue 不会误伤 value(from:) 对其他控件的处理。
    let context = UIKitTestHost.context { root in
        let sw = UISwitch()
        sw.isOn = true
        sw.frame = CGRect(x: 10, y: 10, width: 50, height: 30)
        root.addSubview(sw)

        let seg = UISegmentedControl(items: ["A", "B"])
        seg.selectedSegmentIndex = 1
        seg.frame = CGRect(x: 10, y: 50, width: 200, height: 30)
        root.addSubview(seg)
    }

    let data = UIViewTargetsCollector.collect(query: .default, context: context)
    let targets = allTargetSummaries(from: data)

    #expect(targets.contains { $0["type"]?.stringValue == "UISwitch" && $0["value"]?.stringValue == "on" })
    #expect(targets.contains { $0["type"]?.stringValue == "UISegmentedControl" && $0["value"]?.stringValue == "1" })
}

@Test("UIViewTargetsInput 解析 maxVisitedNodes 默认值和边界")
func viewTargetsQueryParsesMaxVisitedNodes() throws {
    let defaultQuery = try UIViewTargetsInput.parse(from: [:])
    #expect(defaultQuery.maxVisitedNodes == 2000)

    let custom = try UIViewTargetsInput.parse(from: ["maxVisitedNodes": 5000])
    #expect(custom.maxVisitedNodes == 5000)

    for invalid: JSON in [
        ["maxVisitedNodes": 99],
        ["maxVisitedNodes": 20001],
        ["maxVisitedNodes": 1.5],
    ] {
        #expect(throws: CommandInputParseError.self) { try UIViewTargetsInput.parse(from: invalid) }
    }
}
#endif
