//
//  ViewController.swift
//  SPMExample
//
//  Created by 李奇奇 on 2026/6/21.
//

import UIKit
import OSLog
import iOSExploreServer
import iOSExploreUIKit
import iOSExploreDiagnostics

/// 主页菜单项。
private struct MenuItem {
    let title: String
    let subtitle: String
    let icon: String
    let viewControllerType: UIViewController.Type
}

final class ViewController: UIViewController {
    /// 使用 AppDelegate 中的全局 server 实例
    private var server: ExploreServer {
        return AppDelegate.shared.server
    }

    private var logLines: [String] = []
    private let statusLabel = UILabel()
    private let startButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)
    private let diagTabBarButton = UIButton(type: .system)
    private let menuTableView = UITableView()
    private let logTableView = UITableView()
    private let gestureDemoLabel = UILabel()
    private var gestureTapCount = 0
    private nonisolated(unsafe) var eventsTask: Task<Void, Never>?
#if DEBUG
    private var didRunLaunchAutomation = false
#endif

    /// 功能菜单数据。
    private let menuItems: [MenuItem] = [
        MenuItem(title: "导航与截图测试", subtitle: "导航栏按钮、push/pop、present/dismiss、多级导航，供 ui.navigation.* 和 ui.screenshot 验证", icon: "🧭", viewControllerType: NavigationTestViewController.self),
        MenuItem(title: "弹窗测试", subtitle: "5 种 UIAlertController 案例，供 ui.alert.respond 验证", icon: "🔔", viewControllerType: AlertTestViewController.self),
        MenuItem(title: "控件测试", subtitle: "UIButton / UISwitch / UISlider 等 6 类控件，供 ui.control.sendAction 验证", icon: "🎮", viewControllerType: ControlTestViewController.self),
        MenuItem(title: "Controller 结构测试", subtitle: "Navigation / Tab / Modal / Child / Split 等多层嵌套结构，供 ui.controllers 验证", icon: "🏗️", viewControllerType: ControllerStructureTestViewController.self),
        MenuItem(title: "日志诊断测试", subtitle: "模拟网络请求、认证、业务事件等多种场景，验证所有日志来源", icon: "📋", viewControllerType: DiagnosticsTestViewController.self),
        MenuItem(title: "滚动测试", subtitle: "UICollectionView + 30 个 cell，供 ui.scrollToElement 验证", icon: "📜", viewControllerType: ScrollTestViewController.self),
        MenuItem(title: "Wait 测试", subtitle: "5 种 waitMode 动态出现/消失/变化场景,供 ui.wait / ui.waitAny 验证", icon: "⏱️", viewControllerType: WaitTestViewController.self),
        MenuItem(title: "文本输入测试", subtitle: "UITextField / UITextView / UISearchTextField 等多种文本控件，供 ui.input 和 ui.keyboard.dismiss 验证", icon: "⌨️", viewControllerType: InputTestViewController.self),
        MenuItem(title: "Swipe 测试", subtitle: "UITableView swipe actions、UISwipeGestureRecognizer、UIPanGestureRecognizer，供 ui.swipe 验证", icon: "👆", viewControllerType: SwipeTestViewController.self),
        MenuItem(title: "LongPress 测试", subtitle: "UILongPressGestureRecognizer、Cell long press selection，供 ui.longPress 验证", icon: "✋", viewControllerType: LongPressTestViewController.self),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "iOSExploreServer"
        setupLayout()
        updateStatus(running: false)

        // 监听 server 事件（命令已在 AppDelegate 中注册）
        eventsTask = Task { @MainActor [weak self, server] in
            for await event in server.events() {
                guard let self else { return }
                self.appendLog(Self.describe(event))
                switch event {
                case .started: self.updateStatus(running: true)
                case .stopped, .error: self.updateStatus(running: false)
                case .received, .responded: break
                }
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #if DEBUG
        runLaunchAutomationIfNeeded()
        #endif
    }

    deinit {
        eventsTask?.cancel()
    }

    private func setupLayout() {
        // 状态栏区域
        statusLabel.font = .systemFont(ofSize: 15, weight: .medium)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        // 手势 adapter 验证 view
        gestureDemoLabel.text = "👆 gesture tap: 0"
        gestureDemoLabel.accessibilityIdentifier = "example.gestureTap"
        gestureDemoLabel.accessibilityLabel = "gesture-tap-count:0"
        gestureDemoLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        gestureDemoLabel.textAlignment = .center
        gestureDemoLabel.backgroundColor = .systemBlue.withAlphaComponent(0.1)
        gestureDemoLabel.layer.cornerRadius = 8
        gestureDemoLabel.clipsToBounds = true
        gestureDemoLabel.isUserInteractionEnabled = true
        gestureDemoLabel.translatesAutoresizingMaskIntoConstraints = false
        gestureDemoLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(gestureDemoTapped)))

        // 启动/停止按钮
        startButton.setTitle("启动 Server", for: .normal)
        stopButton.setTitle("停止", for: .normal)
        startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
        startButton.translatesAutoresizingMaskIntoConstraints = false
        stopButton.translatesAutoresizingMaskIntoConstraints = false

        // 诊断 TabBar 按钮
        diagTabBarButton.setTitle("🔍 TabBar", for: .normal)
        diagTabBarButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        diagTabBarButton.addTarget(self, action: #selector(diagnoseTabBarTapped), for: .touchUpInside)
        diagTabBarButton.translatesAutoresizingMaskIntoConstraints = false

        // 菜单列表 — 主体区域
        menuTableView.delegate = self
        menuTableView.dataSource = self
        menuTableView.register(UITableViewCell.self, forCellReuseIdentifier: "menuCell")
        menuTableView.translatesAutoresizingMaskIntoConstraints = false
        menuTableView.isScrollEnabled = false
        menuTableView.layer.cornerRadius = 12
        menuTableView.layer.borderWidth = 1
        menuTableView.layer.borderColor = UIColor.separator.cgColor

        // 菜单标题
        let menuTitle = UILabel()
        menuTitle.text = "功能菜单"
        menuTitle.font = .systemFont(ofSize: 20, weight: .bold)
        menuTitle.translatesAutoresizingMaskIntoConstraints = false

        // 日志标题
        let logTitle = UILabel()
        logTitle.text = "事件日志"
        logTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        logTitle.textColor = .secondaryLabel
        logTitle.translatesAutoresizingMaskIntoConstraints = false

        // 日志面板 — 底部紧凑区域，自动滚动
        logTableView.dataSource = self
        logTableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        logTableView.translatesAutoresizingMaskIntoConstraints = false
        logTableView.isScrollEnabled = true
        logTableView.tag = 100
        logTableView.layer.cornerRadius = 8
        logTableView.layer.borderWidth = 1
        logTableView.layer.borderColor = UIColor.separator.cgColor
        logTableView.rowHeight = 20

        view.addSubview(statusLabel)
        view.addSubview(gestureDemoLabel)
        view.addSubview(startButton)
        view.addSubview(stopButton)
        view.addSubview(diagTabBarButton)
        view.addSubview(menuTitle)
        view.addSubview(menuTableView)
        view.addSubview(logTitle)
        view.addSubview(logTableView)

        let menuRowHeight: CGFloat = 64
        let menuTotalHeight = CGFloat(menuItems.count) * menuRowHeight

        NSLayoutConstraint.activate([
            // 状态行（顶部）
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.heightAnchor.constraint(equalToConstant: 32),

            gestureDemoLabel.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            gestureDemoLabel.leadingAnchor.constraint(equalTo: statusLabel.trailingAnchor, constant: 12),
            gestureDemoLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            gestureDemoLabel.heightAnchor.constraint(equalToConstant: 32),

            // 启动/停止按钮行 + 诊断按钮
            startButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            startButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            startButton.heightAnchor.constraint(equalToConstant: 36),

            stopButton.centerYAnchor.constraint(equalTo: startButton.centerYAnchor),
            stopButton.leadingAnchor.constraint(equalTo: startButton.trailingAnchor, constant: 16),
            stopButton.heightAnchor.constraint(equalToConstant: 36),

            diagTabBarButton.centerYAnchor.constraint(equalTo: startButton.centerYAnchor),
            diagTabBarButton.leadingAnchor.constraint(equalTo: stopButton.trailingAnchor, constant: 12),
            diagTabBarButton.heightAnchor.constraint(equalToConstant: 36),

            // 菜单标题
            menuTitle.topAnchor.constraint(equalTo: startButton.bottomAnchor, constant: 20),
            menuTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            menuTitle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            menuTitle.heightAnchor.constraint(equalToConstant: 24),

            // 菜单列表（主体区域）
            menuTableView.topAnchor.constraint(equalTo: menuTitle.bottomAnchor, constant: 8),
            menuTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            menuTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            menuTableView.heightAnchor.constraint(equalToConstant: menuTotalHeight),

            // 日志标题
            logTitle.topAnchor.constraint(equalTo: menuTableView.bottomAnchor, constant: 16),
            logTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            logTitle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            logTitle.heightAnchor.constraint(equalToConstant: 18),

            // 日志面板（底部紧凑区域）
            logTableView.topAnchor.constraint(equalTo: logTitle.bottomAnchor, constant: 4),
            logTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            logTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            logTableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])
    }
}

