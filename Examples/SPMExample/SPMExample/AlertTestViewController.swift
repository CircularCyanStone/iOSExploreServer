//
//  AlertTestViewController.swift
//  SPMExample
//
//  UIAlertController 测试页：承载 5 种弹窗案例，供 ui.alert.respond / ui.topViewHierarchy
//  观察系统标准 alert 的视图层级与 action 结构。
//

import UIKit

/// `ui.alert.respond` 与视图层级观察的测试载体页。
///
/// 页面提供 5 个触发按钮，每个弹出一种典型 `UIAlertController` 形态，覆盖：
/// - 标准 alert（标题/消息/确认 default + 取消 cancel）
/// - 三按钮 alert（destructive + default + cancel，暴露不同 role）
/// - 带输入框 alert（addTextField × 2，登录场景，暴露 textFields）
/// - actionSheet（preferredStyle.actionSheet，视图层级与 alert 不同）
/// - 嵌套 alert（点「继续」后在 handler 内 present 第二个 alert）
///
/// 目的：让 Mac 侧依次 `ui.tap` 触发按钮 → alert present → `ui.alert.respond`
/// 查询 action / textFields，或 `ui.topViewHierarchy` 看 alert 内部视图层级。
final class AlertTestViewController: UIViewController {

    // MARK: 触发按钮

    private let simpleButton = UIButton(type: .system)
    private let threeButtonsButton = UIButton(type: .system)
    private let loginInputButton = UIButton(type: .system)
    private let actionSheetButton = UIButton(type: .system)
    private let nestedButton = UIButton(type: .system)

    // MARK: 状态反馈

    private let statusLabel = UILabel()

    // MARK: 事件流

