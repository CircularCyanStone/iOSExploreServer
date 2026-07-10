#if canImport(UIKit)
import UIKit

// MARK: - Cell 祖先查找

/// `UIGestureTargetExecutor.executeCellSelection(on:)` 与
/// `UIKitActionCapabilityResolver.resolve(view:rootView:)` 共享的 cell / containerView
/// 向上查找 helper。
///
/// #### 用法
/// ```swift
/// guard let cell = view.explore_cellAncestor else { return nil }
/// guard let container = cell.explore_containerViewAncestor else { return nil }
/// ```
extension UIView {
    /// 从自身向上遍历 superview 链，返回第一个 `UITableViewCell` 或 `UICollectionViewCell` 祖先。
    ///
    /// 遍历顺序：`superview` → `superview?.superview` → ... → `nil`（不包含自身）。
    /// 找不到或不在 cell 子树内时返回 `nil`。
    @MainActor
    var explore_cellAncestor: UIView? {
        var current: UIView? = superview
        while let node = current {
            if node is UITableViewCell || node is UICollectionViewCell {
                return node
            }
            current = node.superview
        }
        return nil
    }

    /// 从自身向上遍历 superview 链，返回第一个 `UITableView` 或 `UICollectionView` 祖先。
    ///
    /// 一般跟在 `explore_cellAncestor` 之后调用——从 cell 的 superview 继续向上找。
    /// 找不到时返回 `nil`（正常状态下不应出现，仅防御）。
    @MainActor
    var explore_containerViewAncestor: UIView? {
        var current: UIView? = superview
        while let node = current {
            if node is UITableView || node is UICollectionView {
                return node
            }
            current = node.superview
        }
        return nil
    }

    /// 从自身向上遍历 superview 链，返回第一个 `UIControl` 祖先（不含自身）。
    ///
    /// 用于 ui.inspect 的 rollup 判定：控件内嵌展示节点（典型是 `UIButton` 内部渲染
    /// title 的 `UIButtonLabel`）本身有静态文本，会命中 `hasStaticText` 而 full。但它的
    /// 文本已通过父 control 的 `semanticText`（buttonTitle 等）汇总给父 target，独立签发
    /// 反而破坏"签发=可操作"不变式（其 tap 会返回 `unsupported_target`）。
    ///
    /// 因此 collector 在构造 candidate 时，对"自身非 `UIControl`、祖先链含 `UIControl`"
    /// 的节点标记 `isInControlSubtree=true`，`isFull` 据此 rollup 到父 control。
    ///
    /// 关键边界：`UITableViewCell` / `UICollectionViewCell` **不是** `UIControl`，
    /// 故 cell 子树内的 label 不会被本方法命中，仍按 `hasStaticText` 进 full——这是
    /// spec §3.4「cell 内 UILabel 可被 agent 直接 tap」的核心目标。
    ///
    /// 遍历顺序：`superview` → `superview?.superview` → ... → `nil`（不包含自身）。
    /// 找不到或不在 `UIControl` 子树内时返回 `nil`。
    @MainActor
    var explore_controlAncestor: UIView? {
        var current: UIView? = superview
        while let node = current {
            if node is UIControl {
                return node
            }
            current = node.superview
        }
        return nil
    }
}
#endif
