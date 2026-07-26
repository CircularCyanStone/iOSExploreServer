import Foundation
import iOSExploreServer

/// `ui.waitAny` 的单个等待条件。
///
/// 每个条件由调用方提供稳定 `id`（命中后原样回传为 `matchedID`，用于关联业务结局）和一个
/// wait 模式。模式语义复用 `ui.wait`：
/// - `targetExists` / `targetGone`：需 `accessibilityIdentifier` 或 `path`；
/// - `textExists`：需 `text`；
/// - `snapshotChanged`：需 `viewSnapshotID`（来源必须是 `ui.inspect`）；
/// - `idle`：无额外字段，使用顶层共享的 `stableMs` 稳定窗口。
public struct UIWaitAnyCondition: Sendable, Equatable {
    /// 调用方提供的稳定标识，命中后原样回传为 `matchedID`。
    public let id: String
    /// 等待模式。
    public let mode: WaitMode
    /// textExists 要等待的文本片段。
    public let text: String?
    /// snapshotChanged 参照的 viewSnapshotID。
    public let viewSnapshotID: String?
    /// targetExists / targetGone 的定位目标。
    public let target: UIKitViewLookupTarget?

    /// 创建一条等待条件。
    public init(id: String,
                mode: WaitMode,
                text: String? = nil,
                viewSnapshotID: String? = nil,
                target: UIKitViewLookupTarget? = nil) {
        self.id = id
        self.mode = mode
        self.text = text
        self.viewSnapshotID = viewSnapshotID
        self.target = target
    }
}

/// `ui.waitAny` 的命令参数：在一个轮询循环内按顺序等待多个可能结局，第一个满足立即返回。
///
/// 共享 `timeoutMs` / `intervalMs` / `stableMs` / `includeHidden` 作用于所有 condition：
/// `stableMs` 给所有 idle 条件做稳定窗口，`includeHidden` 给所有 idle / textExists 条件。
/// 超时复用现有 `wait_timeout` 业务错误（不发明新错误码）；cancel 与瞬时层级不可用的处理
/// 对齐 `ui.wait`（继续轮询，不升级为硬失败）。
public struct UIWaitAnyInput: CommandInput, Sendable, Equatable {
    /// conditions 数组长度上限，避免请求体过大。
    static let maxConditions = 16

    /// `ui.waitAny` 在 Swift 执行端使用的 generated 输入定义。
    public static let inputDefinition = UIKitActionContracts.uiWaitAnyInput

    /// 等待条件列表（顺序即命中优先级）。
    public let conditions: [UIWaitAnyCondition]
    /// 业务超时毫秒数（共享）。
    public let timeoutMs: Int
    /// 轮询间隔毫秒数（共享）。
    public let intervalMs: Int
    /// idle 连续稳定毫秒数（共享）。
    public let stableMs: Int
    /// idle / textExists 是否考虑隐藏 view（共享）。
    public let includeHidden: Bool

    /// 创建一条 waitAny 输入。
    public init(conditions: [UIWaitAnyCondition],
                timeoutMs: Int = 3000,
                intervalMs: Int = 100,
                stableMs: Int = 300,
                includeHidden: Bool = false) {
        self.conditions = conditions
        self.timeoutMs = timeoutMs
        self.intervalMs = intervalMs
        self.stableMs = stableMs
        self.includeHidden = includeHidden
    }

    /// 从原始 JSON data 解析 waitAny 输入。
    ///
    /// conditions 是对象数组，无法走 `CommandField<Value>` 的 typed decode，故通过 generated
    /// `AnyCommandField` 读取原始值后手写解析（含 id 唯一、mode 合法、各模式必填字段校验）。
    /// 顶层未知字段和 generated 字段读取完整性仍由 decoder 统一守卫。所有失败统一抛
    /// `CommandInputParseError`，由 `AnyCommand` 映射为 `invalid_data` envelope。
    ///
    /// - Parameter data: `ExploreRequest.data` 中的原始参数对象。
    /// - Returns: 已解析的 waitAny 输入。
    /// - Throws: 顶层未知字段、conditions 缺失/非数组/空/超 16、condition 非对象、缺 id、
    ///   condition 内未知字段、重复 id、未知 mode、mode 必填字段缺失或定位字段非法时抛出
    ///   `CommandInputParseError`。
    public static func parse(from data: JSON) throws -> UIWaitAnyInput {
        var decoder = try inputDefinition.makeDecoder(for: data)
        let rawConditions = try decoder.readRaw(UIKitActionContracts.uiWaitAnyConditionsField)
        let timeoutMs = try decoder.read(UIKitActionContracts.uiWaitAnyTimeoutMsField)
        let intervalMs = try decoder.read(UIKitActionContracts.uiWaitAnyIntervalMsField)
        let stableMs = try decoder.read(UIKitActionContracts.uiWaitAnyStableMsField)
        let includeHidden = try decoder.read(UIKitActionContracts.uiWaitAnyIncludeHiddenField)
        let conditions = try parseConditions(from: rawConditions)
        try decoder.assertAllDeclaredFieldsRead()
        return UIWaitAnyInput(conditions: conditions,
                              timeoutMs: timeoutMs,
                              intervalMs: intervalMs,
                              stableMs: stableMs,
                              includeHidden: includeHidden)
    }

