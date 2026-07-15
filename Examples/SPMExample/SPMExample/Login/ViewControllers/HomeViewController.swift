//
//  HomeViewController.swift
//  SPMExample
//
//  登录成功后的首页
//

import UIKit
import OSLog

/// 首页视图控制器
final class HomeViewController: UIViewController {
    private let viewModel: HomeViewModel
    private let logger = Logger(subsystem: "com.coo.SPMExample", category: "HomeViewController")

    // MARK: - UI Components

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.accessibilityIdentifier = "home_scroll_view"
        return scrollView
    }()

    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let welcomeLabel: UILabel = {
        let label = UILabel()
        label.text = "欢迎回来！"
        label.font = .systemFont(ofSize: 32, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.accessibilityIdentifier = "home_welcome_label"
        return label
    }()

    private let usernameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 24, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.accessibilityIdentifier = "home_username_label"
        return label
    }()

    private let emailLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.accessibilityIdentifier = "home_email_label"
        return label
    }()

    private let userIdLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .tertiaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.accessibilityIdentifier = "home_user_id_label"
        return label
    }()

    private let refreshButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("刷新用户信息", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "home_refresh_button"
        return button
    }()

    private let logoutButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("退出登录", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        button.backgroundColor = .systemRed
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "home_logout_button"
        return button
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    // MARK: - Initialization

    init(user: User) {
        self.viewModel = HomeViewModel(user: user)
        super.init(nibName: nil, bundle: nil)
        logger.info("🔵 HomeViewController 初始化: username=\(user.username)")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        logger.info("🔵 HomeViewController viewDidLoad")

        setupUI()
        setupActions()
        updateUserInfo()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = "首页"
        navigationItem.hidesBackButton = true

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        contentView.addSubview(welcomeLabel)
        contentView.addSubview(usernameLabel)
        contentView.addSubview(emailLabel)
        contentView.addSubview(userIdLabel)
        contentView.addSubview(refreshButton)
        contentView.addSubview(logoutButton)
        contentView.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            // ScrollView
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // ContentView
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            // Welcome Label
            welcomeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 60),
            welcomeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            welcomeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            // Username Label
            usernameLabel.topAnchor.constraint(equalTo: welcomeLabel.bottomAnchor, constant: 24),
            usernameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            usernameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            // Email Label
            emailLabel.topAnchor.constraint(equalTo: usernameLabel.bottomAnchor, constant: 12),
            emailLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            emailLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            // User ID Label
            userIdLabel.topAnchor.constraint(equalTo: emailLabel.bottomAnchor, constant: 8),
            userIdLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            userIdLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            // Refresh Button
            refreshButton.topAnchor.constraint(equalTo: userIdLabel.bottomAnchor, constant: 40),
            refreshButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            // Logout Button
            logoutButton.topAnchor.constraint(equalTo: refreshButton.bottomAnchor, constant: 60),
            logoutButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            logoutButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            logoutButton.heightAnchor.constraint(equalToConstant: 50),
            logoutButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40),

            // Loading Indicator
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: refreshButton.centerYAnchor)
        ])
    }

    private func setupActions() {
        refreshButton.addTarget(self, action: #selector(refreshButtonTapped), for: .touchUpInside)
        logoutButton.addTarget(self, action: #selector(logoutButtonTapped), for: .touchUpInside)
    }

    // MARK: - Actions

    @objc private func refreshButtonTapped() {
        logger.info("🔵 刷新按钮点击")

        Task { @MainActor in
            loadingIndicator.startAnimating()
            refreshButton.isEnabled = false

            await viewModel.refreshUserInfo()

            loadingIndicator.stopAnimating()
            refreshButton.isEnabled = true

            logger.info("✅ 用户信息已刷新")
        }
    }

    @objc private func logoutButtonTapped() {
        logger.info("🔵 退出登录按钮点击")

        let alert = UIAlertController(
            title: "确认退出",
            message: "确定要退出登录吗？",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "退出", style: .destructive) { [weak self] _ in
            self?.performLogout()
        })
        // 防止已有 present 在进行时重复 present（F-21）
        guard presentedViewController == nil else { return }
        present(alert, animated: true)
    }

    private func performLogout() {
        logger.info("✅ 执行退出登录")
        viewModel.logout()

        let loginVC = LoginViewController()
        let navController = UINavigationController(rootViewController: loginVC)
        navController.modalPresentationStyle = .fullScreen

        if let windowScene = view.window?.windowScene,
           let window = windowScene.windows.first {
            window.rootViewController = navController
            UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve, animations: nil)
        }
    }

    // MARK: - UI Updates

    private func updateUserInfo() {
        guard let user = viewModel.user else {
            logger.warning("⚠️ 用户信息为空")
            return
        }

        usernameLabel.text = user.username
        emailLabel.text = user.email
        userIdLabel.text = "ID: \(user.id)"

        logger.info("✅ 用户信息已更新: username=\(user.username)")
    }
}
