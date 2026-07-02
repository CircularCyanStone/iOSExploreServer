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
/// 命令按按钮所在侧和下标定位当前 `UIBarButtonItem`，并允许调用方传入观察时看到的
/// title / accessibilityIdentifier 做二次确认，避免页面变化后误触发。
public struct UINavigationBarButtonInput: CommandInput, Sendable, Equatable {
    private enum Fields {
        static let placement = CommandFields.requiredEnum(
            "placement",
            type: NavigationBarPlacement.self,
            description: "导航栏按钮位置: left / right"
        )
        static let index = CommandFields.requiredInt(
            "index",
            range: 0...20,
            description: "按钮在当前侧的下标, 从 0 开始"
        )
        static let title = CommandFields.optionalString(
            "title",
            description: "观察时看到的按钮标题; 传入时执行前必须一致"
        )
        static let accessibilityIdentifier = CommandFields.optionalString(
            "accessibilityIdentifier",
            description: "观察时看到的按钮 accessibilityIdentifier; 传入时执行前必须一致"
        )
        static let waitAfterMs = CommandFields.int(
            "waitAfterMs",
            range: 0...3000,
            default: 300,
            description: "执行后等待毫秒数, 范围 0...3000, 默认 300"
        )

        static let all: [AnyCommandField] = [
            placement.erased,
            index.erased,
            title.erased,
            accessibilityIdentifier.erased,
            waitAfterMs.erased,
        ]
    }

    /// `ui.navigation.tapBarButton` 暴露给 help 和工具客户端的输入 schema。
    public static let inputSchema = CommandInputSchema(fields: Fields.all)

    /// 按钮位置。
    public let placement: NavigationBarPlacement
    /// 当前侧按钮下标。
    public let index: Int
    /// 可选标题校验。
    public let title: String?
    /// 可选 identifier 校验。
    public let accessibilityIdentifier: String?
    /// 执行后等待毫秒数。
    public let waitAfterMs: Int

    /// 创建导航栏按钮输入。
    ///
    /// - Parameters:
    ///   - placement: 按钮所在侧。
    ///   - index: 当前侧按钮下标。
    ///   - title: 可选标题校验。
    ///   - accessibilityIdentifier: 可选 identifier 校验。
    ///   - waitAfterMs: 执行后等待毫秒数。
    public init(placement: NavigationBarPlacement,
                index: Int,
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
    /// - Parameter decoder: 绑定 `inputSchema` 与请求 data 的字段读取器。
    /// - Returns: 已解析的 navigationBar 按钮输入。
    /// - Throws: 必填缺失、枚举值非法或数值越界时抛出 `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UINavigationBarButtonInput {
        UINavigationBarButtonInput(
            placement: try decoder.read(Fields.placement),
            index: try decoder.read(Fields.index),
            title: try decoder.read(Fields.title),
            accessibilityIdentifier: try decoder.read(Fields.accessibilityIdentifier),
            waitAfterMs: try decoder.read(Fields.waitAfterMs)
        )
    }

    /// 日志用选择器摘要，不记录完整 title / identifier。
    var selectorSummary: String {
        let titleLength = title.map { String($0.count) } ?? "nil"
        let identifierLength = accessibilityIdentifier.map { String($0.count) } ?? "nil"
        return "placement=\(placement.rawValue) index=\(index) titleLength=\(titleLength) identifierLength=\(identifierLength)"
    }
}

