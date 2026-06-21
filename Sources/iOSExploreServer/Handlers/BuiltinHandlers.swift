import Foundation

/// 内置命令。库内不依赖 UIKit；info 仅返回 ProcessInfo/Bundle 可得字段。
enum BuiltinHandlers {
    static func ping(_ req: ExploreRequest) -> ExploreResult {
        .success(["pong": .bool(true)])
    }

    static func echo(_ req: ExploreRequest) -> ExploreResult {
        .success(req.data)
    }

    static func info(_ req: ExploreRequest) -> ExploreResult {
        let processInfo = ProcessInfo.processInfo
        let bundle = Bundle.main
        let info: JSON = [
            "system": .string(processInfo.operatingSystemVersionString),
            "app": .string((bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"),
            "bundle": .string(bundle.bundleIdentifier ?? "unknown"),
        ]
        return .success(info)
    }

    /// 把三个内置命令注册进 router(同步)。
    static func registerAll(into router: Router) {
        router.register(action: "ping", description: "健康检查,返回 pong") { ping($0) }
        router.register(action: "echo", description: "原样回显 data") { echo($0) }
        router.register(action: "info", description: "返回系统/应用/Bundle 信息") { info($0) }
    }
}
