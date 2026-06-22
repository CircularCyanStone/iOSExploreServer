import Foundation

/// `ui.control.sendAction` 支持的 UIControl 事件名。
///
/// 该枚举保持 Foundation-only，UIKit 平台再把它映射为 `UIControl.Event`。
public enum UIControlSendActionEvent: String, Sendable, Equatable {
    /// 按下控件。
    case touchDown
    /// 常见按钮点击完成事件。
    case touchUpInside
    /// 值变化事件，适用于 switch、slider、segmented control 等。
    case valueChanged
    /// 文本编辑变化事件。
    case editingChanged
    /// 文本编辑开始事件。
    case editingDidBegin
    /// 文本编辑结束事件。
    case editingDidEnd
}

/// `ui.control.sendAction` 参数解析结果。
///
/// 失败分支是可返回给调用方的 `invalid_data` 文案，不代表 Swift 异常。
public enum UIControlSendActionQueryParseResult: Sendable, Equatable {
    /// 解析成功。
    case success(UIControlSendActionQuery)
    /// 参数非法。
    case failure(String)
}

/// `ui.control.sendAction` 的命令参数。
///
/// 命令要求调用方明确提供一个定位条件和一个事件名。定位条件只能二选一，避免同一请求里
/// identifier 与 path 指向不同控件导致误触发。
public struct UIControlSendActionQuery: Sendable, Equatable {
    /// 目标控件定位方式。
    public let target: UIControlSendActionTarget
    /// 要发送的 UIControl 事件。
    public let event: UIControlSendActionEvent

    /// 创建 sendAction 查询。
    ///
    /// - Parameters:
    ///   - target: 目标控件定位方式。
    ///   - event: 要发送的 UIControl 事件。
    public init(target: UIControlSendActionTarget, event: UIControlSendActionEvent) {
        self.target = target
        self.event = event
    }

    /// 从命令 `data` 解析查询参数。
    ///
    /// - Parameter data: `ExploreRequest.data`。
    /// - Returns: 成功时返回查询对象；失败时返回可直接放入 `invalid_data` 的说明。
    public static func parse(from data: JSON) -> UIControlSendActionQueryParseResult {
        guard let rawEvent = data["event"]?.stringValue else {
            return .failure("missing required parameter 'event'")
        }
        guard let event = UIControlSendActionEvent(rawValue: rawEvent) else {
            return .failure("event must be one of touchDown, touchUpInside, valueChanged, editingChanged, editingDidBegin, editingDidEnd")
        }

        switch UIKitViewLookupTarget.parse(identifier: data["accessibilityIdentifier"]?.stringValue,
                                           rawPath: data["path"]?.stringValue) {
        case .success(let target):
            return .success(UIControlSendActionQuery(target: target, event: event))
        case .failure(let message):
            return .failure(message)
        }
    }
}
