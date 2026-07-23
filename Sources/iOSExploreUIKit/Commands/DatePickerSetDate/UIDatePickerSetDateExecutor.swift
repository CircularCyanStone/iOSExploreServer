#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.datePicker.setDate` 命令的 executor。
///
/// 职责:在 MainActor 上定位 UIDatePicker → 解析目标日期(`date` 直接用,或 `components`
/// 模式把用户分量叠加到 picker 当前日期上,未提供分量沿用)→ `setDate(_:animated:)`
/// → `sendActions(for: .valueChanged)` 触发 target-action → 返回设置前后日期与 picker mode。
///
/// UIDatePicker 在 `ui.inspect` 里不暴露可设值 action(`UIKitActionCapabilityResolver`
/// 不对 UIDatePicker 声明设值事件),`ui.control.sendAction` 的 value 也不支持 UIDatePicker,
/// 故本 executor 是 UIDatePicker 程序设值的唯一入口。
@MainActor
enum UIDatePickerSetDateExecutor {
    /// 执行日期设置。
    ///
    /// - Parameters:
    ///   - input: 已校验的输入模型。
    ///   - context: 当前 UIKit 查询上下文。
    /// - Returns: 设置结果(type / mode / previousDate / date,日期为 ISO 8601 字符串)。
    /// - Throws: `UIKitCommandError`——定位失败 / 陈旧 / 目标非 UIDatePicker。
    static func execute(input: UIDatePickerSetDateInput, context: UIKitContextProvider.Context) throws -> JSON {
        let action = "ui.datePicker.setDate"

        let located = try UIKitLocatorResolver.locate(
            locator: input.target.locator,
            in: context.rootView,
            notFound: {
                UIKitCommandError.targetNotFound(
                    action: action,
                    message: "datePicker target not found — the page view tree may have changed; call ui.inspect first, then retry with a fresh target",
                    logMessage: "ui datePicker target not found action=\(action) target=\(input.target.logSummary)")
            },
            ambiguous: { count in
                UIKitCommandError.invalidData(action: action, message: "datePicker target ambiguous count=\(count)")
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

        guard let datePicker = located.view as? UIDatePicker else {
            UIKitCommandLogger.error("command", "\(action) target is not UIDatePicker type=\(String(describing: type(of: located.view)))")
            throw UIKitCommandError.invalidData(
                action: action,
                message: "target is not a UIDatePicker (got \(String(describing: type(of: located.view))))"
            )
        }

        let previousDate = datePicker.date
        let calendar = datePicker.calendar ?? .current

        let resolvedDate: Date
        if let date = input.date {
            resolvedDate = date
        } else if let components = input.components {
            resolvedDate = resolveDate(from: components, base: previousDate, calendar: calendar)
        } else {
            // parse 已保证 date 与 components 必有其一
            fatalError("unreachable: date and components both nil after parse")
        }

        datePicker.setDate(resolvedDate, animated: input.animated)
        datePicker.sendActions(for: .valueChanged)

        UIKitCommandLogger.info("command", "\(action) completed mode=\(modeString(datePicker.datePickerMode)) animated=\(input.animated)")

        return [
            "type": .string("UIDatePicker"),
            "mode": .string(modeString(datePicker.datePickerMode)),
            "previousDate": .string(formatISO(previousDate)),
            "date": .string(formatISO(datePicker.date)),
        ]
    }

    /// 把用户提供的分量叠加到 base 日期上:未提供的分量沿用 base,提供的分量覆盖。
    ///
    /// components 模式下用户通常只关心部分分量(如只改 year),其余从 picker 当前值继承,
    /// 避免要求调用方每次都给全 year/month/day/hour/minute。
    private static func resolveDate(from components: DateComponents,
                                    base: Date,
                                    calendar: Calendar) -> Date {
        var merged = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: base)
        if let v = components.year { merged.year = v }
        if let v = components.month { merged.month = v }
        if let v = components.day { merged.day = v }
        if let v = components.hour { merged.hour = v }
        if let v = components.minute { merged.minute = v }
        return calendar.date(from: merged) ?? base
    }

    /// UIDatePicker.Mode 转可读字符串。
    private static func modeString(_ mode: UIDatePicker.Mode) -> String {
        switch mode {
        case .time: return "time"
        case .date: return "date"
        case .dateAndTime: return "dateAndTime"
        case .countDownTimer: return "countDownTimer"
        @unknown default: return "unknown"
        }
    }

    /// 日期转 ISO 8601 字符串(UTC,响应统一格式)。
    private static func formatISO(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
#endif