// MARK: - Server 控制 & 状态
extension ViewController {
    @objc private func startTapped() {
        startServer()
    }

    private func startServer() {
        Task {
            do {
                print("iOSExplore startServer begin")
                try await server.start()
                print("iOSExplore startServer success")
            } catch {
                print("iOSExplore startServer failed error=\(error)")
                appendLog("启动失败：\(error)")
            }
        }
    }

    @objc private func stopTapped() {
        server.stop()
    }

    @objc private func diagnoseTabBarTapped() {
        print("\n" + String(repeating: "=", count: 60))
        print("=== 🔍 TabBar 诊断开始 ===")
        print(String(repeating: "=", count: 60))

        // 遍历所有 window 查找 UITabBarController
        var foundTabBarControllers: [(UITabBarController, String)] = []
        for (idx, window) in UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .enumerated() {
            findTabBarControllers(in: window.rootViewController, path: "window[\(idx)].root", found: &foundTabBarControllers)
        }

        if foundTabBarControllers.isEmpty {
            print("❌ 未找到任何 UITabBarController")
            print(String(repeating: "=", count: 60))
            print("=== 🔍 TabBar 诊断结束 ===")
            print(String(repeating: "=", count: 60) + "\n")
            return
        }

        print("✅ 找到 \(foundTabBarControllers.count) 个 UITabBarController\n")

        for (tabBarController, path) in foundTabBarControllers {
            print("┌─ TabBarController @ \(path)")
            print("│  selectedIndex: \(tabBarController.selectedIndex)")
            print("│  viewControllers.count: \(tabBarController.viewControllers?.count ?? 0)")

            // 输出 UITabBar 自身信息
            let tabBar = tabBarController.tabBar
            print("│")
            print("├─ UITabBar 自身信息:")
            print("│  ├─ type: \(type(of: tabBar))")
            print("│  ├─ frame: \(tabBar.frame)")
            print("│  ├─ isHidden: \(tabBar.isHidden)")
            print("│  ├─ alpha: \(tabBar.alpha)")
            print("│  ├─ isUserInteractionEnabled: \(tabBar.isUserInteractionEnabled)")
            print("│  ├─ window: \(tabBar.window != nil ? "✓ attached" : "✗ detached")")
            print("│  ├─ superview: \(tabBar.superview != nil ? String(describing: type(of: tabBar.superview!)) : "nil")")
            print("│  └─ subviews.count: \(tabBar.subviews.count)")

            // 输出 tab button 信息（递归遍历 tabBar 整个子树找 _UITabButton）
            print("│")
            print("├─ TabButton 详细信息（递归遍历 tabBar 子树）:")
            var allButtons: [(UIView, String)] = []
            collectTabButtons(in: tabBar, path: "tabBar", buttons: &allButtons)

            if allButtons.isEmpty {
                print("│  └─ ⚠️ 未找到任何 TabButton（可能类名不匹配或未生成）")
            } else {
                for (idx, (button, buttonPath)) in allButtons.enumerated() {
                    let typeName = String(describing: type(of: button))
                    print("│  ├─ TabButton[\(idx)] (\(typeName)) @ \(buttonPath):")
                    print("│  │  ├─ frame: \(button.frame)")
                    print("│  │  ├─ isHidden: \(button.isHidden)")
                    print("│  │  ├─ alpha: \(button.alpha)")
                    print("│  │  ├─ window: \(button.window != nil ? "✓" : "✗")")
                    print("│  │  ├─ superview: \(button.superview != nil ? String(describing: type(of: button.superview!)) : "nil")")
                    print("│  │  ├─ accessibilityLabel: \(button.accessibilityLabel ?? "nil")")

                    // 输出继承链（从当前类往上到 NSObject）
                    var inheritanceChain: [String] = []
                    var currentClass: AnyClass? = type(of: button)
                    while let cls = currentClass {
                        inheritanceChain.append(String(describing: cls))
                        currentClass = class_getSuperclass(cls)
                        if inheritanceChain.count > 20 { break } // 防止无限循环
                    }
                    print("│  │  ├─ 继承链: \(inheritanceChain.joined(separator: " → "))")

                    if let control = button as? UIControl {
                        print("│  │  ├─ [UIControl] isEnabled: \(control.isEnabled)")
                        print("│  │  ├─ [UIControl] isSelected: \(control.isSelected)")
                        print("│  │  ├─ [UIControl] allTargets.count: \(control.allTargets.count)")
                        print("│  │  └─ [UIControl] allControlEvents: \(control.allControlEvents.rawValue)")
                    } else {
                        print("│  │  └─ (不是 UIControl 子类)")
                    }
                }
            }

            // 输出每个 tab 的 viewController 与对应 item
            print("│")
            print("└─ 各 Tab 的 ViewController 与 UITabBarItem:")
            if let viewControllers = tabBarController.viewControllers {
                for (idx, vc) in viewControllers.enumerated() {
                    let item = vc.tabBarItem
                    print("   ├─ Tab[\(idx)]:")
                    print("   │  ├─ VC type: \(type(of: vc))")
                    print("   │  ├─ VC.title: \(vc.title ?? "nil")")
                    print("   │  ├─ item.title: \(item?.title ?? "nil")")
                    print("   │  ├─ item.tag: \(item?.tag ?? -1)")
                    print("   │  ├─ item.image: \(item?.image != nil ? "✓ (size \(item!.image!.size))" : "nil")")
                    print("   │  ├─ item.selectedImage: \(item?.selectedImage != nil ? "✓" : "nil")")
                    print("   │  ├─ VC.view.frame: \(vc.view.frame)")
                    print("   │  ├─ VC.view.window: \(vc.view.window != nil ? "✓ attached" : "✗ detached")")
                    print("   │  ├─ VC.view.superview: \(vc.view.superview != nil ? String(describing: type(of: vc.view.superview!)) : "nil")")
                    print("   │  └─ VC.view.subviews.count: \(vc.view.subviews.count)")
                }
            }
            print("")
        }

        print(String(repeating: "=", count: 60))
        print("=== 🔍 TabBar 诊断结束 ===")
        print(String(repeating: "=", count: 60) + "\n")
    }

