#if canImport(UIKit)
import Foundation
import ObjectiveC
import iOSExploreServer
import UIKit

/// 一对已触发的 `(gesture, target, action)` 摘要，供 `UIKitActionExecutor.executeTap` 序列化进
/// `ui.tap` 响应 JSON。
///
/// 值类型且全字段 `Sendable`，可跨 `MainActor` 边界传回命令 handler。字段只含类型名与 selector
/// 名（不含 target 对象引用或原始 payload），避免泄露业务对象。
struct UIGestureTriggeredPair: Sendable {
    /// 手势识别器类型名（如 `UITapGestureRecognizer`）。
    let gestureType: String
    /// target 对象类型名（如 `MyViewController`）。
    let targetType: String
    /// 已派发的 selector 名（如 `handleTap:`）。
    let action: String
}

/// `ui.tap` 的手势 target-action 显式 adapter 执行核心。
///
/// 背景：`UIKitDefaultActivationResolver` 只为 `UIButton`/`UISwitch`/文本输入三类确定目标提供
/// 默认激活路由；依赖 `UIGestureRecognizer`（`UITapGestureRecognizer`/`UILongPressGestureRecognizer`/
/// `UIPanGestureRecognizer` 等）的自定义 view 没有公开激活入口，原本直接 `unsupported_target`。
/// 合成触摸（`UITouch+Synthetic`）在 iOS 26 已被证不可行（见 realTouch spike 报告）。本 executor
/// 是降级方案：**不合成 event**，直接 runtime 读 view 上每个手势的 `_targets` → `_target` +
/// `_action`，按 selector 签名派发——与 Lookin（`LKS_GestureTargetActionsSearcher.m`）同路径，
/// 区别是 Lookin 只 search，本 executor 还 invoke。
///
/// 多手势 / 多 target 决策：**全触发**。一个 view 可能挂多个手势（tap + longPress + pan…），每个
/// 手势的 `_targets` 也可能多元素；adapter 不知道调用方意图，全触发最透明，由调用方据响应里的
/// `gestures` 列表自行判断结果。该决策写进手势 adapter 报告并由 `UIKitActionExecutorTests` 覆盖。
///
/// 隔离：本 executor 跟随 `UIKitActionExecutor` 的 `#if canImport(UIKit)`（不额外 `#if DEBUG`）——
/// 它在 Release 也要编译（macOS 空壳）。底层 runtime 入口 `explore_targetActionPairs()` 是
/// `#if DEBUG #if canImport(UIKit)` 双隔离（私有 ivar 读取绝不进 Release）；只有 `execute(on:)`
/// 的调用路径用 `#if DEBUG ... #else 兜底 #endif` 包裹（参照 `UIAlertRespondExecutor.perform`
/// 的隔离边界），Release 下 `execute(on:)` 直接返回 `nil`，让 `executeTap` fallthrough 到
/// `unsupported_target`。`executeCellSelection(on:)` 走公有 API 兜底路径，不受 DEBUG guard
/// 整体包裹，在 Release 下也可工作（仅其内部 DEBUG 日志受 `#if DEBUG` 控制）。
///
/// ## cellSelection 独立路径
///
/// `executeCellSelection(on:)` 处理 `UITableViewCell`/`UICollectionViewCell` 子树内 view 的
/// selection 触发。它与 `execute(on:)` 互斥：cell 子树不走普通手势 adapter（cell 子 view 的
/// `_longPressGestureRecognized:` 是 prepareForReuse 相关手势，不是 selection 语义），由
/// `executeTap` 的 route==nil 分支优先调本方法。本方法内部流程：
/// 1. 向上找 `UITableViewCell`/`UICollectionViewCell` 祖先；不存在 → 返回 nil（不在 cell 子树）。
/// 2. 继续向上找 `UITableView`/`UICollectionView` 祖先；不存在 → 返回 nil（异常状态）。
/// 3. DEBUG：在 containerView 的 gestureRecognizers 中找 `selectGestureHandler:` 手势，只记日志
///    不 invoke（已验证 `selectGestureHandler:` 无真实触摸事件流时静默跳过 `_selectRowAtIndexPath:`，
///    见 spec §4.2 场景 B）。
/// 4. 公有 API 兜底：`indexPath(for:)` + `delegate.didSelectRow/didSelectItem`。
///    见 spec `docs/superpowers/specs/2026-07-05-uitableviewcell-tap-selection-design.md`。
@MainActor
enum UIGestureTargetExecutor {
    /// 对 view 上所有手势的所有 target-action 按签名派发。
    ///
    /// - Parameter view: 已定位的目标 view（`executeTap` 传入的 canonical target）。
    /// - Returns: 触发摘要列表。`nil` 表示 view 无 `gestureRecognizers`（不该走 adapter，调用方
    ///   fallthrough 到默认路由或 `unsupported_target`）；空数组表示有手势但当前 iOS 版本
    ///   ivar 读不出 target-action（漂移，调用方同样 fallthrough）；非空表示已成功触发这些 pair。
    static func execute(on view: UIView) -> [UIGestureTriggeredPair]? {
        guard let gestures = view.gestureRecognizers, !gestures.isEmpty else {
            return nil
        }
        #if DEBUG
        var triggered: [UIGestureTriggeredPair] = []
        for gesture in gestures {
            for pair in gesture.explore_targetActionPairs() {
                invoke(target: pair.target, action: pair.action, sender: gesture)
                triggered.append(UIGestureTriggeredPair(
                    gestureType: String(describing: Swift.type(of: gesture)),
                    targetType: String(describing: Swift.type(of: pair.target)),
                    action: NSStringFromSelector(pair.action)))
            }
        }
        UIKitCommandLogging.info("command",
            "ui tap gesture adapter path-type=UIView gestures=\(gestures.count) triggered=\(triggered.count)")
        return triggered
        #else
        // Release：私有 ivar 读取入口整体 #if DEBUG 隔离，adapter 不可用。返回 nil 让 executeTap
        // fallthrough 到 unsupported_target（与 default 行为一致，绝不假装成功）。
        return nil
        #endif
    }

