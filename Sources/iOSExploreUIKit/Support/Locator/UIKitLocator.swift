import Foundation

/// UIKit 命令统一目标定位器（执行层别名）。
///
/// `UIKitLocator` 与 `UIKitViewLookupTarget` 是同一个 Foundation-only 值类型
///（`accessibilityIdentifier` / `path` 两种 case）的两个名字：解析层（命令 input 字段、
/// `UIKitLocatorInput.parse` 产出）用 `UIKitViewLookupTarget`，执行层（`UIKitActionPlan`、
/// `UIKitLocatorResolver`、`UIKitActionExecutor`）用 `UIKitLocator`。两者 case、`logSummary`、
/// 文法校验完全一致，故以 typealias 合并到单一实现（`UIKitViewLookupTarget`），消除重复抽象
/// —— 既不必维护两份逐字相同的 `logSummary`，也避免 `UIKitLocator.parse` 退化成对
/// `UIKitViewLookupTarget.parse` 的恒等映射。
///
/// 重构后**不再支持 window 坐标定位**：`ui.tap` 已收敛为只作用于 `ui.inspect` 签发的
/// canonical target 的默认激活，不做 hit-test、不接受裸坐标。若未来需要纯观察的坐标诊断，
/// 另开 `ui.hitTest` 命令，不在本类型表达执行性坐标定位。
///
/// 值类型（`Sendable, Equatable`），可在 macOS 测试覆盖；解析为真实 `UIView` 的工作交给
/// `UIKitLocatorResolver`（`@MainActor`，仅 iOS 编译）。
public typealias UIKitLocator = UIKitViewLookupTarget
