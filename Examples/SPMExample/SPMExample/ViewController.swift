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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "iOSExploreServer"
        setupLayout()
        updateStatus(running: false)

        // 顶部导航入口：进入 UIControl 测试页（供 ui.control.sendAction 命令压测）
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "控件测试",
            style: .plain,
            target: self,
            action: #selector(openControlTest)
        )

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
        Task {
            do { try await server.start() }
            catch { appendLog("启动失败：\(error)") }
        }
    }

    @objc private func stopTapped() {
        server.stop()
    }

    /// push 进入 UIControl 测试页（载体页供 ui.control.sendAction 远程触发）。
    @objc private func openControlTest() {
        navigationController?.pushViewController(ControlTestViewController(), animated: true)
    }

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
