#if canImport(UIKit)
import Foundation
import iOSExploreServer

/// `ui.datePicker.setDate` 命令的输入模型。
///
/// 通过 `accessibilityIdentifier` 或 `path` 定位 `UIDatePicker`,设置其 `date`。
/// 日期来源二选一:
/// - `date`:ISO 8601 字符串(完整 datetime 如 `1990-01-01T00:00:00Z`,可带时区/毫秒;或仅日期 `1990-01-01`);
/// - `year`/`month`/`day`/`hour`/`minute` 分量:只给关心的分量,未提供分量沿用 picker 当前值。
///
/// 两类来源互斥(同时给或都不给均抛 `CommandInputParseError`)。`animated` 控制过渡动画(默认 false)。
/// 该类型整体 Foundation-only：ISO 解析与分量拼装不依赖 UIKit，便于 macOS 输入解析单测；UIKit 类型
/// 只在 executor 内部出现,不穿过 public 边界。
public struct UIDatePickerSetDateInput: CommandInput, Sendable, Equatable {
    /// 目标 UIDatePicker 定位方式(accessibilityIdentifier / path)。
    public let target: UIKitViewLookupTarget
    /// `ui.inspect` 签发的结构化快照标识,可选;identifier / path 两种定位方式都接受陈旧校验。
    public let viewSnapshotID: String?
    /// 已从 ISO 8601 解析的目标日期(与 `components` 互斥)。
    public let date: Date?
    /// 日期分量(与 `date` 互斥);未提供的分量为 nil,执行时沿用 picker 当前值。
    public let components: DateComponents?
    /// 是否动画过渡。
    public let animated: Bool

    /// 创建日期设置输入。
    public init(target: UIKitViewLookupTarget,
                viewSnapshotID: String?,
                date: Date?,
                components: DateComponents?,
                animated: Bool) {
        self.target = target
        self.viewSnapshotID = viewSnapshotID
        self.date = date
        self.components = components
        self.animated = animated
    }

    /// Swift 执行端的 generated 输入定义。
    public static let inputDefinition = UIKitActionContracts.uiDatePickerSetDateInput

    /// 从声明式 decoder 解析输入。
    ///
    /// 读取定位字段、日期来源(date 或分量)与 animated,执行互斥校验后产出 typed 输入。
    /// - Throws: 字段类型/互斥/ISO 解析失败时抛 `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIDatePickerSetDateInput {
        let viewSnapshotID = try decoder.read(UIKitActionContracts.uiDatePickerSetDateViewSnapshotIDField)
        let animated = try decoder.read(UIKitActionContracts.uiDatePickerSetDateAnimatedField)
        let rawDate = try decoder.read(UIKitActionContracts.uiDatePickerSetDateDateField)
        let year = try decoder.read(UIKitActionContracts.uiDatePickerSetDateYearField)
        let month = try decoder.read(UIKitActionContracts.uiDatePickerSetDateMonthField)
        let day = try decoder.read(UIKitActionContracts.uiDatePickerSetDateDayField)
        let hour = try decoder.read(UIKitActionContracts.uiDatePickerSetDateHourField)
        let minute = try decoder.read(UIKitActionContracts.uiDatePickerSetDateMinuteField)
        let target = try UIKitLocatorInput.parse(decoder: &decoder,
                                                  identifierField: UIKitActionContracts.uiDatePickerSetDateAccessibilityIdentifierField,
                                                  pathField: UIKitActionContracts.uiDatePickerSetDatePathField)

        let hasDate = rawDate != nil
        let hasComponents = [year, month, day, hour, minute].contains { $0 != nil }
        if hasDate && hasComponents {
            throw CommandInputParseError("date 与 year/month/day/hour/minute 分量互斥,只能提供一种")
        }
        if !hasDate && !hasComponents {
            throw CommandInputParseError("必须提供 date,或至少一个日期分量(year/month/day/hour/minute)")
        }

        let parsedDate: Date? = try rawDate.map { try Self.parseISO8601($0) }

        let components: DateComponents?
        if hasComponents {
            var dc = DateComponents()
            dc.year = year
            dc.month = month
            dc.day = day
            dc.hour = hour
            dc.minute = minute
            components = dc
        } else {
            components = nil
        }

        return UIDatePickerSetDateInput(target: target,
                                        viewSnapshotID: viewSnapshotID,
                                        date: parsedDate,
                                        components: components,
                                        animated: animated)
    }

    /// 解析 ISO 8601 日期字符串。
    ///
    /// 依次尝试:完整 datetime(带毫秒)→ 完整 datetime(不带毫秒)→ 仅日期 `yyyy-MM-dd`。
    /// 仅日期按 UTC 解析,时间部分为 00:00:00。全部失败抛 `CommandInputParseError`。
    private static func parseISO8601(_ string: String) throws -> Date {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: string) { return date }

        let dayOnly = DateFormatter()
        dayOnly.calendar = Calendar(identifier: .gregorian)
        dayOnly.locale = Locale(identifier: "en_US_POSIX")
        dayOnly.timeZone = TimeZone(identifier: "UTC")
        dayOnly.dateFormat = "yyyy-MM-dd"
        if let date = dayOnly.date(from: string) { return date }

        throw CommandInputParseError("date 无法解析为日期,期望 ISO 8601(如 '1990-01-01T00:00:00Z')或 'yyyy-MM-dd'")
    }
}
#endif
