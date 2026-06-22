import Foundation

/// 命令参数的 JSON 类型声明。
///
/// 该枚举覆盖 `JSONValue` 中除 `null` 以外的类型，用于 `Router` 在进入 handler 前做
/// 轻量参数校验，也用于 `help` 命令向 Mac 侧暴露工具 schema。
public enum ParameterKind: String, Sendable {
    /// JSON 字符串。
    case string

    /// JSON 数字，对应 `JSONValue.double`。
    case number

    /// JSON 布尔值。
    case boolean

    /// JSON 对象。
    case object

    /// JSON 数组。
    case array
}

/// 单个命令参数的描述。
///
/// `Router` 只使用 `name`、`kind`、`required` 做存在性和类型校验；`description`
/// 面向调用方展示，当前由 `help` 命令输出，后续 Mac 侧 MCP tools/list 也可以直接复用。
public struct CommandParameter: Sendable, Equatable {
    /// 参数名，对应请求 `data` 对象里的键。
    public let name: String

    /// 参数期望的 JSON 类型。
    public let kind: ParameterKind

    /// 是否必填。必填参数缺失或显式为 `null` 会返回 `invalid_data`。
    public let required: Bool

    /// 给人或工具客户端阅读的参数说明。
    public let description: String

    /// 创建一个命令参数描述。
    ///
    /// - Parameters:
    ///   - name: 参数名。
    ///   - kind: 参数 JSON 类型。
    ///   - required: 是否必填。
    ///   - description: 参数说明。
    public init(name: String, kind: ParameterKind, required: Bool, description: String) {
        self.name = name
        self.kind = kind
        self.required = required
        self.description = description
    }
}

/// 可被 `ExploreServer` 注册和路由的命令协议。
///
/// 每个新增能力都应该实现为一个新的 `action`，并通过 `register` 注入，而不是修改 HTTP
/// 协议。协议本身保持小而稳定：`action` 负责路由，`description` 和 `parameters`
/// 负责自描述，`handle` 执行业务逻辑。
///
/// 扩展性靠协议扩展默认值：未来新增可选元数据时，应在 extension 中给默认实现，避免
/// 破坏既有命令实现。
public protocol Command: Sendable {
    /// 命令名，也是 HTTP body 中 `action` 字段的匹配键。
    var action: String { get }

    /// 命令人类可读描述，由 `help` 输出给调用方。
    var description: String { get }

    /// 命令参数 schema。路由层会在调用 `handle` 前执行轻量校验。
    var parameters: [CommandParameter] { get }

    /// 执行命令。
    ///
    /// - Parameter request: 已解析并通过参数校验的命令请求。
    /// - Returns: 业务结果。抛出的异常会被 `Router` 捕获并转换为 `internal_error`。
    func handle(_ request: ExploreRequest) async throws -> ExploreResult
}

public extension Command {
    /// 默认无参数，方便简单命令只声明 `action`、`description` 和 `handle`。
    var parameters: [CommandParameter] { [] }
}

/// 闭包注册入口的内部适配器。
///
/// `ExploreServer.register(action:...)` 和 `Router.register(action:...)` 最终都会生成
/// `ClosureCommand`，再走协议对象注册路径。这样闭包命令与结构体命令共享同一套参数校验、
/// 自省和错误转换逻辑。
struct ClosureCommand: Command {
    /// 命令名。
    let action: String

    /// 命令描述。
    let description: String

    /// 参数 schema。
    let parameters: [CommandParameter]

    /// 调用方提供的实际处理闭包。
    let handler: @Sendable (ExploreRequest) async throws -> ExploreResult

    /// 创建一个闭包命令适配器。
    init(action: String,
         description: String = "",
         parameters: [CommandParameter] = [],
         handler: @escaping @Sendable (ExploreRequest) async throws -> ExploreResult) {
        self.action = action
        self.description = description
        self.parameters = parameters
        self.handler = handler
    }

    /// 转发给底层闭包执行。
    func handle(_ request: ExploreRequest) async throws -> ExploreResult {
        try await handler(request)
    }
}
