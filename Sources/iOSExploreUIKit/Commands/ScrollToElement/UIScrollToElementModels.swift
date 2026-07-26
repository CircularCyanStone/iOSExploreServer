import Foundation
import iOSExploreServer

/// `ui.scrollToElement` 的目标匹配方式。
public enum ScrollToElementMatch: String, Sendable, Equatable, CaseIterable {
    /// 按可见文本片段匹配（UILabel.text 等，含目标 value 即命中）。
    case text
    /// 按 accessibilityIdentifier 精确匹配。
    case accessibilityIdentifier
}

/// `ui.scrollToElement` 的命令参数。
///
/// 在指定滚动容器内查找目标（按文本或 identifier），用 `UIScrollView.scrollRectToVisible`
/// 一次性滚到目标可见。
///
/// `path` / `accessibilityIdentifier` **指向滚动容器自身**（即 `UIScrollView`，
/// 含 `UITableView` / `UICollectionView`），而非目标元素。这是与 `ui.scroll` 的重要区别：
/// `ui.scroll` 的 path 指向触发滚动的目标 view，而 `ui.scrollToElement` 的定位字段
/// 明确指向滚动容器（locator 缺省时回退到 keyWindow 最前 scrollView）。当容器是
/// `UITableView` / `UICollectionView` 时，visibleCells 内的子 view 会被额外搜索。
///
/// 命令不签发 viewSnapshotID：滚动后画面变化，agent 应重新 `ui.inspect` 取新
/// viewSnapshotID 再交互。
public struct UIScrollToElementInput: CommandInput, Sendable, Equatable {
    /// `ui.scrollToElement` 在 Swift 执行端使用的 generated 输入定义。
    public static let inputDefinition = UIKitActionContracts.uiScrollToElementInput

    /// 匹配方式。
    public let match: ScrollToElementMatch
    /// 匹配值。
    public let value: String
    /// 滚动容器定位（nil = 不指定容器，从 keyWindow 最前 scrollView 搜索）。
    ///
    /// 指向滚动容器自身（UIScrollView/UITableView/UICollectionView），**不是**目标元素。
    /// 缺省时 executor 从 keyWindow 最前 scrollView 搜索。
    /// 当容器是 UITableView 或 UICollectionView 时，executor 额外搜索 visibleCells。
    public let container: UIKitViewLookupTarget?
    /// 是否动画。
    public let animated: Bool

    /// 创建一条 scroll-to-element 输入。
    public init(match: ScrollToElementMatch = .text,
                value: String,
                container: UIKitViewLookupTarget? = nil,
                animated: Bool = false) {
        self.match = match
        self.value = value
        self.container = container
        self.animated = animated
    }

    /// 按 `CommandInputDecoder` 读取字段并填充默认值。
    ///
    /// - Parameter decoder: 绑定 generated 输入定义与请求 data 的字段读取器。
    /// - Returns: 已解析的 scroll-to-element 输入。
    /// - Throws: 字段类型非法或 `value` 缺失时抛出 `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIScrollToElementInput {
        let match = ScrollToElementMatch(
            rawValue: try decoder.read(UIKitActionContracts.uiScrollToElementMatchField)
        )!
        let value = try decoder.read(UIKitActionContracts.uiScrollToElementValueField)
        let container = try UIKitLocatorInput.parseOptional(
            decoder: &decoder,
            identifierField: UIKitActionContracts.uiScrollToElementAccessibilityIdentifierField,
            pathField: UIKitActionContracts.uiScrollToElementPathField
        )
        let animated = try decoder.read(UIKitActionContracts.uiScrollToElementAnimatedField)
        return UIScrollToElementInput(match: match, value: value, container: container, animated: animated)
    }
}
