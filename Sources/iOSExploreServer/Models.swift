import Foundation

/// 命令协议中可传输的 JSON 值。
///
/// `iOSExploreServer` 只接受和返回 JSON，因此命令参数、命令结果和 envelope
/// 都通过这个枚举表达。它避免把 `Any` 暴露给业务 handler，使跨并发边界的数据保持
/// `Sendable`、可比较，也便于测试中精确断言。
public enum JSONValue: Sendable, Equatable {
    /// JSON 字符串。
    case string(String)

    /// JSON 数字。
    ///
    /// 当前模型统一用 `Double` 保存整数和浮点数；如果业务需要整型语义，应在 handler
    /// 中自行做取整或范围校验。
    case double(Double)

    /// JSON 布尔值。
    case bool(Bool)

    /// JSON 对象，对应 `[String: JSONValue]` 容器。
    case object(JSON)

    /// JSON 数组。
    case array([JSONValue])

    /// JSON null。
    case null
}

extension JSONValue: ExpressibleByStringLiteral {
    /// 允许在构造 `JSON` 时直接写字符串字面量，例如 `["name": "Tom"]`。
    public init(stringLiteral value: String) { self = .string(value) }
}
extension JSONValue: ExpressibleByIntegerLiteral {
    /// 允许直接写整数字面量；内部会转成 `.double`。
    public init(integerLiteral value: Int) { self = .double(Double(value)) }
}
extension JSONValue: ExpressibleByFloatLiteral {
    /// 允许直接写浮点数字面量。
    public init(floatLiteral value: Double) { self = .double(value) }
}
extension JSONValue: ExpressibleByBooleanLiteral {
    /// 允许直接写布尔字面量。
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}
extension JSONValue: ExpressibleByNilLiteral {
    /// 允许直接写 `nil` 字面量表示 JSON null。
    public init(nilLiteral: ()) { self = .null }
}

extension JSONValue {
    /// 当值为 `.string` 时返回底层字符串，否则返回 `nil`。
    public var stringValue: String? { if case .string(let v) = self { return v } else { return nil } }

    /// 当值为 `.double` 时返回底层数字，否则返回 `nil`。
    public var doubleValue: Double? { if case .double(let v) = self { return v } else { return nil } }

    /// 当值为 `.bool` 时返回底层布尔值，否则返回 `nil`。
    public var boolValue: Bool? { if case .bool(let v) = self { return v } else { return nil } }

    /// 当值为 `.array` 时返回底层数组，否则返回 `nil`。
    public var arrayValue: [JSONValue]? { if case .array(let v) = self { return v } else { return nil } }

    /// 当值为 `.object` 时返回底层 JSON 对象，否则返回 `nil`。
    public var objectValue: JSON? { if case .object(let v) = self { return v } else { return nil } }
}

/// JSON 对象容器。
///
/// 命令请求的 `data`、命令成功结果的 `data`，以及 envelope 的内部结构都用它表达。
/// 该类型只允许字符串键和 `JSONValue` 值，避免把非 JSON 类型带入协议层。
public struct JSON: Sendable, Equatable {
    /// 底层 JSON 对象存储。
    ///
    /// 保持公开是为了让集成方在少数场景下可以遍历或批量转换；常规读取建议使用
    /// `subscript`。
    public var storage: [String: JSONValue]

    /// 创建一个 JSON 对象容器。
    ///
    /// - Parameter storage: 初始键值表，默认为空对象。
    public init(_ storage: [String: JSONValue] = [:]) { self.storage = storage }

    /// 读取或写入指定键的 JSON 值。
    public subscript(key: String) -> JSONValue? {
        get { storage[key] }
        set { storage[key] = newValue }
    }
}

extension JSON: ExpressibleByDictionaryLiteral {
    /// 允许直接用字典字面量创建 `JSON`，例如 `["pong": true]`。
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self.storage = Dictionary(uniqueKeysWithValues: elements)
    }
}

/// 路由层传给命令 handler 的请求模型。
///
/// `ExploreRequest` 对应 HTTP body 中的：
///
/// ```json
/// { "action": "...", "data": { ... } }
/// ```
///
/// HTTP 方法、路径、Header 等通信层信息不会进入该模型，库的扩展能力只通过 `action`
/// 和 `data` 体现。
public struct ExploreRequest: Sendable, Equatable {
    /// 命令名，用于在 `Router` 中查找对应 handler。
    public let action: String

    /// 命令参数。缺省时为空 JSON 对象。
    public let data: JSON

    /// 创建一条命令请求。
    ///
    /// - Parameters:
    ///   - action: 命令名。
    ///   - data: 命令参数，默认为空对象。
    public init(action: String, data: JSON = [:]) {
        self.action = action
        self.data = data
    }
}

