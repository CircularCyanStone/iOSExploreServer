#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// 当前页面导航栏摘要读取器。
///
/// 该类型不遍历 UIKit 私有 view，而是直接读取顶部控制器的 `navigationItem`，把
/// `UIBarButtonItem` 转成 Agent 可理解的摘要。这样导航栏按钮不会污染普通 view path，
/// 也不会依赖 `_UIModernBarButton` 这类私有类型。
@MainActor
enum UINavigationBarInspector {
    /// 单个导航栏按钮摘要。
    struct ItemSummary: Sendable, Equatable {
        /// 按钮所在侧。
        let placement: NavigationBarPlacement
        /// 当前侧按钮下标。
        let index: Int
        /// 按钮标题，可能为空。
        let title: String?
        /// 按钮稳定 identifier，可能为空。
        let accessibilityIdentifier: String?
        /// 按钮当前是否可用。
        let isEnabled: Bool

        /// 转为命令响应 JSON。
        func toJSON() -> JSON {
            [
                "placement": .string(placement.rawValue),
                "index": .double(Double(index)),
                "title": title.map(JSONValue.string) ?? .null,
                "accessibilityIdentifier": accessibilityIdentifier.map(JSONValue.string) ?? .null,
                "isEnabled": .bool(isEnabled),
                "availableActions": .array([.string(NavigationBarButtonCommand.actionName)]),
            ]
        }
    }

    /// 当前导航栏整体摘要。
    struct Summary: Sendable, Equatable {
        /// 当前顶部控制器是否处于导航控制器中。
        let available: Bool
        /// 当前导航标题。
        let title: String?
        /// 顶部控制器类型摘要。
        let topViewController: String
        /// 左侧显式按钮。
        let leftItems: [ItemSummary]
        /// 右侧显式按钮。
        let rightItems: [ItemSummary]
        /// 当前导航栈是否可 pop。
        let backAvailable: Bool

        /// 转为命令响应 JSON。
        func toJSON() -> JSON {
            [
                "available": .bool(available),
                "title": title.map(JSONValue.string) ?? .null,
                "topViewController": .string(topViewController),
                "leftItems": .array(leftItems.map { .object($0.toJSON()) }),
                "rightItems": .array(rightItems.map { .object($0.toJSON()) }),
                "backAvailable": .bool(backAvailable),
            ]
        }
    }

    /// 生成当前顶部控制器的导航栏摘要。
    ///
    /// - Parameter topViewController: 当前顶部控制器。
    /// - Returns: 导航栏摘要；不在导航控制器中时 `available=false`。
    static func summarize(topViewController: UIViewController) -> Summary {
        let topName = String(describing: type(of: topViewController))
        guard let navigation = topViewController.navigationController else {
            return Summary(available: false,
                           title: topViewController.navigationItem.title ?? topViewController.title,
                           topViewController: topName,
                           leftItems: [],
                           rightItems: [],
                           backAvailable: false)
        }

        let item = topViewController.navigationItem
        return Summary(available: true,
                       title: item.title ?? topViewController.title ?? navigation.navigationBar.topItem?.title,
                       topViewController: topName,
                       leftItems: summaries(placement: .left, items: barButtonItems(placement: .left, from: item)),
                       rightItems: summaries(placement: .right, items: barButtonItems(placement: .right, from: item)),
                       backAvailable: navigation.viewControllers.count > 1)
    }