    /// 协议要求的 decoder 入口。
    ///
    /// waitAny 需要在同一入口显式执行顶层未知字段校验、复杂数组解析和 generated 字段完整读取
    /// 断言，故真实解析收敛在 `parse(from:)`。`AnyCommand` 始终走 `parse(from:)`，本方法不会
    /// 被调用，仅满足协议签名；若被调用则明确报错而非静默。
    ///
    /// - Parameter decoder: 绑定 generated 输入定义与请求 data 的字段读取器。
    /// - Returns: 已解析的 waitAny 输入。
    /// - Throws: 始终抛出 `CommandInputParseError`，提示改用 `parse(from:)`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIWaitAnyInput {
        throw CommandInputParseError("UIWaitAnyInput must be parsed via parse(from:)")
    }

    /// 从 decoder 读取的原始字段值手写解析 conditions 数组。
    ///
    /// - Parameter raw: `conditions` 的原始字段值。
    /// - Returns: 按顺序解析出的条件列表。
    /// - Throws: conditions 缺失/非数组/空/超 16、任一条件非对象、id 缺失/为空/重复、condition 内
    ///   未知字段、mode 缺失/未知、定位字段非法、mode 必填字段缺失时抛出 `CommandInputParseError`。
    private static func parseConditions(from raw: JSONValue?) throws -> [UIWaitAnyCondition] {
        guard let raw else {
            throw CommandInputParseError("conditions is required")
        }
        guard case .array(let elements) = raw else {
            throw CommandInputParseError("conditions must be an array")
        }
        guard !elements.isEmpty else {
            throw CommandInputParseError("conditions must not be empty")
        }
        guard elements.count <= maxConditions else {
            throw CommandInputParseError("conditions count must be <= \(maxConditions)")
        }

        var seenIDs: Set<String> = []
        var parsed: [UIWaitAnyCondition] = []
        for element in elements {
            guard let obj = element.objectValue else {
                throw CommandInputParseError("each condition must be an object")
            }
            guard let id = try stringValue(obj, "id"), !id.isEmpty else {
                throw CommandInputParseError("condition requires non-empty id")
            }
            // 与顶层 validateNoUnknownFields 一致：拒绝 condition 内未知字段，避免调用方拼错字段
            // （如 acessibilityIdentifier、timeOutMs）被静默忽略。合法字段为 id/mode 与四种模式所需
            // 字段的并集（mode 无关，最小行为变更，不改变跨模式字段的现有宽松处理）。
            let allowedKeys: Set<String> = ["id", "mode", "text", "viewSnapshotID", "accessibilityIdentifier", "path"]
            if let unknown = obj.storage.keys.first(where: { !allowedKeys.contains($0) }) {
                throw CommandInputParseError("condition '\(id)' has unknown field '\(unknown)'")
            }
            guard seenIDs.insert(id).inserted else {
                throw CommandInputParseError("duplicate condition id '\(id)'")
            }
            guard let modeRaw = try stringValue(obj, "mode") else {
                throw CommandInputParseError("condition '\(id)' requires mode")
            }
            guard let mode = WaitMode(rawValue: modeRaw) else {
                throw CommandInputParseError("condition '\(id)' has unknown wait mode '\(modeRaw)'")
            }
            let text = try stringValue(obj, "text", allowsNull: true)
            let viewSnapshotID = try stringValue(obj, "viewSnapshotID", allowsNull: true)
            let identifier = try stringValue(obj, "accessibilityIdentifier", allowsNull: true)
            let path = try stringValue(obj, "path", allowsNull: true)
            let target: UIKitViewLookupTarget?
            if identifier != nil || path != nil {
                do {
                    target = try UIKitViewLookupTarget.parse(identifier: identifier, rawPath: path)
                } catch let error as UIKitLocatorParseError {
                    throw CommandInputParseError("condition '\(id)' locator: \(error.message)")
                }
            } else {
                target = nil
            }
            switch mode {
            case .targetExists, .targetGone:
                guard target != nil else {
                    throw CommandInputParseError("condition '\(id)' \(mode.rawValue) requires accessibilityIdentifier or path")
                }
            case .textExists:
                guard let text, !text.isEmpty else {
                    throw CommandInputParseError("condition '\(id)' textExists requires non-empty text")
                }
            case .snapshotChanged:
                guard viewSnapshotID != nil else {
                    throw CommandInputParseError("condition '\(id)' snapshotChanged requires viewSnapshotID")
                }
            case .idle:
                break
            }
            parsed.append(UIWaitAnyCondition(id: id,
                                             mode: mode,
                                             text: text,
                                             viewSnapshotID: viewSnapshotID,
                                             target: target))
        }
        return parsed
    }

    /// 把已通过 generated wire 校验的嵌套 condition 字符串转成领域值。
    private static func stringValue(_ json: JSON,
                                    _ key: String,
                                    allowsNull: Bool = false) throws -> String? {
        guard let value = json[key] else { return nil }
        switch value {
        case .string(let string):
            return string
        case .null where allowsNull:
            return nil
        default:
            let expected = allowsNull ? "a string or null" : "a string"
            throw CommandInputParseError("condition field '\(key)' must be \(expected)")
        }
    }
}
