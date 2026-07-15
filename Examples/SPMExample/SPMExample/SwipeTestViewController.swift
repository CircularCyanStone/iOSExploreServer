//
//  SwipeTestViewController.swift
//  SPMExample
//
//  Created by Claude for ui.swipe e2e testing.
//

import UIKit

/// 用于验证 `ui.swipe` 命令的测试页面。
///
/// 提供三类测试场景：
/// 1. **UIScrollView swipe actions**：UITableView 带 leading/trailing swipe actions
/// 2. **UISwipeGestureRecognizer**：自定义 view 挂载 swipe gesture
/// 3. **UIPanGestureRecognizer**：自定义 view 挂载 pan gesture
///
/// 测试策略：
/// - 策略 1（UIScrollView）：对 UITableView 执行 left/right 滑动触发 leading/trailing swipe actions
/// - 策略 2（UISwipeGesture）：对带 UISwipeGestureRecognizer 的 view 执行 swipe
/// - 策略 3（UIPanGesture）：对带 UIPanGestureRecognizer 的 view 执行 swipe
final class SwipeTestViewController: UIViewController {
    /// 日志标签（显示 swipe 事件）
    private let logLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        label.numberOfLines = 0
        label.textAlignment = .left
        label.textColor = .label
        label.backgroundColor = .secondarySystemBackground
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.accessibilityIdentifier = "swipe.test.log"
        return label
    }()

    /// UITableView 带 swipe actions（策略 1 测试）
    private let tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.accessibilityIdentifier = "swipe.tableview"
        return tv
    }()

    /// 带 UISwipeGestureRecognizer 的 view（策略 2 测试）
    private let swipeGestureView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemOrange.withAlphaComponent(0.2)
        view.layer.cornerRadius = 8
        view.layer.borderWidth = 2
        view.layer.borderColor = UIColor.systemOrange.cgColor
        view.accessibilityIdentifier = "swipe.gesture.view"
        return view
    }()

    private let swipeGestureLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "👆 UISwipeGesture\n左右滑动触发"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    /// 带 UIPanGestureRecognizer 的 view（策略 3 测试）
    private let panGestureView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemPurple.withAlphaComponent(0.2)
        view.layer.cornerRadius = 8
        view.layer.borderWidth = 2
        view.layer.borderColor = UIColor.systemPurple.cgColor
        view.accessibilityIdentifier = "swipe.pan.view"
        return view
    }()

    private let panGestureLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "✋ UIPanGesture\n任意方向拖动触发"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private var logLines: [String] = []

    /// TableView 数据源（可变）：支持 swipe-to-delete 真删除与 cell 重排。
    /// 初始 5 行；删除后 `numberOfRowsInSection` 返回 `items.count`，cell 真重排，
    /// 用于端到端验证「删除后旧 snapshot 是否误中错位 cell」（F-30 测试床）。
    private var items: [Int] = Array(1...5)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Swipe 测试"

        setupTableView()
        setupGestureViews()
        setupLayout()

        log("页面已加载，等待 swipe 操作...")
        updateLogLabel()
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SwipeCell")
        // 启用 leading/trailing swipe actions
    }

    private func setupGestureViews() {
        // 策略 2：添加 UISwipeGestureRecognizer
        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeLeft(_:)))
        swipeLeft.direction = .left
        swipeGestureView.addGestureRecognizer(swipeLeft)

        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeRight(_:)))
        swipeRight.direction = .right
        swipeGestureView.addGestureRecognizer(swipeRight)

        // 策略 3：添加 UIPanGestureRecognizer
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGestureView.addGestureRecognizer(panGesture)
    }

    private func setupLayout() {
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "策略 1: UITableView Swipe Actions"
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)

        let gestureTitleLabel = UILabel()
        gestureTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        gestureTitleLabel.text = "策略 2 & 3: Gesture Views"
        gestureTitleLabel.font = .systemFont(ofSize: 15, weight: .semibold)

        swipeGestureLabel.translatesAutoresizingMaskIntoConstraints = false
        panGestureLabel.translatesAutoresizingMaskIntoConstraints = false

        swipeGestureView.addSubview(swipeGestureLabel)
        panGestureView.addSubview(panGestureLabel)

        view.addSubview(titleLabel)
        view.addSubview(tableView)
        view.addSubview(gestureTitleLabel)
        view.addSubview(swipeGestureView)
        view.addSubview(panGestureView)
        view.addSubview(logLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            tableView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.heightAnchor.constraint(equalToConstant: 300),

            gestureTitleLabel.topAnchor.constraint(equalTo: tableView.bottomAnchor, constant: 16),
            gestureTitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            swipeGestureView.topAnchor.constraint(equalTo: gestureTitleLabel.bottomAnchor, constant: 8),
            swipeGestureView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            swipeGestureView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            swipeGestureView.heightAnchor.constraint(equalToConstant: 80),

            swipeGestureLabel.topAnchor.constraint(equalTo: swipeGestureView.topAnchor, constant: 8),
            swipeGestureLabel.bottomAnchor.constraint(equalTo: swipeGestureView.bottomAnchor, constant: -8),
            swipeGestureLabel.centerXAnchor.constraint(equalTo: swipeGestureView.centerXAnchor),

            panGestureView.topAnchor.constraint(equalTo: swipeGestureView.bottomAnchor, constant: 12),
            panGestureView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            panGestureView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            panGestureView.heightAnchor.constraint(equalToConstant: 80),

            panGestureLabel.topAnchor.constraint(equalTo: panGestureView.topAnchor, constant: 8),
            panGestureLabel.bottomAnchor.constraint(equalTo: panGestureView.bottomAnchor, constant: -8),
            panGestureLabel.centerXAnchor.constraint(equalTo: panGestureView.centerXAnchor),

            logLabel.topAnchor.constraint(equalTo: panGestureView.bottomAnchor, constant: 16),
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

    @objc private func handleSwipeLeft(_ gesture: UISwipeGestureRecognizer) {
        log("UISwipeGestureRecognizer: left 触发")
    }

    @objc private func handleSwipeRight(_ gesture: UISwipeGestureRecognizer) {
        log("UISwipeGestureRecognizer: right 触发")
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let state: String
        switch gesture.state {
        case .began: state = "began"
        case .changed: state = "changed"
        case .ended: state = "ended"
        default: state = "\(gesture.state.rawValue)"
        }
        log("UIPanGestureRecognizer: \(state)")
    }
}