    /// 按输入选择当前导航栏按钮，并执行 title / identifier 二次确认。
    ///
    /// 支持三种定位方式：
    /// 1. `placement` + `index`: 精确定位指定侧的第 N 个按钮
    /// 2. 仅 `accessibilityIdentifier`: 在 leftItems 和 rightItems 中全局搜索
    /// 3. `placement` + `accessibilityIdentifier`: 只在指定侧搜索
    ///
    /// - Parameters:
    ///   - input: 已解析的按钮选择输入。
    ///   - topViewController: 当前顶部控制器。
    /// - Returns: 匹配的 `UIBarButtonItem` 及其实际位置信息。
    /// - Throws: 导航栏不可用、按钮不存在或二次确认不一致时抛 `UIKitCommandError`。
    static func item(for input: UINavigationBarButtonInput,
                     topViewController: UIViewController) throws -> (item: UIBarButtonItem, placement: NavigationBarPlacement, index: Int) {
        guard topViewController.navigationController != nil else {
            throw UIKitCommandError.navigationBarUnavailable(
                action: NavigationBarButtonCommand.actionName,
                top: String(describing: type(of: topViewController))
            )
        }

        let navigationItem = topViewController.navigationItem

        // 情况 1: placement + index 精确定位
        if let placement = input.placement, let index = input.index {
            let items = barButtonItems(placement: placement, from: navigationItem)
            guard index < items.count else {
                throw UIKitCommandError.navigationBarItemNotFound(
                    action: NavigationBarButtonCommand.actionName,
                    selector: input.selectorSummary
                )
            }
            let item = items[index]
            try verifyItem(item, input: input)
            return (item, placement, index)
        }

        // 情况 2 & 3: 通过 accessibilityIdentifier 搜索（全局或指定侧）
        if let identifier = input.accessibilityIdentifier {
            let searchPlacements: [NavigationBarPlacement] = input.placement.map { [$0] } ?? [.left, .right]

            for placement in searchPlacements {
                let items = barButtonItems(placement: placement, from: navigationItem)
                if let foundIndex = items.firstIndex(where: { $0.accessibilityIdentifier == identifier }) {
                    let item = items[foundIndex]
                    try verifyItem(item, input: input)
                    return (item, placement, foundIndex)
                }
            }

            // 未找到匹配的 accessibilityIdentifier
            throw UIKitCommandError.navigationBarItemNotFound(
                action: NavigationBarButtonCommand.actionName,
                selector: input.selectorSummary
            )
        }

        // 情况 4: 只有 placement 没有 index 也没有 accessibilityIdentifier（参数不足）
        throw UIKitCommandError.invalidNavigationBarSelector(
            action: NavigationBarButtonCommand.actionName,
            reason: "必须提供 (placement + index) 或 accessibilityIdentifier"
        )
    }

    /// 验证按钮的 title 和 accessibilityIdentifier 是否与输入一致。
    ///
    /// - Parameters:
    ///   - item: 待验证的按钮。
    ///   - input: 用户输入的期望值。
    /// - Throws: 当 title 或 identifier 不匹配时抛 `UIKitCommandError.navigationBarItemMismatch`。
    private static func verifyItem(_ item: UIBarButtonItem, input: UINavigationBarButtonInput) throws {
        if let expectedTitle = input.title, item.title != expectedTitle {
            throw UIKitCommandError.navigationBarItemMismatch(
                action: NavigationBarButtonCommand.actionName,
                selector: input.selectorSummary
            )
        }
        if let expectedIdentifier = input.accessibilityIdentifier,
           item.accessibilityIdentifier != expectedIdentifier {
            throw UIKitCommandError.navigationBarItemMismatch(
                action: NavigationBarButtonCommand.actionName,
                selector: input.selectorSummary
            )
        }
    }

    /// 生成指定侧的按钮摘要。
    private static func summaries(placement: NavigationBarPlacement,
                                  items: [UIBarButtonItem]) -> [ItemSummary] {
        items.enumerated().map { index, item in
            ItemSummary(placement: placement,
                        index: index,
                        title: item.title,
                        accessibilityIdentifier: item.accessibilityIdentifier,
                        isEnabled: item.isEnabled)
        }
    }

    /// 读取 navigationItem 当前侧的按钮列表，兼容单按钮和数组写法。
    private static func barButtonItems(placement: NavigationBarPlacement,
                                       from navigationItem: UINavigationItem) -> [UIBarButtonItem] {
        switch placement {
        case .left:
            return navigationItem.leftBarButtonItems ?? single(navigationItem.leftBarButtonItem)
        case .right:
            return navigationItem.rightBarButtonItems ?? single(navigationItem.rightBarButtonItem)
        }
    }

    /// 把可选单按钮转为数组。
    private static func single(_ item: UIBarButtonItem?) -> [UIBarButtonItem] {
        item.map { [$0] } ?? []
    }
}
#endif

