import Foundation
import iOSExploreServer

/// `ui.wait` 的等待模式。
///
/// 枚举保持 Foundation-only。executor 在 `@MainActor` 域内按模式轮询 UI 状态：
/// - `idle`：等待画面连续 `stableMs` 不变（动画/加载静止）。
/// - `targetExists` / `targetGone`：等待目标 view 出现 / 消失。
/// - `textExists`：等待可见文本出现（用 `UIKitVisibleTextCollector`）。
/// - `snapshotChanged`：等待页面身份（window + 顶部控制器实例）变化，典型用于检测跳转或弹窗。
///
/// case 顺序进入 schema 的 enum 列表，调整需同步测试与 help 文案。
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
/// `textExists` 需 `text`，`snapshotChanged` 需 `snapshotID`，`idle` 无额外要求。
public struct UIWaitInput: CommandInput, Sendable, Equatable {
    private enum Fields {
        static let mode = CommandFields.enumValue(
            "mode",
            type: WaitMode.self,
            default: .idle,
            description: "等待模式: idle / targetExists / targetGone / textExists / snapshotChanged"
        )
        static let timeoutMs = CommandFields.int(
            "timeoutMs",
            range: 0...30_000,
            default: 3000,
            description: "业务超时毫秒数, 范围 0...30000, 默认 3000"
        )
        static let intervalMs = CommandFields.int(
            "intervalMs",
            range: 50...5000,
            default: 100,
            description: "轮询间隔毫秒数, 范围 50...5000, 默认 100"
        )
        static let stableMs = CommandFields.int(
            "stableMs",
            range: 0...10_000,
            default: 300,
            description: "idle 模式下连续稳定的毫秒数, 范围 0...10000, 默认 300"
        )
        static let text = CommandFields.optionalString(
            "text",
            description: "textExists 模式要等待的文本片段"
        )
        static let snapshotID = CommandFields.optionalString(
            "snapshotID",
            description: "snapshotChanged 模式参照的 snapshotID"
        )
        static let accessibilityIdentifier = UIKitLocatorFields.accessibilityIdentifier
        static let path = UIKitLocatorFields.path
        static let includeHidden = CommandFields.bool(
            "includeHidden",
            default: false,
            description: "idle/textExists 是否考虑隐藏 view, 默认 false"
        )

        static let all: [AnyCommandField] = [
            mode.erased,
            timeoutMs.erased,
            intervalMs.erased,
            stableMs.erased,
            text.erased,
            snapshotID.erased,
            accessibilityIdentifier.erased,
            path.erased,
            includeHidden.erased,
        ]
    }

    /// `ui.wait` 暴露给 help 和工具客户端的输入 schema。
    public static let inputSchema = CommandInputSchema(fields: Fields.all)

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
    /// 参照快照标识（snapshotChanged）。
    public let snapshotID: String?
    /// 目标定位（targetExists / targetGone）。
    public let target: UIKitViewLookupTarget?
    /// 是否考虑隐藏 view。
    public let includeHidden: Bool

    /// 创建一条 wait 输入。
    public init(mode: WaitMode,
                timeoutMs: Int = 3000,
                intervalMs: Int = 100,
                stableMs: Int = 300,
                text: String? = nil,
                snapshotID: String? = nil,
                target: UIKitViewLookupTarget? = nil,
                includeHidden: Bool = false) {
        self.mode = mode
        self.timeoutMs = timeoutMs
        self.intervalMs = intervalMs
        self.stableMs = stableMs
        self.text = text
        self.snapshotID = snapshotID
        self.target = target
        self.includeHidden = includeHidden
    }

    /// 按 `CommandInputDecoder` 读取字段并校验模式约束。
    ///
    /// - Parameter decoder: 绑定 `inputSchema` 与请求 data 的字段读取器。
    /// - Returns: 已解析的 wait 输入。
    /// - Throws: 字段类型/范围非法，或模式所需字段缺失时抛出 `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIWaitInput {
        let mode = try decoder.read(Fields.mode)
        let timeoutMs = try decoder.read(Fields.timeoutMs)
        let intervalMs = try decoder.read(Fields.intervalMs)
        let stableMs = try decoder.read(Fields.stableMs)
        let text = try decoder.read(Fields.text)
        let snapshotID = try decoder.read(Fields.snapshotID)
        let target = try UIKitLocatorInput.parseOptional(decoder: &decoder)
        let includeHidden = try decoder.read(Fields.includeHidden)

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
            guard snapshotID != nil else {
                throw CommandInputParseError("snapshotChanged requires snapshotID")
            }
        case .idle:
            break
        }

        return UIWaitInput(mode: mode,
                           timeoutMs: timeoutMs,
                           intervalMs: intervalMs,
                           stableMs: stableMs,
                           text: text,
                           snapshotID: snapshotID,
                           target: target,
                           includeHidden: includeHidden)
    }
}
