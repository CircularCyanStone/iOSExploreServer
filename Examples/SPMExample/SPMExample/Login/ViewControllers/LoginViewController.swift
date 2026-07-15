//
//  LoginViewController.swift
//  SPMExample
//
//  登录界面
//

import UIKit
import OSLog

/// 登录视图控制器
final class LoginViewController: UIViewController {
    private let viewModel = LoginViewModel()
    private let logger = Logger(subsystem: "com.coo.SPMExample", category: "LoginViewController")

    /// 是否正在提交请求（同步重入守卫）。在 fire-and-forget Task 调度前置位，
    /// 防止两次快速 tap 都在异步 `updateLoadingState` 执行前通过，导致重复登录请求（F-19）。
    private var isLoading = false

    // MARK: - UI Components

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.accessibilityIdentifier = "login_scroll_view"
        return scrollView
    }()

    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "欢迎登录"
        label.font = .systemFont(ofSize: 32, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.accessibilityIdentifier = "login_title"
        return label
    }()

    private let usernameTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "用户名"
        textField.borderStyle = .roundedRect
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.accessibilityIdentifier = "login_username_field"
        return textField
    }()

    private let passwordTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "密码"
        textField.borderStyle = .roundedRect
        textField.isSecureTextEntry = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.accessibilityIdentifier = "login_password_field"
        return textField
    }()

    private let loginButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("登录", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "login_button"
        return button
    }()

    private let registerButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("还没有账号？去注册", for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "goto_register_button"
        return button
    }()

    private let forgotPasswordButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("忘记密码？", for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "goto_reset_password_button"
        return button
    }()

    private let errorLabel: UILabel = {
        let label = UILabel()
        label.textColor = .systemRed
        label.font = .systemFont(ofSize: 14)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.accessibilityIdentifier = "login_error_label"
        label.isHidden = true
        return label
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        logger.info("🔵 LoginViewController viewDidLoad")

        setupUI()
        setupBindings()
        setupActions()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = "登录"

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        contentView.addSubview(titleLabel)
        contentView.addSubview(usernameTextField)
        contentView.addSubview(passwordTextField)
        contentView.addSubview(errorLabel)
        contentView.addSubview(loginButton)
        contentView.addSubview(registerButton)
        contentView.addSubview(forgotPasswordButton)
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

            // Title
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 60),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            // Username
            usernameTextField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 40),
            usernameTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            usernameTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            usernameTextField.heightAnchor.constraint(equalToConstant: 44),

            // Password
            passwordTextField.topAnchor.constraint(equalTo: usernameTextField.bottomAnchor, constant: 16),
            passwordTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            passwordTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            passwordTextField.heightAnchor.constraint(equalToConstant: 44),

            // Error Label
            errorLabel.topAnchor.constraint(equalTo: passwordTextField.bottomAnchor, constant: 12),
            errorLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            errorLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            // Login Button
            loginButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 12),
            loginButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            loginButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            loginButton.heightAnchor.constraint(equalToConstant: 50),

            // Forgot Password Button
            forgotPasswordButton.topAnchor.constraint(equalTo: loginButton.bottomAnchor, constant: 16),
            forgotPasswordButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            // Register Button
            registerButton.topAnchor.constraint(equalTo: forgotPasswordButton.bottomAnchor, constant: 8),
            registerButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            registerButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40),

            // Loading Indicator
            loadingIndicator.centerXAnchor.constraint(equalTo: loginButton.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: loginButton.centerYAnchor)
        ])
    }

    private func setupBindings() {
        usernameTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        passwordTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
    }

    private func setupActions() {
        loginButton.addTarget(self, action: #selector(loginButtonTapped), for: .touchUpInside)
        registerButton.addTarget(self, action: #selector(registerButtonTapped), for: .touchUpInside)
        forgotPasswordButton.addTarget(self, action: #selector(forgotPasswordButtonTapped), for: .touchUpInside)
    }

    // MARK: - Actions

    @objc private func textFieldDidChange() {
        viewModel.username = usernameTextField.text ?? ""
        viewModel.password = passwordTextField.text ?? ""
    }

    @objc private func loginButtonTapped() {
        // 同步重入守卫：在 Task 外立即置位，确保两次快速 tap 第二次直接返回
        guard !isLoading else { return }
        isLoading = true
        logger.info("🔵 登录按钮点击")
        view.endEditing(true)

        Task { @MainActor in
            updateLoadingState(isLoading: true)

            if let response = await viewModel.login(), response.success {
                updateLoadingState(isLoading: false)
                navigateToHome(user: response.user!)
            } else {
                updateLoadingState(isLoading: false)
                showError(viewModel.errorMessage)
            }
        }
    }

    @objc private func registerButtonTapped() {
        logger.info("🔵 注册按钮点击")
        let registerVC = RegisterViewController()
        navigationController?.pushViewController(registerVC, animated: true)
    }

    @objc private func forgotPasswordButtonTapped() {
        logger.info("🔵 忘记密码按钮点击")
        let resetPasswordVC = ResetPasswordViewController()
        navigationController?.pushViewController(resetPasswordVC, animated: true)
    }

    // MARK: - UI Updates

    private func updateLoadingState(isLoading: Bool) {
        self.isLoading = isLoading
        if isLoading {
            loadingIndicator.startAnimating()
            loginButton.setTitle("", for: .normal)
            loginButton.isEnabled = false
        } else {
            loadingIndicator.stopAnimating()
            loginButton.setTitle("登录", for: .normal)
            loginButton.isEnabled = true
        }
    }

    private func showError(_ message: String?) {
        if let message = message {
            errorLabel.text = message
            errorLabel.isHidden = false
            logger.warning("⚠️ 显示错误信息: \(message)")
        } else {
            errorLabel.isHidden = true
        }
    }

    private func navigateToHome(user: User) {
        logger.info("✅ 登录成功，跳转到首页: username=\(user.username)")
        let homeVC = HomeViewController(user: user)
        navigationController?.setViewControllers([homeVC], animated: true)
    }
}
