import Foundation

/// 内置健康检查命令。
///
/// 主要用于 Mac 侧确认 USB 转发、端口监听和 JSON envelope 是否工作正常。
struct PingCommand: Command {
    /// 固定 action 名。
    let action = "ping"

    /// `help` 命令展示的说明。
    let description = "健康检查,返回 pong"

    /// 返回 `{ "pong": true }`。
    func handle(_ request: ExploreRequest) async throws -> ExploreResult {
        ExploreLogger.debug(.command, "command ping handled")
        return .success(["pong": .bool(true)])
    }
}

/// 内置回显命令。
///
/// 用于验证请求 body 中 `data` 的解析和 JSON 类型转换是否符合预期。
struct EchoCommand: Command {
    /// 固定 action 名。
    let action = "echo"

    /// `help` 命令展示的说明。
    let description = "原样回显 data"

    /// 原样返回请求中的 `data`。
    func handle(_ request: ExploreRequest) async throws -> ExploreResult {
        ExploreLogger.debug(.command, "command echo handled keys=\(request.data.storage.count)")
        return .success(request.data)
    }
}

/// 内置基础信息命令。
///
/// 库硬性不依赖 UIKit，因此这里仅返回 `Foundation` 可取得的系统、应用版本和 bundle
/// identifier。设备型号、系统名称等 UIKit 信息应由宿主 App 注册自定义 handler 提供。
struct InfoCommand: Command {
    /// 固定 action 名。
    let action = "info"

    /// `help` 命令展示的说明。
    let description = "返回系统/应用/Bundle 信息"

    /// 返回 `ProcessInfo` 和 `Bundle.main` 可取得的基础信息。
    func handle(_ request: ExploreRequest) async throws -> ExploreResult {
        ExploreLogger.debug(.command, "command info handled")
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
/// 返回所有已注册命令的 `action`、`description`、`parameters`，结构有意靠近 MCP
/// tools/list 所需信息，方便后续 Mac 侧自动发现可调用能力。
struct HelpCommand: Command {
    /// 固定 action 名。
    let action = "help"

    /// `help` 命令展示的说明。
    let description = "列出所有已注册命令及其参数说明"

    /// 用于读取命令元数据快照的路由器。
    private let router: Router

    /// 创建 help 命令。
    init(router: Router) { self.router = router }

    /// 读取当前命令元数据并转换为 JSON 数组。
    func handle(_ request: ExploreRequest) async throws -> ExploreResult {
        ExploreLogger.debug(.command, "command help handled")
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

/// 内置命令注册入口。
///
/// `ExploreServer` 初始化时调用一次，把 ping/echo/info/help 注入同一个 `Router`。
enum BuiltinHandlers {
    /// 把内置命令注册进 router（同步）。
    static func registerAll(into router: Router) {
        ExploreLogger.info(.command, "builtin handlers register all")
        router.register(PingCommand())
        router.register(EchoCommand())
        router.register(InfoCommand())
        router.register(HelpCommand(router: router))
    }
}
