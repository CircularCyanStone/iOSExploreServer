import Testing
import Foundation
import iOSExploreServer
@testable import iOSExploreUIKit

#if canImport(UIKit)
import UIKit

// MARK: - UIPickerSelectRowInput 解析测试

@Test("解析 row 选行")
func pickerInputParsesRow() throws {
    let input = try UIPickerSelectRowInput.parse(from: [
        "accessibilityIdentifier": .string("city"),
        "component": .double(0),
        "row": .double(2)
    ])
    #expect(input.target == .accessibilityIdentifier("city"))
    #expect(input.component == 0)
    #expect(input.row == 2)
    #expect(input.title == nil)
    #expect(input.animated == false)
}

@Test("解析 title 选行")
func pickerInputParsesTitle() throws {
    let input = try UIPickerSelectRowInput.parse(from: [
        "component": .double(0),
        "title": .string("上海")
    ])
    #expect(input.row == nil)
    #expect(input.title == "上海")
}

@Test("解析 animated=true")
func pickerInputParsesAnimated() throws {
    let input = try UIPickerSelectRowInput.parse(from: ["component": .double(0), "row": .double(1), "animated": .bool(true)])
    #expect(input.animated == true)
}

@Test("拒绝 component 缺失")
func pickerInputRejectsMissingComponent() {
    #expect(throws: CommandInputParseError.self) {
        _ = try UIPickerSelectRowInput.parse(from: ["row": .double(0)])
    }
}

@Test("拒绝 row 与 title 同时提供")
func pickerInputRejectsBoth() {
    #expect(throws: CommandInputParseError.self) {
        _ = try UIPickerSelectRowInput.parse(from: ["component": .double(0), "row": .double(0), "title": .string("x")])
    }
}

@Test("拒绝 row 与 title 都不提供")
func pickerInputRejectsNeither() {
    #expect(throws: CommandInputParseError.self) {
        _ = try UIPickerSelectRowInput.parse(from: ["component": .double(0)])
    }
}

@Test("schema 声明全部字段")
func pickerInputSchemaFields() {
    let fields = UIPickerSelectRowInput.inputSchema.fields.map(\.name)
    #expect(fields.contains("component"))
    #expect(fields.contains("row"))
    #expect(fields.contains("title"))
    #expect(fields.contains("animated"))
}

// MARK: - UIPickerSelectRowExecutor 测试

/// 测试用 UIPickerView dataSource/delegate:按 component 存标题二维数组,记录 didSelectRow。
private final class TestPickerDataSource: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
    let titles: [[String]]
    var didSelectRow: Int?
    var didSelectComponent: Int?

    init(titles: [[String]]) { self.titles = titles }

    func numberOfComponents(in pickerView: UIPickerView) -> Int { titles.count }
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        titles[component].count
    }
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        titles[component][row]
    }
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        didSelectRow = row
        didSelectComponent = component
    }
}

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

@Test("按 row 选行成功") @MainActor
func selectRowByIndex() throws {
    let vc = UIViewController()
    let picker = UIPickerView()
    picker.accessibilityIdentifier = "city"
    let dataSource = TestPickerDataSource(titles: [["北京", "上海", "广州"]])
    picker.dataSource = dataSource
    picker.delegate = dataSource
    vc.view.addSubview(picker)

    let ctx = makeContext(rootViewController: vc, topViewController: vc, rootView: vc.view)
    let input = UIPickerSelectRowInput(target: .accessibilityIdentifier("city"),
                                       viewSnapshotID: nil,
                                       component: 0,
                                       row: 2,
                                       title: nil,
                                       animated: false)
    let result = try UIPickerSelectRowExecutor.execute(input: input, context: ctx)

    #expect(result["type"]?.stringValue == "UIPickerView")
    #expect(result["numberOfComponents"]?.doubleValue == 1)
    #expect(result["numberOfRowsInComponent"]?.doubleValue == 3)
    #expect(result["selectedRow"]?.doubleValue == 2)
    #expect(result["selectedTitle"]?.stringValue == "广州")
    #expect(picker.selectedRow(inComponent: 0) == 2)
    #expect(dataSource.didSelectRow == 2)
}

