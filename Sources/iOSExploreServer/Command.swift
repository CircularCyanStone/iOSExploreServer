import Foundation

/// 命令执行日志归属。
///
/// core 内置命令使用 `.core`，扩展模块（如 UIKit 命令）使用自定义 category，把日志接入
/// 同一套 `ExploreLogging` sink，同时避免 core 暴露内部 `ExploreLogCategory`。
public enum CommandLogCategory: Sendable, Equatable {
    /// core 命令日志，最终进入内部 `command` category。
    case core
    /// 扩展命令日志，category 由扩展模块指定。
    case extensionCommand(category: String)
}

/// 可被 `ExploreServer` 注册和路由的 typed 命令协议。
///
/// 每个新增能力都应该实现为一个新的 `action`，并通过 `register` 注入，而不是修改 HTTP
/// 协议。命令输入先由 `Input` 从动态 JSON 解析成 Swift 值，再进入业务逻辑；`help`
/// 通过 `Input.inputSchema` 暴露工具可读 schema。
public protocol Command: Sendable {
    /// 命令输入类型，负责 schema 暴露与 JSON data 解析。
    associatedtype Input: CommandInput

    /// 命令名，也是 HTTP body 中 `action` 字段的匹配键。
    var action: String { get }

    /// 命令人类可读描述，由 `help` 输出给调用方。
    var description: String { get }

    /// 执行命令。
    ///
    /// - Parameter input: 已按 `Input.inputSchema` 解析并校验的 typed 输入。
    /// - Returns: 业务结果。抛出的异常会由 `AnyCommand` 捕获并转换为 `internal_error`。
    /// - Throws: 命令执行中出现的未转换异常。
    func handle(_ input: Input) async throws -> ExploreResult
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
    /// 命令名，也是 HTTP body 中 `action` 字段的匹配键。
    public let action: String

    /// 命令人类可读描述，由 `help` 输出给调用方。
    public let description: String

    /// 命令输入 schema，由 `help` 输出给调用方和工具客户端。
    public let inputSchema: CommandInputSchema

    /// 命令执行日志归属。
    public let logCategory: CommandLogCategory

    private let executor: @Sendable (ExploreRequest) async -> CommandExecutionOutcome

    /// 包装一个协议命令对象。
    ///
    /// - Parameters:
    ///   - command: 具体命令对象。
    ///   - logCategory: 命令日志归属；core 命令默认走内部 `command` category。
    public init<C: Command>(_ command: C, logCategory: CommandLogCategory = .core) {
        self.action = command.action
        self.description = command.description
        self.inputSchema = C.Input.inputSchema
        self.logCategory = logCategory
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

    /// 创建一个 typed 闭包命令。
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
        self.action = action
        self.description = description
        self.inputSchema = Input.inputSchema
        self.logCategory = logCategory
        self.executor = { request in
            let inputValue: Input
            do {
                inputValue = try Input.parse(from: request.data)
            } catch let error as CommandInputParseError {
                return .parseFailed(ExploreServerError.invalidData(action: action, message: error.message))
            } catch {
                return .parseUnexpected(ExploreServerError.unexpectedInputParseError(action: action, error: error))
            }
            do {
                return .completed(try await handler(inputValue))
            } catch {
                return .handlerFailed(ExploreServerError.handlerThrown(action: action, error: error))
            }
        }
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
        case .failure(let code, let message):
            emit(.error, "command \(action) failed code=\(code.rawValue) message=\(message)")
        }
    }

    private func emit(_ level: ExploreLogLevel, _ message: String) {
        switch logCategory {
        case .core:
            Self.emitCore(level, message)
        case .extensionCommand(let category):
            ExploreLogging.emitExtension(level: level, category: category, message: message)
        }
    }

    private static func emitCore(_ level: ExploreLogLevel, _ message: String) {
        switch level {
        case .debug:
            ExploreLogger.debug(.command, message)
        case .info:
            ExploreLogger.info(.command, message)
        case .error:
            ExploreLogger.error(.command, message)
        case .fault:
            ExploreLogger.fault(.command, message)
        }
    }
}
