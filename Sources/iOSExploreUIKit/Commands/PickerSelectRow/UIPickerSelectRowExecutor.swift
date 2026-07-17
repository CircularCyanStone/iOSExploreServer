#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.picker.selectRow` 命令的 executor。
///
/// 职责:在 MainActor 上定位 UIPickerView → 校验 component 范围 → 按 row 或 title 解析目标行
/// → `selectRow(_:inComponent:animated:)` → 手动触发 `pickerView(_:didSelectRow:inComponent:)`
/// delegate(覆盖业务逻辑,selectRow 本身不触发)→ 返回各维度信息便于验证。
///
/// UIPickerView 不是 UIControl,`ui.inspect` 不会为其声明任何 action,`ui.control.sendAction`
/// 完全不适用,故本 executor 是 UIPickerView 程序选行的唯一入口。
@MainActor
enum UIPickerSelectRowExecutor {
    /// 执行行选择。
    ///
    /// - Parameters:
    ///   - input: 已校验的输入模型。
    ///   - context: 当前 UIKit 查询上下文。
    /// - Returns: 选择结果(numberOfComponents / component / numberOfRowsInComponent /
    ///   selectedRow / selectedTitle)。
    /// - Throws: `UIKitCommandError`——定位失败 / 陈旧 / 目标非 UIPickerView / component 或 row 越界 / title 未匹配。
    static func execute(input: UIPickerSelectRowInput, context: UIKitContextProvider.Context) throws -> JSON {
        let action = "ui.picker.selectRow"

        let located = try UIKitLocatorResolver.locate(
            locator: input.target.locator,
            in: context.rootView,
            notFound: {
                UIKitCommandError.targetNotFound(
                    action: action,
                    message: "picker target not found — the page view tree may have changed; call ui.inspect first, then retry with a fresh target",
                    logMessage: "ui picker target not found action=\(action) target=\(input.target.logSummary)")
            },
            ambiguous: { count in
                UIKitCommandError.invalidData(action: action, message: "picker target ambiguous count=\(count)")
            }
        )

        if let viewSnapshotID = input.viewSnapshotID {
            try UIKitActionExecutor.validateViewSnapshot(
                located: located,
                viewSnapshotID: viewSnapshotID,
                context: context,
                action: action
            )
        }

        guard let picker = located.view as? UIPickerView else {
            UIKitCommandLogging.error("command", "\(action) target is not UIPickerView type=\(String(describing: type(of: located.view)))")
            throw UIKitCommandError.invalidData(
                action: action,
                message: "target is not a UIPickerView (got \(String(describing: type(of: located.view))))"
            )
        }

        let numberOfComponents = picker.numberOfComponents
        guard input.component < numberOfComponents else {
            let msg = "component \(input.component) out of range (total \(numberOfComponents))"
            UIKitCommandLogging.error("command", "\(action) \(msg)")
            throw UIKitCommandError.invalidData(action: action, message: msg)
        }
        let numberOfRows = picker.numberOfRows(inComponent: input.component)

        let targetRow: Int
        if let row = input.row {
            targetRow = row
        } else if let title = input.title {
            targetRow = try resolveRow(byTitle: title,
                                       component: input.component,
                                       numberOfRows: numberOfRows,
                                       picker: picker,
                                       action: action)
        } else {
            // parse 已保证 row 与 title 必有其一
            fatalError("unreachable: row and title both nil after parse")
        }

        guard targetRow < numberOfRows else {
            let msg = "row \(targetRow) out of range (component \(input.component) has \(numberOfRows) rows)"
            UIKitCommandLogging.error("command", "\(action) \(msg)")
            throw UIKitCommandError.invalidData(action: action, message: msg)
        }

        picker.selectRow(targetRow, inComponent: input.component, animated: input.animated)
        // selectRow 不会触发 delegate,手动补调以覆盖挂在 didSelectRow 上的业务逻辑(与 ui.tabBar.selectTab 触发 delegate 同理)
        picker.delegate?.pickerView?(picker, didSelectRow: targetRow, inComponent: input.component)

        let selectedTitle = picker.delegate?.pickerView?(picker, titleForRow: targetRow, forComponent: input.component)

        UIKitCommandLogging.info("command", "\(action) completed component=\(input.component) selectedRow=\(targetRow) animated=\(input.animated)")

        return [
            "type": .string("UIPickerView"),
            "numberOfComponents": .double(Double(numberOfComponents)),
            "component": .double(Double(input.component)),
            "numberOfRowsInComponent": .double(Double(numberOfRows)),
            "selectedRow": .double(Double(targetRow)),
            "selectedTitle": selectedTitle.map(JSONValue.string) ?? .null,
        ]
    }

    /// 按 title 在指定 component 中查找首个匹配行。
    ///
    /// 遍历该 component 全部行,调 delegate 的 `titleForRow:forComponent:` 比对。若 picker 无
    /// delegate 或所有行 title 均为 nil(delegate 用 `viewForRow` 而非 `titleForRow` 渲染),
    /// 无法按 title 匹配,抛出相应错误。
    private static func resolveRow(byTitle title: String,
                                   component: Int,
                                   numberOfRows: Int,
                                   picker: UIPickerView,
                                   action: String) throws -> Int {
        guard let delegate = picker.delegate else {
            UIKitCommandLogging.error("command", "\(action) picker has no delegate; cannot resolve title")
            throw UIKitCommandError.invalidData(action: action, message: "picker has no delegate; cannot resolve row by title (delegate must implement titleForRow or use row index instead)")
        }
        for row in 0..<numberOfRows {
            if let rowTitle = delegate.pickerView?(picker, titleForRow: row, forComponent: component), rowTitle == title {
                return row
            }
        }
        UIKitCommandLogging.error("command", "\(action) title not found title=\(title) component=\(component)")
        throw UIKitCommandError.targetNotFound(
            action: action,
            message: "row with title '\(title)' not found in component \(component)",
            logMessage: "ui picker title match failed action=\(action) title=\(title) component=\(component)"
        )
    }
}
#endif
