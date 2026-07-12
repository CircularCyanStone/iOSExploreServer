import Testing
@testable import iOSExploreServer
@testable import iOSExploreUIKit

@Test("UIViewHierarchyNode 转 JSON 保留 indexPath 字段")
func viewHierarchyNodeJSONIncludesIndexPath() {
    let node = UIViewHierarchyNode(
        path: "root/0",
        type: "UITableViewCell",
        accessibility: UIViewHierarchyAccessibility(identifier: "cell.id"),
        frame: UIViewHierarchyRect(x: 0, y: 50, width: 375, height: 44),
        bounds: UIViewHierarchyRect(x: 0, y: 0, width: 375, height: 44),
        state: UIViewHierarchyState(isHidden: false, alpha: 1, isOpaque: true, isUserInteractionEnabled: true),
        text: nil,
        appearance: nil,
        control: nil,
        image: nil,
        scroll: nil,
        subviews: [],
        indexPath: IndexPathSummary(section: 0, item: 2)
    )

    let json = node.toJSON()
    guard case .object(let indexPath)? = json["indexPath"] else { Issue.record("indexPath not object"); return }
    #expect(indexPath["section"] == .double(0))
    #expect(indexPath["item"] == .double(2))
}

@Test("UIViewHierarchyNode 默认 indexPath 为 nil 时不序列化")
func viewHierarchyNodeJSONOmitsIndexPathWhenNil() {
    let node = UIViewHierarchyNode(
        path: "root/0", type: "UIButton",
        accessibility: UIViewHierarchyAccessibility(),
        frame: UIViewHierarchyRect(x: 0, y: 0, width: 44, height: 44),
        bounds: UIViewHierarchyRect(x: 0, y: 0, width: 44, height: 44),
        state: UIViewHierarchyState(isHidden: false, alpha: 1, isOpaque: true, isUserInteractionEnabled: true),
        subviews: []
    )

    let json = node.toJSON()
    #expect(json["indexPath"] == nil, "nil indexPath 不应出现")
}

@Test("UIViewHierarchyBuilder 传递 indexPath 到节点")
func viewHierarchyBuilderPassesIndexPathToNode() {
    let root = TestViewElement(type: "Root", subviews: [
        TestViewElement(type: "UITableViewCell", indexPath: IndexPathSummary(section: 0, item: 2)),
        TestViewElement(type: "UIView"),
        TestViewElement(type: "UICollectionViewCell", indexPath: IndexPathSummary(section: 1, item: 3)),
    ])

    let node = UIViewHierarchyBuilder.build(from: root, query: .default)

    #expect(node.subviews[0].indexPath == IndexPathSummary(section: 0, item: 2))
    #expect(node.subviews[1].indexPath == nil)
    #expect(node.subviews[2].indexPath == IndexPathSummary(section: 1, item: 3))
}

@Test("UIViewHierarchyNode 转 JSON 保留结构、语义、文本和外观字段")
func viewHierarchyNodeJSONIncludesCoreAndAcceptanceFields() {
    let node = UIViewHierarchyNode(
        path: "root",
        type: "UIButton",
        accessibility: UIViewHierarchyAccessibility(identifier: "mine.header.avatar",
                                                    label: "头像",
                                                    value: nil,
                                                    hint: "打开个人资料"),
        frame: UIViewHierarchyRect(x: 10, y: 20, width: 44, height: 44),
        bounds: UIViewHierarchyRect(x: 0, y: 0, width: 44, height: 44),
        state: UIViewHierarchyState(isHidden: false,
                                    alpha: 1,
                                    isOpaque: false,
                                    isUserInteractionEnabled: true),
        text: UIViewHierarchyText(value: "我",
                                  fontName: ".SFUI-Semibold",
                                  fontSize: 16,
                                  textColor: "#FFFFFF",
                                  textAlignment: "center",
                                  numberOfLines: 1),
        appearance: UIViewHierarchyAppearance(backgroundColor: "#1677FF",
                                              tintColor: "#FFFFFF",
                                              cornerRadius: 8,
                                              borderWidth: 1,
                                              borderColor: "#0057D9"),
        control: UIViewHierarchyControl(isEnabled: true,
                                        isSelected: false,
                                        isHighlighted: false,
                                        horizontalAlignment: "center",
                                        verticalAlignment: "center"),
        image: nil,
        scroll: nil,
        subviews: []
    )

    let json = node.toJSON()
    #expect(json["path"]?.stringValue == "root")
    #expect(json["type"]?.stringValue == "UIButton")
    #expect(json["accessibilityIdentifier"]?.stringValue == "mine.header.avatar")

    guard case .object(let frame)? = json["frame"] else { Issue.record("frame not object"); return }
    #expect(frame["x"] == .double(10))
    #expect(frame["width"] == .double(44))

    guard case .object(let text)? = json["text"] else { Issue.record("text not object"); return }
    #expect(text["value"]?.stringValue == "我")
    #expect(text["fontSize"] == .double(16))
    #expect(text["textColor"]?.stringValue == "#FFFFFF")

    guard case .object(let appearance)? = json["appearance"] else { Issue.record("appearance not object"); return }
    #expect(appearance["backgroundColor"]?.stringValue == "#1677FF")
    #expect(appearance["cornerRadius"] == .double(8))
}

