//
//  InputTestViewController.swift
//  SPMExample
//
//  Created for ui.input and ui.keyboard.dismiss E2E testing
//

import UIKit

/// 文本输入测试页面，提供多种文本控件场景供 `ui.input` 和 `ui.keyboard.dismiss` 验证。
final class InputTestViewController: UIViewController {
    // MARK: - 场景 1: 简单 UITextField (replace 模式)
    private let simpleTextField = UITextField()
    private let simpleLabel = UILabel()

    // MARK: - 场景 2: 预填充内容的 UITextField (append 模式)
    private let prefillTextField = UITextField()
    private let prefillLabel = UILabel()

    // MARK: - 场景 3: UITextView (多行文本)
    private let textView = UITextView()
    private let textViewLabel = UILabel()

    // MARK: - 场景 4: UISearchTextField (搜索框)
    private let searchField = UISearchTextField()
    private let searchLabel = UILabel()

    // MARK: - 场景 5: 密码输入框 (secure text)
    private let passwordField = UITextField()
    private let passwordLabel = UILabel()

    // MARK: - 场景 6: 数字键盘
    private let numberField = UITextField()
    private let numberLabel = UILabel()

    // MARK: - 场景 7: 不可编辑的 UITextField
    private let disabledTextField = UITextField()
    private let disabledLabel = UILabel()

    // MARK: - 键盘控制按钮
    private let dismissButton = UIButton(type: .system)
    private let keyboardStatusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "文本输入测试"

        setupScrollView()
        updateKeyboardStatus()

