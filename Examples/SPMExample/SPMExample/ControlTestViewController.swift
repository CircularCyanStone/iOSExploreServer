//
//  ControlTestViewController.swift
//  SPMExample
//
//  UIControl 测试页：承载 6 类控件，供 ui.control.sendAction 命令远程触发
//  target-action 并观察效果。
//

import UIKit

/// `ui.control.sendAction` 命令的测试载体页。
///
/// 页面提供 UIButton / UISwitch / UISlider / UISegmentedControl / UIStepper / UITextField
/// 六类控件，覆盖命令支持的对应事件族（触摸 / 值变化 / 文本编辑）。每个控件都挂载
/// target-action：命令触发后既更新自身状态 label，又向底部事件流追加一条记录，从而让
/// Mac 侧 curl 能直观判断 sendAction 是否真正生效——命令本身只触发 target-action，
/// 不模拟触摸坐标，必须有可见反馈才能验证。
final class ControlTestViewController: UIViewController {

    // MARK: 控件

    private let button = UIButton(type: .system)
    private let toggleSwitch = UISwitch()
    private let slider = UISlider()
    private let segmented = UISegmentedControl()
    private let stepper = UIStepper()
    private let textField = UITextField()

    // MARK: 状态反馈 label（每控件就近一条）

    private let buttonStateLabel = UILabel()
    private let switchStateLabel = UILabel()
    private let sliderStateLabel = UILabel()
    private let segmentedStateLabel = UILabel()
    private let stepperStateLabel = UILabel()
    private let textfieldStateLabel = UILabel()

    // MARK: 事件流

    private let eventsView = UITextView()
    private var events: [String] = []
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// button 的 touchDown / touchUpInside 累计触发次数。
    private var buttonCount = 0

