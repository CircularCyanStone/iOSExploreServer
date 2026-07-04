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
    /// 手势 adapter 真机验证 view：挂 `UITapGestureRecognizer`，target-action 累加计数并回写
    /// accessibilityLabel，供 `ui.tap`（gesture 分支）远程触发后用 `debug.gestureTapCount` 校验副作用。
    private let gestureDemoLabel = UILabel()
    private var gestureTapCount = 0
    private nonisolated(unsafe) var eventsTask: Task<Void, Never>?
    #if DEBUG
    private var didRunLaunchAutomation = false
    /// 合成触摸 spike 最近一次结果（供 `debug.syntheticTapSpike` 命令读取，真机验证用）。
    private var lastSyntheticTapSpikeResult = "not run"
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

        // 非 #if DEBUG probe：确认 viewDidLoad 执行 + 设备跑的是新 binary（含本改动）。
        server.register(action: "debug.probe",
                        description: "alive probe (非 DEBUG, 验证新 binary)",
                        input: EmptyCommandInput.self) { _ in
            .success(["alive": .bool(true), "build": .string("gesture-adapter-2026-07-04")])
        }

        // 手势 adapter 真机验证：回读 gestureDemoLabel 的 tap 计数，校验 ui.tap gesture 分支
        // 触发的 target-action 副作用真发生（不只是 executor 派发）。
        server.register(action: "debug.gestureTapCount",
                        description: "返回 gesture demo view 的 tap 计数（手势 adapter 验证）",
                        input: EmptyCommandInput.self) { [weak self] _ in
            await MainActor.run {
                .success(["count": .double(Double(self?.gestureTapCount ?? -1))])
            }
        }

        #if DEBUG
        // Debug 工具：运行合成触摸 spike 并返回结果（真机验证 ui.tap realTouch 可行性）。
        // 非生产命令，仅用于在真实 App 进程确认模拟器结论。
        server.register(action: "debug.syntheticTapSpike",
                        description: "运行合成触摸 spike，返回真机 4 场景结果",
                        input: EmptyCommandInput.self) { [weak self] _ in
            await MainActor.run {
                guard let self else { return .success(["result": .string("host unavailable")]) }
                self.runSyntheticTapSpike()
                return .success(["result": .string(self.lastSyntheticTapSpikeResult)])
            }
        }
        #endif

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

        // 手势 adapter 验证 view：挂 UITapGestureRecognizer。ui.viewTargets 因 hasGestureRecognizers
        // 把它列为 canonical target；ui.tap 走 gesture 分支远程触发 gestureDemoTapped。
        gestureDemoLabel.text = "👆 gesture tap: 0"
        gestureDemoLabel.accessibilityIdentifier = "example.gestureTap"
        gestureDemoLabel.accessibilityLabel = "gesture-tap-count:0"
        gestureDemoLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        gestureDemoLabel.textAlignment = .center
        gestureDemoLabel.backgroundColor = .systemBlue.withAlphaComponent(0.12)
        gestureDemoLabel.layer.cornerRadius = 8
        gestureDemoLabel.clipsToBounds = true
        gestureDemoLabel.isUserInteractionEnabled = true
        gestureDemoLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(gestureDemoTapped)))

        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = UIStackView(arrangedSubviews: [startButton, stopButton])
        buttonRow.spacing = 16
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let header = UIStackView(arrangedSubviews: [statusLabel, buttonRow, gestureDemoLabel])
        header.axis = .vertical
        header.spacing = 12
        header.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(header)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            gestureDemoLabel.heightAnchor.constraint(equalToConstant: 44),
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

    /// 手势 adapter 验证 view 的 target-action：累加计数并回写 label 文本 + accessibilityLabel。
    /// ui.tap 的 gesture 分支远程触发它；`debug.gestureTapCount` 回读计数校验副作用真发生。
    @objc private func gestureDemoTapped() {
        gestureTapCount += 1
        gestureDemoLabel.text = "👆 gesture tap: \(gestureTapCount)"
        gestureDemoLabel.accessibilityLabel = "gesture-tap-count:\(gestureTapCount)"
        appendLog("gesture demo tapped: \(gestureTapCount)")
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
        let shouldRunSyntheticTapTest = arguments.contains("--ios-explore-synthetic-tap-test")
            || environment["IOS_EXPLORE_SYNTHETIC_TAP_TEST"] == "1"
        print("iOSExplore launch automation autostart=\(shouldAutostart) openAlertTest=\(shouldOpenAlertTest) syntheticTap=\(shouldRunSyntheticTapTest) arguments=\(ProcessInfo.processInfo.arguments)")

        if shouldAutostart {
            appendLog("launch automation: start server")
            startServer()
        }
        if shouldOpenAlertTest {
            appendLog("launch automation: open alert test")
            openAlertTest()
        }
        if shouldRunSyntheticTapTest {
            appendLog("launch automation: synthetic tap test")
            // 延迟让 view 完成 appear + 布局，再在真实 key window 上合成触摸。
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 800_000_000)
                self?.runSyntheticTapSpike()
            }
        }
    }

    /// 真机合成触摸 spike：在真实 App 进程（有 UIApplication / gestureEnvironment / scene）
    /// 跑 4 场景，验证 `explore_sendSyntheticTap` 在真实 key window 上能否触发
    /// gesture / plain view / 遮挡 / UIButton。结果存 `lastSyntheticTapSpikeResult`。
    @MainActor
    private func runSyntheticTapSpike() {
        guard let window = view.window else {
            lastSyntheticTapSpikeResult = "no window"
            print("[synthetic-tap-spike] REAL aborted: no window")
            return
        }
        let result = SyntheticTapSpikeRunner.runAll(in: view, window: window)
        lastSyntheticTapSpikeResult = String(describing: result)
        print("[synthetic-tap-spike] REAL iOS \(UIDevice.current.systemVersion) \(result)")
        appendLog("synthetic tap: \(result)")
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

#if DEBUG
/// 真机合成触摸 spike runner：在真实 App 进程跑 4 个场景，汇总结果。
///
/// 场景对齐 `UITouchSyntheticSpikeTests`（gesture / plain view / 遮挡 / UIButton），
/// 但运行在真实 key window 上（有 UIApplication、gestureEnvironment、scene），用于确认
/// 模拟器结论（iOS 26 UIEvent touches 挂载失败）在真机同样成立。
@MainActor
enum SyntheticTapSpikeRunner {
    /// spike 4 场景结果汇总。
    struct Result: CustomStringConvertible {
        var gestureFired = false
        var plainBegan = 0
        var plainEnded = 0
        var overlayFired = false
        var bottomFired = false
        var buttonFired = false
        var hitTestDescription = "nil"
        var attachedTouchCount = -1
        var missing: [String] = []

        var description: String {
            "gesture=\(gestureFired) plainBegan=\(plainBegan) plainEnded=\(plainEnded) "
                + "overlay=\(overlayFired) bottom=\(bottomFired) button=\(buttonFired) "
                + "hitTest=\(hitTestDescription) attached=\(attachedTouchCount) missing=\(missing)"
        }
    }

    /// 手势 / target-action 计数器（gesture 的 target 是弱引用，由 `runAll` 局部变量强持有）。
    @MainActor
    final class Counter: NSObject {
        var fired = false
        @objc func didTap() { fired = true }
    }

    /// 普通 view touches 计数器（非 UIControl）。
    @MainActor
    final class Recorder: UIView {
        var began = 0
        var ended = 0
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { began &+= 1 }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { ended &+= 1 }
    }

    /// 在 container（已挂 window）上跑 4 场景，返回汇总。
    ///
    /// 每个场景临时把测试 view 加到 container 顶层，合成 tap 其中心点（转 window 坐标），
    /// 跑完移除，互不干扰。counter / recorder 由本方法局部变量强持有，sendTap 同步验证期间 alive。
    static func runAll(in container: UIView, window: UIWindow) -> Result {
        var r = Result()
        let frame = CGRect(x: 40, y: 260, width: 120, height: 120)
        let centerInContainer = CGPoint(x: frame.midX, y: frame.midY)

        // 场景 1：UITapGestureRecognizer（手势识别器路径）。
        let gCounter = Counter()
        let gView = UIView(frame: frame)
        gView.backgroundColor = .systemRed.withAlphaComponent(0.3)
        gView.addGestureRecognizer(UITapGestureRecognizer(target: gCounter, action: #selector(Counter.didTap)))
        container.addSubview(gView)
        container.layoutIfNeeded()
        let gDiag = window.explore_sendSyntheticTap(at: container.convert(centerInContainer, to: window))
        r.gestureFired = gCounter.fired
        r.hitTestDescription = gDiag.hitTestViewDescription ?? "nil"
        r.attachedTouchCount = gDiag.attachedTouchCount
        r.missing = gDiag.missingFields
        gView.removeFromSuperview()

        // 场景 2：普通 UIView touchesBegan/Ended（非 UIControl）。
        let pView = Recorder(frame: frame)
        container.addSubview(pView)
        container.layoutIfNeeded()
        _ = window.explore_sendSyntheticTap(at: container.convert(centerInContainer, to: window))
        r.plainBegan = pView.began
        r.plainEnded = pView.ended
        pView.removeFromSuperview()

        // 场景 3：透明遮挡——底层 + 完全覆盖的遮挡层，合成 tap 应命中遮挡层而非底层。
        let bCounter = Counter()
        let oCounter = Counter()
        let bView = UIView(frame: frame)
        bView.addGestureRecognizer(UITapGestureRecognizer(target: bCounter, action: #selector(Counter.didTap)))
        let oView = UIView(frame: frame)
        oView.addGestureRecognizer(UITapGestureRecognizer(target: oCounter, action: #selector(Counter.didTap)))
        container.addSubview(bView)
        container.addSubview(oView)
        container.layoutIfNeeded()
        _ = window.explore_sendSyntheticTap(at: container.convert(centerInContainer, to: window))
        r.bottomFired = bCounter.fired
        r.overlayFired = oCounter.fired
        bView.removeFromSuperview()
        oView.removeFromSuperview()

        // 场景 4：UIButton touchUpInside（与 default 模式兼容）。
        var buttonFired = false
        let button = UIButton(type: .system)
        button.setTitle("Spike", for: .normal)
        button.frame = frame
        button.addAction(UIAction { _ in buttonFired = true }, for: .touchUpInside)
        container.addSubview(button)
        container.layoutIfNeeded()
        _ = window.explore_sendSyntheticTap(at: container.convert(centerInContainer, to: window))
        r.buttonFired = buttonFired
        button.removeFromSuperview()

        return r
    }
}
#endif
