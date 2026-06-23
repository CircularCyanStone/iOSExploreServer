import Foundation

/// UIKit 查询参数中的安全整数解析工具。
///
/// 命令协议把 JSON 数字统一表示为 `Double`。直接把任意 `Double` 转为 `Int` 会在超出
/// `Int` 范围时触发 Swift 运行时断言，因此所有 UIKit 查询的整数参数必须先在这里完成
/// 有限性、整数性和范围校验，再生成 `Int`。
enum UIKitQueryNumber {
    /// 解析非负整数。
    ///
    /// - Parameter value: JSON 数字值。
    /// - Returns: 值为有限、非负且可安全转换的整数时返回该整数；否则返回 `nil`。
    static func nonNegativeInteger(_ value: Double) -> Int? {
        guard let integer = integer(value), integer >= 0 else { return nil }
        return integer
    }

    /// 解析限定范围内的整数。
    ///
    /// - Parameters:
    ///   - value: JSON 数字值。
    ///   - range: 允许的闭区间。
    /// - Returns: 值可安全转换且位于指定范围时返回该整数；否则返回 `nil`。
    static func integer(_ value: Double, in range: ClosedRange<Int>) -> Int? {
        guard let integer = integer(value), range.contains(integer) else {
            return nil
        }
        return integer
    }

    /// 把有限且处于 `Int` 表示范围内的整数值安全转换为 `Int`。
    ///
    /// - Parameter value: JSON 数字值。
    /// - Returns: 安全转换结果；小数、NaN、无穷或超出 `Int` 范围时返回 `nil`。
    private static func integer(_ value: Double) -> Int? {
        guard value.isFinite,
              value >= Double(Int.min),
              value < Double(Int.max),
              value.rounded(.towardZero) == value else {
            return nil
        }
        return Int(value)
    }
}
