//
//  DatePickerPickerTestViewController.swift
//  SPMExample
//
//  Created for ui.datePicker.setDate / ui.picker.selectRow e2e testing.
//

import UIKit

/// 用于验证 `ui.datePicker.setDate` 与 `ui.picker.selectRow` 命令的测试页面。
///
/// 提供一个 UIDatePicker(.date mode)和一个 UIPickerView(单列城市),各自带
/// accessibilityIdentifier 供命令定位,并用 label 实时显示当前值便于 iOSDriver 读回校验。
final class DatePickerPickerTestViewController: UIViewController {

    // MARK: - DatePicker

    private let datePicker: UIDatePicker = {
        let dp = UIDatePicker()
        dp.translatesAutoresizingMaskIntoConstraints = false
        dp.datePickerMode = .date
        dp.preferredDatePickerStyle = .wheels
        dp.accessibilityIdentifier = "datepicker.test"
        // 初始日期固定为 1990-01-01 UTC,便于端到端断言「设值后发生变化」
        dp.date = Date(timeIntervalSince1970: 631152000)
        return dp
    }()

    private let dateTitleLabel = DatePickerPickerTestViewController.makeTitleLabel(text: "📅 UIDatePicker (identifier=datepicker.test)")
    private let dateValueLabel = DatePickerPickerTestViewController.makeValueLabel(identifier: "datepicker.test.value")

    // MARK: - Picker

    private let picker: UIPickerView = {
        let p = UIPickerView()
        p.translatesAutoresizingMaskIntoConstraints = false
        p.accessibilityIdentifier = "picker.test"
        return p
    }()

    private let pickerTitleLabel = DatePickerPickerTestViewController.makeTitleLabel(text: "🎒 UIPickerView (identifier=picker.test)")
    private let pickerValueLabel = DatePickerPickerTestViewController.makeValueLabel(identifier: "picker.test.value")

    private let cities = ["北京", "上海", "广州", "深圳", "杭州"]

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "DatePicker/Picker 测试"

        datePicker.addTarget(self, action: #selector(dateChanged(_:)), for: .valueChanged)
        picker.dataSource = self
        picker.delegate = self

        setupLayout()
        updateLabels()
    }

    private func setupLayout() {
        view.addSubview(dateTitleLabel)
        view.addSubview(datePicker)
        view.addSubview(dateValueLabel)
        view.addSubview(pickerTitleLabel)
        view.addSubview(picker)
        view.addSubview(pickerValueLabel)

        NSLayoutConstraint.activate([
            dateTitleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            dateTitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            dateTitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            datePicker.topAnchor.constraint(equalTo: dateTitleLabel.bottomAnchor, constant: 8),
            datePicker.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            datePicker.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            dateValueLabel.topAnchor.constraint(equalTo: datePicker.bottomAnchor, constant: 8),
            dateValueLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            dateValueLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            pickerTitleLabel.topAnchor.constraint(equalTo: dateValueLabel.bottomAnchor, constant: 24),
            pickerTitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            pickerTitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            picker.topAnchor.constraint(equalTo: pickerTitleLabel.bottomAnchor, constant: 8),
            picker.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            picker.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            picker.heightAnchor.constraint(equalToConstant: 180),

            pickerValueLabel.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 8),
            pickerValueLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            pickerValueLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
    }

    /// 同步把 DatePicker 当前日期与 Picker 当前选中行写入 label,供 iOSDriver 读回校验设值是否生效。
    private func updateLabels() {
        dateValueLabel.text = "当前 date: \(Self.isoFormatter.string(from: datePicker.date))"
        let row = picker.selectedRow(inComponent: 0)
        let city = (0..<cities.count).contains(row) ? cities[row] : "(未选)"
        pickerValueLabel.text = "当前选中: row=\(row) title=\(city)"
    }

    @objc private func dateChanged(_ sender: UIDatePicker) {
        updateLabels()
    }

    // MARK: - 控件工厂

    private static func makeTitleLabel(text: String) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.numberOfLines = 0
        return label
    }

    private static func makeValueLabel(identifier: String) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        label.numberOfLines = 0
        label.backgroundColor = .secondarySystemBackground
        label.layer.cornerRadius = 6
        label.clipsToBounds = true
        label.accessibilityIdentifier = identifier
        return label
    }
}

// MARK: - UIPickerView DataSource & Delegate

extension DatePickerPickerTestViewController: UIPickerViewDataSource, UIPickerViewDelegate {
    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { cities.count }
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? { cities[row] }
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) { updateLabels() }
}
