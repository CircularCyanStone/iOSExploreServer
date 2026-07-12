//
//  WaitTestViewController.swift
//  SPMExample
//
//  专门用于验证 ui.wait / ui.waitAny 五种 mode 的测试页。
//  所有"触发条件"动作都在主线程异步延迟执行,让 ui.wait 在轮询过程中观察到状态变化。
//

import UIKit

/// `ui.wait` / `ui.waitAny` 命令的端到端验证页。
///
/// 五种 WaitMode 各有对应入口按钮,按下后会在主线程异步延迟若干秒改变 UI 状态——
/// 让 ui.wait 在轮询过程中能"撞上"条件满足/不满足的时刻,从而验证:
/// - targetExists / targetGone: 红色方块延迟出现/消失
/// - textExists: 文本延迟出现/消失
/// - snapshotChanged: 跳转/弹层导致整页指纹变化
/// - idle: 持续动画一段时间后停下,验证 stableMs 稳定窗口
/// - 各种 timeoutMs / intervalMs / stableMs 边界
final class WaitTestViewController: UIViewController {

    /// 持续动画用的小方块;按下「启动动画」后会持续 2.5s 位置抖动,
    /// 验证 idle 模式 stableMs 应在动画停下后才满足。
    private let animatingBox = UIView()
    private var displayLink: CADisplayLink?
    private var animationStart: CFTimeInterval = 0
    private var animationDuration: CFTimeInterval = 2.5
    private var pendingAnimationWorkItem: DispatchWorkItem?

    /// 可显隐的红色方块,默认隐藏;按下「延迟显示红块」2 秒后显示。
    private let targetBox = UIView()
    private var pendingShowTargetWorkItem: DispatchWorkItem?

    /// 可显隐的文本标签,默认隐藏;按下「延迟显示文本」2 秒后显示。
    private let textLabel = UILabel()
    private var pendingShowTextWorkItem: DispatchWorkItem?

