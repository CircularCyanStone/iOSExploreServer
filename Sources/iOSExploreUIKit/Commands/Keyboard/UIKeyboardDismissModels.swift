import Foundation
import iOSExploreServer

/// `ui.keyboard.dismiss` 的键盘收起策略。
///
/// 枚举保持 Foundation-only，UIKit executor 再据此选择 `resignFirstResponder`、
/// `endEditing(true)` 或两者组合。case 顺序会进入 schema 的 enum 列表，调整需同步测试。
public enum KeyboardDismissStrategy: String, Sendable, Equatable, CaseIterable {
    /// 自动策略：先让当前 first responder resign，仍未收起时再对 window 调用 `endEditing(true)`。
    case auto
    /// 只对当前 first responder 调用 `resignFirstResponder()`。
    case resignFirstResponder
    /// 只对当前 window 调用 `endEditing(true)`。
    case endEditing
}

/// `ui.keyboard.dismiss` 的命令参数。
///
/// 命令可在无参数时按自动策略收起键盘；`waitAfterMs` 用于执行后短暂等待，让 UIKit first
/// responder 状态稳定，便于 agent 紧接着读取 UI 状态。
public struct UIKeyboardDismissInput: CommandInput, Sendable, Equatable {
    private enum Fields {
        static let strategy = CommandFields.enumValue(
            "strategy",
            type: KeyboardDismissStrategy.self,
            default: .auto,
            description: "键盘收起策略: auto / resignFirstResponder / endEditing"
        )
        static let waitAfterMs = CommandFields.int(
            "waitAfterMs",
            range: 0...3000,
            default: 200,
            description: "执行后等待毫秒数，范围 0...3000，默认 200"
        )

        static let all: [AnyCommandField] = [
            strategy.erased,
            waitAfterMs.erased,
        ]
    }

    /// `ui.keyboard.dismiss` 暴露给 help 和工具客户端的输入 schema。
    public static let inputSchema = CommandInputSchema(fields: Fields.all)

    /// 键盘收起策略。
    public let strategy: KeyboardDismissStrategy
    /// 执行后等待毫秒数。
    public let waitAfterMs: Int

    /// 创建一条 keyboard dismiss 输入。
    ///
    /// - Parameters:
    ///   - strategy: 键盘收起策略，默认 `.auto`。
    ///   - waitAfterMs: 执行后等待毫秒数，默认 200。
    public init(strategy: KeyboardDismissStrategy = .auto, waitAfterMs: Int = 200) {
        self.strategy = strategy
        self.waitAfterMs = waitAfterMs
    }

    /// 按 `CommandInputDecoder` 读取字段并填充默认值。
    ///
    /// - Parameter decoder: 绑定 `inputSchema` 与请求 data 的字段读取器。
    /// - Returns: 已解析的 keyboard dismiss 输入。
    /// - Throws: 字段类型、枚举值或 `waitAfterMs` 范围非法时抛出 `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIKeyboardDismissInput {
        let strategy = try decoder.read(Fields.strategy)
        let waitAfterMs = try decoder.read(Fields.waitAfterMs)
        return UIKeyboardDismissInput(strategy: strategy, waitAfterMs: waitAfterMs)
    }
}
