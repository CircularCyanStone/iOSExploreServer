import Foundation
import iOSExploreServer

/// `ui.wait` 的等待模式。
///
/// 枚举保持 Foundation-only。executor 在 `@MainActor` 域内按模式轮询 UI 状态：
/// - `idle`：等待画面连续 `stableMs` 不变（动画/加载静止）。
/// - `targetExists` / `targetGone`：等待目标 view 出现 / 消失。
/// - `textExists`：等待可见文本出现（用 `UIKitVisibleTextCollector`）。
/// - `snapshotChanged`：等待结构指纹表变化（用 `ui.inspect` 签发的 `viewSnapshotID`
///   重采 whole-table 比对），典型用于检测跳转、弹窗或同页内容变化。
///
/// rawValue 必须与 `contracts/` 中的 enum 一致，新增取值需同步合同与测试。
public enum WaitMode: String, Sendable, Equatable, CaseIterable {
    case idle
    case targetExists
    case targetGone
    case textExists
    case snapshotChanged
}

/// `ui.wait` 的命令参数。
///
/// 命令在业务 `timeoutMs` 内按 `intervalMs` 轮询，满足条件即返回；超时抛 `wait_timeout`。
/// 各模式对字段的要求：`targetExists`/`targetGone` 需 `accessibilityIdentifier` 或 `path`，
/// `textExists` 需 `text`，`snapshotChanged` 需 `viewSnapshotID`（来源必须是 `ui.inspect`），
/// `idle` 无额外要求。
public struct UIWaitInput: CommandInput, Sendable, Equatable {
    /// `ui.wait` 在 Swift 执行端使用的 generated 输入定义。
    public static let inputDefinition = UIKitActionContracts.uiWaitInput

    /// 等待模式。
    public let mode: WaitMode
    /// 业务超时毫秒数。
    public let timeoutMs: Int
    /// 轮询间隔毫秒数。
    public let intervalMs: Int
    /// idle 连续稳定毫秒数。
    public let stableMs: Int
    /// 要等待的文本（textExists）。
    public let text: String?
    /// 参照的结构化快照标识（snapshotChanged），来源必须是 `ui.inspect`。
    public let viewSnapshotID: String?
    /// 目标定位（targetExists / targetGone）。
    public let target: UIKitViewLookupTarget?
    /// 是否考虑隐藏 view。对 idle/textExists 控制是否纳入隐藏 view 的文本/活动签名；
    /// 对 targetExists/targetGone 控制是否把 `isHidden=true` 的 view 计入"存在"。
    /// 默认 false：targetExists 不在隐藏 view 上误判为存在，targetGone 在隐藏 view 上判定为"消失"。
    public let includeHidden: Bool

    /// 创建一条 wait 输入。
    public init(mode: WaitMode,
                timeoutMs: Int = 3000,
                intervalMs: Int = 100,
                stableMs: Int = 300,
                text: String? = nil,
                viewSnapshotID: String? = nil,
                target: UIKitViewLookupTarget? = nil,
                includeHidden: Bool = false) {
        self.mode = mode
        self.timeoutMs = timeoutMs
        self.intervalMs = intervalMs
        self.stableMs = stableMs
        self.text = text
        self.viewSnapshotID = viewSnapshotID
        self.target = target
        self.includeHidden = includeHidden
    }

    /// 按 `CommandInputDecoder` 读取字段并校验模式约束。
    ///
    /// - Parameter decoder: 绑定 generated 输入定义与请求 data 的字段读取器。
    /// - Returns: 已解析的 wait 输入。
    /// - Throws: 字段类型/范围非法，或模式所需字段缺失时抛出 `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIWaitInput {
        let modeRaw = try decoder.read(UIKitActionContracts.uiWaitModeField)
        guard let mode = WaitMode(rawValue: modeRaw) else {
            throw CommandInputParseError("unknown wait mode '\(modeRaw)'")
        }
        let timeoutMs = try decoder.read(UIKitActionContracts.uiWaitTimeoutMsField)
        let intervalMs = try decoder.read(UIKitActionContracts.uiWaitIntervalMsField)
        let stableMs = try decoder.read(UIKitActionContracts.uiWaitStableMsField)
        let text = try decoder.read(UIKitActionContracts.uiWaitTextField)
        let viewSnapshotID = try decoder.read(UIKitActionContracts.uiWaitViewSnapshotIDField)
        let target = try UIKitLocatorInput.parseOptional(
            decoder: &decoder,
            identifierField: UIKitActionContracts.uiWaitAccessibilityIdentifierField,
            pathField: UIKitActionContracts.uiWaitPathField
        )
        let includeHidden = try decoder.read(UIKitActionContracts.uiWaitIncludeHiddenField)

        switch mode {
        case .targetExists, .targetGone:
            guard target != nil else {
                throw CommandInputParseError("\(mode.rawValue) requires accessibilityIdentifier or path")
            }
        case .textExists:
            guard let text, !text.isEmpty else {
                throw CommandInputParseError("textExists requires non-empty text")
            }
        case .snapshotChanged:
            guard viewSnapshotID != nil else {
                throw CommandInputParseError("snapshotChanged requires viewSnapshotID")
            }
        case .idle:
            break
        }

        return UIWaitInput(mode: mode,
                           timeoutMs: timeoutMs,
                           intervalMs: intervalMs,
                           stableMs: stableMs,
                           text: text,
                           viewSnapshotID: viewSnapshotID,
                           target: target,
                           includeHidden: includeHidden)
    }
}
