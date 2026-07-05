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
}
#endif