        // 监听键盘事件
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    private func setupScrollView() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        // 创建所有测试场景
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])

        // 场景 1: 简单 TextField (replace 模式)
        stack.addArrangedSubview(createSection(
            title: "场景 1: 简单 TextField",
            description: "用于测试 replace 模式",
            textField: simpleTextField,
            resultLabel: simpleLabel,
            identifier: "simpleTextField"
        ))

        // 场景 2: 预填充 TextField (append 模式)
        prefillTextField.text = "初始内容"
        stack.addArrangedSubview(createSection(
            title: "场景 2: 预填充 TextField",
            description: "用于测试 append 模式",
            textField: prefillTextField,
            resultLabel: prefillLabel,
            identifier: "prefillTextField"
        ))

        // 场景 3: TextView (多行文本)
        textView.font = .systemFont(ofSize: 16)
        textView.layer.borderColor = UIColor.systemGray4.cgColor
        textView.layer.borderWidth = 1
        textView.layer.cornerRadius = 8
        textView.accessibilityIdentifier = "textView"
        textView.delegate = self
        textView.heightAnchor.constraint(equalToConstant: 100).isActive = true
        stack.addArrangedSubview(createSectionWithTextView(
            title: "场景 3: UITextView",
            description: "用于测试多行文本输入",
            textView: textView,
            resultLabel: textViewLabel
        ))

        // 场景 4: SearchTextField
        stack.addArrangedSubview(createSection(
            title: "场景 4: 搜索框",
            description: "UISearchTextField 专用测试",
            textField: searchField,
            resultLabel: searchLabel,
            identifier: "searchField"
        ))

        // 场景 5: 密码框
        passwordField.isSecureTextEntry = true
        stack.addArrangedSubview(createSection(
            title: "场景 5: 密码输入",
            description: "测试 secure text entry",
            textField: passwordField,
            resultLabel: passwordLabel,
            identifier: "passwordField"
        ))

        // 场景 6: 数字键盘
        numberField.keyboardType = .numberPad
        stack.addArrangedSubview(createSection(
            title: "场景 6: 数字键盘",
            description: "numberPad 键盘类型",
            textField: numberField,
            resultLabel: numberLabel,
            identifier: "numberField"
        ))

        // 场景 7: 不可编辑
        disabledTextField.isEnabled = false
        disabledTextField.text = "不可编辑"
        disabledTextField.backgroundColor = .systemGray5
        stack.addArrangedSubview(createSection(
            title: "场景 7: 禁用状态",
            description: "测试错误处理",
            textField: disabledTextField,
            resultLabel: disabledLabel,
            identifier: "disabledTextField"
        ))

        // 键盘控制区域
        let keyboardSection = UIView()
        let keyboardStack = UIStackView()
        keyboardStack.axis = .vertical
        keyboardStack.spacing = 8
        keyboardStack.translatesAutoresizingMaskIntoConstraints = false
        keyboardSection.addSubview(keyboardStack)

        NSLayoutConstraint.activate([
            keyboardStack.topAnchor.constraint(equalTo: keyboardSection.topAnchor),
            keyboardStack.leadingAnchor.constraint(equalTo: keyboardSection.leadingAnchor),
            keyboardStack.trailingAnchor.constraint(equalTo: keyboardSection.trailingAnchor),
            keyboardStack.bottomAnchor.constraint(equalTo: keyboardSection.bottomAnchor),
        ])

        let keyboardTitle = UILabel()
        keyboardTitle.text = "键盘控制"
        keyboardTitle.font = .boldSystemFont(ofSize: 18)
        keyboardStack.addArrangedSubview(keyboardTitle)

        keyboardStatusLabel.text = "键盘状态: 未显示"
        keyboardStatusLabel.font = .systemFont(ofSize: 14)
        keyboardStatusLabel.textColor = .secondaryLabel
        keyboardStatusLabel.accessibilityIdentifier = "keyboardStatus"
        keyboardStack.addArrangedSubview(keyboardStatusLabel)

        dismissButton.setTitle("手动收起键盘", for: .normal)
        dismissButton.addTarget(self, action: #selector(dismissKeyboardTapped), for: .touchUpInside)
        dismissButton.accessibilityIdentifier = "dismissKeyboardButton"
        keyboardStack.addArrangedSubview(dismissButton)

        stack.addArrangedSubview(keyboardSection)
    }

    private func createSection(title: String, description: String, textField: UITextField, resultLabel: UILabel, identifier: String) -> UIView {
        let container = UIView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .boldSystemFont(ofSize: 18)
        stack.addArrangedSubview(titleLabel)

        let descLabel = UILabel()
        descLabel.text = description
        descLabel.font = .systemFont(ofSize: 14)
        descLabel.textColor = .secondaryLabel
        descLabel.numberOfLines = 0
        stack.addArrangedSubview(descLabel)

        textField.borderStyle = .roundedRect
        textField.placeholder = "请输入..."
        textField.accessibilityIdentifier = identifier
        textField.delegate = self
        stack.addArrangedSubview(textField)

        resultLabel.text = "结果: (未输入)"
        resultLabel.font = .systemFont(ofSize: 14)
        resultLabel.textColor = .systemGreen
        resultLabel.numberOfLines = 0
        resultLabel.accessibilityIdentifier = "\(identifier)Result"
        stack.addArrangedSubview(resultLabel)

        return container
    }

    private func createSectionWithTextView(title: String, description: String, textView: UITextView, resultLabel: UILabel) -> UIView {
        let container = UIView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .boldSystemFont(ofSize: 18)
        stack.addArrangedSubview(titleLabel)

        let descLabel = UILabel()
        descLabel.text = description
        descLabel.font = .systemFont(ofSize: 14)
        descLabel.textColor = .secondaryLabel
        descLabel.numberOfLines = 0
        stack.addArrangedSubview(descLabel)

        stack.addArrangedSubview(textView)

        resultLabel.text = "结果: (未输入)"
        resultLabel.font = .systemFont(ofSize: 14)
        resultLabel.textColor = .systemGreen
        resultLabel.numberOfLines = 0
        resultLabel.accessibilityIdentifier = "textViewResult"
        stack.addArrangedSubview(resultLabel)

        return container
    }

    @objc private func dismissKeyboardTapped() {
        view.endEditing(true)
    }

    @objc private func keyboardWillShow() {
        updateKeyboardStatus()
    }

    @objc private func keyboardWillHide() {
        updateKeyboardStatus()
    }

    private func updateKeyboardStatus() {
        let hasFirstResponder = view.findFirstResponder() != nil
        keyboardStatusLabel.text = hasFirstResponder ? "键盘状态: 显示中" : "键盘状态: 未显示"
    }
}

// MARK: - UITextFieldDelegate & UITextViewDelegate
extension InputTestViewController: UITextFieldDelegate, UITextViewDelegate {
    func textFieldDidEndEditing(_ textField: UITextField) {
        updateResultLabel(for: textField)
        updateKeyboardStatus()
    }

    func textFieldDidChangeSelection(_ textField: UITextField) {
        updateResultLabel(for: textField)
    }

    func textViewDidChange(_ textView: UITextView) {
        textViewLabel.text = "结果: \(textView.text ?? "(空)")"
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        updateKeyboardStatus()
    }

    private func updateResultLabel(for textField: UITextField) {
        let label: UILabel
        switch textField {
        case simpleTextField: label = simpleLabel
        case prefillTextField: label = prefillLabel
        case searchField: label = searchLabel
        case passwordField: label = passwordLabel
        case numberField: label = numberLabel
        case disabledTextField: label = disabledLabel
        default: return
        }

        if textField.isSecureTextEntry {
            let length = textField.text?.count ?? 0
            label.text = "结果: [已屏蔽] (长度: \(length))"
        } else {
            label.text = "结果: \(textField.text ?? "(空)")"
        }
    }
}

// MARK: - Helper
extension UIView {
    func findFirstResponder() -> UIView? {
        if isFirstResponder {
            return self
        }
        for subview in subviews {
            if let firstResponder = subview.findFirstResponder() {
                return firstResponder
            }
        }
        return nil
    }
}
