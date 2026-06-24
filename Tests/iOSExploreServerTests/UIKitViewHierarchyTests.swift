import Testing
@testable import iOSExploreServer
@testable import iOSExploreUIKit

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
                                            query: UIViewHierarchyQuery(maxDepth: 1))

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
                                               query: UIViewHierarchyQuery(accessibilityIdentifier: "mine.header.avatar"))
    #expect(exact.map(\.type) == ["Avatar"])
    #expect(exact.first?.path == "root/0")

    let prefixed = UIViewHierarchyBuilder.matches(in: root,
                                                  query: UIViewHierarchyQuery(accessibilityIdentifierPrefix: "mine."))
    #expect(prefixed.map(\.type) == ["Avatar", "Settings"])
    #expect(prefixed.map(\.path) == ["root/0", "root/1"])
}

@Test("UIViewHierarchyQuery 从命令 data 解析详情级别和筛选参数")
func viewHierarchyQueryParsesCommandData() throws {
    let query = try UIViewHierarchyQuery.parse(from: [
        "detailLevel": "full",
        "maxDepth": 3,
        "includeHidden": true,
        "accessibilityIdentifierPrefix": "mine.",
    ])

    #expect(query.detailLevel == .full)
    #expect(query.maxDepth == 3)
    #expect(query.includeHidden == true)
    #expect(query.accessibilityIdentifierPrefix == "mine.")

    #expect(throws: QueryParseError.self) {
        try UIViewHierarchyQuery.parse(from: ["detailLevel": "unknown"])
    }
}

#if !canImport(UIKit)
@Test("UIViewHierarchyQuery 拒绝无法安全转换为 Int 的 maxDepth")
func viewHierarchyQueryRejectsOutOfRangeMaxDepth() {
    #expect(throws: QueryParseError.self) {
        try UIViewHierarchyQuery.parse(from: [
            "maxDepth": .double(Double.greatestFiniteMagnitude),
        ])
    }
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
         subviews: [TestViewElement] = []) {
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
    }
}
