import Foundation
import iOSExploreServer

/// `ui.control.sendAction` 支持的 UIControl 事件名。
///
/// 该枚举保持 Foundation-only，UIKit 平台再把它映射为 `UIControl.Event`。
///
/// - Note: case 声明顺序即 `CaseIterable.allCases` 顺序，被 `QueryDecoder.requiredEnum`
///   的 "must be one of ..." 错误文案依赖，勿随意重排。
public enum UIControlSendActionEvent: String, Sendable, Equatable, CaseIterable {
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
public struct UIControlSendActionQuery: UIKitQueryParsing, Sendable, Equatable {
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

    /// 按 `QueryDecoder` 读取 snapshotID/event；identifier/path 取值经 builder 但领域校验
    /// （互斥/path 文法）保留在 `UIKitViewLookupTarget.parse`。
    public static func parse(decoding d: inout QueryDecoder) throws -> UIControlSendActionQuery {
        let snapshotID = d.string("snapshotID")
        let event: UIControlSendActionEvent = try d.requiredEnum("event")
        let target = try UIKitViewLookupTarget.parse(identifier: d.data["accessibilityIdentifier"]?.stringValue,
                                                     rawPath: d.data["path"]?.stringValue)
        return UIControlSendActionQuery(target: target, event: event, snapshotID: snapshotID)
    }
}
