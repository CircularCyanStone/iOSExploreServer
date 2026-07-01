#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// 一段可见文本及其来源 path 与 view 类型。
///
/// 仅用于 `ui.wait` 的 textExists / idle 判断，**不**随响应返回原文（避免泄露屏幕内容）；
/// 调用方只在 MainActor 域内用它做包含/签名判断。
struct UIKitVisibleTextFragment: Sendable, Equatable {
    /// 从根 view 起的下标路径字符串，如 `root/0/2`。
    let path: String
    /// view 的运行时类型名。
    let viewType: String
    /// 文本内容。
    let text: String
}

/// `ui.wait` 使用的可见文本采集器。
///
/// 递归遍历 view 树，收集 `UILabel.text`、`UIButton.currentTitle`、`UITextField.placeholder`、
/// `accessibilityLabel` 以及非编辑态 `accessibilityValue`。**有意不收集** `UITextField.text` /
/// `UITextView.text`——这些是用户输入，可能含敏感信息，不应进入 wait 的判断与日志。这与
/// `UIViewHierarchyCollector.textInfo`（完整采集，含编辑文本，用于 `ui.topViewHierarchy`
/// 的视觉验收）是有意分工：wait 只需要"判断屏幕是否出现某文本"，不需要用户输入。
///
/// 日志只记录片段数量与命中摘要，不记录文本原文。
@MainActor
enum UIKitVisibleTextCollector {
    /// 递归采集可见文本片段。
    ///
    /// - Parameters:
    ///   - root: 遍历起点（通常是顶部控制器根 view）。
    ///   - includeHidden: 是否进入隐藏 / 透明 view。
    ///   - path: 当前 path 下标链。
    ///   - fragments: 累积采集结果的容器。
    static func collect(from root: UIView,
                        includeHidden: Bool,
                        into fragments: inout [UIKitVisibleTextFragment],
                        path: [Int] = []) {
        if !includeHidden, root.isHidden || root.alpha <= 0 { return }
        if let fragment = fragment(of: root, path: path) {
            fragments.append(fragment)
        }
        for (index, child) in root.subviews.enumerated() {
            collect(from: child, includeHidden: includeHidden, into: &fragments, path: path + [index])
        }
    }

    /// 便捷入口：返回完整片段数组。
    static func collect(from root: UIView, includeHidden: Bool) -> [UIKitVisibleTextFragment] {
        var fragments: [UIKitVisibleTextFragment] = []
        collect(from: root, includeHidden: includeHidden, into: &fragments, path: [])
        return fragments
    }

    /// 判断 `root` 中是否存在包含 `text` 的可见文本（textExists 模式用）。
    static func contains(text: String, in root: UIView, includeHidden: Bool) -> Bool {
        var fragments: [UIKitVisibleTextFragment] = []
        collect(from: root, includeHidden: includeHidden, into: &fragments, path: [])
        return fragments.contains { $0.text.contains(text) }
    }

    /// 从单个 view 提取首个非空可见文本片段（不收集编辑态文本）。
    private static func fragment(of view: UIView, path: [Int]) -> UIKitVisibleTextFragment? {
        let pathString = "root" + path.map { "/\($0)" }.joined()
        let viewType = String(describing: type(of: view))

        if let label = view as? UILabel, let text = label.text, !text.isEmpty {
            return UIKitVisibleTextFragment(path: pathString, viewType: viewType, text: text)
        }
        if let button = view as? UIButton {
            let title = button.title(for: .normal) ?? button.currentTitle
            if let title, !title.isEmpty {
                return UIKitVisibleTextFragment(path: pathString, viewType: viewType, text: title)
            }
        }
        if let textField = view as? UITextField {
            // 只取 placeholder；不取 text（用户输入）。
            if let placeholder = textField.placeholder, !placeholder.isEmpty {
                return UIKitVisibleTextFragment(path: pathString, viewType: viewType, text: placeholder)
            }
            // textField 无 placeholder 时仍可走 accessibilityLabel。
        }
        if let label = view.accessibilityLabel, !label.isEmpty {
            return UIKitVisibleTextFragment(path: pathString, viewType: viewType, text: label)
        }
        // accessibilityValue：跳过可编辑控件（其 value 是用户输入文本）。
        if view is UITextField || view is UITextView { return nil }
        if let value = view.accessibilityValue, !value.isEmpty {
            return UIKitVisibleTextFragment(path: pathString, viewType: viewType, text: value)
        }
        return nil
    }
}
#endif
