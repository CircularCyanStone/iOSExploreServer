import Foundation

/// 内置健康检查命令。
///
/// 主要用于 Mac 侧确认 USB 转发、端口监听和 JSON envelope 是否工作正常。
struct PingCommand: Command {
    /// 无参数输入。
    typealias Input = EmptyCommandInput

    /// 由 canonical bundle 生成的 core 合同。
    let contract = CoreActionContracts.pingContract

    /// 返回 `{ "pong": true }`。
    ///
    /// - Parameter input: 空输入，ping 不读取请求 data。
    /// - Returns: `{ "pong": true }`。
    func handle(_ input: EmptyCommandInput) async throws -> ExploreResult {
        ESLogger.debug(.command, "command ping handled")
        return .success(["pong": .bool(true)])
    }
}

/// 内置回显命令。
///
/// 用于验证请求 body 中 `data` 的解析和 JSON 类型转换是否符合预期。
struct EchoCommand: Command {
    /// 原始 JSON 输入，允许任意字段并完整透传。
    typealias Input = RawJSONInput

    /// 由 canonical bundle 生成的 core 合同。
    let contract = CoreActionContracts.echoContract

    /// 原样返回请求中的 `data`。
    ///
    /// - Parameter input: 保留原始 data 的输入模型。
    /// - Returns: 与请求 data 完全一致的 JSON object。
    func handle(_ input: RawJSONInput) async throws -> ExploreResult {
        ESLogger.debug(.command, "command echo handled keys=\(input.data.storage.count)")
        return .success(input.data)
    }
}

/// 内置基础信息命令。
///
/// 库硬性不依赖 UIKit，因此这里仅返回 `Foundation` 可取得的系统、应用版本和 bundle
/// identifier。设备型号、系统名称等 UIKit 信息应由宿主 App 注册自定义 handler 提供。
struct InfoCommand: Command {
    /// 无参数输入。
    typealias Input = EmptyCommandInput

    /// 由 canonical bundle 生成的 core 合同。
    let contract = CoreActionContracts.infoContract

    /// 返回 `ProcessInfo` 和 `Bundle.main` 可取得的基础信息。
    ///
    /// - Parameter input: 空输入，info 不读取请求 data。
    /// - Returns: 系统、应用版本和 bundle identifier。
    func handle(_ input: EmptyCommandInput) async throws -> ExploreResult {
        ESLogger.debug(.command, "command info handled")
        let processInfo = ProcessInfo.processInfo
        let bundle = Bundle.main
        let info: JSON = [
            "system": .string(processInfo.operatingSystemVersionString),
            "app": .string((bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"),
            "bundle": .string(bundle.bundleIdentifier ?? "unknown"),
        ]
        return .success(info)
    }
}

/// 内置命令自省能力。
///
/// 返回所有已注册命令的 `action`、`description`、`inputSchema`，结构有意靠近 MCP
/// tools/list 所需信息，方便后续 Mac 侧自动发现可调用能力。
struct HelpCommand: Command {
    /// 无参数输入。
    typealias Input = EmptyCommandInput

    /// 由 canonical bundle 生成的 core 合同。
    let contract = CoreActionContracts.helpContract

    /// 用于读取命令元数据快照的路由器。
    private let router: Router

    /// 创建 help 命令。
    ///
    /// - Parameter router: 用于读取命令元数据快照的路由器。
    init(router: Router) { self.router = router }

    /// 读取当前命令合同并构造成包含公共 bundle metadata 的 JSON object。
    ///
    /// - Parameter input: 空输入，help 不读取请求 data。
    /// - Returns: 包含协议版本、合同版本/哈希和所有已注册命令完整 metadata 的 JSON object。
    func handle(_ input: EmptyCommandInput) async throws -> ExploreResult {
        let contracts = router.commandMetadata()
        ESLogger.debug(.command,
                       "command help metadata projection count=\(contracts.count) protocolVersion=\(CoreActionContracts.protocolVersion) contractVersion=\(CoreActionContracts.contractVersion)")
        let entries: [JSONValue] = contracts.map { contract in
            return .object(JSON([
                "action": .string(contract.action),
                "description": .string(contract.description),
                "inputSchema": .object(contract.inputSchema.toJSON()),
                "provider": .string(contract.provider.rawValue),
                "stability": .string(contract.stability.rawValue),
                "result": .object([
                    "kind": .string(contract.resultKind.rawValue),
                ]),
                "errors": .array(contract.declaredErrors.map { .string($0) }),
                "idempotency": .string(contract.idempotency.rawValue),
                "timeoutClass": .string(contract.timeoutClass.rawValue),
                "contractVersion": .string(contract.contractVersion),
                "contractHash": .string(contract.contractHash),
                "contractSource": .string(contract.contractSource.rawValue),
            ]))
        }
        return .success(JSON([
            "protocolVersion": .string(CoreActionContracts.protocolVersion),
            "contractVersion": .string(CoreActionContracts.contractVersion),
            "contractHash": .string(CoreActionContracts.contractHash),
            "commands": .array(entries),
        ]))
    }
}

/// 内置命令注册入口。
///
/// `ExploreServer` 初始化时调用一次，把 ping/echo/info/help 注入同一个 `Router`。
enum BuiltinHandlers {
    /// 把内置命令注册进 router（同步）。
    static func registerAll(into router: Router) {
        ESLogger.info(.command, "builtin handlers register all")
        router.register(PingCommand())
        router.register(EchoCommand())
        router.register(InfoCommand())
        router.register(HelpCommand(router: router))
    }
}
