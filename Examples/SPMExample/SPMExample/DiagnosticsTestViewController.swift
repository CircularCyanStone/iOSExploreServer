//
//  DiagnosticsTestViewController.swift
//  SPMExample
//
//  日志诊断测试页：模拟各种业务场景写入不同来源和等级的日志，供 `app.logs.read` / `app.logs.mark`
//  真实闭环验证。覆盖 explore、bridge、stdout、stderr、nslog、oslog 六种来源以及 debug / info /
//  error / fault 四种等级。
//

import UIKit
import OSLog
import iOSExploreServer
import iOSExploreDiagnostics

/// 日志诊断测试页。
///
/// 页面提供多种业务场景模拟按钮，每个按钮触发后会通过不同路径写入日志到 `AppLogStore`：
/// - 网络请求场景（bridge + stdout）
/// - 认证流程场景（bridge + stderr + oslog）
/// - 业务事件场景（bridge + explore）
/// - 内存告警等系统级场景（oslog + nslog）
/// - 综合链路追踪场景（全来源混合）
///
/// 所有场景写入后会显示 mark cursor，方便复制到 Mac 侧 `app.logs.read` 验证。
final class DiagnosticsTestViewController: UIViewController {

    // MARK: - 场景按钮

    private let networkRequestButton = UIButton(type: .system)
    private let authFlowButton = UIButton(type: .system)
    private let businessEventButton = UIButton(type: .system)
    private let systemAlertButton = UIButton(type: .system)
    private let fullTraceButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)

    /// 场景说明
    private let descriptionLabel = UILabel()
    private let cursorLabel = UILabel()
    private let cursorCopyButton = UIButton(type: .system)

    // MARK: - 事件流

    private let eventsView = UITextView()
    private var events: [String] = []
    private var lastMarkCursor: String?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "日志诊断测试"
        view.backgroundColor = .systemBackground
        setupControls()
        setupLayout()
    }

    // MARK: - 控件配置

    private func setupControls() {
        configureButton(networkRequestButton,
                        title: "🌐 网络请求场景",
                        subtitle: "模拟 API 请求发起和响应，写入 stdout + bridge",
                        identifier: "diagnostics.networkRequest",
                        action: #selector(simulateNetworkRequest))
        configureButton(authFlowButton,
                        title: "🔐 认证流程场景",
                        subtitle: "模拟登录流程中的调试输出和错误，写入 stdout + stderr + oslog + bridge",
                        identifier: "diagnostics.authFlow",
                        action: #selector(simulateAuthFlow))
        configureButton(businessEventButton,
                        title: "📊 业务事件场景",
                        subtitle: "模拟用户操作埋点和业务事件，写入 bridge + explore",
                        identifier: "diagnostics.businessEvent",
                        action: #selector(simulateBusinessEvent))
        configureButton(systemAlertButton,
                        title: "⚠️ 系统级场景",
                        subtitle: "模拟内存告警、配置加载失败等，写入 nslog + oslog + stderr",
                        identifier: "diagnostics.systemAlert",
                        action: #selector(simulateSystemAlert))
        configureButton(fullTraceButton,
                        title: "🔍 全链路追踪场景",
                        subtitle: "模拟一次完整用户操作在多个模块产生的全部来源日志",
                        identifier: "diagnostics.fullTrace",
                        action: #selector(simulateFullTrace))
        configureClearButton(clearButton,
                             title: "🗑 清空事件流",
                             identifier: "diagnostics.clear",
                             action: #selector(clearEvents))

        descriptionLabel.text = """
        点击场景按钮，模拟真实业务环境中的日志输出。
        每次写入后会更新 mark cursor，可用 `app.logs.read` 读取验证。
        """
        descriptionLabel.font = .systemFont(ofSize: 13)
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.numberOfLines = 0

        cursorLabel.text = "mark cursor: (尚未使用)"
        cursorLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        cursorLabel.textColor = .systemBlue
        cursorLabel.numberOfLines = 2
        cursorLabel.isUserInteractionEnabled = true
        cursorLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(copyCursor)))

        cursorCopyButton.setTitle("📋 复制 cursor", for: .normal)
        cursorCopyButton.addTarget(self, action: #selector(copyCursor), for: .touchUpInside)

        eventsView.isEditable = false
        eventsView.isScrollEnabled = true
        eventsView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        eventsView.backgroundColor = .secondarySystemBackground
        eventsView.layer.cornerRadius = 8
        eventsView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        eventsView.text = "(等待事件)"
    }

    private func configureButton(_ button: UIButton, title: String, subtitle: String, identifier: String, action: Selector) {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.subtitle = subtitle
        config.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 11)
            return outgoing
        }
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        config.baseBackgroundColor = .systemBlue.withAlphaComponent(0.15)
        config.baseForegroundColor = .label
        button.configuration = config
        button.accessibilityIdentifier = identifier
        button.addTarget(self, action: action, for: .touchUpInside)
        button.contentHorizontalAlignment = .leading
    }

    private func configureClearButton(_ button: UIButton, title: String, identifier: String, action: Selector) {
        button.setTitle(title, for: .normal)
        button.accessibilityIdentifier = identifier
        button.addTarget(self, action: action, for: .touchUpInside)
        button.setTitleColor(.systemRed, for: .normal)
    }

    // MARK: - 布局

    private func setupLayout() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        view.addSubview(scrollView)

        let sections: [UIStackView] = [
            makeSection(networkRequestButton),
            makeSection(authFlowButton),
            makeSection(businessEventButton),
            makeSection(systemAlertButton),
            makeSection(fullTraceButton),
        ]

        let cursorRow = UIStackView(arrangedSubviews: [cursorLabel, cursorCopyButton])
        cursorRow.spacing = 8
        cursorRow.alignment = .center

        let eventsTitle = UILabel()
        eventsTitle.text = "事件流（最新在顶，最多 100 条）"
        eventsTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        eventsTitle.textColor = .secondaryLabel

        let mainStack = UIStackView(arrangedSubviews: [descriptionLabel])
        sections.forEach { mainStack.addArrangedSubview($0) }
        mainStack.addArrangedSubview(cursorRow)
        mainStack.addArrangedSubview(clearButton)
        mainStack.addArrangedSubview(eventsTitle)
        mainStack.addArrangedSubview(eventsView)
        mainStack.axis = .vertical
        mainStack.spacing = 16
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),

            eventsView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
    }

    private func makeSection(_ control: UIView) -> UIStackView {
        let section = UIStackView(arrangedSubviews: [control])
        section.axis = .vertical
        section.spacing = 4
        section.alignment = .fill
        return section
    }

    // MARK: - 业务场景模拟

    /// 🌐 网络请求场景：模拟一次 API 请求的全过程。
    ///
    /// 产生来源：stdout（curl 日志）+ bridge（业务埋点）+ explore（iOSExplore 内部）
    @objc private func simulateNetworkRequest() {
        logEvent("🌐 网络请求场景开始")
        let requestID = UUID().uuidString.prefix(8)
        let endpoint = "/api/v2/users/profile"

        // stdout: 模拟 curl 调试日志
        print("[Network] [\(requestID)] → GET \(endpoint)")
        print("[Network] [\(requestID)] headers: Authorization=Bearer ***, Accept=application/json")
        print("[Network] [\(requestID)] ← 200 OK")
        print("[Network] [\(requestID)] body: {\"id\": 1024, \"name\": \"Alice\", \"role\": \"admin\"}")

        // bridge: 业务埋点
        ExploreAppLog.emit(.info, category: "network.api",
                           message: "API request completed action=getUserProfile status=200 latency=342ms")
        ExploreAppLog.emit(.debug, category: "network.api",
                           message: "API response decoded count=1 fields=[id,name,role]")
        ExploreAppLog.emit(.info, category: "network.api",
                           message: "API request metadata recorded",
                           metadata: ["requestID": String(requestID),
                                      "endpoint": endpoint,
                                      "statusCode": "200",
                                      "latency": "342ms"])

        // oslog: 系统日志记录
        os_log("[Network] [%{public}@] GET %{public}@ completed with status 200",
               log: OSLog(subsystem: "com.coo.SPMExample", category: "network"),
               type: .info, String(requestID), endpoint)

        logEvent("  ✓ stdout × 4, bridge × 3, oslog × 1")
        updateMarkCursor()
    }

    /// 🔐 认证流程场景：模拟登录、Token 刷新、鉴权失败等。
    ///
    /// 产生来源：stdout（调试输出）+ stderr（错误）+ oslog（系统日志）+ bridge（业务埋点）
    @objc private func simulateAuthFlow() {
        logEvent("🔐 认证流程场景开始")
        let token = UUID().uuidString.prefix(8)

        // stdout: 调试输出
        print("[Auth] token refresh requested for session=abc-123")
        print("[Auth] new token=\(token) (expires in 3600s)")

        // stderr: 模拟错误输出
        fputs("[Auth] WARNING: previous token expired at 2026-07-05T10:00:00Z\n", stderr)
        fputs("[Auth] ERROR: token validation failed for endpoint /api/v2/admin (retry=1/3)\n", stderr)
        fputs("[Auth] INFO: retry succeeded on attempt 2/3\n", stderr)

        // bridge: 认证业务埋点
        ExploreAppLog.emit(.info, category: "auth.token",
                           message: "Token refreshed session=abc-123 expiresIn=3600s")
        ExploreAppLog.emit(.error, category: "auth.validation",
                           message: "Token validation failed endpoint=/api/v2/admin retryCount=1")
        ExploreAppLog.emit(.info, category: "auth.validation",
                           message: "Token refresh succeeded endpoint=/api/v2/admin retryCount=2")
        ExploreAppLog.emit(.fault, category: "auth.session",
                           message: "Session abc-123: refresh threshold exceeded, forcing re-login")

        // oslog
        os_log("[Auth] session=abc-123 token refresh completed",
               log: OSLog(subsystem: "com.coo.SPMExample", category: "auth"),
               type: .info)
        os_log("[Auth] endpoint=%{public}@ retry=1/3: 401 Unauthorized",
               log: OSLog(subsystem: "com.coo.SPMExample", category: "auth"),
               type: .error, "/api/v2/admin")

        logEvent("  ✓ stdout × 2, stderr × 3, bridge × 4, oslog × 2")
        updateMarkCursor()
    }

    /// 📊 业务事件场景：模拟用户操作埋点。
    ///
    /// 产生来源：bridge + explore + ioslog
    @objc private func simulateBusinessEvent() {
        logEvent("📊 业务事件场景开始")

        let operations = ["PageView", "ButtonClick", "Swipe", "Scroll", "PullToRefresh"]
        for (i, op) in operations.enumerated() {
            let duration = Int.random(in: 10...500)
            ExploreAppLog.emit(.info, category: "analytics.user",
                               message: "userEvent name=\(op) duration=\(duration)ms",
                               metadata: ["eventIndex": "\(i)", "duration": "\(duration)ms"])

            if op == "ButtonClick" {
                ExploreAppLog.emit(.debug, category: "analytics.user",
                                   message: "userEvent action=buttonTap target=example.controlTest position=(120,340)")
            }
        }

        // UIKit 交互相关
        fputs("[Analytics] INFO: rendering completed for page=UserProfile in 45ms\n", stderr)
        print("[Analytics] debug: touch event at (120, 340) on example.controlTest")

        ExploreAppLog.emit(.info, category: "analytics.performance",
                           message: "Page UserProfile rendered in 45ms domNodes=127")

        os_log("[Analytics] page=UserProfile impression recorded",
               log: OSLog(subsystem: "com.coo.SPMExample", category: "analytics"),
               type: .info)

        logEvent("  ✓ bridge × 6, stderr × 1, stdout × 1, oslog × 1")
        updateMarkCursor()
    }

    /// ⚠️ 系统级场景：模拟内存告警、配置加载失败等。
    ///
    /// 产生来源：nslog + oslog + stderr + bridge
    @objc private func simulateSystemAlert() {
        logEvent("⚠️ 系统级场景开始")

        // NSLog: 遗留系统告警
        NSLog("[System] [WARNING] Memory pressure: Footprint=145MB (warning at 140MB)")
        NSLog("[System] [ERROR] ImageCache: Failed to evict expired entries count=12 error=disk_full")
        usleep(50_000)

        // oslog: 系统级日志
        os_log("[System] memory warning received footprint=%{public}dMB threshold=%{public}dMB",
               log: OSLog(subsystem: "com.coo.SPMExample", category: "system"),
               type: .fault, 145, 140)
        os_log("[System] ImageCache eviction failed count=12",
               log: OSLog(subsystem: "com.coo.SPMExample", category: "system"),
               type: .error)

        // stderr: 加载失败
        fputs("[ConfigLoader] FATAL: Unable to load config from /var/containers/Bundle/Application/xxx/app.config\n", stderr)
        fputs("[ConfigLoader] ERROR: fallback to default config (feature_flags disabled)\n", stderr)

        // bridge: 系统事件上报
        ExploreAppLog.emit(.fault, category: "system.memory",
                           message: "Memory pressure warning footprint=145MB threshold=140MB")
        ExploreAppLog.emit(.error, category: "system.cache",
                           message: "ImageCache eviction failed count=12 error=disk_full")
        ExploreAppLog.emit(.error, category: "system.config",
                           message: "Config load failed, using defaults path=app.config")
        ExploreAppLog.emit(.info, category: "system.config",
                           message: "Fallback configuration applied features=0 (all disabled)")

        // Swift Logger
        let logger = Logger(subsystem: "com.coo.SPMExample", category: "system")
        logger.fault("System integrity check failed: code=0xE003, module=ImageCache")

        logEvent("  ✓ nslog × 2, oslog × 3, stderr × 2, bridge × 4, Logger × 1")
        updateMarkCursor()
    }

    /// 🔍 全链路追踪场景：模拟一次完整用户操作在多个模块产生的日志。
    ///
    /// 模拟场景：用户点击「设置」→ 加载配置 → 网络请求 → 渲染页面 → 完成。
    /// 覆盖所有 6 个来源 + 所有 5 个等级（debug/info/error/fault/unknown）。
    @objc private func simulateFullTrace() {
        logEvent("🔍 全链路追踪场景开始")
        let traceID = UUID().uuidString.prefix(6)

        // Step 1: 用户进入设置页
        ExploreAppLog.emit(.info, category: "trace.step",
                           message: "[\(traceID)] Step 1/5: User navigated to Settings")
        print("[Trace] [\(traceID)] User tapped 'Settings' from main menu (touch at (280, 500))")

        // Step 2: 加载本地配置
        ExploreAppLog.emit(.debug, category: "trace.step",
                           message: "[\(traceID)] Step 2/5: Loading local config from UserDefaults")
        print("[Trace] [\(traceID)] UserDefaults keys loaded: 24 entries")
        NSLog("[Trace] [%@] Config loaded: theme=dark, fontSize=16, language=zh-Hans", String(traceID))

        // Step 3: 网络请求同步远程配置
        ExploreAppLog.emit(.info, category: "trace.step",
                           message: "[\(traceID)] Step 3/5: Fetching remote config from /api/v1/config")
        print("[Trace] [\(traceID)] → GET /api/v1/config (timeout=10s)")
        usleep(30_000)  // 模拟延迟
        fputs("[Trace] [\(traceID)] WARNING: config fetch took 3.2s (threshold=2s)\n", stderr)
        print("[Trace] [\(traceID)] ← 200 OK (cache-control: max-age=300)")

        // Step 4: 应用配置，部分失效
        ExploreAppLog.emit(.info, category: "trace.step",
                           message: "[\(traceID)] Step 4/5: Applying remote config items=42")
        fputs("[Trace] [\(traceID)] ERROR: feature flag 'beta_experiment' has invalid value\n", stderr)
        ExploreAppLog.emit(.error, category: "trace.step",
                           message: "[\(traceID)] Invalid feature flag: beta_experiment=unknown (expected=true/false)")
        os_log("[Trace] [%{public}@] Feature flag validation error count=1",
               log: OSLog(subsystem: "com.coo.SPMExample", category: "trace"),
               type: .error, String(traceID))

        // Step 5: 完成
        ExploreAppLog.emit(.info, category: "trace.step",
                           message: "[\(traceID)] Step 5/5: Settings page rendered (latency=3.8s)")
        print("[Trace] [\(traceID)] Settings page fully rendered: 7 sections, 42 items")
        let logger = Logger(subsystem: "com.coo.SPMExample", category: "trace")
        logger.info("[\(traceID)] User settings flow completed successfully")

        logEvent("  ✓ bridge × 6, stdout × 4, nslog × 1, stderr × 2, oslog × 1, Logger × 1")
        updateMarkCursor()
    }

    // MARK: - 辅助

    /// 执行 app.logs.mark 并保存 cursor。
    private func updateMarkCursor() {
        // 通过 ExploreAppLog 内部机制写入 mark — 但由于无法直接调 HTTP 命令，
        // 我们在本地记录一个模拟 cursor 供 UI 展示，实际 curl 验证用 Mac 侧 mark。
        // 此处通过 bridge 发一条分隔线，帮助在 app.logs.read 中识别场景边界。
        ExploreAppLog.emit(.info, category: "diagnostics.scenario",
                           message: "--- SCENARIO BOUNDARY ---")
        lastMarkCursor = ""
        cursorLabel.text = "✅ 场景已写入（建议从 Mac 侧发 app.logs.mark 获取 cursor）"
        logEvent("  📌 mark cursor 已更新，建议从 Mac 侧执行 app.logs.mark 获取精确位置")
    }

    @objc private func copyCursor() {
        guard let cursor = lastMarkCursor, !cursor.isEmpty else {
            UIPasteboard.general.string = cursorLabel.text ?? ""
            logEvent("📋 已复制到剪贴板")
            return
        }
        UIPasteboard.general.string = cursor
        logEvent("📋 cursor 已复制到剪贴板")
    }

    @objc private func clearEvents() {
        events.removeAll()
        eventsView.text = "(等待事件)"
    }

    private func logEvent(_ line: String) {
        let entry = "\(dateFormatter.string(from: Date()))  \(line)"
        events.insert(entry, at: 0)
        if events.count > 100 { events.removeLast() }
        eventsView.text = events.joined(separator: "\n")
    }
}