    /// 递归查找 controller 树中的所有 UITabBarController
    private func findTabBarControllers(in controller: UIViewController?, path: String, found: inout [(UITabBarController, String)]) {
        guard let controller else { return }

        if let tabBarController = controller as? UITabBarController {
            found.append((tabBarController, path))
            // 继续递归 selected VC
            if let selected = tabBarController.selectedViewController {
                findTabBarControllers(in: selected, path: "\(path).selected", found: &found)
            }
        } else if let navController = controller as? UINavigationController {
            // nav 栈顶
            if let top = navController.topViewController {
                findTabBarControllers(in: top, path: "\(path).nav.top", found: &found)
            }
        }

        // presented modal
        if let presented = controller.presentedViewController {
            findTabBarControllers(in: presented, path: "\(path).presented", found: &found)
        }

        // child controllers
        for (idx, child) in controller.children.enumerated() {
            findTabBarControllers(in: child, path: "\(path).child[\(idx)]", found: &found)
        }
    }

    /// 递归收集 view 子树中所有的 TabButton（类名包含 "TabButton"）
    private func collectTabButtons(in view: UIView, path: String, buttons: inout [(UIView, String)]) {
        let typeName = String(describing: type(of: view))
        if typeName.contains("TabButton") || typeName.contains("TabBarButton") {
            buttons.append((view, path))
        }
        for (idx, subview) in view.subviews.enumerated() {
            collectTabButtons(in: subview, path: "\(path)/\(idx)", buttons: &buttons)
        }
    }

