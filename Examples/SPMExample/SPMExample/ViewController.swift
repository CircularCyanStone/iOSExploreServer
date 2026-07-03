//
//  ViewController.swift
//  SPMExample
//
//  Created by 李奇奇 on 2026/6/21.
//

import UIKit
import iOSExploreServer
import iOSExploreUIKit

private struct ExampleGreetingInput: CommandInput {
    static let nameField = CommandFields.optionalString("name", description: "名字；缺省时返回 world")
    static let inputSchema = CommandInputSchema(fields: [nameField.erased])

    let name: String

    static func parse(decoding decoder: inout CommandInputDecoder) throws -> ExampleGreetingInput {
        ExampleGreetingInput(name: try decoder.read(nameField) ?? "world")
    }
}

final class ViewController: UIViewController {
    private let server = ExploreServer()
    private var logLines: [String] = []
    private let statusLabel = UILabel()
    private let startButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)
    private let tableView = UITableView()
    private nonisolated(unsafe) var eventsTask: Task<Void, Never>?
    #if DEBUG
    private var didRunLaunchAutomation = false
    #endif

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "iOSExploreServer"
        setupLayout()
        updateStatus(running: false)

        // 顶部导航入口：进入 UIControl 测试页（供 ui.control.sendAction 命令压测）。
        // 同时是 `ui.navigation.tapBarButton` 的真实闭环样本：补稳定 identifier，让 Agent
        // 观察到 `navigationBar.rightItems[0]` 后可带 identifier 二次确认再触发，而不是坐标硬点。
        let controlTestItem = UIBarButtonItem(
            title: "控件测试",
            style: .plain,
            target: self,
            action: #selector(openControlTest)
        )
        controlTestItem.accessibilityIdentifier = "example.controlTest"
        navigationItem.rightBarButtonItem = controlTestItem

        // 顶部导航左上角入口：进入 UIAlertController 测试页（供 ui.alert.respond 观察系统标准弹窗）。
        // 与右侧「控件测试」对称，同样补稳定 identifier，供 ui.navigation.tapBarButton 真实闭环。
        let alertTestItem = UIBarButtonItem(
            title: "弹窗测试",
            style: .plain,
            target: self,
            action: #selector(openAlertTest)
        )
        alertTestItem.accessibilityIdentifier = "example.alertTest"
        navigationItem.leftBarButtonItem = alertTestItem

        // 演示自定义命令 + UIKit 信息注入(register 同步,无需 Task)
        server.register(action: "greet", description: "按 name 打招呼", input: ExampleGreetingInput.self) { input in
            .success(["message": .string("Hello, \(input.name)")])
        }
        server.register(action: "device", description: "返回设备机型与名称(UIKit 注入)", input: EmptyCommandInput.self) { _ in
            return await MainActor.run {
                .success(["model": .string(UIDevice.current.model),
                          "name": .string(UIDevice.current.name)])
            }
        }

        // 显式开放 UIKit 命令（ui.topViewHierarchy / ui.viewTargets /
        // ui.control.sendAction / ui.tap）。core 不自动注册，由宿主决定是否启用。
        server.registerUIKitCommands()

        // 订阅事件 → 日志面板
        eventsTask = Task { @MainActor [weak self, server] in
            for await event in server.events() {
                guard let self else { return }
                self.appendLog(Self.describe(event))
                // 只有生命周期事件改变运行状态；请求/响应事件只记日志，
                // 否则每来一个 curl 都会把 UI 误显示为「已停止」（server 其实仍在监听）。
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
        statusLabel.font = .systemFont(ofSize: 15, weight: .medium)
        startButton.setTitle("启动 Server", for: .normal)
        stopButton.setTitle("停止", for: .normal)
        startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)

        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = UIStackView(arrangedSubviews: [startButton, stopButton])
        buttonRow.spacing = 16
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let header = UIStackView(arrangedSubviews: [statusLabel, buttonRow])
        header.axis = .vertical
        header.spacing = 12
        header.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(header)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            tableView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func startTapped() {
        startServer()
    }

    /// 启动 ExploreServer 并把失败写入日志面板。
    ///
    /// 手动按钮和 Debug 启动参数共用同一条路径，避免测试工具自动启动 server 时走另一份逻辑。
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

    /// push 进入 UIControl 测试页（载体页供 ui.control.sendAction 远程触发）。
    @objc private func openControlTest() {
        navigationController?.pushViewController(ControlTestViewController(), animated: true)
    }

    /// push 进入 UIAlertController 测试页（载体页供 ui.alert.respond 远程观察系统标准弹窗）。
    @objc private func openAlertTest() {
        navigationController?.pushViewController(AlertTestViewController(), animated: true)
    }

    #if DEBUG
    /// Debug 测试工具启动入口。
    ///
    /// 真实闭环验证不能依赖先远程点击“启动 Server”按钮，因为 server 未启动时 HTTP 命令本身
    /// 不可达。这里读取启动参数/环境变量，允许 XcodeBuildMCP 或 xcodebuild launch 时自动启动
    /// server，并可选进入弹窗测试页。未传这些开关时，示例 App 的手动体验保持不变。
    private func runLaunchAutomationIfNeeded() {
        guard !didRunLaunchAutomation else { return }
        didRunLaunchAutomation = true

        let arguments = Set(ProcessInfo.processInfo.arguments)
        let environment = ProcessInfo.processInfo.environment
        let shouldAutostart = arguments.contains("--ios-explore-autostart")
            || environment["IOS_EXPLORE_AUTOSTART"] == "1"
        let shouldOpenAlertTest = arguments.contains("--ios-explore-open-alert-test")
            || environment["IOS_EXPLORE_OPEN_ALERT_TEST"] == "1"
        print("iOSExplore launch automation autostart=\(shouldAutostart) openAlertTest=\(shouldOpenAlertTest) arguments=\(ProcessInfo.processInfo.arguments)")

        if shouldAutostart {
            appendLog("launch automation: start server")
            startServer()
        }
        if shouldOpenAlertTest {
            appendLog("launch automation: open alert test")
            openAlertTest()
        }
    }
    #endif

    @MainActor
    private func updateStatus(running: Bool) {
        statusLabel.text = running ? "● 监听中 :\(serverPort)" : "○ 已停止"
        statusLabel.textColor = running ? .systemGreen : .secondaryLabel
    }

    private var serverPort: UInt16 { 38321 }

    @MainActor
    private func appendLog(_ line: String) {
        logLines.insert(line, at: 0)
        if logLines.count > 200 { logLines.removeLast() }
        tableView.reloadData()
    }

    private static func describe(_ event: ServerEvent) -> String {
        switch event {
        case .started(let port): return "started :\(port)"
        case .stopped: return "stopped"
        case .received(_, _, let action): return "← POST action=\(action ?? "?")"
        case .responded(let status, let ok): return "→ \(status) ok=\(ok)"
        case .error(let msg): return "error \(msg)"
        }
    }
}

extension ViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { logLines.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.text = logLines[indexPath.row]
        config.textProperties.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        cell.contentConfiguration = config
        return cell
    }
}
