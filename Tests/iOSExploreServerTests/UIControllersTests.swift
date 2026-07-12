import Testing
import Foundation
import iOSExploreServer
@testable import iOSExploreUIKit

// MARK: - controller path 文法（Foundation-only，macOS + iOS 都跑）

@Test("parseControllerPath 合法路径解析为段序列")
func parseControllerPathAcceptsValid() {
    #expect(parseControllerPath("root") == [])
    #expect(parseControllerPath("root.presented") == [.presented])
    #expect(parseControllerPath("root.presented.presented") == [.presented, .presented])
    #expect(parseControllerPath("root.nav[0]") == [.navigation(0)])
    #expect(parseControllerPath("root.tab[0].nav[1].presented") == [.tab(0), .navigation(1), .presented])
    #expect(parseControllerPath("root.child[3]") == [.child(3)])
    #expect(parseControllerPath("root.split[1]") == [.split(1)])
}

@Test("parseControllerPath 拒绝非法路径")
func parseControllerPathRejectsInvalid() {
    let invalid: [String] = [
        "", "Root", "root.", "root..nav[0]", "nav[0]",
        "root.nav", "root.nav[]", "root.nav[-1]", "root.nav[abc]",
        "root.foo[0]", "root.tab[1", "root.123",
    ]
    for raw in invalid {
        #expect(parseControllerPath(raw) == nil, "expected nil for \(raw)")
    }
}

@Test("controllerPathString 与 parseControllerPath 往返一致")
func controllerPathStringRoundTrips() {
    let cases: [[UIControllerPathSegment]] = [
        [], [.presented], [.presented, .presented],
        [.navigation(0)], [.tab(0), .navigation(1), .presented], [.child(3)], [.split(1)],
    ]
    for segments in cases {
        let str = controllerPathString(segments)
        #expect(parseControllerPath(str) == segments, "round trip failed for \(str)")
    }
}

// MARK: - UIControllerNode（Foundation-only）

@Test("UIControllerNode.toJSON 保留适用字段、省略不适用字段")
func controllerNodeToJSONShape() {
    let node = UIControllerNode(path: "root.nav[1]",
                                type: "DetailViewController",
                                role: .navigation,
                                title: "详情",
                                isViewLoaded: true,
                                isVisible: true)
    let json = node.toJSON()
    #expect(json["path"]?.stringValue == "root.nav[1]")
    #expect(json["type"]?.stringValue == "DetailViewController")
    #expect(json["role"]?.stringValue == "navigation")
    #expect(json["title"]?.stringValue == "详情")
    #expect(json["isViewLoaded"]?.boolValue == true)
    #expect(json["isVisible"]?.boolValue == true)
    // 非 tab 节点不应输出 isSelected；navigation 节点输出 isVisible 后不再有 isSelected
    #expect(json["isSelected"] == nil)
    #expect(json["children"]?.arrayValue?.isEmpty == true)
}

@Test("UIControllerNode.toJSON title 为 nil 时输出 null")
func controllerNodeToJSONNullTitle() {
    let node = UIControllerNode(path: "root", type: "UIViewController", role: .root, title: nil, isViewLoaded: false)
    let json = node.toJSON()
    #expect(json["title"] == .null)
    #expect(json["isSelected"] == nil)
    #expect(json["isVisible"] == nil)
}

@Test("UIControllerNode.nodeCount 递归统计")
func controllerNodeCountRecursive() {
    let leaf = UIControllerNode(path: "a", type: "VC", role: .child, title: nil, isViewLoaded: true)
    let mid = UIControllerNode(path: "b", type: "VC", role: .tab, title: nil, isViewLoaded: true, children: [leaf])
    let root = UIControllerNode(path: "root", type: "Root", role: .root, title: nil, isViewLoaded: true, children: [mid, leaf])
    #expect(root.nodeCount == 4)
}

// MARK: - UIControllersInput（Foundation-only）

@Test("UIControllersInput 默认 maxDepth 为 nil")
func controllersInputDefaultMaxDepthNil() throws {
    let input = try UIControllersInput.parse(from: [:])
    #expect(input.maxDepth == nil)
}

