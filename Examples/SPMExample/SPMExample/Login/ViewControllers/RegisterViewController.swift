//
//  RegisterViewController.swift
//  SPMExample
//
//  注册界面
//

import UIKit
import OSLog

/// 注册视图控制器
final class RegisterViewController: UIViewController {
    private let viewModel = RegisterViewModel()
    private let logger = Logger(subsystem: "com.coo.SPMExample", category: "RegisterViewController")

    /// 是否正在提交请求（同步重入守卫）。在 fire-and-forget Task 调度前置位，
    /// 防止两次快速 tap 都在异步 `updateLoadingState` 执行前通过，导致重复注册请求（F-19）。
    private var isLoading = false

    // MARK: - UI Components

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.accessibilityIdentifier = "register_scroll_view"
        return scrollView
    }()

    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "创建账号"
        label.font = .systemFont(ofSize: 32, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.accessibilityIdentifier = "register_title"
        return label
    }()

    private let usernameTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "用户名"
        textField.borderStyle = .roundedRect
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.accessibilityIdentifier = "register_username_field"
        return textField
    }()

    private let emailTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "邮箱"
        textField.borderStyle = .roundedRect
        textField.keyboardType = .emailAddress
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.accessibilityIdentifier = "register_email_field"
        return textField
    }()

    private let passwordTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "密码（至少6位）"
        textField.borderStyle = .roundedRect
        textField.isSecureTextEntry = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.accessibilityIdentifier = "register_password_field"
        return textField
    }()

    private let confirmPasswordTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "确认密码"
        textField.borderStyle = .roundedRect
        textField.isSecureTextEntry = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.accessibilityIdentifier = "register_confirm_password_field"
        return textField
    }()

    private let registerButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("注册", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        button.backgroundColor = .systemGreen
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "register_button"
        return button
    }()

    private let backToLoginButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("已有账号？去登录", for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "back_to_login_button"
        return button
    }()

    private let errorLabel: UILabel = {
        let label = UILabel()
        label.textColor = .systemRed
        label.font = .systemFont(ofSize: 14)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.accessibilityIdentifier = "register_error_label"
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
        logger.info("🔵 RegisterViewController viewDidLoad")

        setupUI()
        setupBindings()
        setupActions()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = "注册"

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        contentView.addSubview(titleLabel)
        contentView.addSubview(usernameTextField)
        contentView.addSubview(emailTextField)
        contentView.addSubview(passwordTextField)
        contentView.addSubview(confirmPasswordTextField)
        contentView.addSubview(errorLabel)
        contentView.addSubview(registerButton)
        contentView.addSubview(backToLoginButton)
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
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 40),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            // Username
            usernameTextField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 40),
            usernameTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            usernameTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            usernameTextField.heightAnchor.constraint(equalToConstant: 44),

            // Email
            emailTextField.topAnchor.constraint(equalTo: usernameTextField.bottomAnchor, constant: 16),
            emailTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            emailTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            emailTextField.heightAnchor.constraint(equalToConstant: 44),

            // Password
            passwordTextField.topAnchor.constraint(equalTo: emailTextField.bottomAnchor, constant: 16),
            passwordTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            passwordTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            passwordTextField.heightAnchor.constraint(equalToConstant: 44),

            // Confirm Password
            confirmPasswordTextField.topAnchor.constraint(equalTo: passwordTextField.bottomAnchor, constant: 16),
            confirmPasswordTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            confirmPasswordTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            confirmPasswordTextField.heightAnchor.constraint(equalToConstant: 44),

            // Error Label
            errorLabel.topAnchor.constraint(equalTo: confirmPasswordTextField.bottomAnchor, constant: 12),
            errorLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            errorLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            // Register Button
            registerButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 12),
            registerButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            registerButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            registerButton.heightAnchor.constraint(equalToConstant: 50),

            // Back to Login Button
            backToLoginButton.topAnchor.constraint(equalTo: registerButton.bottomAnchor, constant: 16),
            backToLoginButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            backToLoginButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40),

            // Loading Indicator
            loadingIndicator.centerXAnchor.constraint(equalTo: registerButton.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: registerButton.centerYAnchor)
        ])
    }

    private func setupBindings() {
        usernameTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        emailTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        passwordTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        confirmPasswordTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
    }

    private func setupActions() {
        registerButton.addTarget(self, action: #selector(registerButtonTapped), for: .touchUpInside)
        backToLoginButton.addTarget(self, action: #selector(backToLoginButtonTapped), for: .touchUpInside)
    }

    // MARK: - Actions

    @objc private func textFieldDidChange() {
        viewModel.username = usernameTextField.text ?? ""
        viewModel.email = emailTextField.text ?? ""
        viewModel.password = passwordTextField.text ?? ""
        viewModel.confirmPassword = confirmPasswordTextField.text ?? ""
    }

    @objc private func registerButtonTapped() {
        // 同步重入守卫：在 Task 外立即置位，确保两次快速 tap 第二次直接返回
        guard !isLoading else { return }
        isLoading = true
        logger.info("🔵 注册按钮点击")
        view.endEditing(true)

        Task { @MainActor in
            updateLoadingState(isLoading: true)

            if let response = await viewModel.register(), response.success {
                updateLoadingState(isLoading: false)
                showSuccessAndNavigateToLogin()
            } else {
                updateLoadingState(isLoading: false)
                showError(viewModel.errorMessage)
            }
        }
    }

    @objc private func backToLoginButtonTapped() {
        logger.info("🔵 返回登录按钮点击")
        navigationController?.popViewController(animated: true)
    }

    // MARK: - UI Updates

    private func updateLoadingState(isLoading: Bool) {
        self.isLoading = isLoading
        if isLoading {
            loadingIndicator.startAnimating()
            registerButton.setTitle("", for: .normal)
            registerButton.isEnabled = false
        } else {
            loadingIndicator.stopAnimating()
            registerButton.setTitle("注册", for: .normal)
            registerButton.isEnabled = true
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

    private func showSuccessAndNavigateToLogin() {
        logger.info("✅ 注册成功，显示提示并返回登录页")

        let alert = UIAlertController(
            title: "注册成功",
            message: "账号创建成功，请使用新账号登录",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        })
        // self 可能已被 navigation.back pop（view.window == nil），此时在 self 上 present 会静默失败（F-20）；
        // 同时防止已有 present 在进行时重复 present（F-21）。
        guard let presenter = presenterForAlert(), presenter.presentedViewController == nil else {
            logger.warning("⚠️ 无可用的 present 容器，跳过成功提示")
            return
        }
        presenter.present(alert, animated: true)
    }

    /// 找到可用于 present alert 的最顶层 VC。
    /// self 仍在 window 中时返回 self；若 self 已被 pop（view.window == nil），
    /// 回退到当前活跃 keyWindow 的 rootViewController 链顶端，避免 present 静默失败。
    private func presenterForAlert() -> UIViewController? {
        if view.window != nil { return self }
        let activeScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let window = activeScene?.windows.first(where: { $0.isKeyWindow }),
              let root = window.rootViewController else { return nil }
        var top: UIViewController = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
