//
//  ControllerStructureTestViewController.swift
//  SPMExample
//
//  ui.controllers 命令测试页：构建多层嵌套的 controller 结构，
//  包含 Navigation / Tab / Split / Child / Presented 各种容器类型。
//

import UIKit

/// `ui.controllers` 命令的测试载体页。
///
/// 页面提供按钮动态构建各种 controller 结构：
/// - Navigation stack (push 多层)
/// - Tab container (多个 tab)
/// - Presented modal (单层和链式)
/// - Child controller (容器嵌套)
/// - Split view (master-detail)
///
/// 每个按钮触发后会修改 controller 层次，命令调用后可观察结构树变化。
final class ControllerStructureTestViewController: UIViewController {

    // MARK: - UI Components

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let statusLabel = UILabel()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Controller 结构测试"
        view.backgroundColor = .systemBackground

        setupLayout()
        updateStatus()
    }

    // MARK: - Layout

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40),
        ])

        // 说明文本
        let intro = UILabel()
        intro.text = "通过 ui.controllers 命令观察 controller 结构变化。每个操作后调用命令查看树形结构。"
        intro.font = .systemFont(ofSize: 13)
        intro.textColor = .secondaryLabel
        intro.numberOfLines = 0
        contentStack.addArrangedSubview(intro)

        // 当前状态
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .label
        statusLabel.numberOfLines = 0
        statusLabel.backgroundColor = .secondarySystemBackground
        statusLabel.layer.cornerRadius = 8
        statusLabel.clipsToBounds = true
        statusLabel.textAlignment = .left
        let statusPadding = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        statusLabel.layoutMargins = statusPadding
        contentStack.addArrangedSubview(statusLabel)

        // Navigation 操作
        contentStack.addArrangedSubview(makeSectionTitle("Navigation Stack"))
        contentStack.addArrangedSubview(makeButton("Push 一层 VC", action: #selector(pushOneLevel)))
        contentStack.addArrangedSubview(makeButton("Push 三层 VC", action: #selector(pushThreeLevels)))
        contentStack.addArrangedSubview(makeButton("Pop 回根", action: #selector(popToRoot)))

        // Tab 操作
        contentStack.addArrangedSubview(makeSectionTitle("Tab Container"))
        contentStack.addArrangedSubview(makeButton("Present TabBar (3 tabs)", action: #selector(presentTabBar)))

        // Modal 操作
        contentStack.addArrangedSubview(makeSectionTitle("Modal Presentation"))
        contentStack.addArrangedSubview(makeButton("Present 单层 Modal", action: #selector(presentSingleModal)))
        contentStack.addArrangedSubview(makeButton("Present 链式 Modal (3层)", action: #selector(presentChainedModals)))
        contentStack.addArrangedSubview(makeButton("Dismiss All Modals", action: #selector(dismissAllModals)))

        // Child 操作
        contentStack.addArrangedSubview(makeSectionTitle("Child Controllers"))
        contentStack.addArrangedSubview(makeButton("Add Child VC", action: #selector(addChildVC)))
        contentStack.addArrangedSubview(makeButton("Remove Child VC", action: #selector(removeChildVC)))

        // Split 操作
        contentStack.addArrangedSubview(makeSectionTitle("Split View"))
        contentStack.addArrangedSubview(makeButton("Present SplitView", action: #selector(presentSplitView)))
    }

    private func makeSectionTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 14, weight: .bold)
        label.textColor = .label
        return label
    }

    private func makeButton(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        return button
    }

    // MARK: - Status Update

    private func updateStatus() {
        var lines: [String] = []

        if let nav = navigationController {
            lines.append("📍 Navigation Stack: \(nav.viewControllers.count) 层")
        }

        if let presented = presentedViewController {
            var count = 0
            var current: UIViewController? = presented
            while current != nil {
                count += 1
                current = current?.presentedViewController
            }
            lines.append("🎭 Presented: \(count) 层")
        }

        if !children.isEmpty {
            lines.append("👶 Child VCs: \(children.count) 个")
        }

        if lines.isEmpty {
            lines.append("⚪️ 当前无特殊结构")
        }

        statusLabel.text = lines.joined(separator: "\n")
    }

    // MARK: - Navigation Actions

    @objc private func pushOneLevel() {
        let vc = SimpleTestViewController(level: 1, color: .systemGreen)
        navigationController?.pushViewController(vc, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.updateStatus()
        }
    }

    @objc private func pushThreeLevels() {
        guard let nav = navigationController else { return }
        let vc1 = SimpleTestViewController(level: 1, color: .systemGreen)
        let vc2 = SimpleTestViewController(level: 2, color: .systemOrange)
        let vc3 = SimpleTestViewController(level: 3, color: .systemPurple)

        nav.pushViewController(vc1, animated: false)
        nav.pushViewController(vc2, animated: false)
        nav.pushViewController(vc3, animated: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.updateStatus()
        }
    }

    @objc private func popToRoot() {
        navigationController?.popToRootViewController(animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.updateStatus()
        }
    }

    // MARK: - Tab Actions

    @objc private func presentTabBar() {
        let tab1 = SimpleTestViewController(level: 0, color: .systemRed)
        tab1.title = "Tab 1"
        tab1.tabBarItem = UITabBarItem(title: "Tab 1", image: nil, tag: 0)

        let tab2 = SimpleTestViewController(level: 0, color: .systemBlue)
        tab2.title = "Tab 2"
        tab2.tabBarItem = UITabBarItem(title: "Tab 2", image: nil, tag: 1)

        let tab3 = SimpleTestViewController(level: 0, color: .systemGreen)
        tab3.title = "Tab 3"
        tab3.tabBarItem = UITabBarItem(title: "Tab 3", image: nil, tag: 2)

        let tabBarVC = UITabBarController()
        tabBarVC.viewControllers = [tab1, tab2, tab3]
        tabBarVC.selectedIndex = 0

        present(tabBarVC, animated: true) { [weak self] in
            self?.updateStatus()
        }
    }

    // MARK: - Modal Actions

    @objc private func presentSingleModal() {
        let modal = SimpleTestViewController(level: 1, color: .systemIndigo)
        modal.title = "Modal 1"
        modal.modalPresentationStyle = .pageSheet

        present(modal, animated: true) { [weak self] in
            self?.updateStatus()
        }
    }

    @objc private func presentChainedModals() {
        let modal1 = SimpleTestViewController(level: 1, color: .systemIndigo)
        modal1.title = "Modal 1"
        modal1.modalPresentationStyle = .pageSheet

        present(modal1, animated: true) { [weak self] in
            let modal2 = SimpleTestViewController(level: 2, color: .systemPink)
            modal2.title = "Modal 2"
            modal2.modalPresentationStyle = .pageSheet

            modal1.present(modal2, animated: true) {
                let modal3 = SimpleTestViewController(level: 3, color: .systemTeal)
                modal3.title = "Modal 3"
                modal3.modalPresentationStyle = .pageSheet

                modal2.present(modal3, animated: true) {
                    self?.updateStatus()
                }
            }
        }
    }

    @objc private func dismissAllModals() {
        presentedViewController?.dismiss(animated: true) { [weak self] in
            self?.updateStatus()
        }
    }

    // MARK: - Child Actions

    private var childVC: SimpleTestViewController?
    private var childContainer: UIView?

    @objc private func addChildVC() {
        // 如果已存在，先移除
        if childVC != nil {
            removeChildVC()
        }

        let child = SimpleTestViewController(level: 0, color: .systemYellow)
        child.title = "Child VC"

        let container = UIView()
        container.backgroundColor = .systemGray6
        container.layer.borderColor = UIColor.systemGray3.cgColor
        container.layer.borderWidth = 2
        container.layer.cornerRadius = 8
        container.translatesAutoresizingMaskIntoConstraints = false

        contentStack.addArrangedSubview(container)

        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(child.view)
        child.didMove(toParent: self)

        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            child.view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            child.view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            child.view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            container.heightAnchor.constraint(equalToConstant: 150),
        ])

        childVC = child
        childContainer = container
        updateStatus()
    }

    @objc private func removeChildVC() {
        guard let child = childVC, let container = childContainer else { return }

        child.willMove(toParent: nil)
        child.view.removeFromSuperview()
        child.removeFromParent()

        container.removeFromSuperview()

        childVC = nil
        childContainer = nil
        updateStatus()
    }

    // MARK: - Split Actions

    @objc private func presentSplitView() {
        let primary = SimpleTestViewController(level: 0, color: .systemRed)
        primary.title = "Primary"

        let secondary = SimpleTestViewController(level: 0, color: .systemBlue)
        secondary.title = "Secondary"

        let splitVC = UISplitViewController()
        splitVC.viewControllers = [primary, secondary]
        splitVC.preferredDisplayMode = .oneBesideSecondary

        present(splitVC, animated: true) { [weak self] in
            self?.updateStatus()
        }
    }
}

// MARK: - Simple Test View Controller

/// 简单的测试 VC，用于填充各种容器结构。
class SimpleTestViewController: UIViewController {

    private let level: Int
    private let color: UIColor

    init(level: Int, color: UIColor) {
        self.level = level
        self.color = color
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = color

        let label = UILabel()
        label.text = title ?? "Level \(level)"
        label.font = .systemFont(ofSize: 24, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        // 如果在 navigation stack 中，添加返回按钮
        if navigationController != nil {
            let backButton = UIButton(type: .system)
            backButton.setTitle("← Pop", for: .normal)
            backButton.setTitleColor(.white, for: .normal)
            backButton.addTarget(self, action: #selector(popBack), for: .touchUpInside)
            backButton.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(backButton)

            NSLayoutConstraint.activate([
                backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
                backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            ])
        }

        // 如果是 modal，添加关闭按钮
        if presentingViewController != nil {
            let dismissButton = UIButton(type: .system)
            dismissButton.setTitle("✕ Dismiss", for: .normal)
            dismissButton.setTitleColor(.white, for: .normal)
            dismissButton.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)
            dismissButton.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(dismissButton)

            NSLayoutConstraint.activate([
                dismissButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
                dismissButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            ])
        }
    }

    @objc private func popBack() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func dismissSelf() {
        dismiss(animated: true)
    }
}