    /// 按 selector 实际签名派发 action，适配手势 target-action 的 0/1/2 参三种签名。
    ///
    /// 复用 `UINavigationBarButtonExecutor.invoke` 的签名探测逻辑：用 ObjC runtime 读方法真实
    /// 参数个数（含 `self`/`_cmd` 两个隐式参数），因此无参 action 为 2、一参 action 为 3、两参
    /// `(_:forEvent:)` action 为 4。不走 `UIApplication.sendAction`——它在模拟器单测里对无参
    /// selector 不会真正派发（见 `UINavigationBarButtonExecutor.trigger` 注释）。
    ///
    /// `sender` 传手势识别器本身：手势 target-action 约定第一个参数（如有）是 `UIGestureRecognizer`，
    /// 不是 view（与 UIControl 的 sender 是控件本身同理）。
    private static func invoke(target: NSObject, action: Selector, sender: UIGestureRecognizer) {
        let argumentCount: UInt
        if let method = class_getInstanceMethod(type(of: target), action) {
            argumentCount = UInt(method_getNumberOfArguments(method))
        } else {
            argumentCount = 2
        }
        switch argumentCount {
        case 3:
            // func action(_:UIGestureRecognizer)
            target.perform(action, with: sender)
        case 4:
            // func action(_:UIGestureRecognizer, forEvent:UIEvent?)
            target.perform(action, with: sender, with: nil)
        default:
            // func action() 或其他未知签名：按无参派发
            target.perform(action)
        }
    }
}

// MARK: - Cell Selection