    // MARK: 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "UIControl 测试"
        view.backgroundColor = .systemBackground
        setupControls()
        setupLayout()
    }

    // MARK: 控件配置

    /// 配置六类控件：设 accessibilityIdentifier（命令主定位方式，须唯一）、初始值、target-action。
    private func setupControls() {
        button.setTitle("点我 (test.button)", for: .normal)
        button.accessibilityIdentifier = "test.button"
        button.addTarget(self, action: #selector(buttonTouchDown), for: .touchDown)
        button.addTarget(self, action: #selector(buttonTouchUpInside), for: .touchUpInside)
        buttonStateLabel.text = "等待 touchDown / touchUpInside"

        toggleSwitch.accessibilityIdentifier = "test.switch"
        toggleSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
        switchStateLabel.text = "off"

        slider.accessibilityIdentifier = "test.slider"
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.value = 0.5
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        sliderStateLabel.text = "0.50"

        segmented.accessibilityIdentifier = "test.segmented"
        segmented.insertSegment(withTitle: "A", at: 0, animated: false)
        segmented.insertSegment(withTitle: "B", at: 1, animated: false)
        segmented.insertSegment(withTitle: "C", at: 2, animated: false)
        segmented.selectedSegmentIndex = 0
        segmented.addTarget(self, action: #selector(segmentedChanged), for: .valueChanged)
        segmentedStateLabel.text = "A"

        stepper.accessibilityIdentifier = "test.stepper"
        stepper.minimumValue = 0
        stepper.maximumValue = 10
        stepper.stepValue = 1
        stepper.value = 0
        stepper.addTarget(self, action: #selector(stepperChanged), for: .valueChanged)
        stepperStateLabel.text = "0"

        textField.accessibilityIdentifier = "test.textfield"
        textField.placeholder = "输入文本 (test.textfield)"
        textField.borderStyle = .roundedRect
        textField.addTarget(self, action: #selector(textEditingBegan), for: .editingDidBegin)
        textField.addTarget(self, action: #selector(textEditingChanged), for: .editingChanged)
        textField.addTarget(self, action: #selector(textEditingEnded), for: .editingDidEnd)
        textfieldStateLabel.text = "未编辑"

        eventsView.isEditable = false
        eventsView.isScrollEnabled = true
        eventsView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        eventsView.backgroundColor = .secondarySystemBackground
        eventsView.layer.cornerRadius = 8
        eventsView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        eventsView.text = "(等待事件)"
    }

    // MARK: 布局

    /// ScrollView + 垂直主 stack：顶部说明、六个控件区块、底部事件流。
    private func setupLayout() {
        let intro = UILabel()
        intro.text = "以下控件可经 ui.control.sendAction 远程触发。定位用 accessibilityIdentifier，或 ui.topViewHierarchy 返回的 path。"
        intro.font = .systemFont(ofSize: 13)
        intro.textColor = .secondaryLabel
        intro.numberOfLines = 0

        let sections: [UIStackView] = [
            makeSection(title: "UIButton  ·  test.button  ·  touchDown / touchUpInside",
                        control: button, state: buttonStateLabel, fullWidth: true),
            makeSection(title: "UISwitch  ·  test.switch  ·  valueChanged",
                        control: toggleSwitch, state: switchStateLabel, fullWidth: false),
            makeSection(title: "UISlider  ·  test.slider  ·  valueChanged",
                        control: slider, state: sliderStateLabel, fullWidth: true),
            makeSection(title: "UISegmentedControl  ·  test.segmented  ·  valueChanged",
                        control: segmented, state: segmentedStateLabel, fullWidth: true),
            makeSection(title: "UIStepper  ·  test.stepper  ·  valueChanged",
                        control: stepper, state: stepperStateLabel, fullWidth: false),
            makeSection(title: "UITextField  ·  test.textfield  ·  editingChanged / editingDidBegin / editingDidEnd",
                        control: textField, state: textfieldStateLabel, fullWidth: true),
        ]

        let eventsTitle = UILabel()
        eventsTitle.text = "事件流（最新在顶，最多 50 条）"
        eventsTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        eventsTitle.textColor = .secondaryLabel

        let mainStack = UIStackView(arrangedSubviews: [intro])
        sections.forEach { mainStack.addArrangedSubview($0) }
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

    /// 构建单个控件区块：标题 + 控件 + 状态反馈，垂直排列。
    private func makeSection(title: String, control: UIView, state: UILabel, fullWidth: Bool) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabel
        titleLabel.numberOfLines = 0

        state.font = .systemFont(ofSize: 13, weight: .medium)
        state.textColor = .label
        state.textAlignment = .right
        state.numberOfLines = 0

        let section = UIStackView(arrangedSubviews: [titleLabel, host(control, fullWidth: fullWidth), state])
        section.axis = .vertical
        section.spacing = 6
        section.alignment = .fill
        return section
    }

    /// 非全宽控件（switch / stepper）左对齐包裹，避免被垂直 stack 拉伸。
    private func host(_ control: UIView, fullWidth: Bool) -> UIView {
        if fullWidth { return control }
        let spacer = UIView()
        let row = UIStackView(arrangedSubviews: [control, spacer])
        row.alignment = .center
        return row
    }

    // MARK: target-action

    @objc private func buttonTouchDown() {
        buttonCount += 1
        buttonStateLabel.text = "touchDown · 累计 \(buttonCount)"
        logEvent(identifier: "test.button", event: "touchDown")
    }

    @objc private func buttonTouchUpInside() {
        buttonCount += 1
        buttonStateLabel.text = "touchUpInside · 累计 \(buttonCount)"
        logEvent(identifier: "test.button", event: "touchUpInside")
    }

    @objc private func switchChanged() {
        let on = toggleSwitch.isOn
        toggleSwitch.setOn(!on, animated: true)
        switchStateLabel.text = !on ? "on" : "off"
        logEvent(identifier: "test.switch", event: "valueChanged → \(!on ? "on" : "off")")
    }

    @objc private func sliderChanged() {
        let text = String(format: "%.2f", slider.value)
        sliderStateLabel.text = text
        logEvent(identifier: "test.slider", event: "valueChanged → \(text)")
    }

    @objc private func segmentedChanged() {
        let title = segmented.titleForSegment(at: segmented.selectedSegmentIndex) ?? "?"
        segmentedStateLabel.text = title
        logEvent(identifier: "test.segmented", event: "valueChanged → \(title)")
    }

    @objc private func stepperChanged() {
        let value = Int(stepper.value)
        stepperStateLabel.text = "\(value)"
        logEvent(identifier: "test.stepper", event: "valueChanged → \(value)")
    }

    @objc private func textEditingBegan() {
        textfieldStateLabel.text = "编辑中: \(textField.text ?? "")"
        logEvent(identifier: "test.textfield", event: "editingDidBegin")
    }

    @objc private func textEditingChanged() {
        textfieldStateLabel.text = "编辑中: \(textField.text ?? "")"
        logEvent(identifier: "test.textfield", event: "editingChanged")
    }

    @objc private func textEditingEnded() {
        textfieldStateLabel.text = "已结束: \(textField.text ?? "")"
        logEvent(identifier: "test.textfield", event: "editingDidEnd")
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
