import Foundation

/// 参数类型,与 JSONValue 同构:使 schema 与 data 载荷类型系统统一演进。
public enum ParameterKind: String, Sendable {
    case string, number, boolean, object, array
}

/// 命令参数描述(对齐 MCP inputSchema 字段)。
public struct CommandParameter: Sendable, Equatable {
    public let name: String
    public let kind: ParameterKind
    public let required: Bool
    public let description: String

    public init(name: String, kind: ParameterKind, required: Bool, description: String) {
        self.name = name
        self.kind = kind
        self.required = required
        self.description = description
    }
}

/// 命令协议:承载 action 名、人类可读描述、参数 schema 与处理逻辑。
/// 扩展性靠协议扩展默认值:新增可选字段时在 extension 给默认,既有实现无需改动。
public protocol Command: Sendable {
    var action: String { get }
    var description: String { get }
    var parameters: [CommandParameter] { get }
    func handle(_ request: ExploreRequest) async throws -> ExploreResult
}

public extension Command {
    var parameters: [CommandParameter] { [] }
}

/// 闭包注册入口的适配器:与协议入口共享同一条路由路径。
struct ClosureCommand: Command {
    let action: String
    let description: String
    let parameters: [CommandParameter]
    let handler: @Sendable (ExploreRequest) async throws -> ExploreResult

    init(action: String,
         description: String = "",
         parameters: [CommandParameter] = [],
         handler: @escaping @Sendable (ExploreRequest) async throws -> ExploreResult) {
        self.action = action
        self.description = description
        self.parameters = parameters
        self.handler = handler
    }

    func handle(_ request: ExploreRequest) async throws -> ExploreResult {
        try await handler(request)
    }
}