    @MainActor
    private func updateStatus(running: Bool) {
        statusLabel.text = running ? "● 监听中 :\(serverPort)" : "○ 已停止"
        statusLabel.textColor = running ? .systemGreen : .secondaryLabel
    }

    private var serverPort: UInt16 { 38321 }

    @objc private func gestureDemoTapped() {
        gestureTapCount += 1
        gestureDemoLabel.text = "👆 gesture tap: \(gestureTapCount)"
        gestureDemoLabel.accessibilityLabel = "gesture-tap-count:\(gestureTapCount)"
        appendLog("gesture demo tapped: \(gestureTapCount)")
    }

    @MainActor
    private func appendLog(_ line: String) {
        logLines.insert(line, at: 0)
        if logLines.count > 200 { logLines.removeLast() }
        logTableView.reloadData()
        // 新日志自动滚动到顶部（最新在最上面）
        if logLines.isEmpty == false {
            logTableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
        }
    }
}

// MARK: - Launch Automation
extension ViewController {
    private func runLaunchAutomationIfNeeded() {
        guard !didRunLaunchAutomation else { return }
        didRunLaunchAutomation = true

        // server 已在 AppDelegate.didFinishLaunchingWithOptions 中启动，
        // 这里只负责根据启动参数打开特定测试页面。
        let arguments = Set(ProcessInfo.processInfo.arguments)
        let environment = ProcessInfo.processInfo.environment

        let shouldOpenAlertTest = arguments.contains("--ios-explore-open-alert-test")
            || environment["IOS_EXPLORE_OPEN_ALERT_TEST"] == "1"
        let shouldOpenSwipeTest = arguments.contains("--ios-explore-open-swipe-test")
            || environment["IOS_EXPLORE_OPEN_SWIPE_TEST"] == "1"
        let shouldOpenLongPressTest = arguments.contains("--ios-explore-open-longpress-test")
            || environment["IOS_EXPLORE_OPEN_LONGPRESS_TEST"] == "1"

        if shouldOpenAlertTest {
            appendLog("launch automation: open alert test")
            openAlertTest()
        }
        if shouldOpenSwipeTest {
            appendLog("launch automation: open swipe test")
            openSwipeTest()
        }
        if shouldOpenLongPressTest {
            appendLog("launch automation: open longPress test")
            openLongPressTest()
        }
    }