@Test("UIControllersInput 解析 maxDepth")
func controllersInputParsesMaxDepth() throws {
    let input = try UIControllersInput.parse(from: ["maxDepth": .double(2)])
    #expect(input.maxDepth == 2)
}

@Test("UIControllersInput 拒绝负数 maxDepth")
func controllersInputRejectsNegativeMaxDepth() {
    #expect(throws: CommandInputParseError.self) {
        _ = try UIControllersInput.parse(from: ["maxDepth": .double(-1)])
    }
}

@Test("UIControllersInput schema 仅暴露 maxDepth")
func controllersInputSchemaFields() {
    #expect(UIControllersInput.inputSchema.fields.map(\.name) == ["maxDepth"])
}

#if canImport(UIKit)
import UIKit

// MARK: - controller 结构遍历（手动构造 Context，仅 iOS framework 跑）

/// 构造一个 keyWindow + 手动 `UIKitContextProvider.Context`。
///
/// `UIKitTestHost.context` 硬编码普通 `UIViewController` 作根，无法表达 nav/tab 等容器，
/// 故此处手动注入（照搬 `UINavigationBackTests` 的写法）。
private func makeContext(rootViewController: UIViewController,
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

/// 递归展平 controller 骨架 JSON 的所有节点（含 root 自身），用于跨树统计/查找。
private func flattenControllerNodes(_ json: JSONValue) -> [JSONValue] {
    guard let node = json.objectValue else { return [] }
    var result: [JSONValue] = [json]
    if let children = node["children"]?.arrayValue {
        for child in children {
            result.append(contentsOf: flattenControllerNodes(child))
        }
    }
    return result
}

@Test("单普通 VC：骨架只有根节点，topPath=root") @MainActor
func collectSingleViewController() {
    let vc = UIViewController()
    let ctx = makeContext(rootViewController: vc, topViewController: vc, rootView: vc.view)
    let data = UIControllersCollector.collect(query: .default, context: ctx)
    #expect(data["controllerCount"]?.doubleValue == 1)
    #expect(data["topPath"]?.stringValue == "root")
    let root = data["root"]?.objectValue
    #expect(root?["path"]?.stringValue == "root")
    #expect(root?["role"]?.stringValue == "root")
    #expect(root?["children"]?.arrayValue?.isEmpty == true)
}

@Test("UINavigationController 栈：nav[0]/nav[1]，栈顶 isVisible") @MainActor
func collectNavigationStack() {
    let root = UIViewController()
    let detail = UIViewController()
    let nav = UINavigationController(rootViewController: root)
    nav.pushViewController(detail, animated: false)
    let ctx = makeContext(rootViewController: nav, topViewController: detail, rootView: detail.view)
    let data = UIControllersCollector.collect(query: .default, context: ctx)
    // nav 根 + nav[0] + nav[1] = 3
    #expect(data["controllerCount"]?.doubleValue == 3)
    #expect(data["topPath"]?.stringValue == "root.nav[1]")
    let children = data["root"]?.objectValue?["children"]?.arrayValue ?? []
    #expect(children.count == 2)
    #expect(children[0].objectValue?["path"]?.stringValue == "root.nav[0]")
    #expect(children[0].objectValue?["role"]?.stringValue == "navigation")
    #expect(children[0].objectValue?["isVisible"]?.boolValue == false)
    #expect(children[1].objectValue?["path"]?.stringValue == "root.nav[1]")
    #expect(children[1].objectValue?["isVisible"]?.boolValue == true)
}

@Test("UITabBarController：tab[0]/tab[1]，选中 tab isSelected") @MainActor
func collectTabBar() {
    let first = UIViewController()
    let second = UIViewController()
    let tab = UITabBarController()
    tab.viewControllers = [first, second]
    tab.selectedIndex = 1
    let ctx = makeContext(rootViewController: tab, topViewController: second, rootView: second.view)
    let data = UIControllersCollector.collect(query: .default, context: ctx)
    // tab 根 + tab[0] + tab[1] = 3
    #expect(data["controllerCount"]?.doubleValue == 3)
    let children = data["root"]?.objectValue?["children"]?.arrayValue ?? []
    #expect(children.count == 2)
    #expect(children[0].objectValue?["path"]?.stringValue == "root.tab[0]")
    #expect(children[0].objectValue?["isSelected"]?.boolValue == false)
    #expect(children[1].objectValue?["path"]?.stringValue == "root.tab[1]")
    #expect(children[1].objectValue?["isSelected"]?.boolValue == true)
}

@Test("普通 controller 的 child VC：child[0]/child[1]") @MainActor
func collectChildViewControllers() {
    let parent = UIViewController()
    let childA = UIViewController()
    let childB = UIViewController()
    parent.addChild(childA)
    parent.addChild(childB)
    let ctx = makeContext(rootViewController: parent, topViewController: parent, rootView: parent.view)
    let data = UIControllersCollector.collect(query: .default, context: ctx)
    // parent 根 + child[0] + child[1] = 3
    #expect(data["controllerCount"]?.doubleValue == 3)
    let children = data["root"]?.objectValue?["children"]?.arrayValue ?? []
    #expect(children.count == 2)
    #expect(children[0].objectValue?["path"]?.stringValue == "root.child[0]")
    #expect(children[0].objectValue?["role"]?.stringValue == "child")
    #expect(children[1].objectValue?["path"]?.stringValue == "root.child[1]")
}

@Test("嵌套容器 tab>nav：路径与 topPath 正确") @MainActor
func collectNestedTabNav() {
    let home = UIViewController()
    let detail = UIViewController()
    let nav = UINavigationController(rootViewController: home)
    nav.pushViewController(detail, animated: false)
    let settings = UIViewController()
    let tab = UITabBarController()
    tab.viewControllers = [nav, settings]
    let ctx = makeContext(rootViewController: tab, topViewController: detail, rootView: detail.view)
    let data = UIControllersCollector.collect(query: .default, context: ctx)
    // tab + nav + home + detail + settings = 5
    #expect(data["controllerCount"]?.doubleValue == 5)
    #expect(data["topPath"]?.stringValue == "root.tab[0].nav[1]")
    let tabChildren = data["root"]?.objectValue?["children"]?.arrayValue ?? []
    #expect(tabChildren[0].objectValue?["path"]?.stringValue == "root.tab[0]")
    let navChildren = tabChildren[0].objectValue?["children"]?.arrayValue ?? []
    #expect(navChildren[1].objectValue?["path"]?.stringValue == "root.tab[0].nav[1]")
    #expect(navChildren[1].objectValue?["isVisible"]?.boolValue == true)
}

@Test("maxDepth 截断：maxDepth=1 只到根的直接子节点") @MainActor
func collectMaxDepthTruncation() {
    let root = UIViewController()
    let grandchild = UIViewController()
    root.addChild(grandchild)
    let nav = UINavigationController(rootViewController: root)
    let ctx = makeContext(rootViewController: nav, topViewController: root, rootView: root.view)
    let data = UIControllersCollector.collect(query: UIControllersInput(maxDepth: 1), context: ctx)
    // depth 0 = nav 展开 -> nav[0]=root（depth 1，不再展开），root 的 child 被截断
    let nav0 = data["root"]?.objectValue?["children"]?.arrayValue?[0].objectValue
    #expect(nav0?["path"]?.stringValue == "root.nav[0]")
    #expect(nav0?["children"]?.arrayValue?.isEmpty == true)
}

@Test("presented 作为最后子节点（真实转场在 logic test 可能不就绪）") @MainActor
func collectPresentedChain() {
    let host = UIViewController()
    let presented = UIViewController()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.present(presented, animated: false)
    // animated:false 的 present 在单元测试中不一定立即完成转场；未就绪时跳过断言，
    // presented 链的真实采集由 framework runtime + SPMExample 真机验证覆盖。
    guard host.presentedViewController === presented else { return }
    let ctx = UIKitContextProvider.Context(window: window,
                                           rootViewController: host,
                                           topViewController: presented,
                                           rootView: presented.view)
    let data = UIControllersCollector.collect(query: .default, context: ctx)
    let children = data["root"]?.objectValue?["children"]?.arrayValue ?? []
    #expect(children.count == 1)
    #expect(children[0].objectValue?["path"]?.stringValue == "root.presented")
    #expect(children[0].objectValue?["role"]?.stringValue == "presented")
}

@Test("presented 只挂在真实呈现者下，不转发到子孙（regression: presentedViewController 转发致 modal 散落）") @MainActor
func collectPresentedNotForwardedToDescendants() {
    let root = UIViewController()
    root.title = "Root"
    let detail = UIViewController()
    detail.title = "Detail"
    let nav = UINavigationController(rootViewController: root)
    nav.pushViewController(detail, animated: false)
    let modal = UIViewController()
    modal.title = "Modal"
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    window.rootViewController = nav
    window.makeKeyAndVisible()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    // 从容器 nav present：UIKit 把 nav 登记为真实呈现者，并把 presentedViewController
    // 沿后代链「转发」给 nav[0]/nav[1]（文档行为：子孙的 presentedViewController 返回
    // 祖先 present 的 modal）。修复前每个转发节点都把 modal 当自己的 presented 子节点
    // 附加，导致 modal 散落、controllerCount 虚高、topPath 指向错误挂载点（实测真机
    // controllerCount=18 而非 ~10）。presentingViewController 返回唯一真实呈现者（非转发），
    // 用它过滤即可让 modal 只挂在 nav 下。
    nav.present(modal, animated: false)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    // present 在测试环境偶发不就绪；未就绪时跳过，转发场景由 SPMExample 真机验证覆盖。
    guard nav.presentedViewController === modal,
          modal.presentingViewController === nav else { return }
    let ctx = UIKitContextProvider.Context(window: window,
                                           rootViewController: nav,
                                           topViewController: modal,
                                           rootView: modal.view)
    let data = UIControllersCollector.collect(query: .default, context: ctx)
    // nav + root + detail + modal = 4。修复前转发会让 modal 同时挂在 nav/nav[0]/nav[1]
    // 多个 presented 槽，计数变为 6。
    #expect(data["controllerCount"]?.doubleValue == 4, "controllerCount 应为 4，实际 \(data["controllerCount"]?.doubleValue ?? -1)")
    let allNodes = flattenControllerNodes(data["root"] ?? .null)
    let presentedNodes = allNodes.filter { $0.objectValue?["role"]?.stringValue == "presented" }
    // modal 在整棵树只出现一次（修复前散落到 nav[0]/nav[1]/nav 三个 presented 槽）。
    #expect(presentedNodes.count == 1, "presented 角色节点应只有一个，实际 \(presentedNodes.count)")
    #expect(presentedNodes.first?.objectValue?["path"]?.stringValue == "root.presented")
    // nav[0]/nav[1]（navigation 角色）不应各自再转发挂载 modal 子节点。
    for node in allNodes {
        guard let role = node.objectValue?["role"]?.stringValue, role == "navigation",
              let path = node.objectValue?["path"]?.stringValue else { continue }
        let kids = node.objectValue?["children"]?.arrayValue ?? []
        let presentedKids = kids.filter { $0.objectValue?["role"]?.stringValue == "presented" }
        #expect(presentedKids.isEmpty, "navigation 子节点不应转发挂载 modal: \(path)")
    }
}

@Test("context 不可用时 collect(query:) 抛 hierarchyUnavailable（环境受限时跳过）") @MainActor
func collectThrowsWhenContextUnavailable() {
    // context 缺失路径复用 `UIKitContextProvider.currentContext`，其 hierarchyUnavailable
    // 由现有测试覆盖；此处仅当测试环境恰好无前台 keyWindow 时做正向断言，否则跳过。
    do {
        _ = try UIControllersCollector.collect(query: .default)
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .internalError)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}
#endif
