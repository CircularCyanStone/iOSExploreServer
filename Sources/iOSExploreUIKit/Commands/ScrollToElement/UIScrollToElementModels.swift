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
/// 一次性滚到目标可见。`container` 缺省时用 keyWindow 最前 scrollView。命令不签发 snapshot：
/// 滚动后画面变化，agent 应重新 `ui.screenshot` 取新 snapshotID 再交互。
public struct UIScrollToElementInput: CommandInput, Sendable, Equatable {
    private enum Fields {
        static let match = CommandFields.enumValue(
            "match",
            type: ScrollToElementMatch.self,
            default: .text,
            description: "匹配方式: text / accessibilityIdentifier"
        )
        static let value = CommandFields.requiredString(
            "value",
            description: "匹配值: text 片段或 accessibilityIdentifier"
        )
        static let accessibilityIdentifier = UIKitLocatorFields.accessibilityIdentifier
        static let path = UIKitLocatorFields.path
        static let animated = CommandFields.bool(
            "animated",
            default: false,
            description: "是否动画, 默认 false"
        )

        static let all: [AnyCommandField] = [
            match.erased,
            value.erased,
            accessibilityIdentifier.erased,
            path.erased,
            animated.erased,
        ]
    }

    /// `ui.scrollToElement` 暴露给 help 和工具客户端的输入 schema。
    public static let inputSchema = CommandInputSchema(fields: Fields.all)

    /// 匹配方式。
    public let match: ScrollToElementMatch
    /// 匹配值。
    public let value: String
    /// 滚动容器定位（nil = foremost scrollView）。
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
    /// - Parameter decoder: 绑定 `inputSchema` 与请求 data 的字段读取器。
    /// - Returns: 已解析的 scroll-to-element 输入。
    /// - Throws: 字段类型非法或 `value` 缺失时抛出 `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIScrollToElementInput {
        let match = try decoder.read(Fields.match)
        let value = try decoder.read(Fields.value)
        let container = try UIKitLocatorInput.parseOptional(decoder: &decoder)
        let animated = try decoder.read(Fields.animated)
        return UIScrollToElementInput(match: match, value: value, container: container, animated: animated)
    }
}