@Test("UIViewHierarchyBuilder 递归生成 path 并保留子视图顺序")
func viewHierarchyBuilderGeneratesRecursivePaths() {
    let root = TestViewElement(type: "Root", subviews: [
        TestViewElement(type: "Header"),
        TestViewElement(type: "Body", subviews: [
            TestViewElement(type: "Avatar")
        ])
    ])

    let node = UIViewHierarchyBuilder.build(from: root, query: .default)

    #expect(node.path == "root")
    #expect(node.subviews.map(\.path) == ["root/0", "root/1"])
    #expect(node.subviews[1].subviews.first?.path == "root/1/0")
    #expect(node.subviews[1].subviews.first?.type == "Avatar")
}

@Test("UIViewHierarchyBuilder 按 maxDepth 截断递归")
func viewHierarchyBuilderHonorsMaxDepth() {
    let root = TestViewElement(type: "Root", subviews: [
        TestViewElement(type: "Level1", subviews: [
            TestViewElement(type: "Level2")
        ])
    ])

    let node = UIViewHierarchyBuilder.build(from: root,
                                            query: UIViewHierarchyInput(maxDepth: 1))

    #expect(node.subviews.count == 1)
    #expect(node.subviews[0].path == "root/0")
    #expect(node.subviews[0].subviews.isEmpty)
}

@Test("UIViewHierarchyBuilder 默认过滤隐藏视图")
func viewHierarchyBuilderFiltersHiddenViewsByDefault() {
    let root = TestViewElement(type: "Root", subviews: [
        TestViewElement(type: "Visible"),
        TestViewElement(type: "Hidden", state: UIViewHierarchyState(isHidden: true,
                                                                    alpha: 1,
                                                                    isOpaque: false,
                                                                    isUserInteractionEnabled: true))
    ])

    let node = UIViewHierarchyBuilder.build(from: root, query: .default)

    #expect(node.subviews.map(\.type) == ["Visible"])
}

@Test("UIViewHierarchyBuilder 可按 accessibilityIdentifier 精确和前缀筛选")
func viewHierarchyBuilderFiltersByAccessibilityIdentifier() {
    let root = TestViewElement(type: "Root", subviews: [
        TestViewElement(type: "Avatar",
                        accessibility: UIViewHierarchyAccessibility(identifier: "mine.header.avatar")),
        TestViewElement(type: "Settings",
                        accessibility: UIViewHierarchyAccessibility(identifier: "mine.menu.settings")),
        TestViewElement(type: "Home",
                        accessibility: UIViewHierarchyAccessibility(identifier: "home.feed"))
    ])

    let exact = UIViewHierarchyBuilder.matches(in: root,
                                               query: UIViewHierarchyInput(accessibilityIdentifier: "mine.header.avatar"))
    #expect(exact.map(\.type) == ["Avatar"])
    #expect(exact.first?.path == "root/0")

    let prefixed = UIViewHierarchyBuilder.matches(in: root,
                                                  query: UIViewHierarchyInput(accessibilityIdentifierPrefix: "mine."))
    #expect(prefixed.map(\.type) == ["Avatar", "Settings"])
    #expect(prefixed.map(\.path) == ["root/0", "root/1"])
}

@Test("UIViewHierarchyInput 从命令 data 解析详情级别和筛选参数")
func viewHierarchyQueryParsesCommandData() throws {
    let query = try UIViewHierarchyInput.parse(from: [
        "detailLevel": "full",
        "maxDepth": 3,
        "includeHidden": true,
        "accessibilityIdentifierPrefix": "mine.",
    ])

    #expect(query.detailLevel == .full)
    #expect(query.maxDepth == 3)
    #expect(query.includeHidden == true)
    #expect(query.accessibilityIdentifierPrefix == "mine.")
    #expect(query.controller == nil)

    #expect(throws: CommandInputParseError.self) {
        try UIViewHierarchyInput.parse(from: ["detailLevel": "unknown"])
    }
}