/// 命令 handler 的业务执行结果。
///
/// 注意它表达的是业务层成功或失败。通信层错误，例如非 `POST /`、HTTP body 不完整、
/// JSON 无法解析，不会通过 `ExploreResult` 返回，而是由 HTTP 层直接生成 400/500
/// envelope。
public enum ExploreResult: Sendable, Equatable {
    /// 业务成功，`JSON` 会被序列化进响应 envelope 的 `data` 字段，顶层 `code` 为 `ok`。
    case success(JSON)

    /// 业务失败，错误码和说明会被序列化进响应 envelope 的顶层 `code/message` 字段。
    case failure(code: ExploreError, message: String)
}

/// 统一 envelope 中失败 `code` 的取值。
///
/// 通信失败用 HTTP 状态码表达，业务失败统一 HTTP 200 + 顶层 `code`。新增能力（如 UIKit
/// 扩展命令）的业务错误码必须先在此枚举落点，再由对应错误工厂（`ExploreServerError` /
/// `UIKitCommandError`）引用，避免在调用点散写字符串。
public enum ExploreError: String, Sendable {
    /// `Router` 没有找到请求 action 对应的命令。
    case unknownAction = "unknown_action"

    /// 请求 data 无法按命令 `CommandInput` schema 解析。
    case invalidData = "invalid_data"

    /// handler 抛出异常，路由层将其兜底转换为内部错误。
    case internalError = "internal_error"

    /// HTTP 请求本身不符合协议，例如不是 `POST /` 或 body 不是合法命令 JSON。
    case badRequest = "bad_request"

    /// 命令执行超时（业务侧超时，区别于传输层 `readTimeout` 的 408）。
    ///
    /// 由 `ExploreServerError.commandTimeout` 引用；以 HTTP 200 + 顶层 `timeout` 返回，
    /// 不断开传输层。
    case timeout = "timeout"

    /// 命令产生的响应体超过最大尺寸（如截图/快照过大无法封装）。
    case responseTooLarge = "response_too_large"

    /// 定位器指向的元素已陈旧（snapshot 失效或视图树变化），无法可靠执行动作。
    case staleLocator = "stale_locator"

    /// 等待条件在业务 deadline 内未满足。
    case waitTimeout = "wait_timeout"

    /// 当前页面没有可返回的导航路径。
    case navigationBackUnavailable = "navigation_back_unavailable"

    /// 当前页面没有可操作的导航栏。
    case navigationBarUnavailable = "navigation_bar_unavailable"

    /// 指定的导航栏按钮不存在。
    case navigationBarItemNotFound = "navigation_bar_item_not_found"

    /// 导航栏按钮与调用方观察到的标题或 identifier 不一致。
    case navigationBarItemMismatch = "navigation_bar_item_mismatch"

    /// 导航栏按钮存在但当前不可用。
    case navigationBarItemDisabled = "navigation_bar_item_disabled"

    /// 导航栏按钮存在但没有可安全触发的 target-action 或 customView 控件动作。
    case navigationBarItemUnsupported = "navigation_bar_item_unsupported"

    /// 当前没有可处理的 UIAlertController。
    case alertUnavailable = "alert_unavailable"

    /// 指定的 alert 按钮不存在。
    case alertButtonNotFound = "alert_button_not_found"

    /// 当前 alert 不能安全默认选择按钮，需要调用方明确指定。
    case alertButtonRequired = "alert_button_required"

    /// 已选中 alert 按钮，但无法取到或执行对应的 handler。
    case alertButtonTriggerFailed = "alert_button_trigger_failed"

    /// 键盘或 first responder 收起失败。
    case keyboardDismissFailed = "keyboard_dismiss_failed"

    /// 目标在当前 UI 树或滚动搜索后仍未找到。
    case targetNotFound = "target_not_found"

    /// 输入被业务规则拒绝（如非法文本、不可编辑元素），区别于 schema 解析失败的 `invalid_data`。
    case inputRejected = "input_rejected"

    /// 视图正处于过渡态（如动画/页面切换中），当前动作无法安全执行。
    case transitionInProgress = "transition_in_progress"

    /// 文本输入类型不被支持（如向非文本控件输入、不支持的键盘类型）。
    case unsupportedTextInputType = "unsupported_text_input_type"

    /// 让目标视图成为 first responder 失败，无法进入编辑/焦点状态。
    case becomeFirstResponderFailed = "become_first_responder_failed"

    /// 渲染失败（如截图/快照采集时图层合成失败、上下文丢失）。
    case renderingFailed = "rendering_failed"

    /// 找不到可滚动的容器视图，无法执行滚动命令。
    case scrollContainerUnavailable = "scroll_container_unavailable"
}
