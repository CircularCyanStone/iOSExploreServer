import Foundation

/// 命令执行日志归属。
///
/// core 内置命令使用 `.core`，扩展模块（如 UIKit 命令）使用自定义 category，把日志接入
/// 同一套 `ESLogger` sink，同时避免 core 暴露内部 `ESLogCategory`。
public enum CommandLogCategory: Sendable, Equatable {
    /// core 命令日志，最终进入内部 `command` category。
    case core
    /// 扩展命令日志，category 由扩展模块指定。
    case extensionCommand(category: String)
}

/// 可被 `ExploreServer` 注册和路由的 typed 命令协议。
///
/// 每个新增能力都应该提供完整 `CommandContract` 并通过 `register` 注入，而不是修改 HTTP
/// 协议。合同负责对外 metadata；命令输入仍由 `Input` 从动态 JSON 解析成 Swift 值，再进入
/// 业务逻辑，确保合同迁移不会改变现有 parser 行为。
public protocol Command: Sendable {
    /// 命令输入类型，负责 schema 暴露与 JSON data 解析。
    associatedtype Input: CommandInput

    /// 命令的完整 wire-level 合同。
    var contract: CommandContract { get }

    /// 执行命令。
    ///
    /// - Parameter input: 已按 `Input.inputSchema` 解析并校验的 typed 输入。
    /// - Returns: 业务结果。抛出的异常会由 `AnyCommand` 捕获并转换为 `internal_error`。
    /// - Throws: 命令执行中出现的未转换异常。
    func handle(_ input: Input) async throws -> ExploreResult

    /// 命令自声明的执行超时（纳秒）。
    ///
    /// nil 表示沿用全局 `ClientSession.Configuration.commandTimeoutNanoseconds`；
    /// 高耗时命令（如截图）可返回具体值覆盖全局上限。类型对齐
    /// `commandTimeoutNanoseconds: UInt64` 与 `withTimeout(nanoseconds: UInt64)`，
    /// 不使用 `Duration`，避免在路由查表路径引入额外单位换算。默认 nil 由协议扩展提供。
    var timeoutNanoseconds: UInt64? { get }
}

public extension Command {
    /// 命令名，由 `contract.action` 派生。
    var action: String { contract.action }

    /// 命令人类可读描述，由 `contract.description` 派生。
    var description: String { contract.description }

    /// 默认不自声明超时，所有命令沿用全局 `commandTimeoutNanoseconds`。
    var timeoutNanoseconds: UInt64? { nil }
}

private enum CommandExecutionOutcome: Sendable {
    case completed(ExploreResult)
    case parseFailed(ExploreServerError)
    case parseUnexpected(ExploreServerError)
    case handlerFailed(ExploreServerError)
}

/// 类型擦除后的命令。
///
/// `Router` 只保存 `AnyCommand`，因此无需关心每个命令的具体 `Input` 类型。该适配器负责
/// typed input 解析、handler 异常兜底和命令级日志，确保协议对象注册与闭包注册走同一条
/// 执行路径。
public struct AnyCommand: Sendable {
    /// 命令的完整 wire-level 合同。
    public let contract: CommandContract

    /// 命令名，也是 HTTP body 中 `action` 字段的匹配键。
    public var action: String { contract.action }

    /// 命令人类可读描述，由 `help` 输出给调用方。
    public var description: String { contract.description }

    /// 命令输入 schema，由 `help` 输出给调用方和工具客户端。
    public var inputSchema: CommandInputSchema { contract.inputSchema }

    /// 命令执行日志归属。
    public let logCategory: CommandLogCategory

    /// 命令自声明的执行超时（纳秒）。
    ///
    /// 透传自协议命令的 `Command.timeoutNanoseconds`；闭包命令构造时为 nil。由
    /// `Router.commandTimeout(for:)` 在路由前查表读取，决定 `withTimeout` 包裹的上限。
    public let timeoutNanoseconds: UInt64?

    private let executor: @Sendable (ExploreRequest) async -> CommandExecutionOutcome

    /// 包装一个协议命令对象。
    ///
    /// - Parameters:
    ///   - command: 具体命令对象。
    ///   - logCategory: 命令日志归属；core 命令默认走内部 `command` category。
    public init<C: Command>(_ command: C, logCategory: CommandLogCategory = .core) {
        self.contract = command.contract
        self.logCategory = logCategory
        self.timeoutNanoseconds = command.timeoutNanoseconds
        self.executor = { request in
            let input: C.Input
            do {
                input = try C.Input.parse(from: request.data)
            } catch let error as CommandInputParseError {
                return .parseFailed(ExploreServerError.invalidData(action: command.action, message: error.message))
            } catch {
                return .parseUnexpected(ExploreServerError.unexpectedInputParseError(action: command.action, error: error))
            }
            do {
                return .completed(try await command.handle(input))
            } catch {
                return .handlerFailed(ExploreServerError.handlerThrown(action: command.action, error: error))
            }
        }
    }