    private let eventsView = UITextView()
    private var events: [String] = []
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    // MARK: 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "UIAlertController 测试"
        view.backgroundColor = .systemBackground
        setupControls()
        setupLayout()
    }

    // MARK: 控件配置

    /// 配置 5 个触发按钮：设 accessibilityIdentifier（ui.inspect 主定位方式）+ target-action。
    private func setupControls() {
        configureTrigger(simpleButton,
                         title: "弹出标准 alert（确认/取消）",
                         identifier: "alert.trigger.simple",
                         action: #selector(presentSimpleAlert))
        configureTrigger(threeButtonsButton,
                         title: "弹出三按钮 alert（删除/收藏/取消）",
                         identifier: "alert.trigger.threeButtons",
                         action: #selector(presentThreeButtonAlert))
        configureTrigger(loginInputButton,
                         title: "弹出带输入框 alert（登录）",
                         identifier: "alert.trigger.loginInput",
                         action: #selector(presentLoginInputAlert))
        configureTrigger(actionSheetButton,
                         title: "弹出 actionSheet（底部）",
                         identifier: "alert.trigger.actionSheet",
                         action: #selector(presentActionSheet))
        configureTrigger(nestedButton,
                         title: "弹出嵌套 alert（点继续弹第二个）",
                         identifier: "alert.trigger.nested",
                         action: #selector(presentNestedAlert))

        statusLabel.text = "点击上方按钮弹出对应 alert，然后用 ui.alert.respond 观察"
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0

        eventsView.isEditable = false
        eventsView.isScrollEnabled = true
        eventsView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        eventsView.backgroundColor = .secondarySystemBackground
        eventsView.layer.cornerRadius = 8
        eventsView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        eventsView.text = "(等待事件)"
    }

    private func configureTrigger(_ button: UIButton, title: String, identifier: String, action: Selector) {
        button.setTitle(title, for: .normal)
        button.accessibilityIdentifier = identifier
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    // MARK: 布局

    /// ScrollView + 垂直主 stack：顶部说明、5 个触发区块、状态反馈、底部事件流。
    private func setupLayout() {
        let intro = UILabel()
        intro.text = "依次点按钮弹出 alert，配合 Mac 侧 ui.alert.respond / ui.topViewHierarchy 分析视图层级。触发按钮均带 accessibilityIdentifier，可被 ui.inspect 发现并由 ui.tap 远程触发。"
        intro.font = .systemFont(ofSize: 13)
        intro.textColor = .secondaryLabel
        intro.numberOfLines = 0

        let sections: [UIStackView] = [
            makeSection(title: "标准 alert  ·  alert.trigger.simple", control: simpleButton),
            makeSection(title: "三按钮 alert（default/destructive/cancel）  ·  alert.trigger.threeButtons", control: threeButtonsButton),
            makeSection(title: "带输入框 alert（addTextField × 2）  ·  alert.trigger.loginInput", control: loginInputButton),
            makeSection(title: "actionSheet（preferredStyle.actionSheet）  ·  alert.trigger.actionSheet", control: actionSheetButton),
            makeSection(title: "嵌套 alert（handler 内 present）  ·  alert.trigger.nested", control: nestedButton),
        ]

        let eventsTitle = UILabel()
        eventsTitle.text = "事件流（最新在顶）"
        eventsTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        eventsTitle.textColor = .secondaryLabel

        let mainStack = UIStackView(arrangedSubviews: [intro])
        sections.forEach { mainStack.addArrangedSubview($0) }
        mainStack.addArrangedSubview(statusLabel)
        mainStack.addArrangedSubview(eventsTitle)
        mainStack.addArrangedSubview(eventsView)
        mainStack.axis = .vertical
        mainStack.spacing = 24
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        view.addSubview(scrollView)
        contentView.addSubview(mainStack)

        // contentView 宽度锁齐 frameLayoutGuide，确保只垂直滚动。
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

            eventsView.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
    }

    /// 构建单个触发区块：标题 + 触发按钮，垂直排列。
    private func makeSection(title: String, control: UIView) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabel
        titleLabel.numberOfLines = 0

        let section = UIStackView(arrangedSubviews: [titleLabel, control])
        section.axis = .vertical
        section.spacing = 6
        section.alignment = .fill
        return section
    }

    // MARK: alert 案例

    /// 标准 alert：标题 + 消息 + 确认(default) + 取消(cancel)。
    @objc private func presentSimpleAlert() {
        let alert = UIAlertController(title: "确认操作",
                                      message: "是否继续执行此操作？",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel, handler: { [weak self] _ in
            self?.logEvent(identifier: "simple", event: "取消")
            self?.statusLabel.text = "标准 alert：点了「取消」(cancel)"
        }))
        alert.addAction(UIAlertAction(title: "确认", style: .default, handler: { [weak self] _ in
            self?.logEvent(identifier: "simple", event: "确认")
            self?.statusLabel.text = "标准 alert：点了「确认」(default)"
        }))
        logEvent(identifier: "simple", event: "present alert")
        present(alert, animated: true)
    }

    /// 三按钮 alert：删除(destructive) + 收藏(default) + 取消(cancel)，暴露三种 role。
    @objc private func presentThreeButtonAlert() {
        let alert = UIAlertController(title: "文件操作",
                                      message: "选择对当前文件的操作",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "删除", style: .destructive, handler: { [weak self] _ in
            self?.logEvent(identifier: "threeButtons", event: "删除")
            self?.statusLabel.text = "三按钮 alert：点了「删除」(destructive)"
        }))
        alert.addAction(UIAlertAction(title: "收藏", style: .default, handler: { [weak self] _ in
            self?.logEvent(identifier: "threeButtons", event: "收藏")
            self?.statusLabel.text = "三按钮 alert：点了「收藏」(default)"
        }))
        alert.addAction(UIAlertAction(title: "取消", style: .cancel, handler: { [weak self] _ in
            self?.logEvent(identifier: "threeButtons", event: "取消")
            self?.statusLabel.text = "三按钮 alert：点了「取消」(cancel)"
        }))
        logEvent(identifier: "threeButtons", event: "present alert")
        present(alert, animated: true)
    }

    /// 带输入框 alert：addTextField × 2（用户名 + 密码），登录场景。
    /// ui.alert.respond 会暴露 textFields 的 placeholder 与 isSecure，但**不回 text 原文**。
    @objc private func presentLoginInputAlert() {
        let alert = UIAlertController(title: "登录",
                                      message: "请输入账号和密码",
                                      preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "用户名"
            tf.accessibilityIdentifier = "alert.input.username"
        }
        alert.addTextField { tf in
            tf.placeholder = "密码"
            tf.isSecureTextEntry = true
            tf.accessibilityIdentifier = "alert.input.password"
        }
        alert.addAction(UIAlertAction(title: "登录", style: .default, handler: { [weak self] _ in
            let user = alert.textFields?[0].text ?? ""
            self?.logEvent(identifier: "loginInput", event: "登录 user=\(user)")
            self?.statusLabel.text = "输入框 alert：点了「登录」(user=\(user))"
        }))
        alert.addAction(UIAlertAction(title: "取消", style: .cancel, handler: { [weak self] _ in
            self?.logEvent(identifier: "loginInput", event: "取消")
            self?.statusLabel.text = "输入框 alert：点了「取消」"
        }))
        logEvent(identifier: "loginInput", event: "present alert")
        present(alert, animated: true)
    }

    /// actionSheet：preferredStyle.actionSheet，视图层级与 alert 不同（底部弹出）。
    /// iPad 必须给 popoverPresentationController 指定 sourceView，否则崩溃。
    @objc private func presentActionSheet() {
        let sheet = UIAlertController(title: "选择图片来源",
                                      message: nil,
                                      preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "拍照", style: .default, handler: { [weak self] _ in
            self?.logEvent(identifier: "actionSheet", event: "拍照")
            self?.statusLabel.text = "actionSheet：点了「拍照」"
        }))
        sheet.addAction(UIAlertAction(title: "从相册选择", style: .default, handler: { [weak self] _ in
            self?.logEvent(identifier: "actionSheet", event: "从相册选择")
            self?.statusLabel.text = "actionSheet：点了「从相册选择」"
        }))
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel, handler: { [weak self] _ in
            self?.logEvent(identifier: "actionSheet", event: "取消")
            self?.statusLabel.text = "actionSheet：点了「取消」"
        }))
        // iPad 上 actionSheet 必须有 popover source，否则崩溃；iPhone 上会被忽略但无害。
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = actionSheetButton
            popover.sourceRect = actionSheetButton.bounds
        }
        logEvent(identifier: "actionSheet", event: "present sheet")
        present(sheet, animated: true)
    }

    /// 嵌套 alert：点「继续」后在 handler 内 present 第二个 alert。
    /// 用于观察连续 present 时视图层级与 ui.alert.respond 的命中目标。
    @objc private func presentNestedAlert() {
        let first = UIAlertController(title: "步骤 1 / 2",
                                      message: "点击继续弹出第二个 alert",
                                      preferredStyle: .alert)
        first.addAction(UIAlertAction(title: "继续", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            self.logEvent(identifier: "nested", event: "步骤1 继续 → present 步骤2")
            let second = UIAlertController(title: "步骤 2 / 2",
                                           message: "这是第二个 alert",
                                           preferredStyle: .alert)
            second.addAction(UIAlertAction(title: "完成", style: .default, handler: { [weak self] _ in
                self?.logEvent(identifier: "nested", event: "步骤2 完成")
                self?.statusLabel.text = "嵌套 alert：流程完成"
            }))
            self.present(second, animated: true)
            self.statusLabel.text = "嵌套 alert：已弹出第二个"
        }))
        first.addAction(UIAlertAction(title: "取消", style: .cancel, handler: { [weak self] _ in
            self?.logEvent(identifier: "nested", event: "步骤1 取消")
            self?.statusLabel.text = "嵌套 alert：步骤 1 取消"
        }))
        logEvent(identifier: "nested", event: "present 步骤1")
        present(first, animated: true)
    }

    // MARK: 事件流

    /// 追加一条事件记录到事件流顶部，最多保留 50 条。
    private func logEvent(identifier: String, event: String) {
        let line = "\(dateFormatter.string(from: Date()))  \(identifier)  \(event)"
        events.insert(line, at: 0)
        if events.count > 50 { events.removeLast() }
        eventsView.text = events.joined(separator: "\n")
    }
}