    /// 状态标签,记录最近一次动作,便于 inspector 与肉眼对照。
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Wait 测试"
        view.backgroundColor = .systemBackground
        setupLayout()
    }

    deinit {
        displayLink?.invalidate()
        pendingAnimationWorkItem?.cancel()
        pendingShowTargetWorkItem?.cancel()
        pendingShowTextWorkItem?.cancel()
    }

    // MARK: - Layout

    private func setupLayout() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false

        let buttons: [(String, String, Selector)] = [
            ("延迟 2s 显示红块 (targetExists)", "wait.showTarget", #selector(showTargetTapped)),
            ("延迟 2s 隐藏红块 (targetGone)", "wait.hideTarget", #selector(hideTargetTapped)),
            ("延迟 2s 显示文本 (textExists)", "wait.showText", #selector(showTextTapped)),
            ("延迟 2s 隐藏文本", "wait.hideText", #selector(hideTextTapped)),
            ("启动 2.5s 动画 (idle 稳定)", "wait.startAnimation", #selector(startAnimationTapped)),
            ("立即停止动画 (idle 立即稳)", "wait.stopAnimation", #selector(stopAnimationTapped)),
            ("延迟 2s push 子页 (snapshotChanged 跳转)", "wait.pushChild", #selector(pushChildTapped)),
            ("延迟 2s 弹出 alert (snapshotChanged 弹层)", "wait.presentAlert", #selector(presentAlertTapped)),
            ("延迟 3s 重新 reload 整页 (snapshotChanged 同页变化)", "wait.reloadPage", #selector(reloadPageTapped)),
        ]

        for (title, identifier, sel) in buttons {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.titleLabel?.numberOfLines = 0
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
            button.contentHorizontalAlignment = .leading
            button.accessibilityIdentifier = identifier
            button.addTarget(self, action: sel, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }

        // 红色方块 — 默认隐藏,targetExists/targetGone 用
        targetBox.backgroundColor = .systemRed
        targetBox.accessibilityIdentifier = "wait.targetBox"
        targetBox.translatesAutoresizingMaskIntoConstraints = false
        targetBox.isHidden = true

        // 文本标签 — 默认隐藏,textExists 用
        textLabel.text = "Wait 文本已出现"
        textLabel.accessibilityIdentifier = "wait.textLabel"
        textLabel.font = .systemFont(ofSize: 18, weight: .bold)
        textLabel.textAlignment = .center
        textLabel.textColor = .systemBlue
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.isHidden = true

        // 动画方块 — 持续动画时位置抖动,idle 用
        animatingBox.backgroundColor = .systemGreen
        animatingBox.accessibilityIdentifier = "wait.animatingBox"
        animatingBox.translatesAutoresizingMaskIntoConstraints = false
        animatingBox.frame = CGRect(x: 100, y: 100, width: 40, height: 40)

        statusLabel.text = "状态: 准备就绪"
        statusLabel.accessibilityIdentifier = "wait.statusLabel"
        statusLabel.font = .systemFont(ofSize: 13, weight: .regular)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        view.addSubview(targetBox)
        view.addSubview(textLabel)
        view.addSubview(animatingBox)
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            targetBox.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 16),
            targetBox.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            targetBox.widthAnchor.constraint(equalToConstant: 60),
            targetBox.heightAnchor.constraint(equalToConstant: 60),

            textLabel.topAnchor.constraint(equalTo: targetBox.bottomAnchor, constant: 16),
            textLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            animatingBox.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 16),
            animatingBox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            animatingBox.widthAnchor.constraint(equalToConstant: 40),
            animatingBox.heightAnchor.constraint(equalToConstant: 40),

            statusLabel.topAnchor.constraint(equalTo: animatingBox.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
    }

    // MARK: - Actions

    @objc private func showTargetTapped() {
        pendingShowTargetWorkItem?.cancel()
        updateStatus("将在 2s 后显示红块")
        let work = DispatchWorkItem { [weak self] in
            self?.targetBox.isHidden = false
            self?.updateStatus("红块已显示")
        }
        pendingShowTargetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    @objc private func hideTargetTapped() {
        // 先确保红块可见再触发隐藏,否则 targetGone 没有可等待的初始"存在"
        targetBox.isHidden = false
        pendingShowTargetWorkItem?.cancel()
        updateStatus("红块先显示,2s 后隐藏")
        let work = DispatchWorkItem { [weak self] in
            self?.targetBox.isHidden = true
            self?.updateStatus("红块已隐藏")
        }
        pendingShowTargetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    @objc private func showTextTapped() {
        pendingShowTextWorkItem?.cancel()
        updateStatus("将在 2s 后显示文本")
        let work = DispatchWorkItem { [weak self] in
            self?.textLabel.isHidden = false
            self?.updateStatus("文本已显示")
        }
        pendingShowTextWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    @objc private func hideTextTapped() {
        textLabel.isHidden = false
        pendingShowTextWorkItem?.cancel()
        updateStatus("文本先显示,2s 后隐藏")
        let work = DispatchWorkItem { [weak self] in
            self?.textLabel.isHidden = true
            self?.updateStatus("文本已隐藏")
        }
        pendingShowTextWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    @objc private func startAnimationTapped() {
        displayLink?.invalidate()
        animationStart = CACurrentMediaTime()
        displayLink = CADisplayLink(target: self, selector: #selector(animationTick))
        displayLink?.add(to: .main, forMode: .common)
        updateStatus("动画启动,2.5s 后自动停")
    }

    @objc private func stopAnimationTapped() {
        displayLink?.invalidate()
        displayLink = nil
        pendingAnimationWorkItem?.cancel()
        updateStatus("动画已手动停止")
    }

    @objc private func animationTick() {
        let elapsed = CACurrentMediaTime() - animationStart
        if elapsed >= animationDuration {
            displayLink?.invalidate()
            displayLink = nil
            updateStatus("动画已自动停止")
            return
        }
        // 用 sin 抖动,触发 idle 的"画面活动签名"每帧变化
        let offset = CGFloat(sin(elapsed * 6.0) * 30.0)
        animatingBox.transform = CGAffineTransform(translationX: offset, y: 0)
    }

    @objc private func pushChildTapped() {
        updateStatus("将在 2s 后 push 子页")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            let child = UIViewController()
            child.view.backgroundColor = .systemTeal
            child.title = "Wait 子页"
            let label = UILabel()
            label.text = "已跳转到子页"
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            child.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: child.view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: child.view.centerYAnchor),
            ])
            self.navigationController?.pushViewController(child, animated: true)
            self.updateStatus("已 push 子页")
        }
    }

    @objc private func presentAlertTapped() {
        updateStatus("将在 2s 后弹 alert")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            let alert = UIAlertController(title: "Wait 弹层",
                                          message: "snapshotChanged 应在该 alert 出现时命中",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alert, animated: true)
            self.updateStatus("已弹 alert")
        }
    }

    @objc private func reloadPageTapped() {
        updateStatus("将在 3s 后重新 reload 整页")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self else { return }
            // 通过重新触发 viewDidLoad 等价的方式制造指纹变化:换一批按钮文本
            self.targetBox.backgroundColor = self.targetBox.backgroundColor == .systemRed ? .systemPink : .systemRed
            self.textLabel.text = self.textLabel.text == "Wait 文本已出现" ? "Wait 文本(更新版)" : "Wait 文本已出现"
            self.updateStatus("页面已重新加载,指纹变化")
        }
    }

    private func updateStatus(_ text: String) {
        statusLabel.text = "状态: \(text)"
    }
}