@Test("UIViewHierarchyInput 解析 controller 参数")
func viewHierarchyQueryParsesController() throws {
    let query = try UIViewHierarchyInput.parse(from: [
        "controller": "root.nav[0]",
    ])
    #expect(query.controller == "root.nav[0]")
}

@Test("UIViewHierarchyInput controller 缺省为 nil")
func viewHierarchyQueryControllerDefaultsToNil() throws {
    let query = try UIViewHierarchyInput.parse(from: [:])
    #expect(query.controller == nil)
}

@Test("UIViewHierarchyInput schema 按工具展示顺序声明字段")
func viewHierarchyInputSchemaUsesExpectedFieldOrder() {
    #expect(UIViewHierarchyInput.inputSchema.fields.map(\.name) == [
        "detailLevel",
        "maxDepth",
        "includeHidden",
        "accessibilityIdentifier",
        "accessibilityIdentifierPrefix",
        "controller",
    ])
}

#if !canImport(UIKit)
@Test("UIViewHierarchyInput 拒绝无法安全转换为 Int 的 maxDepth")
func viewHierarchyQueryRejectsOutOfRangeMaxDepth() {
    #expect(throws: CommandInputParseError.self) {
        try UIViewHierarchyInput.parse(from: [
            "maxDepth": .double(Double.greatestFiniteMagnitude),
        ])
    }
}
#endif

@Test("UIViewHierarchyAppearance cornerRadius=nil 经 JSONCoder 编码写 null 而非 NaN")
func appearanceCornerRadiusNilSerializesToNull() throws {
    // 采集层 finiteDouble 对非有限 CGFloat 返回 nil，对应 cornerRadius=nil。
    // toJSON 把 nil 写为 .null，JSONCoder.encode 对 .null 输出 null，
    // 不再走 _writeJSONNumber 抛 NSException 的崩溃路径。
    let appearance = UIViewHierarchyAppearance(backgroundColor: "#FFFFFF",
                                               tintColor: nil,
                                               cornerRadius: nil,
                                               borderWidth: nil,
                                               borderColor: nil)
    let json = appearance.toJSON()
    #expect(json["cornerRadius"] == .null)
    #expect(json["borderWidth"] == .null)

    // 整棵 node 走 toJSON + JSONCoder.encode：不应抛、不应 abort。
    let node = UIViewHierarchyNode(
        path: "root", type: "UIView",
        accessibility: UIViewHierarchyAccessibility(),
        frame: UIViewHierarchyRect(x: 0, y: 0, width: 0, height: 0),
        bounds: UIViewHierarchyRect(x: 0, y: 0, width: 0, height: 0),
        state: UIViewHierarchyState(isHidden: false, alpha: 1, isOpaque: false, isUserInteractionEnabled: true),
        text: nil,
        appearance: appearance,
        control: nil,
        image: nil,
        scroll: nil,
        subviews: []
    )
    let encoded = JSONCoder.encode(node.toJSON())
    let decoded = try #require(JSONCoder.decode(encoded))
    guard case .object(let appearanceDecoded)? = decoded["appearance"] else {
        Issue.record("appearance not object"); return
    }
    #expect(appearanceDecoded["cornerRadius"] == .null)
}

#if canImport(UIKit)
import UIKit

// MARK: - UIKit 真实采集（仅 iOS framework 跑）

/// 构造 keyWindow + 手动 `UIKitContextProvider.Context`（对齐 UIControllersTests 写法）。
private func makeHierarchyContext(rootViewController: UIViewController,
                                  topViewController: UIViewController,
                                  rootView: UIView) -> UIKitContextProvider.Context {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    window.rootViewController = rootViewController
    window.makeKeyAndVisible()
    return UIKitContextProvider.Context(window: window,
                                        rootViewController: rootViewController,
                                        topViewController: topViewController,
                                        rootView: rootView)
}

/// 递归在层级 JSON 中查找 type 等于 `typeName` 的首个节点。
private func findNode(in json: JSONValue?, typeName: String) -> JSONValue? {
    guard let node = json?.objectValue else { return nil }
    if node["type"]?.stringValue == typeName { return json }
    for child in node["subviews"]?.arrayValue ?? [] {
        if let found = findNode(in: child, typeName: typeName) { return found }
    }
    return nil
}

