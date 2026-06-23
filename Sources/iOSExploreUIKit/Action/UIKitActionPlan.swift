import Foundation

/// UIKit 动作计划。
///
/// 把 tap 与 control.sendAction 两种 UIKit 动作的"执行意图"收敛为一个值类型枚举。adapter
/// （`UITapCommand`/`UIControlSendActionCommand`）只负责解析请求并构造本计划，随后
/// `await UIKitActionExecutor.execute(plan)`；执行逻辑（取 Context、resolve locator、
/// capability 校验、hit-test / sendActions、生成 JSON）集中在 `@MainActor` 的 executor 中。
///
/// 本类型刻意保持 Foundation-only（`Sendable, Equatable`）：它只描述"做什么动作"和"作用在
/// 哪个 locator 上"，不持有 UIKit 对象，因此可在 macOS 测试覆盖构造与字段保留。真实运行时
/// 行为（hit-test、sendActions）由 executor 在 UIKit 隔离域执行，由 Task 7 的 iOS framework
/// 测试覆盖。
///
/// 当前不携带 snapshotID：Task 6 会为 `.path` 变体加 snapshotID，并在 executor 内对陈旧
/// path 做校验。本任务专注把既有 tap/control 执行逻辑正确迁入 executor，保留迁移前行为。
public enum UIKitActionPlan: Sendable, Equatable {
    /// 点击动作。executor 会按 locator 取得目标（坐标则直接 hit-test），命中校验后对
    /// `UIControl` 派发第一版 `touchUpInside` fallback。
    ///
    /// - Parameter locator: 点击目标的统一定位器（identifier / path / windowPoint）。
    case tap(locator: UIKitLocator)
    /// 向 `UIControl` 发送 target-action 事件。executor 会 resolve locator 成 view，校验其
    /// 为 `UIControl`，再 `sendActions(for:)`。
    ///
    /// - Parameters:
    ///   - locator: 目标控件的统一定位器（identifier / path）。
    ///   - event: 要发送的 UIControl 事件。
    case controlEvent(locator: UIKitLocator, event: UIControlSendActionEvent)
}
