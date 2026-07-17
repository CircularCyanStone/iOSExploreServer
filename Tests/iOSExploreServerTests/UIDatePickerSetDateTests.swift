import Testing
import Foundation
import iOSExploreServer
@testable import iOSExploreUIKit

#if canImport(UIKit)
import UIKit

// MARK: - UIDatePickerSetDateInput 解析测试
// 注:Input 经 UIKitLocatorInput.parse,accessibilityIdentifier/path 至少一个(与 ui.tap/ui.input
// 一致,操作具体 picker 必须定位)。下列每个 parse(from:) 都带 identifier,确保测的是 date/components
// /animated 的解析与互斥校验,而非误撞 identifier 缺失。

@Test("解析 date ISO8601 完整 datetime")
func datePickerInputParsesFullISO() throws {
    let input = try UIDatePickerSetDateInput.parse(from: [
        "accessibilityIdentifier": .string("birthday"),
        "date": .string("1990-01-01T00:00:00Z")
    ])
    #expect(input.target == .accessibilityIdentifier("birthday"))
    #expect(input.date != nil)
    #expect(input.components == nil)
    #expect(input.animated == false)
}

@Test("解析 date 仅日期 yyyy-MM-dd")
func datePickerInputParsesDateOnly() throws {
    let input = try UIDatePickerSetDateInput.parse(from: [
        "accessibilityIdentifier": .string("birthday"),
        "date": .string("1990-01-01")
    ])
    #expect(input.date != nil)
}

@Test("解析 components 分量")
func datePickerInputParsesComponents() throws {
    let input = try UIDatePickerSetDateInput.parse(from: [
        "accessibilityIdentifier": .string("birthday"),
        "year": .double(1990),
        "month": .double(6),
        "day": .double(15)
    ])
    #expect(input.date == nil)
    #expect(input.components?.year == 1990)
    #expect(input.components?.month == 6)
    #expect(input.components?.day == 15)
    #expect(input.components?.hour == nil)
}

@Test("解析 animated=true")
func datePickerInputParsesAnimated() throws {
    let input = try UIDatePickerSetDateInput.parse(from: [
        "accessibilityIdentifier": .string("birthday"),
        "date": .string("1990-01-01"),
        "animated": .bool(true)
    ])
    #expect(input.animated == true)
}

@Test("拒绝 date 与 components 同时提供")
func datePickerInputRejectsBoth() throws {
    #expect(throws: CommandInputParseError.self) {
        _ = try UIDatePickerSetDateInput.parse(from: [
            "accessibilityIdentifier": .string("birthday"),
            "date": .string("1990-01-01"),
            "year": .double(1990)
        ])
    }
}

@Test("拒绝 date 与 components 都不提供")
func datePickerInputRejectsNeither() {
    #expect(throws: CommandInputParseError.self) {
        _ = try UIDatePickerSetDateInput.parse(from: ["accessibilityIdentifier": .string("birthday")])
    }
}

@Test("拒绝非法 date 格式")
func datePickerInputRejectsBadDate() {
    #expect(throws: CommandInputParseError.self) {
        _ = try UIDatePickerSetDateInput.parse(from: [
            "accessibilityIdentifier": .string("birthday"),
            "date": .string("not-a-date")
        ])
    }
}

@Test("schema 声明全部字段")
func datePickerInputSchemaFields() {
    let fields = UIDatePickerSetDateInput.inputSchema.fields.map(\.name)
    #expect(fields.contains("date"))
    #expect(fields.contains("year"))
    #expect(fields.contains("month"))
    #expect(fields.contains("day"))
    #expect(fields.contains("hour"))
    #expect(fields.contains("minute"))
    #expect(fields.contains("animated"))
}

// MARK: - UIDatePickerSetDateExecutor 测试