@Test("controller 参数采集非栈顶 VC 视图不被 window 守卫清空（regression）") @MainActor
func collectControllerOverrideSkipsWindowGuard() throws {
    let root = UIViewController()
    let label = UILabel(frame: CGRect(x: 10, y: 10, width: 100, height: 30))
    label.text = "RootLabel"
    root.view.addSubview(label)
    let detail = UIViewController()
    let nav = UINavigationController(rootViewController: root)
    nav.pushViewController(detail, animated: false)
    // 让出一次 RunLoop 使 push 转场真正完成：之后 nav 只挂载栈顶 detail.view，
    // root.view 脱离 window（root.view.window == nil）。
    let ctx = makeHierarchyContext(rootViewController: nav,
                                   topViewController: detail,
                                   rootView: detail.view)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    let query = try UIViewHierarchyInput.parse(from: ["controller": "root.nav[0]"])
    let data = try UIViewHierarchyCollector.collectTopViewHierarchy(query: query, context: ctx)
    // 修复前：root.view 不在 window 层级 → isAttachedToWindow=false → subviews 被守卫清空
    // → nodeCount=1（只剩 root.view 自身），controller 参数的核心用途失效。
    // 修复后：controller-override 路径跳过 window 守卫 → label 子树正常采集。
    let nodeCount = data["nodeCount"]?.doubleValue ?? 0
    #expect(nodeCount > 1, "非栈顶 VC 的视图层级应包含子视图，nodeCount=\(nodeCount)")
    #expect(data["controller"]?.stringValue == "root.nav[0]")
    let rootChildren = data["root"]?.objectValue?["subviews"]?.arrayValue ?? []
    #expect(rootChildren.contains { $0.objectValue?["type"]?.stringValue == "UILabel" } == true,
            "应采集到 root.view 下的 UILabel 子视图")
}

@Test("UIStepper value 被采集为数值字符串（对齐 slider 输出格式）") @MainActor
func collectStepperValueExposed() throws {
    let host = UIViewController()
    let stepper = UIStepper(frame: CGRect(x: 10, y: 10, width: 100, height: 30))
    stepper.value = 5
    host.view.addSubview(stepper)
    let ctx = makeHierarchyContext(rootViewController: host,
                                   topViewController: host,
                                   rootView: host.view)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    let data = try UIViewHierarchyCollector.collectTopViewHierarchy(query: .default, context: ctx)
    let stepperNode = findNode(in: data["root"], typeName: "UIStepper")
    #expect(stepperNode != nil, "应采集到 UIStepper 节点")
    // 修复前：UIStepper 默认不暴露数值型 accessibilityValue → accessibilityValue=null，
    // executor 能写 stepper.value 但采集器读不到，设值闭环断裂。
    // 修复后：直接读 stepper.value，输出对齐 slider 的 String(Double(...)) 格式 → "5.0"。
    let value = stepperNode?.objectValue?["accessibilityValue"]?.stringValue
    #expect(value == "5.0", "UIStepper value 应为 \"5.0\"，实际 \(value ?? "nil")")
}

#endif

private struct TestViewElement: UIViewHierarchyElement {
    let type: String
    var accessibility: UIViewHierarchyAccessibility
    var frame: UIViewHierarchyRect
    var bounds: UIViewHierarchyRect
    var state: UIViewHierarchyState
    var text: UIViewHierarchyText?
    var appearance: UIViewHierarchyAppearance?
    var control: UIViewHierarchyControl?
    var image: UIViewHierarchyImage?
    var scroll: UIViewHierarchyScroll?
    var subviews: [TestViewElement]
    var indexPath: IndexPathSummary?

    init(type: String,
         accessibility: UIViewHierarchyAccessibility = UIViewHierarchyAccessibility(),
         frame: UIViewHierarchyRect = UIViewHierarchyRect(x: 0, y: 0, width: 100, height: 100),
         bounds: UIViewHierarchyRect = UIViewHierarchyRect(x: 0, y: 0, width: 100, height: 100),
         state: UIViewHierarchyState = UIViewHierarchyState(isHidden: false,
                                                            alpha: 1,
                                                            isOpaque: false,
                                                            isUserInteractionEnabled: true),
         text: UIViewHierarchyText? = nil,
         appearance: UIViewHierarchyAppearance? = nil,
         control: UIViewHierarchyControl? = nil,
         image: UIViewHierarchyImage? = nil,
         scroll: UIViewHierarchyScroll? = nil,
         subviews: [TestViewElement] = [],
         indexPath: IndexPathSummary? = nil) {
        self.type = type
        self.accessibility = accessibility
        self.frame = frame
        self.bounds = bounds
        self.state = state
        self.text = text
        self.appearance = appearance
        self.control = control
        self.image = image
        self.scroll = scroll
        self.subviews = subviews
        self.indexPath = indexPath
    }
}
