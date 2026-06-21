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

    /// 把三个内置命令注册进 router。
    static func registerAll(into router: Router) async {
        await router.register(action: "ping") { ping($0) }
        await router.register(action: "echo") { echo($0) }
        await router.register(action: "info") { info($0) }
    }
}
