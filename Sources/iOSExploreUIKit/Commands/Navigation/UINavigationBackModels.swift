import Foundation
import iOSExploreServer

/// `ui.navigation.back` 的返回策略。
///
/// 枚举保持 Foundation-only，UIKit executor 再据此选择 dismiss、navigation pop 或两者组合。
/// rawValue 必须与 `contracts/` 中的 enum 一致，新增取值需同步合同与测试。
public enum NavigationBackStrategy: String, Sendable, Equatable, CaseIterable {
    /// 自动策略：先尝试 dismiss 被 present 的控制器，仍无可返回时再尝试 navigation pop。
    case auto
    /// 只走 `UINavigationController.popViewController`，没有导航栈时失败。
    case navigationController
    /// 只走 `UIViewController.dismiss`，没有被 present 的控制器时失败。
    case dismiss
}

/// `ui.navigation.back` 的命令参数。
///
/// 命令可在无参数时按自动策略返回上一页；`animated` 默认关闭以减少转场等待，`waitAfterMs`
/// 用于执行后短暂等待转场稳定，便于 agent 紧接着读取 UI 状态。
///
/// 输入字段使用 `strategy` 而非 `mode`：旧版本文档中提到的 `mode` 字段
/// （auto/dismiss/pop）从未被实现。实际已存在的字段是 `strategy`
/// （NavigationBackStrategy 枚举，含 auto / navigationController / dismiss 三个值）。
public struct UINavigationBackInput: CommandInput, Sendable, Equatable {
    /// `ui.navigation.back` 在 Swift 执行端使用的 generated 输入定义。
    public static let inputDefinition = UIKitActionContracts.uiNavigationBackInput

    /// 返回策略。
    public let strategy: NavigationBackStrategy
    /// 是否动画。
    public let animated: Bool
    /// 执行后等待毫秒数。
    public let waitAfterMs: Int

    /// 创建一条 navigation back 输入。
    ///
    /// - Parameters:
    ///   - strategy: 返回策略，默认 `.auto`。
    ///   - animated: 是否动画，默认 `false`。
    ///   - waitAfterMs: 执行后等待毫秒数，默认 300。
    public init(strategy: NavigationBackStrategy = .auto,
                animated: Bool = false,
                waitAfterMs: Int = 300) {
        self.strategy = strategy
        self.animated = animated
        self.waitAfterMs = waitAfterMs
    }

    /// 按 `CommandInputDecoder` 读取字段并填充默认值。
    ///
    /// - Parameter decoder: 绑定 generated 输入定义与请求 data 的字段读取器。
    /// - Returns: 已解析的 navigation back 输入。
    /// - Throws: 字段类型、枚举值或 `waitAfterMs` 范围非法时抛出 `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UINavigationBackInput {
        let strategyValue = try decoder.read(UIKitActionContracts.uiNavigationBackStrategyField)
        guard let strategy = NavigationBackStrategy(rawValue: strategyValue) else {
            throw CommandInputParseError("unsupported navigation back strategy '\(strategyValue)'")
        }
        let animated = try decoder.read(UIKitActionContracts.uiNavigationBackAnimatedField)
        let waitAfterMs = try decoder.read(UIKitActionContracts.uiNavigationBackWaitAfterMsField)
        return UINavigationBackInput(strategy: strategy, animated: animated, waitAfterMs: waitAfterMs)
    }
}