// MARK: - UITableViewDataSource & Delegate

extension SwipeTestViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SwipeCell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.text = "Cell \(items[indexPath.row])"
        config.secondaryText = "左右滑动查看 actions"
        cell.contentConfiguration = config
        cell.accessibilityIdentifier = "swipe.cell.\(indexPath.row)"
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        60
    }

    // MARK: - Swipe Actions

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
            guard let self = self else { completion(false); return }
            // 防御：确保 indexPath 在并发/连续删除场景下仍有效，避免越界崩溃
            guard indexPath.row < self.items.count else {
                self.log("Trailing Swipe: 删除取消，row=\(indexPath.row) 已不存在")
                completion(false)
                return
            }
            // 真删除：先移除数据源，再 deleteRows 触发 cell 重排（动画 .automatic）
            let removed = self.items.remove(at: indexPath.row)
            self.tableView.deleteRows(at: [indexPath], with: .automatic)
            self.log("Trailing Swipe: 已删除 Cell \(removed)（row=\(indexPath.row)），剩余 \(self.items.count) 行")
            completion(true)
        }
        deleteAction.backgroundColor = .systemRed

        let archiveAction = UIContextualAction(style: .normal, title: "归档") { [weak self] _, _, completion in
            self?.log("Trailing Swipe: 归档 Cell \(indexPath.row + 1)")
            completion(true)
        }
        archiveAction.backgroundColor = .systemBlue

        return UISwipeActionsConfiguration(actions: [deleteAction, archiveAction])
    }

    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let starAction = UIContextualAction(style: .normal, title: "⭐ 收藏") { [weak self] _, _, completion in
            self?.log("Leading Swipe: 收藏 Cell \(indexPath.row + 1)")
            completion(true)
        }
        starAction.backgroundColor = .systemYellow

        let shareAction = UIContextualAction(style: .normal, title: "分享") { [weak self] _, _, completion in
            self?.log("Leading Swipe: 分享 Cell \(indexPath.row + 1)")
            completion(true)
        }
        shareAction.backgroundColor = .systemGreen

        return UISwipeActionsConfiguration(actions: [starAction, shareAction])
    }
}
