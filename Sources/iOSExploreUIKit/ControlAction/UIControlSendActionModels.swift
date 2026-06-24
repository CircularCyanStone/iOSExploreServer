import Foundation
import iOSExploreServer

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

/// `ui.control.sendAction` 的命令参数。
///
/// 命令要求调用方明确提供一个定位条件和一个事件名。定位条件只能二选一，避免同一请求里
/// identifier 与 path 指向不同控件导致误触发。
public struct UIControlSendActionQuery: Sendable, Equatable {
    /// 目标控件定位方式。
    public let target: UIControlSendActionTarget
    /// 要发送的 UIControl 事件。
    public let event: UIControlSendActionEvent
    /// 可选的快照标识，用于对 `.path` 定位做陈旧校验。
    public let snapshotID: String?

    /// 创建 sendAction 查询。
    ///
    /// - Parameters:
    ///   - target: 目标控件定位方式。
    ///   - event: 要发送的 UIControl 事件。
    ///   - snapshotID: 可选 snapshotID，默认 nil。
    public init(target: UIControlSendActionTarget, event: UIControlSendActionEvent, snapshotID: String? = nil) {
        self.target = target
        self.event = event
        self.snapshotID = snapshotID
    }

    /// 从命令 `data` 解析查询参数。
    ///
    /// - Parameter data: `ExploreRequest.data`。
    /// - Returns: 解析出的查询对象。
    /// - Throws: `QueryParseError`，文案可直接放入 `invalid_data`。
    public static func parse(from data: JSON) throws -> UIControlSendActionQuery {
        let snapshotID = data["snapshotID"]?.stringValue
        guard let rawEvent = data["event"]?.stringValue else {
            throw QueryParseError("missing required parameter 'event'")
        }
        guard let event = UIControlSendActionEvent(rawValue: rawEvent) else {
            throw QueryParseError("event must be one of touchDown, touchUpInside, valueChanged, editingChanged, editingDidBegin, editingDidEnd")
        }

        let target = try UIKitViewLookupTarget.parse(identifier: data["accessibilityIdentifier"]?.stringValue,
                                                     rawPath: data["path"]?.stringValue)
        return UIControlSendActionQuery(target: target, event: event, snapshotID: snapshotID)
    }
}
