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

private struct ExampleGreetingInput: CommandInput {
    static let nameField = CommandFields.optionalString("name", description: "名字；缺省时返回 world")
    static let inputSchema = CommandInputSchema(fields: [nameField.erased])

    let name: String

    static func parse(decoding decoder: inout CommandInputDecoder) throws -> ExampleGreetingInput {
        ExampleGreetingInput(name: try decoder.read(nameField) ?? "world")
    }
}

#if DEBUG
private struct ExampleStdIOMessageInput: CommandInput {
    static let messageField = CommandFields.optionalString("message", description: "写入 stdout/stderr 的文本；缺省时使用默认诊断 marker。")
    static let tokenField = CommandFields.optionalString("token", description: "兼容测试脚本的短 token；未传 message 时作为写入文本。")
    static let inputSchema = CommandInputSchema(fields: [messageField.erased, tokenField.erased])

    let message: String

    static func parse(decoding decoder: inout CommandInputDecoder) throws -> ExampleStdIOMessageInput {
        let messageValue = try decoder.read(messageField)
        let tokenValue = try decoder.read(tokenField)
        let message = messageValue ?? tokenValue ?? "SPMExample stdio diagnostic marker"
        return ExampleStdIOMessageInput(message: message)
    }
}
#endif

/// 主页菜单项。
private struct MenuItem {
    let title: String
    let subtitle: String
    let icon: String
    let viewControllerType: UIViewController.Type
}

final class ViewController: UIViewController {
    private let server = ExploreServer()
    private var logLines: [String] = []
    private let statusLabel = UILabel()
    private let startButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)
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
        MenuItem(title: "弹窗测试", subtitle: "5 种 UIAlertController 案例，供 ui.alert.respond 验证", icon: "🔔", viewControllerType: AlertTestViewController.self),
        MenuItem(title: "控件测试", subtitle: "UIButton / UISwitch / UISlider 等 6 类控件，供 ui.control.sendAction 验证", icon: "🎮", viewControllerType: ControlTestViewController.self),
        MenuItem(title: "日志诊断测试", subtitle: "模拟网络请求、认证、业务事件等多种场景，验证所有日志来源", icon: "📋", viewControllerType: DiagnosticsTestViewController.self),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "iOSExploreServer"
        setupLayout()
        updateStatus(running: false)

        server.register(action: "greet", description: "按 name 打招呼", input: ExampleGreetingInput.self) { input in
            .success(["message": .string("Hello, \(input.name)")])
        }
        server.register(action: "device", description: "返回设备机型与名称(UIKit 注入)", input: EmptyCommandInput.self) { _ in
            return await MainActor.run {
                .success(["model": .string(UIDevice.current.model),
                          "name": .string(UIDevice.current.name)])
            }
        }

        server.registerUIKitCommands()

        #if DEBUG
        server.registerDiagnosticsCommands(Self.exampleDiagnosticsConfiguration())
        #else
        server.registerDiagnosticsCommands(.init(captureStdout: false, captureStderr: false))
        #endif

        server.register(action: "debug.probe",
                        description: "alive probe (非 DEBUG, 验证新 binary)",
                        input: EmptyCommandInput.self) { _ in
            .success(["alive": .bool(true), "build": .string("gesture-adapter-2026-07-04")])
        }

        server.register(action: "debug.emitAppLog",
                        description: "写入一条 SPMExample bridge 诊断日志",
                        input: EmptyCommandInput.self) { _ in
            ExploreAppLog.emit(.info,
                               category: "spm.example",
                               message: "SPMExample bridge diagnostic marker")
            return .success(["emitted": .bool(true)])
        }

        #if DEBUG
        server.register(action: "debug.emitStdout",
                        description: "向 stdout 写入一条 SPMExample 诊断文本",
                        input: ExampleStdIOMessageInput.self) { input in
            Self.emitStdIOMessage(input.message, source: "stdout")
        }
        server.register(action: "debug.emitStderr",
                        description: "向 stderr 写入一条 SPMExample 诊断文本",
                        input: ExampleStdIOMessageInput.self) { input in
            Self.emitStdIOMessage(input.message, source: "stderr")
        }
        server.register(action: "debug.emitNSLog",
                        description: "通过 NSLog 写入一条 SPMExample 诊断文本",
                        input: ExampleStdIOMessageInput.self) { input in
            Self.emitNSLogMessage(input.message)
        }
        server.register(action: "debug.emitOSLog",
                        description: "通过 os_log 写入一条 SPMExample 诊断文本",
                        input: ExampleStdIOMessageInput.self) { input in
            Self.emitOSLogMessage(input.message)
        }
        server.register(action: "debug.emitLogger",
                        description: "通过 Swift Logger 写入一条 SPMExample 诊断文本",
                        input: ExampleStdIOMessageInput.self) { input in
            Self.emitLoggerMessage(input.message)
        }
        #endif

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

            // 启动/停止按钮行
            startButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            startButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            startButton.heightAnchor.constraint(equalToConstant: 36),

            stopButton.centerYAnchor.constraint(equalTo: startButton.centerYAnchor),
            stopButton.leadingAnchor.constraint(equalTo: startButton.trailingAnchor, constant: 16),
            stopButton.heightAnchor.constraint(equalToConstant: 36),

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

        let arguments = Set(ProcessInfo.processInfo.arguments)
        let environment = ProcessInfo.processInfo.environment
        let shouldAutostart = true
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

    private func openAlertTest() {
        navigationController?.pushViewController(AlertTestViewController(), animated: true)
    }
}