/// cell selection adapter 的尝试结果摘要，跨 MainActor 边界回传到 handler。
@MainActor
struct UICellSelectionAttempt: Sendable, Equatable {
    /// 是否成功触发 selection。
    let activated: Bool
    /// 实际触发的路由摘要。
    let activationRoute: String
    /// 入参 view 的运行时类型名。
    let viewType: String
    /// 外层 tableView/CollectionView 的运行时类型名。
    let containerViewType: String?
    /// 命中的 cell 类型名。
    let cellType: String?
    /// 公有 API 路径解析到的 indexPath 摘要。
    let indexPathSummary: IndexPathSummary?
}

// `IndexPathSummary` 定义已移至 `Support/Parsing/IndexPathSummary.swift`（Foundation-only
// 共享 public 类型），同 module 内可直接引用，无需在此重复定义。

@MainActor
extension UIGestureTargetExecutor {
    /// 在 cell 子树内尝试触发 cell selection。
    ///
    /// 流程：
    /// 1. 向上找 `UITableViewCell`/`UICollectionViewCell` 祖先；不存在 → 返回 nil（不在 cell 子树）。
    /// 2. 继续向上找 `UITableView`/`UICollectionView` 祖先；不存在 → 返回 nil（异常状态）。
    /// 3. DEBUG：在 containerView 的 gestureRecognizers 中找 `selectGestureHandler:` 手势，
    ///    只记日志**不 invoke**（已 spike 验证：无真实触摸事件流时 `_UISelectionInteraction` 内部
    ///    静默跳过 `_selectRowAtIndexPath:`，invoke 无效果）。
    /// 4. 公有 API 路径：`indexPath(for:)` + `delegate.didSelectRow/didSelectItem`。
    ///
    /// - Parameter view: `executeTap` 传入的已定位 canonical target。
    /// - Returns: `nil` 表示 view 不在 cell 子树内；`non-nil` 表示在 cell 子树内，已尝试触发。
    static func executeCellSelection(on view: UIView) -> UICellSelectionAttempt? {
        let viewType = String(describing: Swift.type(of: view))

        // 1. 向上找 cell 祖先
        guard let cell = view.explore_cellAncestor else {
            UIKitCommandLogging.info("command",
                "cell selection skip: view not in cell subtree viewType=\(viewType)")
            return nil
        }
        let cellType = String(describing: Swift.type(of: cell))

        // 2. 向上找 containerView 祖先
        guard let container = cell.explore_containerViewAncestor else {
            UIKitCommandLogging.info("command",
                "cell selection skip: cell without tableView ancestor cellType=\(cellType) viewType=\(viewType)")
            return nil
        }
        let containerType = String(describing: Swift.type(of: container))

        // 3. DEBUG：记录 selectGestureHandler: 是否存在（仅观察，不 invoke）
        #if DEBUG
        let gestures = container.gestureRecognizers ?? []
        var foundSelectGestureHandler = false
        for (i, g) in gestures.enumerated() {
            let gestureType = String(describing: Swift.type(of: g))
            for pair in g.explore_targetActionPairs() {
                let actionName = NSStringFromSelector(pair.action)
                let targetType = String(describing: Swift.type(of: pair.target))
                if actionName == "selectGestureHandler:" {
                    foundSelectGestureHandler = true
                    UIKitCommandLogging.info("command",
                        "cell selection observed selectGestureHandler: on container=\(containerType) gesture[\(i)]=\(gestureType) target=\(targetType) — bypassed (B scenario)")
                }
            }
        }
        if !foundSelectGestureHandler {
            UIKitCommandLogging.info("command",
                "cell selection no selectGestureHandler: found on container=\(containerType) viewType=\(viewType)")
        }
        #endif

        // 4. 公有 API 路径：indexPath(for:) + delegate.didSelectRow/didSelectItem
        if let tableView = container as? UITableView {
            return trySelectTableViewRow(tableView: tableView, cell: cell, viewType: viewType, cellType: cellType, containerType: containerType)
        } else if let collectionView = container as? UICollectionView {
            return trySelectCollectionViewItem(collectionView: collectionView, cell: cell, viewType: viewType, cellType: cellType, containerType: containerType)
        } else {
            UIKitCommandLogging.info("command",
                "cell selection unsupported container type=\(containerType) viewType=\(viewType)")
            return UICellSelectionAttempt(
                activated: false,
                activationRoute: "cell.select.unsupported-container",
                viewType: viewType,
                containerViewType: containerType,
                cellType: cellType,
                indexPathSummary: nil
            )
        }
    }

