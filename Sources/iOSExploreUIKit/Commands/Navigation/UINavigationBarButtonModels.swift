import Foundation
import iOSExploreServer

/// 导航栏按钮所在位置。
public enum NavigationBarPlacement: String, Sendable, Equatable, CaseIterable {
    /// 左侧按钮列表。
    case left
    /// 右侧按钮列表。
    case right
}

/// `ui.navigation.tapBarButton` 的命令参数。
///
/// 命令按按钮所在侧和下标定位当前 `UIBarButtonItem`，或通过 `accessibilityIdentifier` 全局搜索。
/// 允许调用方传入观察时看到的 title / accessibilityIdentifier 做二次确认，避免页面变化后误触发。
///
/// **定位方式**:
/// - `placement` + `index`: 精确定位指定侧的第 N 个按钮
/// - 仅 `accessibilityIdentifier`: 在 leftItems 和 rightItems 中全局搜索
/// - `placement` + `accessibilityIdentifier`: 只在指定侧搜索（防误点）
/// - `placement` + `index` + `accessibilityIdentifier`: 精确定位 + 二次确认
public struct UINavigationBarButtonInput: CommandInput, Sendable, Equatable {
    /// `ui.navigation.tapBarButton` 在 Swift 执行端使用的 generated 输入定义。
    public static let inputDefinition = UIKitActionContracts.uiNavigationTapBarButtonInput

    /// 按钮位置（可选，与 `accessibilityIdentifier` 配合使用）。
    public let placement: NavigationBarPlacement?
    /// 当前侧按钮下标（可选）。
    public let index: Int?
    /// 可选标题校验。
    public let title: String?
    /// 可选 identifier 校验（可单独用于全局搜索）。
    public let accessibilityIdentifier: String?
    /// 执行后等待毫秒数。
    public let waitAfterMs: Int

    /// 创建导航栏按钮输入。
    ///
    /// - Parameters:
    ///   - placement: 按钮所在侧（可选）。
    ///   - index: 当前侧按钮下标（可选）。
    ///   - title: 可选标题校验。
    ///   - accessibilityIdentifier: 可选 identifier 校验。
    ///   - waitAfterMs: 执行后等待毫秒数。
    public init(placement: NavigationBarPlacement? = nil,
                index: Int? = nil,
                title: String? = nil,
                accessibilityIdentifier: String? = nil,
                waitAfterMs: Int = 300) {
        self.placement = placement
        self.index = index
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
        self.waitAfterMs = waitAfterMs
    }

    /// 按 `CommandInputDecoder` 读取字段并构造 typed input。
    ///
    /// - Parameter decoder: 绑定 generated 输入定义与请求 data 的字段读取器。
    /// - Returns: 已解析的 navigationBar 按钮输入。
    /// - Throws: 必填缺失、枚举值非法或数值越界时抛出 `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UINavigationBarButtonInput {
        let placementValue = try decoder.read(UIKitActionContracts.uiNavigationTapBarButtonPlacementField)

        let placement: NavigationBarPlacement?
        if let placementValue {
            guard let parsed = NavigationBarPlacement(rawValue: placementValue) else {
                throw CommandInputParseError("placement must be 'left' or 'right'")
            }
            placement = parsed
        } else {
            placement = nil
        }

        return UINavigationBarButtonInput(
            placement: placement,
            index: try decoder.read(UIKitActionContracts.uiNavigationTapBarButtonIndexField),
            title: try decoder.read(UIKitActionContracts.uiNavigationTapBarButtonTitleField),
            accessibilityIdentifier: try decoder.read(
                UIKitActionContracts.uiNavigationTapBarButtonAccessibilityIdentifierField
            ),
            waitAfterMs: try decoder.read(UIKitActionContracts.uiNavigationTapBarButtonWaitAfterMsField)
        )
    }

    /// 日志用选择器摘要，不记录完整 title / identifier。
    var selectorSummary: String {
        let placementStr = placement.map { $0.rawValue } ?? "nil"
        let indexStr = index.map(String.init) ?? "nil"
        let titleLength = title.map { String($0.count) } ?? "nil"
        let identifierLength = accessibilityIdentifier.map { String($0.count) } ?? "nil"
        return "placement=\(placementStr) index=\(indexStr) titleLength=\(titleLength) identifierLength=\(identifierLength)"
    }
}
