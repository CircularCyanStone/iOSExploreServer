import Testing
@testable import iOSExploreServer
import iOSExploreUIKit

/// 验证 core 初始化不再自动注册 UIKit 命令。
///
/// 重构后 UIKit 能力由独立模块 `iOSExploreUIKit` 提供，宿主必须显式调用
/// `ExploreServer.registerUIKitCommands()`。该测试断言 `ExploreServer()` 默认
/// 初始化后 `help` 不包含任何 `ui.*` action。
///
/// 注意：在 macOS 上 `canImport(UIKit)` 为 false，UIKit 命令本就不会注册，因此该
/// 测试在 macOS 上恒为 PASS；真正的 iOS 自动注册回归防护由 Task 7 的 framework
/// 测试完成。
@Suite("UIKit 命令注册")
struct UIKitCommandRegistrationTests {
    @Test("core 初始化不会自动注册 UIKit action")
    func coreDoesNotAutoRegisterUIKitCommands() async {
        let server = ExploreServer()
        #expect((await server.routerSnapshotRoute(ExploreRequest(action: "help"))).commandActions.contains("ui.tap") == false)
    }

#if canImport(UIKit)
    /// 显式注册后，`help` 必须列出全部四个 UIKit action。
    ///
    /// 该测试仅在 iOS（framework 工程 `xcodebuild ... test`）下编译运行；macOS SPM 下
    /// `canImport(UIKit)` 为 false，整个方法不参与编译。它是 UIKit 命令"显式注册"语义
    /// 的正向回归点：防止后续重构悄悄漏掉某个命令或改了 action 名而无人发现。
    @Test("显式注册后 help 包含 UIKit actions")
    func explicitRegistrationAddsUIKitCommands() async {
        let server = ExploreServer()
        server.registerUIKitCommands()
        let result = await server.routerSnapshotRoute(ExploreRequest(action: "help"))
        #expect(result.commandActions.contains("ui.topViewHierarchy"))
        #expect(result.commandActions.contains("ui.viewTargets"))
        #expect(result.commandActions.contains("ui.control.sendAction"))
        #expect(result.commandActions.contains("ui.tap"))
    }
#endif
}

private extension ExploreResult {
    /// 提取 `help` 响应中所有注册命令的 action 名称。
    var commandActions: [String] {
        guard case .success(let data) = self,
              case .array(let commands)? = data["commands"] else { return [] }
        return commands.compactMap {
            guard case .object(let command) = $0 else { return nil }
            return command["action"]?.stringValue
        }
    }
}