    /// 使用显式合同创建一个 typed 闭包命令。
    ///
    /// `contract.inputSchema` 用于 metadata 输出，实际执行仍调用 `Input.parse(from:)`，因此
    /// generated schema 接入不会在 Task 5 之前改变现有手写 parser。
    ///
    /// - Parameters:
    ///   - contract: 命令的完整 wire-level 合同。
    ///   - input: 命令输入类型，负责实际 JSON 解析。
    ///   - logCategory: 命令日志归属；core 命令默认走内部 `command` category。
    ///   - handler: 已拿到 typed 输入后的业务处理闭包。
    public init<Input: CommandInput>(contract: CommandContract,
                                     input: Input.Type,
                                     logCategory: CommandLogCategory = .core,
                                     handler: @escaping @Sendable (Input) async throws -> ExploreResult) {
        self.contract = contract
        self.logCategory = logCategory
        self.timeoutNanoseconds = nil
        self.executor = { request in
            let inputValue: Input
            do {
                inputValue = try Input.parse(from: request.data)
            } catch let error as CommandInputParseError {
                return .parseFailed(ExploreServerError.invalidData(action: contract.action, message: error.message))
            } catch {
                return .parseUnexpected(ExploreServerError.unexpectedInputParseError(action: contract.action,
                                                                                     error: error))
            }
            do {
                return .completed(try await handler(inputValue))
            } catch {
                return .handlerFailed(ExploreServerError.handlerThrown(action: contract.action, error: error))
            }
        }
    }

    /// 创建一个 runtime extension typed 闭包命令。
    ///
    /// 该兼容入口会使用 `Input.inputSchema` 构造保守合同：命令属于 runtime extension，按
    /// side-effecting 处理且不声明错误码；合同版本和哈希沿用公共 core bundle。
    ///
    /// - Parameters:
    ///   - action: 命令名，也是 HTTP body 中 `action` 字段的匹配键。
    ///   - description: 命令人类可读描述，由 `help` 输出。
    ///   - input: 命令输入类型。
    ///   - logCategory: 命令日志归属；core 命令默认走内部 `command` category。
    ///   - handler: 已拿到 typed 输入后的业务处理闭包。
    public init<Input: CommandInput>(action: String,
                                     description: String = "",
                                     input: Input.Type,
                                     logCategory: CommandLogCategory = .core,
                                     handler: @escaping @Sendable (Input) async throws -> ExploreResult) {
        let contract = CommandContract(action: action,
                                       description: description,
                                       inputSchema: Input.inputSchema,
                                       provider: .extension,
                                       stability: .`internal`,
                                       resultKind: .json,
                                       declaredErrors: [],
                                       idempotency: .sideEffecting,
                                       timeoutClass: .standard,
                                       contractVersion: CoreActionContracts.contractVersion,
                                       contractHash: CoreActionContracts.contractHash,
                                       contractSource: .runtime)
        self.init(contract: contract,
                  input: input,
                  logCategory: logCategory,
                  handler: handler)
    }

    /// 解析请求 data 并执行命令。
    ///
    /// 方法不会向路由层抛错：输入解析失败映射为 `invalid_data`，handler 未转换异常映射为
    /// `internal_error`。日志只记录 action、schema 字段数和错误摘要，不输出完整 payload。
    ///
    /// - Parameter request: 已由 HTTP 层解析出的命令请求。
    /// - Returns: 业务成功或失败 envelope 的中间结果。
    public func handle(_ request: ExploreRequest) async -> ExploreResult {
        emit(.debug, "command \(action) start schemaFields=\(inputSchema.fields.count) payloadKeys=\(request.data.storage.count)")
        switch await executor(request) {
        case .completed(let result):
            logCompleted(result)
            return result
        case .parseFailed(let error):
            emit(.error, "command \(action) parse failed code=\(error.code.rawValue) message=\(error.logMessage)")
            return .failure(code: error.code, message: error.message)
        case .parseUnexpected(let error):
            emit(.error, "command \(action) parse unexpected code=\(error.code.rawValue) message=\(error.logMessage)")
            return .failure(code: error.code, message: error.message)
        case .handlerFailed(let error):
            emit(.error, "command \(action) failed code=\(error.code.rawValue) message=\(error.logMessage)")
            return .failure(code: error.code, message: error.message)
        }
    }

    private func logCompleted(_ result: ExploreResult) {
        switch result {
        case .success(let data):
            emit(.info, "command \(action) completed ok=true resultKeys=\(data.storage.count)")
        case .failure(let code, let message, _):
            emit(.error, "command \(action) failed code=\(code.rawValue) message=\(message)")
        }
    }

    private func emit(_ level: ESLogLevel, _ message: String) {
        switch logCategory {
        case .core:
            Self.emitCore(level, message)
        case .extensionCommand(let category):
            ESLogger.emitExtension(level: level, category: category, message: message)
        }
    }

    private static func emitCore(_ level: ESLogLevel, _ message: String) {
        switch level {
        case .debug:
            ESLogger.debug(.command, message)
        case .info:
            ESLogger.info(.command, message)
        case .error:
            ESLogger.error(.command, message)
        case .fault:
            ESLogger.fault(.command, message)
        }
    }
}
