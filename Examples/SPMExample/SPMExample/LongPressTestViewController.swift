//
//  LongPressTestViewController.swift
//  SPMExample
//
//  Created by Claude for ui.longPress e2e testing.
//

import UIKit

/// 用于验证 `ui.longPress` 命令的测试页面。
///
/// 提供三类测试场景：
/// 1. **UILongPressGestureRecognizer**：自定义 view 挂载 long press gesture
/// 2. **UITableView cell**：支持 cell 子树内的 long press selection
/// 3. **无 longPress gesture**：验证 unsupportedTarget 错误
///
/// 测试策略：
/// - 策略 1（UILongPressGesture）：对带 UILongPressGestureRecognizer 的 view 执行 long press
/// - 策略 2（Cell long press）：对 UITableViewCell 执行 long press 触发 selection
/// - 策略 3：无 gesture view 验证错误
final class LongPressTestViewController: UIViewController {
    /// 日志标签（显示 longPress 事件）
    private let logLabel: UILabel = {
        let label = UILabel()
        // 必须显式关闭 autoresizing mask 转约束，否则与显式 Auto Layout 约束冲突，
        // 会破坏整个 VC 的垂直布局（曾导致 tableView height=0、cell 不渲染）。
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        label.numberOfLines = 0
        label.textAlignment = .left
        label.textColor = .label
        label.backgroundColor = .secondarySystemBackground
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.accessibilityIdentifier = "longpress.test.log"
        return label
    }()

    /// 带 UILongPressGestureRecognizer 的 view（策略 1 测试）
    private let longPressGestureView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemGreen.withAlphaComponent(0.2)
        view.layer.cornerRadius = 8
        view.layer.borderWidth = 2
        view.layer.borderColor = UIColor.systemGreen.cgColor
        view.accessibilityIdentifier = "longpress.gesture.view"
        return view
    }()

    private let longPressGestureLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "✋ UILongPressGesture\n长按触发"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    /// 带普通点击的 view（策略 3：验证无 gesture 时返回 unsupportedTarget）
    private let noGestureView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemGray.withAlphaComponent(0.2)
        view.layer.cornerRadius = 8
        view.layer.borderWidth = 2
        view.layer.borderColor = UIColor.systemGray.cgColor
        view.accessibilityIdentifier = "longpress.nogesture.view"
        return view
    }()

    private let noGestureLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "❌ 无 LongPress Gesture\n预期返回 unsupportedTarget"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    /// UITableView 测试 cell selection（策略 2 测试）
    private let tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.accessibilityIdentifier = "longpress.tableview"
        return tv
    }()

    private var logLines: [String] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "LongPress 测试"

        setupTableView()
        setupGestureViews()
        setupLayout()

        log("页面已加载，等待 longPress 操作...")
        updateLogLabel()
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "LongPressCell")
    }

    private func setupGestureViews() {
        // 策略 1：添加 UILongPressGestureRecognizer
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        longPressGestureView.addGestureRecognizer(longPress)
    }

    private func setupLayout() {
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "策略 1 & 3: Gesture Views"
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)

        longPressGestureLabel.translatesAutoresizingMaskIntoConstraints = false
        noGestureLabel.translatesAutoresizingMaskIntoConstraints = false

        longPressGestureView.addSubview(longPressGestureLabel)
        noGestureView.addSubview(noGestureLabel)

        view.addSubview(titleLabel)
        view.addSubview(longPressGestureView)
        view.addSubview(noGestureView)
        view.addSubview(tableView)
        view.addSubview(logLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            longPressGestureView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            longPressGestureView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            longPressGestureView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            longPressGestureView.heightAnchor.constraint(equalToConstant: 60),

            longPressGestureLabel.topAnchor.constraint(equalTo: longPressGestureView.topAnchor, constant: 8),
            longPressGestureLabel.bottomAnchor.constraint(equalTo: longPressGestureView.bottomAnchor, constant: -8),
            longPressGestureLabel.centerXAnchor.constraint(equalTo: longPressGestureView.centerXAnchor),

            noGestureView.topAnchor.constraint(equalTo: longPressGestureView.bottomAnchor, constant: 12),
            noGestureView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            noGestureView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            noGestureView.heightAnchor.constraint(equalToConstant: 60),

            noGestureLabel.topAnchor.constraint(equalTo: noGestureView.topAnchor, constant: 8),
            noGestureLabel.bottomAnchor.constraint(equalTo: noGestureView.bottomAnchor, constant: -8),
            noGestureLabel.centerXAnchor.constraint(equalTo: noGestureView.centerXAnchor),

            tableView.topAnchor.constraint(equalTo: noGestureView.bottomAnchor, constant: 16),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.heightAnchor.constraint(equalToConstant: 200),

            logLabel.topAnchor.constraint(equalTo: tableView.bottomAnchor, constant: 16),
            logLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            logLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            logLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }

    private func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logLines.insert("[\(timestamp)] \(message)", at: 0)
        if logLines.count > 10 { logLines.removeLast() }
        updateLogLabel()
    }

    private func updateLogLabel() {
        logLabel.text = logLines.joined(separator: "\n")
    }

    // MARK: - Gesture Handlers

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            log("UILongPressGestureRecognizer: began 触发")
        case .ended:
            log("UILongPressGestureRecognizer: ended 触发")
        case .cancelled:
            log("UILongPressGestureRecognizer: cancelled 触发")
        default:
            log("UILongPressGestureRecognizer: state=\(gesture.state.rawValue)")
        }
    }
}

// MARK: - UITableViewDataSource & Delegate

extension LongPressTestViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        5
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "LongPressCell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.text = "Cell \(indexPath.row + 1)"
        config.secondaryText = "长按选择 cell"
        cell.contentConfiguration = config
        cell.accessibilityIdentifier = "longpress.cell.\(indexPath.row)"
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        60
    }

    // UITableView 默认支持 cell selection
}