@Test("按 title 选行成功") @MainActor
func selectRowByTitle() throws {
    let vc = UIViewController()
    let picker = UIPickerView()
    picker.accessibilityIdentifier = "city"
    let dataSource = TestPickerDataSource(titles: [["北京", "上海", "广州"]])
    picker.dataSource = dataSource
    picker.delegate = dataSource
    vc.view.addSubview(picker)

    let ctx = makeContext(rootViewController: vc, topViewController: vc, rootView: vc.view)
    let input = UIPickerSelectRowInput(target: .accessibilityIdentifier("city"),
                                       viewSnapshotID: nil,
                                       component: 0,
                                       row: nil,
                                       title: "上海",
                                       animated: false)
    let result = try UIPickerSelectRowExecutor.execute(input: input, context: ctx)

    #expect(result["selectedRow"]?.doubleValue == 1)
    #expect(picker.selectedRow(inComponent: 0) == 1)
}

@Test("component 越界抛错") @MainActor
func selectRowComponentOutOfRange() throws {
    let vc = UIViewController()
    let picker = UIPickerView()
    picker.accessibilityIdentifier = "city"
    let dataSource = TestPickerDataSource(titles: [["北京", "上海"]])
    picker.dataSource = dataSource
    picker.delegate = dataSource
    vc.view.addSubview(picker)

    let ctx = makeContext(rootViewController: vc, topViewController: vc, rootView: vc.view)
    let input = UIPickerSelectRowInput(target: .accessibilityIdentifier("city"),
                                       viewSnapshotID: nil,
                                       component: 5,
                                       row: 0,
                                       title: nil,
                                       animated: false)
    #expect(throws: UIKitCommandError.self) {
        _ = try UIPickerSelectRowExecutor.execute(input: input, context: ctx)
    }
}

@Test("row 越界抛错") @MainActor
func selectRowOutOfRange() throws {
    let vc = UIViewController()
    let picker = UIPickerView()
    picker.accessibilityIdentifier = "city"
    let dataSource = TestPickerDataSource(titles: [["北京", "上海"]])
    picker.dataSource = dataSource
    picker.delegate = dataSource
    vc.view.addSubview(picker)

    let ctx = makeContext(rootViewController: vc, topViewController: vc, rootView: vc.view)
    let input = UIPickerSelectRowInput(target: .accessibilityIdentifier("city"),
                                       viewSnapshotID: nil,
                                       component: 0,
                                       row: 99,
                                       title: nil,
                                       animated: false)
    #expect(throws: UIKitCommandError.self) {
        _ = try UIPickerSelectRowExecutor.execute(input: input, context: ctx)
    }
}

@Test("title 未匹配抛错") @MainActor
func selectRowTitleNotFound() throws {
    let vc = UIViewController()
    let picker = UIPickerView()
    picker.accessibilityIdentifier = "city"
    let dataSource = TestPickerDataSource(titles: [["北京", "上海"]])
    picker.dataSource = dataSource
    picker.delegate = dataSource
    vc.view.addSubview(picker)

    let ctx = makeContext(rootViewController: vc, topViewController: vc, rootView: vc.view)
    let input = UIPickerSelectRowInput(target: .accessibilityIdentifier("city"),
                                       viewSnapshotID: nil,
                                       component: 0,
                                       row: nil,
                                       title: "深圳",
                                       animated: false)
    #expect(throws: UIKitCommandError.self) {
        _ = try UIPickerSelectRowExecutor.execute(input: input, context: ctx)
    }
}

@Test("目标非 UIPickerView 抛错") @MainActor
func selectRowNonPickerThrows() throws {
    let vc = UIViewController()
    let label = UILabel()
    label.accessibilityIdentifier = "notpicker"
    vc.view.addSubview(label)

    let ctx = makeContext(rootViewController: vc, topViewController: vc, rootView: vc.view)
    let input = UIPickerSelectRowInput(target: .accessibilityIdentifier("notpicker"),
                                       viewSnapshotID: nil,
                                       component: 0,
                                       row: 0,
                                       title: nil,
                                       animated: false)
    #expect(throws: UIKitCommandError.self) {
        _ = try UIPickerSelectRowExecutor.execute(input: input, context: ctx)
    }
}

#endif
