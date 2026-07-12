//
//  NavigationTestViewController.swift
//  SPMExample
//
//  Created for Navigation & Screenshot E2E Testing
//

import UIKit

/// Navigation 与 Screenshot 端到端测试页面。
///
/// 包含多种导航场景：
/// 1. 导航栏按钮（left/right/multiple）
/// 2. 多级 push 导航
/// 3. present/dismiss 场景
/// 4. 不同的导航栏配置
final class NavigationTestViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var actionLog: [String] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // 配置导航栏按钮
        setupNavigationBar()

        // 配置主界面
        setupUI()
    }

    private func setupNavigationBar() {
        // Left buttons (2 个)
        let leftButton1 = UIBarButtonItem(
            title: "编辑",
            style: .plain,
            target: self,
            action: #selector(leftButton1Tapped)
        )
        leftButton1.accessibilityIdentifier = "nav.left.edit"

        let leftButton2 = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(leftButton2Tapped)
        )
        leftButton2.accessibilityIdentifier = "nav.left.add"

        navigationItem.leftBarButtonItems = [leftButton1, leftButton2]

        // Right buttons (3 个)
        let rightButton1 = UIBarButtonItem(
            title: "分享",
            style: .plain,
            target: self,
            action: #selector(rightButton1Tapped)
        )
        rightButton1.accessibilityIdentifier = "nav.right.share"

        let rightButton2 = UIBarButtonItem(
            barButtonSystemItem: .search,
            target: self,
            action: #selector(rightButton2Tapped)
        )
        rightButton2.accessibilityIdentifier = "nav.right.search"

        let rightButton3 = UIBarButtonItem(
            image: UIImage(systemName: "gear"),
            style: .plain,
            target: self,
            action: #selector(rightButton3Tapped)
        )
        rightButton3.accessibilityIdentifier = "nav.right.settings"

        navigationItem.rightBarButtonItems = [rightButton1, rightButton2, rightButton3]
    }

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32),
        ])

        // 添加测试场景按钮
        addSectionTitle("Push 导航测试")
        addButton("Push Level 2 (有返回按钮)", action: #selector(pushLevel2))
        addButton("Push Level 2 (自定义 title)", action: #selector(pushLevel2CustomTitle))
        addButton("Push Level 2 (无导航栏)", action: #selector(pushLevel2NoNavBar))

        addSectionTitle("Present 模态测试")
        addButton("Present 全屏", action: #selector(presentFullScreen))
        addButton("Present 卡片样式", action: #selector(presentPageSheet))
        addButton("Present 有导航栏", action: #selector(presentWithNavigation))

        addSectionTitle("特殊导航场景")
        addButton("Push 3 级嵌套", action: #selector(pushNested3Levels))
        addButton("Present 后再 Push", action: #selector(presentThenPush))

        addSectionTitle("导航栏按钮状态")
        let statusLabel = UILabel()
        statusLabel.text = "Left: 编辑, 添加 | Right: 分享, 搜索, 设置"
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.accessibilityIdentifier = "nav.buttonStatus"
        stackView.addArrangedSubview(statusLabel)

        addSectionTitle("操作日志")
        let logLabel = UILabel()
        logLabel.text = "等待操作..."
        logLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logLabel.textColor = .label
        logLabel.numberOfLines = 0
        logLabel.accessibilityIdentifier = "nav.actionLog"
        logLabel.tag = 999 // 用于更新
        stackView.addArrangedSubview(logLabel)
    }

    private func addSectionTitle(_ title: String) {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 18, weight: .bold)
        label.textColor = .label
        stackView.addArrangedSubview(label)
    }

    private func addButton(_ title: String, action: Selector) {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.contentHorizontalAlignment = .leading
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        button.backgroundColor = .systemBlue.withAlphaComponent(0.1)
        button.layer.cornerRadius = 8
        stackView.addArrangedSubview(button)
    }

    private func logAction(_ action: String) {
        actionLog.insert("[\(Date().formatted(.dateTime.hour().minute().second()))] \(action)", at: 0)
        if actionLog.count > 10 { actionLog.removeLast() }

        if let logLabel = stackView.viewWithTag(999) as? UILabel {
            logLabel.text = actionLog.joined(separator: "\n")
        }
    }

    // MARK: - Navigation Bar Button Actions

    @objc private func leftButton1Tapped() {
        logAction("Left Button 1 (编辑) tapped")
    }

    @objc private func leftButton2Tapped() {
        logAction("Left Button 2 (添加) tapped")
    }

    @objc private func rightButton1Tapped() {
        logAction("Right Button 1 (分享) tapped")
    }

    @objc private func rightButton2Tapped() {
        logAction("Right Button 2 (搜索) tapped")
    }

    @objc private func rightButton3Tapped() {
        logAction("Right Button 3 (设置) tapped")
    }

    // MARK: - Push Navigation

    @objc private func pushLevel2() {
        let vc = NavigationLevel2ViewController(level: 2, configuration: .standard)
        navigationController?.pushViewController(vc, animated: true)
        logAction("Pushed Level 2 (standard)")
    }

    @objc private func pushLevel2CustomTitle() {
        let vc = NavigationLevel2ViewController(level: 2, configuration: .customBackTitle)
        navigationController?.pushViewController(vc, animated: true)
        logAction("Pushed Level 2 (custom back title)")
    }

    @objc private func pushLevel2NoNavBar() {
        let vc = NavigationLevel2ViewController(level: 2, configuration: .hiddenNavBar)
        navigationController?.pushViewController(vc, animated: true)
        logAction("Pushed Level 2 (hidden nav bar)")
    }

    @objc private func pushNested3Levels() {
        let vc = NavigationLevel2ViewController(level: 2, configuration: .nestedPush)
        navigationController?.pushViewController(vc, animated: true)
        logAction("Pushed Level 2 (will auto-push to Level 3)")
    }

    // MARK: - Present Modal

    @objc private func presentFullScreen() {
        let vc = NavigationModalViewController(style: .fullScreen)
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true)
        logAction("Presented full screen modal")
    }

    @objc private func presentPageSheet() {
        let vc = NavigationModalViewController(style: .pageSheet)
        vc.modalPresentationStyle = .pageSheet
        present(vc, animated: true)
        logAction("Presented page sheet modal")
    }

    @objc private func presentWithNavigation() {
        let contentVC = NavigationModalViewController(style: .withNavigation)
        let navVC = UINavigationController(rootViewController: contentVC)
        navVC.modalPresentationStyle = .pageSheet
        present(navVC, animated: true)
        logAction("Presented modal with navigation")
    }

    @objc private func presentThenPush() {
        let contentVC = NavigationModalViewController(style: .allowPush)
        let navVC = UINavigationController(rootViewController: contentVC)
        navVC.modalPresentationStyle = .fullScreen
        present(navVC, animated: true)
        logAction("Presented modal (can push inside)")
    }
}

// MARK: - Level 2 View Controller

enum NavigationConfiguration {
    case standard
    case customBackTitle
    case hiddenNavBar
    case nestedPush
}

final class NavigationLevel2ViewController: UIViewController {
    private let level: Int
    private let configuration: NavigationConfiguration
    private let label = UILabel()

    init(level: Int, configuration: NavigationConfiguration) {
        self.level = level
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Level \(level)"

        switch configuration {
        case .standard:
            // 默认返回按钮
            break
        case .customBackTitle:
            navigationItem.backButtonTitle = "自定义返回"
        case .hiddenNavBar:
            navigationController?.setNavigationBarHidden(true, animated: false)
        case .nestedPush:
            // 会自动 push 到 Level 3
            break
        }

        setupUI()

        // 自动 push 下一级
        if case .nestedPush = configuration {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.pushNextLevel()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if case .hiddenNavBar = configuration {
            navigationController?.setNavigationBarHidden(false, animated: false)
        }
    }

    private func setupUI() {
        label.text = "Level \(level)\nConfiguration: \(configName)"
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.accessibilityIdentifier = "level\(level).label"
        view.addSubview(label)

        let pushButton = UIButton(type: .system)
        pushButton.setTitle("Push Level \(level + 1)", for: .normal)
        pushButton.addTarget(self, action: #selector(pushNextLevel), for: .touchUpInside)
        pushButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pushButton)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            pushButton.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 20),
            pushButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    @objc private func pushNextLevel() {
        let nextVC = NavigationLevel2ViewController(level: level + 1, configuration: .standard)
        navigationController?.pushViewController(nextVC, animated: true)
    }

    private var configName: String {
        switch configuration {
        case .standard: return "standard"
        case .customBackTitle: return "customBackTitle"
        case .hiddenNavBar: return "hiddenNavBar"
        case .nestedPush: return "nestedPush"
        }
    }
}

// MARK: - Modal View Controller

enum ModalStyle {
    case fullScreen
    case pageSheet
    case withNavigation
    case allowPush
}

final class NavigationModalViewController: UIViewController {
    private let style: ModalStyle
    private let label = UILabel()

    init(style: ModalStyle) {
        self.style = style
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Modal - \(styleName)"

        setupUI()

        if case .withNavigation = style {
            setupNavigationBarButtons()
        }

        if case .allowPush = style {
            setupNavigationBarButtons()
        }
    }

    private func setupNavigationBarButtons() {
        let doneButton = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissModal)
        )
        doneButton.accessibilityIdentifier = "modal.done"
        navigationItem.rightBarButtonItem = doneButton
    }

    private func setupUI() {
        label.text = "Modal Style: \(styleName)\n\n这是一个 \(styleName) 模态页面"
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.accessibilityIdentifier = "modal.label"
        view.addSubview(label)

        let dismissButton = UIButton(type: .system)
        dismissButton.setTitle("Dismiss", for: .normal)
        dismissButton.addTarget(self, action: #selector(dismissModal), for: .touchUpInside)
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.accessibilityIdentifier = "modal.dismissButton"
        view.addSubview(dismissButton)

        var constraints = [
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            dismissButton.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 20),
            dismissButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ]

        if case .allowPush = style {
            let pushButton = UIButton(type: .system)
            pushButton.setTitle("Push Inside Modal", for: .normal)
            pushButton.addTarget(self, action: #selector(pushInsideModal), for: .touchUpInside)
            pushButton.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(pushButton)

            constraints.append(contentsOf: [
                pushButton.topAnchor.constraint(equalTo: dismissButton.bottomAnchor, constant: 16),
                pushButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            ])
        }

        NSLayoutConstraint.activate(constraints)
    }

    @objc private func dismissModal() {
        if let nav = navigationController {
            nav.dismiss(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    @objc private func pushInsideModal() {
        let vc = NavigationLevel2ViewController(level: 2, configuration: .standard)
        navigationController?.pushViewController(vc, animated: true)
    }

    private var styleName: String {
        switch style {
        case .fullScreen: return "fullScreen"
        case .pageSheet: return "pageSheet"
        case .withNavigation: return "withNavigation"
        case .allowPush: return "allowPush"
        }
    }
}