/// 构造测试用 UIKitContextProvider.Context(把目标 view 挂进 keyWindow)。
private func makeContext(rootViewController: UIViewController,
                         topViewController: UIViewController,
                         rootView: UIView) -> UIKitContextProvider.Context {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    window.rootViewController = rootViewController
    window.makeKeyAndVisible()
    return UIKitContextProvider.Context(window: window,
                                        rootViewController: rootViewController,
                                        topViewController: topViewController,
                                        rootView: rootView)
}

@Test("按 date 设置日期成功") @MainActor
func setDateByISO() throws {
    let vc = UIViewController()
    let picker = UIDatePicker()
    picker.accessibilityIdentifier = "birthday"
    picker.datePickerMode = .date
    picker.date = Date(timeIntervalSince1970: 0)
    vc.view.addSubview(picker)

    let ctx = makeContext(rootViewController: vc, topViewController: vc, rootView: vc.view)
    let input = UIDatePickerSetDateInput(target: .accessibilityIdentifier("birthday"),
                                         viewSnapshotID: nil,
                                         date: Date(timeIntervalSince1970: 631152000), // 1990-01-01 00:00:00Z
                                         components: nil,
                                         animated: false)
    let result = try UIDatePickerSetDateExecutor.execute(input: input, context: ctx)

    #expect(result["type"]?.stringValue == "UIDatePicker")
    #expect(result["mode"]?.stringValue == "date")
    let delta = abs(picker.date.timeIntervalSince1970 - 631152000)
    #expect(delta < 1)
}

@Test("按 components 设置日期,提供的分量覆盖、未提供分量沿用当前值") @MainActor
func setDateByComponents() throws {
    let vc = UIViewController()
    let picker = UIDatePicker()
    picker.accessibilityIdentifier = "birthday"
    picker.datePickerMode = .date
    picker.date = Date(timeIntervalSince1970: 946684800) // 2000-01-01 00:00:00Z

    let gregorianUTC = { () -> Calendar in
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    picker.calendar = gregorianUTC
    vc.view.addSubview(picker)

    let ctx = makeContext(rootViewController: vc, topViewController: vc, rootView: vc.view)
    var dc = DateComponents()
    dc.year = 1990
    dc.month = 6
    dc.day = 15
    let input = UIDatePickerSetDateInput(target: .accessibilityIdentifier("birthday"),
                                         viewSnapshotID: nil,
                                         date: nil,
                                         components: dc,
                                         animated: false)
    _ = try UIDatePickerSetDateExecutor.execute(input: input, context: ctx)

    let comps = gregorianUTC.dateComponents([.year, .month, .day], from: picker.date)
    #expect(comps.year == 1990)
    #expect(comps.month == 6)
    #expect(comps.day == 15)
}

@Test("目标非 UIDatePicker 抛错") @MainActor
func setDateNonDatePickerThrows() throws {
    let vc = UIViewController()
    let label = UILabel()
    label.accessibilityIdentifier = "notpicker"
    vc.view.addSubview(label)

    let ctx = makeContext(rootViewController: vc, topViewController: vc, rootView: vc.view)
    let input = UIDatePickerSetDateInput(target: .accessibilityIdentifier("notpicker"),
                                         viewSnapshotID: nil,
                                         date: Date(timeIntervalSince1970: 0),
                                         components: nil,
                                         animated: false)
    #expect(throws: UIKitCommandError.self) {
        _ = try UIDatePickerSetDateExecutor.execute(input: input, context: ctx)
    }
}

// valueChanged 触发不在此单测覆盖:UIControl.sendActions(for:) 在 XCTest host(无真实 UI 事件循环、
// UIDatePicker 未到运行时态)下不 dispatch target-action,单测断言会假阴(实测 cap.fired 恒 false)。
// 该行为由端到端验证覆盖:SPMExample 的 DatePickerPickerTestViewController 里 datepicker.test.value
// label 在 valueChanged 回调中更新,实测 ui.datePicker.setDate 后 label 同步显示新日期(2000-02-29),
// 证明 Executor 的 setDate + sendActions(.valueChanged) 真实触发了 target-action。

#endif
