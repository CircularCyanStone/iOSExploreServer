//
//  ResetPasswordViewController.swift
//  SPMExample
//
//  重置密码界面
//

import UIKit
import OSLog

/// 重置密码视图控制器
final class ResetPasswordViewController: UIViewController {
    private let viewModel = ResetPasswordViewModel()
    private let logger = Logger(subsystem: "com.coo.SPMExample", category: "ResetPasswordViewController")

    /// 是否正在提交请求（同步重入守卫）。在 fire-and-forget Task 调度前置位，
    /// 防止两次快速 tap 都在异步 `updateLoadingState` 执行前通过，导致重复重置请求（F-19）。
    private var isLoading = false

    // MARK: - UI Components

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.accessibilityIdentifier = "reset_password_scroll_view"
        return scrollView
    }()

    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "重置密码"
        label.font = .systemFont(ofSize: 32, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.accessibilityIdentifier = "reset_password_title"
        return label
    }()

    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.text = "请输入您的用户名和邮箱以重置密码"
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.accessibilityIdentifier = "reset_password_description"
        return label
    }()

    private let usernameTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "用户名"
        textField.borderStyle = .roundedRect
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.accessibilityIdentifier = "reset_username_field"
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
        textField.accessibilityIdentifier = "reset_email_field"
        return textField
    }()

    private let newPasswordTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "新密码（至少6位）"
        textField.borderStyle = .roundedRect
        textField.isSecureTextEntry = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.accessibilityIdentifier = "reset_new_password_field"
        return textField
    }()

    private let confirmPasswordTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "确认新密码"
        textField.borderStyle = .roundedRect
        textField.isSecureTextEntry = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.accessibilityIdentifier = "reset_confirm_password_field"
        return textField
    }()

    private let resetButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("重置密码", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        button.backgroundColor = .systemOrange
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "reset_password_button"
        return button
    }()

    private let backToLoginButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("返回登录", for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "back_to_login_from_reset_button"
        return button
    }()

    private let errorLabel: UILabel = {
        let label = UILabel()
        label.textColor = .systemRed
        label.font = .systemFont(ofSize: 14)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.accessibilityIdentifier = "reset_password_error_label"
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
        logger.info("🔵 ResetPasswordViewController viewDidLoad")

        setupUI()
        setupBindings()
        setupActions()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = "重置密码"

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        contentView.addSubview(titleLabel)
        contentView.addSubview(descriptionLabel)
        contentView.addSubview(usernameTextField)
        contentView.addSubview(emailTextField)
        contentView.addSubview(newPasswordTextField)
        contentView.addSubview(confirmPasswordTextField)
        contentView.addSubview(errorLabel)
        contentView.addSubview(resetButton)
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

            // Description
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            descriptionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            descriptionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            // Username
            usernameTextField.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 30),
            usernameTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            usernameTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            usernameTextField.heightAnchor.constraint(equalToConstant: 44),

            // Email
            emailTextField.topAnchor.constraint(equalTo: usernameTextField.bottomAnchor, constant: 16),
            emailTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            emailTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            emailTextField.heightAnchor.constraint(equalToConstant: 44),

            // New Password
            newPasswordTextField.topAnchor.constraint(equalTo: emailTextField.bottomAnchor, constant: 16),
            newPasswordTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            newPasswordTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            newPasswordTextField.heightAnchor.constraint(equalToConstant: 44),

            // Confirm Password
            confirmPasswordTextField.topAnchor.constraint(equalTo: newPasswordTextField.bottomAnchor, constant: 16),
            confirmPasswordTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            confirmPasswordTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            confirmPasswordTextField.heightAnchor.constraint(equalToConstant: 44),

            // Error Label
            errorLabel.topAnchor.constraint(equalTo: confirmPasswordTextField.bottomAnchor, constant: 12),
            errorLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            errorLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            // Reset Button
            resetButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 12),
            resetButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            resetButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            resetButton.heightAnchor.constraint(equalToConstant: 50),

            // Back to Login Button
            backToLoginButton.topAnchor.constraint(equalTo: resetButton.bottomAnchor, constant: 16),
            backToLoginButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            backToLoginButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40),

            // Loading Indicator
            loadingIndicator.centerXAnchor.constraint(equalTo: resetButton.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: resetButton.centerYAnchor)
        ])
    }

    private func setupBindings() {
        usernameTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        emailTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        newPasswordTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        confirmPasswordTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
    }

    private func setupActions() {
        resetButton.addTarget(self, action: #selector(resetButtonTapped), for: .touchUpInside)
        backToLoginButton.addTarget(self, action: #selector(backToLoginButtonTapped), for: .touchUpInside)
    }

    // MARK: - Actions

    @objc private func textFieldDidChange() {
        viewModel.username = usernameTextField.text ?? ""
        viewModel.email = emailTextField.text ?? ""
        viewModel.newPassword = newPasswordTextField.text ?? ""
        viewModel.confirmPassword = confirmPasswordTextField.text ?? ""
    }

    @objc private func resetButtonTapped() {
        // 同步重入守卫：在 Task 外立即置位，确保两次快速 tap 第二次直接返回
        guard !isLoading else { return }
        isLoading = true
        logger.info("🔵 重置密码按钮点击")
        view.endEditing(true)

        Task { @MainActor in
            updateLoadingState(isLoading: true)

            if let response = await viewModel.resetPassword(), response.success {
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
            resetButton.setTitle("", for: .normal)
            resetButton.isEnabled = false
        } else {
            loadingIndicator.stopAnimating()
            resetButton.setTitle("重置密码", for: .normal)
            resetButton.isEnabled = true
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
        logger.info("✅ 密码重置成功，显示提示并返回登录页")

        let alert = UIAlertController(
            title: "重置成功",
            message: "密码已重置，请使用新密码登录",
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