// MARK: - Diagnostics 配置 & Debug 命令
extension ViewController {
    #if DEBUG
    static func exampleDiagnosticsConfiguration() -> DiagnosticsConfiguration {
        DiagnosticsConfiguration(captureStdout: true,
                                 captureStderr: true,
                                 captureNSLog: true,
                                 captureOSLog: true)
    }

    nonisolated static func emitStdIOMessage(_ message: String, source: String) -> ExploreResult {
        let line = message + "\n"
        let data = Data(line.utf8)
        switch source {
        case "stdout":
            FileHandle.standardOutput.write(data)
        case "stderr":
            FileHandle.standardError.write(data)
        default:
            return .failure(code: .invalidData, message: "unsupported stdio source")
        }
        ExploreAppLog.emit(.info,
                           category: "spm.example.stdio",
                           message: "SPMExample \(source) debug command wrote bytes=\(data.count)")
        return .success([
            "source": .string(source),
            "message": .string(message),
            "bytes": .double(Double(data.count)),
        ])
    }

    static func emitStdIOMessageForTesting(_ message: String, source: String) -> ExploreResult {
        emitStdIOMessage(message, source: source)
    }

    nonisolated static func emitNSLogMessage(_ message: String) -> ExploreResult {
        NSLog("%@", message)
        ExploreAppLog.emit(.info,
                           category: "spm.example.nslog",
                           message: "SPMExample NSLog debug command emitted")
        return .success([
            "source": .string("nslog"),
            "message": .string(message),
        ])
    }

    static func emitNSLogMessageForTesting(_ message: String) -> ExploreResult {
        emitNSLogMessage(message)
    }

    nonisolated static func emitOSLogMessage(_ message: String) -> ExploreResult {
        os_log("%{public}@", log: OSLog(subsystem: "com.coo.SPMExample",
                                        category: "diagnostics"),
               type: .error,
               message)
        return .success([
            "source": .string("oslog"),
            "message": .string(message),
            "api": .string("os_log"),
        ])
    }

    static func emitOSLogMessageForTesting(_ message: String) -> ExploreResult {
        emitOSLogMessage(message)
    }

    nonisolated static func emitLoggerMessage(_ message: String) -> ExploreResult {
        if #available(iOS 14.0, macOS 11.0, *) {
            let logger = Logger(subsystem: "com.coo.SPMExample", category: "diagnostics")
            logger.error("\(message, privacy: .public)")
            return .success([
                "source": .string("oslog"),
                "message": .string(message),
                "api": .string("Logger"),
            ])
        }
        return .failure(code: .unsupportedTarget,
                        message: "Swift Logger requires iOS 14 or newer.")
    }

    static func emitLoggerMessageForTesting(_ message: String) -> ExploreResult {
        emitLoggerMessage(message)
    }

    static func stdIOMessageForTesting(data: JSON) throws -> String {
        try ExampleStdIOMessageInput.parse(from: data).message
    }
    #endif

    #if DEBUG
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
        tableView.deselectRow(at: indexPath, animated: true)
        guard tableView.tag != 100 else { return }

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