    /// 通过 UITableView 公有 API 触发 cell selection。
    ///
    /// 先 `indexPath(for:)` 定位 cell 的 indexPath，再调 `delegate.tableView?(tableView, didSelectRowAt:)`。
    private static func trySelectTableViewRow(tableView: UITableView, cell: UIView, viewType: String, cellType: String, containerType: String) -> UICellSelectionAttempt? {
        guard let typedCell = cell as? UITableViewCell else {
            UIKitCommandLogging.info("command",
                "cell selection cell not UITableViewCell actual=\(cellType)")
            return UICellSelectionAttempt(
                activated: false,
                activationRoute: "cell.select.not-tableview-cell",
                viewType: viewType,
                containerViewType: containerType,
                cellType: cellType,
                indexPathSummary: nil
            )
        }
        guard let indexPath = tableView.indexPath(for: typedCell) else {
            UIKitCommandLogging.info("command",
                "cell selection indexPath(for:) returned nil for cell=\(cellType)")
            return UICellSelectionAttempt(
                activated: false,
                activationRoute: "cell.select.indexPath-nil",
                viewType: viewType,
                containerViewType: containerType,
                cellType: cellType,
                indexPathSummary: nil
            )
        }
        let summary = IndexPathSummary(section: indexPath.section, item: indexPath.row)

        // 调 delegate.didSelectRow
        tableView.delegate?.tableView?(tableView, didSelectRowAt: indexPath)

        UIKitCommandLogging.info("command",
            "cell selection public API path activated tableView=\(containerType) section=\(indexPath.section) row=\(indexPath.row)")
        return UICellSelectionAttempt(
            activated: true,
            activationRoute: "cell.select.public",
            viewType: viewType,
            containerViewType: containerType,
            cellType: cellType,
            indexPathSummary: summary
        )
    }

    /// 通过 UICollectionView 公有 API 触发 cell selection。
    private static func trySelectCollectionViewItem(collectionView: UICollectionView, cell: UIView, viewType: String, cellType: String, containerType: String) -> UICellSelectionAttempt? {
        guard let typedCell = cell as? UICollectionViewCell else {
            UIKitCommandLogging.info("command",
                "cell selection cell not UICollectionViewCell actual=\(cellType)")
            return UICellSelectionAttempt(
                activated: false,
                activationRoute: "cell.select.not-collectionview-cell",
                viewType: viewType,
                containerViewType: containerType,
                cellType: cellType,
                indexPathSummary: nil
            )
        }
        guard let indexPath = collectionView.indexPath(for: typedCell) else {
            UIKitCommandLogging.info("command",
                "cell selection indexPath(for:) returned nil for cell=\(cellType)")
            return UICellSelectionAttempt(
                activated: false,
                activationRoute: "cell.select.indexPath-nil",
                viewType: viewType,
                containerViewType: containerType,
                cellType: cellType,
                indexPathSummary: nil
            )
        }
        let summary = IndexPathSummary(section: indexPath.section, item: indexPath.item)

        // 调 delegate.didSelectItem
        collectionView.delegate?.collectionView?(collectionView, didSelectItemAt: indexPath)

        UIKitCommandLogging.info("command",
            "cell selection public API path activated collectionView=\(containerType) section=\(indexPath.section) item=\(indexPath.item)")
        return UICellSelectionAttempt(
            activated: true,
            activationRoute: "cell.select.public",
            viewType: viewType,
            containerViewType: containerType,
            cellType: cellType,
            indexPathSummary: summary
        )
    }
}
#endif
