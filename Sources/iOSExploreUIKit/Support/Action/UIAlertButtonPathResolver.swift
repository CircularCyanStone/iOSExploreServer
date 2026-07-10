#if DEBUG
#if canImport(UIKit)
import Foundation
import UIKit

/// 从 alert VC 视图树解析按钮路径。
///
/// iOS 26 上 `UIAlertController` 的按钮通过公开 `subviews` DFS 可正常抵达（深度约 9-11），
/// 实际包含链为 `_UIAlertControllerView → … → _UIAlertControllerActionView → UILabel`。
/// 本类型从 `rootView.subviews` 递归遍历，找到 `_UIAlertControllerActionView` 后匹配
/// 其内 `UILabel.text == alert.actions[i].title`，返回可被 `ui.tap` / `ui.inspect`
/// 使用的稳定 path 字符串。
///
/// 该文件受 `#if DEBUG` 保护，不会进入 Release 二进制——符合项目硬规则：私有 API 路径解析
/// 只用于 Debug 探索工具。
@MainActor
enum UIAlertButtonPathResolver {
    /// 一个已解析路径的按钮摘要。
    struct ResolvedButton: Sendable, Equatable {
        /// 在 `alert.actions` 中的下标。
        let index: Int
        /// 按钮标题（可能为 nil）。
        let title: String?
        /// 按钮角色。
        let role: AlertButtonRole
        /// 该按钮 `_UIAlertControllerActionView` 的定位路径；未解析到时为 nil。
        let path: String?
    }

    /// 解析 alert 按钮的路径。
    ///
    /// DFS 遍历 `rootView.subviews`，在每个子树中查找 `_UIAlertControllerActionView`
    /// 类型的 view，并将该 view 下找到的 `UILabel.text` 与 `alert.actions[i].title` 匹配。
    /// 匹配成功的按钮返回 `UIKitViewLookupTarget.pathString(from:)` 格式的 path。
    ///
    /// - Parameters:
    ///   - alert: 待解析的 `UIAlertController`。
    ///   - rootView: 当前顶部控制器的根 view。
    /// - Returns: 每个按钮的解析结果；未找到 view 树或无 actions 时返回空数组。
    static func resolveButtons(in alert: UIAlertController, rootView: UIView) -> [ResolvedButton] {
        let actions = alert.actions
        guard !actions.isEmpty else { return [] }

        var resolved = [Int: String?]()
        for (subviewIndex, subview) in rootView.subviews.enumerated() {
            dfsFindButtons(
                view: subview,
                actions: actions,
                resolved: &resolved,
                indexPath: [subviewIndex]
            )
            if resolved.count == actions.count { break }
        }

        return actions.enumerated().map { index, action in
            ResolvedButton(
                index: index,
                title: action.title,
                role: AlertButtonRole(style: action.style),
                path: resolved[index] ?? nil
            )
        }
    }

    // MARK: - Private

    /// DFS 递归：在 view 子树中查找 `_UIAlertControllerActionView` 并匹配 action title。
    private static func dfsFindButtons(
        view: UIView,
        actions: [UIAlertAction],
        resolved: inout [Int: String?],
        indexPath: [Int]
    ) {
        if resolved.count == actions.count { return }

        let typeName = String(describing: type(of: view))

        // 到达按钮 view：在其子树中查找 UILabel 并按 text 匹配 action。
        if typeName.contains("_UIAlertControllerActionView") {
            let viewPath = UIKitViewLookupTarget.pathString(from: indexPath)
            var claimedActions = Set(resolved.keys)
            let labelPath = findLabelForUnclaimedAction(
                in: view,
                actions: actions,
                claimedActions: &claimedActions,
                basePath: viewPath
            )
            for (key, path) in labelPath {
                resolved[key] = path
            }
            return
        }

        // 递归子节点。
        for (childIndex, child) in view.subviews.enumerated() {
            dfsFindButtons(
                view: child,
                actions: actions,
                resolved: &resolved,
                indexPath: indexPath + [childIndex]
            )
            if resolved.count == actions.count { return }
        }
    }

    /// 在 `_UIAlertControllerActionView` 子树中查找 `UILabel`，匹配尚未认领的 action。
    ///
    /// 返回 `[actionIndex: path]`——每个已认领 action 的路径即该 action view 本身的路径
    /// （`_UIAlertControllerActionView` 是比 `UILabel` 更稳定的点击目标）。
    private static func findLabelForUnclaimedAction(
        in view: UIView,
        actions: [UIAlertAction],
        claimedActions: inout Set<Int>,
        basePath: String
    ) -> [Int: String] {
        var result = [Int: String]()
        collectLabels(
            in: view,
            actions: actions,
            claimedActions: &claimedActions,
            result: &result,
            basePath: basePath
        )
        return result
    }

    /// 递归收集 UILabel，匹配尚未认领的 action title。
    private static func collectLabels(
        in view: UIView,
        actions: [UIAlertAction],
        claimedActions: inout Set<Int>,
        result: inout [Int: String],
        basePath: String
    ) {
        if let label = view as? UILabel, let labelText = label.text {
            for (index, action) in actions.enumerated() {
                if !claimedActions.contains(index), action.title == labelText {
                    claimedActions.insert(index)
                    result[index] = basePath
                    return
                }
            }
        }
        for child in view.subviews {
            collectLabels(in: child, actions: actions, claimedActions: &claimedActions, result: &result, basePath: basePath)
            if result.count == actions.count { return }
        }
    }
}
#endif
#endif