    private func openAlertTest() {
        navigationController?.pushViewController(AlertTestViewController(), animated: true)
    }

    private func openSwipeTest() {
        navigationController?.pushViewController(SwipeTestViewController(), animated: true)
    }

    private func openLongPressTest() {
        navigationController?.pushViewController(LongPressTestViewController(), animated: true)
    }
}

// MARK: - Diagnostics / Debug 测试入口（转发到 AppDelegate）
//
// 真正的命令注册、Diagnostics 配置和 emit 实现都在 AppDelegate（server 归属处）。
// 这里只保留测试用例调用的入口，转发到 AppDelegate，避免逻辑分散。
extension ViewController {
    #if DEBUG
    static func exampleDiagnosticsConfiguration() -> DiagnosticsConfiguration {
        AppDelegate.shared.exampleDiagnosticsConfiguration()
    }

    static func emitStdIOMessageForTesting(_ message: String, source: String) -> ExploreResult {
        AppDelegate.emitStdIOMessage(message, source: source)
    }

    static func emitNSLogMessageForTesting(_ message: String) -> ExploreResult {
        AppDelegate.emitNSLogMessage(message)
    }

    static func emitOSLogMessageForTesting(_ message: String) -> ExploreResult {
        AppDelegate.emitOSLogMessage(message)
    }

    static func emitLoggerMessageForTesting(_ message: String) -> ExploreResult {
        AppDelegate.emitLoggerMessage(message)
    }

    static func stdIOMessageForTesting(data: JSON) throws -> String {
        try AppDelegate.stdIOMessageForTesting(data: data)
    }

    func registeredCommandActionsForTesting() -> [String] {
        server.commandMetadata().map(\.action)
    }
    #endif
}

// MARK: - 日志面板 TableView
extension ViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        tableView.tag == 100 ? logLines.count : menuItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView.tag == 100 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            var config = cell.defaultContentConfiguration()
            config.text = logLines[indexPath.row]
            config.textProperties.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            cell.contentConfiguration = config
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "menuCell", for: indexPath)
            let item = menuItems[indexPath.row]
            var config = cell.defaultContentConfiguration()
            config.text = "\(item.icon)  \(item.title)"
            config.secondaryText = item.subtitle
            config.secondaryTextProperties.font = UIFont.systemFont(ofSize: 12)
            config.secondaryTextProperties.color = .secondaryLabel
            config.textProperties.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
            cell.accessoryType = .disclosureIndicator
            cell.contentConfiguration = config
            return cell
        }
    }
}

// MARK: - 菜单列表 Delegate
extension ViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        tableView.tag == 100 ? 20 : 64
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView.tag == 100 {
            // 日志行被选中时保留系统选择高亮作为可见反馈（不立即 deselect），
            // 避免 tap 返回 activated=true 但页面无可见变化。
            // 系统会在下次选中或触摸其他行时自动清除高亮。
            return
        }
        tableView.deselectRow(at: indexPath, animated: true)

        let item = menuItems[indexPath.row]
        let vc = item.viewControllerType.init()
        vc.title = item.title
        navigationController?.pushViewController(vc, animated: true)
    }

    fileprivate static func describe(_ event: ServerEvent) -> String {
        switch event {
        case .started(let port): return "started :\(port)"
        case .stopped: return "stopped"
        case .received(_, _, let action):
            let actionName = action ?? "?"
            return "← POST action=\(actionName)"
        case .responded(let status, let ok): return "→ \(status) ok=\(ok)"
        case .error(let msg): return "error \(msg)"
        }
    }
}
