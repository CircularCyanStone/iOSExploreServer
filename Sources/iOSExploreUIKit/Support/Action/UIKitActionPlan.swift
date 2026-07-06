import Foundation
import iOSExploreServer

/// UIKit 动作计划。
///
/// 把 tap 与 control.sendAction 两种 UIKit 动作的"执行意图"收敛为一个值类型枚举。adapter
/// （`UITapCommand`/`UIControlSendActionCommand`）只负责解析请求并构造本计划，随后
/// `await UIKitActionExecutor.execute(plan)`；执行逻辑（取 Context、resolve locator、
/// capability 校验、默认激活路由或 `sendActions(for:)`、生成 JSON）集中在 `@MainActor`
/// 的 executor 中。
///
/// 本类型刻意保持 Foundation-only（`Sendable, Equatable`）：它只描述"做什么动作"、"作用在
/// 哪个 locator 上"以及"携带哪个 `viewSnapshotID` 做陈旧校验"，不持有 UIKit 对象，因此可在
/// macOS 测试覆盖构造与字段保留。真实运行时行为（resolve、sendActions、focus）由 executor
/// 在 UIKit 隔离域执行，由 iOS framework 测试覆盖。
///
/// 重构后 `viewSnapshotID` 对 tap 与 controlEvent 都是**必填**：两者都必须作用于
/// `ui.viewTargets` 结构化观察签发的 canonical target，executor 统一用 `viewSnapshotID`
/// 做 path/context/fingerprint/semanticDigest 陈旧校验（identifier 与 path 同一流程），
/// 不再有坐标 tap、hit-test 或 nearest ancestor fallback。
public enum UIKitActionPlan: Sendable, Equatable {
    /// 默认激活动作：对 canonical target 执行其类型对应的默认激活路由。
    ///
    /// executor 会 resolve locator、用 `viewSnapshotID` 做陈旧校验，再按 target 类型路由：
    /// `UIButton` → `sendActions(.touchUpInside)`；`UISwitch` → 翻转 + `.valueChanged`；
    /// 文本输入 → `becomeFirstResponder()`。它**不是**触摸注入，也不做 hit-test。
    ///
    /// - Parameters:
    ///   - locator: canonical target 的统一定位器（identifier / path）。
    ///   - viewSnapshotID: `ui.viewTargets` 签发的结构化 target 指纹快照标识，必填。
    case tap(locator: UIKitLocator, viewSnapshotID: String)
    /// 向 `UIControl` 发送 target-action 事件。executor 会 resolve locator、用
    /// `viewSnapshotID` 做陈旧校验、校验目标自身为 `UIControl` 且当前声明该精确事件，
    /// 若携带 `value`，executor 会先对 `UISlider`/`UISegmentedControl`/`UIStepper`/`UISwitch`
    /// 写入目标值，再 `sendActions(for:)`。不做 hit-test、不找祖先 control。
    ///
    /// - Parameters:
    ///   - locator: 目标控件的统一定位器（identifier / path）。
    ///   - event: 要发送的 UIControl 事件。
    ///   - value: 要在发送事件前写入控件的可选值；缺省表示只发事件不改值。
    ///   - viewSnapshotID: `ui.viewTargets` 签发的结构化 target 指纹快照标识，必填。
    case controlEvent(locator: UIKitLocator,
                      event: UIControlSendActionEvent,
                      value: JSONValue? = nil,
                      viewSnapshotID: String)
}
