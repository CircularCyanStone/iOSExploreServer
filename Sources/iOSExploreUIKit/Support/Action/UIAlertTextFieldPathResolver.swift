#if DEBUG
#if canImport(UIKit)
import Foundation
import UIKit

/// 从 alert VC 视图树解析输入框路径。
///
/// 与按钮不同，输入框（`_UIAlertControllerTextField`，即 `UITextField` 子类）的模型对象
/// 同时存在于 `UIAlertController.textFields` 数组与视图树中——理想情况下是同一对象。本解析器
/// 先用**对象身份**（`===`）匹配（最精确）；身份未命中时（某些 iOS 版本或测试环境下对象可能被
/// 系统包装、或 textField 尚未完成布局入树）退回按 DFS 先序的 `UITextField` 顺序对应
/// `alert.textFields` 下标——系统按 `addTextField` 顺序把输入框 addSubview，DFS 先序与数组
/// 下标一致。这样比 `UIAlertButtonPathResolver` 的 `UILabel.text` 匹配更稳健，且不依赖
/// 私有类名（只按公开的 `UITextField` 类型收集），抗 iOS 版本漂移。
///
/// 返回的 path 指向 `UITextField` 本身（实现 `UITextInput`，可被 `ui.input` 直接定位写入）。
/// 该文件受 `#if DEBUG` 保护，不进 Release 二进制——符合项目硬规则：私有 API 路径解析只用于
/// Debug 探索工具。
@MainActor
enum UIAlertTextFieldPathResolver {
    /// 一个已解析路径的输入框摘要。
    struct ResolvedTextField: Sendable, Equatable {
        /// 在 `alert.textFields` 中的下标。
        let index: Int
        /// 该输入框的定位路径；未解析到时为 nil。
        let path: String?
    }

    /// 解析 alert 输入框的路径。
    ///
    /// 先 DFS 收集 `rootView` 子树里所有 `UITextField`（先序），再对 `alert.textFields` 每个
    /// 输入框优先用对象身份（`===`）在收集结果里找命中；身份未命中时按下标取 DFS 先序第 i 个
    /// `UITextField`（系统保证 `addTextField` 顺序与视图先序一致）。命中即返回
    /// `UIKitViewLookupTarget.pathString(from:)` 格式的 path（如 `root/0/0/1/0`）。
    ///
    /// - Parameters:
    ///   - alert: 待解析的 `UIAlertController`。
    ///   - rootView: 当前顶部控制器的根 view。
    /// - Returns: 每个输入框的解析结果，顺序与 `alert.textFields` 一致；无 textFields 或视图树里
    ///   找不到足够 `UITextField` 时，对应位 path 为 nil。
    static func resolveTextFields(in alert: UIAlertController, rootView: UIView) -> [ResolvedTextField] {
        let textFields = alert.textFields ?? []
        guard !textFields.isEmpty else { return [] }

        var discovered: [(textField: UITextField, indexes: [Int])] = []
        collectTextFields(in: rootView, indexes: [], into: &discovered)

        return textFields.enumerated().map { index, textField in
            let path: String?
            if let hit = discovered.first(where: { $0.textField === textField }) {
                path = UIKitViewLookupTarget.pathString(from: hit.indexes)
            } else if index < discovered.count {
                path = UIKitViewLookupTarget.pathString(from: discovered[index].indexes)
            } else {
                path = nil
            }
            return ResolvedTextField(index: index, path: path)
        }
    }

    /// DFS 先序收集子树里所有 `UITextField`（`_UIAlertControllerTextField` 是其子类）。
    ///
    /// 从 `root` 本身开始检查，再递归 `subviews`；`indexes` 记录从 `rootView` 到当前节点的
    /// subviews 下标链，使 path 与 `ui.topViewHierarchy` / `ui.inspect` 同口径（`root/...`）。
    private static func collectTextFields(in root: UIView,
                                          indexes: [Int],
                                          into out: inout [(textField: UITextField, indexes: [Int])]) {
        if let textField = root as? UITextField {
            out.append((textField, indexes))
        }
        for (childIndex, child) in root.subviews.enumerated() {
            collectTextFields(in: child, indexes: indexes + [childIndex], into: &out)
        }
    }
}
#endif
#endif
