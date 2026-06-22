import Foundation

/// 内置命令。库内不依赖 UIKit;info 仅返回 ProcessInfo/Bundle 可得字段。

struct PingCommand: Command {
    let action = "ping"
    let description = "健康检查,返回 pong"
    func handle(_ request: ExploreRequest) async throws -> ExploreResult {
        .success(["pong": .bool(true)])
    }
}

struct EchoCommand: Command {
    let action = "echo"
    let description = "原样回显 data"
    func handle(_ request: ExploreRequest) async throws -> ExploreResult {
        .success(request.data)
    }
}

struct InfoCommand: Command {
    let action = "info"
    let description = "返回系统/应用/Bundle 信息"
    func handle(_ request: ExploreRequest) async throws -> ExploreResult {
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

/// 列出所有已注册命令的 action/description/parameters(对齐 MCP tools/list)。
struct HelpCommand: Command {
    let action = "help"
    let description = "列出所有已注册命令及其参数说明"
    private let router: Router
    init(router: Router) { self.router = router }

    func handle(_ request: ExploreRequest) async throws -> ExploreResult {
        let entries: [JSONValue] = router.commandMetadata().map { entry in
            let params: [JSONValue] = entry.parameters.map { p in
                .object(JSON([
                    "name": .string(p.name),
                    "kind": .string(p.kind.rawValue),
                    "required": .bool(p.required),
                    "description": .string(p.description),
                ]))
            }
            return .object(JSON([
                "action": .string(entry.action),
                "description": .string(entry.description),
                "parameters": .array(params),
            ]))
        }
        return .success(JSON(["commands": .array(entries)]))
    }
}

enum BuiltinHandlers {
    /// 把内置命令注册进 router(同步)。
    static func registerAll(into router: Router) {
        router.register(PingCommand())
        router.register(EchoCommand())
        router.register(InfoCommand())
        router.register(HelpCommand(router: router))
    }
}
