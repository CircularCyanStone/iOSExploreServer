#if canImport(UIKit)
import iOSExploreServer
import UIKit

/// UIKit 命令显式注册入口。
///
/// 重构后 core 不再自动注册 UIKit 命令；宿主 App 在初始化 `ExploreServer` 后，
/// 调用 `server.registerUIKitCommands()` 把 `ui.topViewHierarchy`、`ui.viewTargets`、
/// `ui.control.sendAction`、`ui.tap` 四个命令显式挂到 router 上。
///
/// 该扩展整体位于 `#if canImport(UIKit)` 内：macOS 下不参与编译，iOS 下提供注册
/// 实现。注册前后通过 `UIKitCommandLogging` 记录进入与完成（含注册数量），便于
/// 排查「UIKit 命令未注册」类问题。
public extension ExploreServer {
    /// 注册全部 UIKit 命令。
    ///
    /// 幂等调用安全：重复注册同一 action 会覆盖旧 handler，不会报错。建议在
    /// `ExploreServer.init` 之后、`start()` 之前调用一次。
    func registerUIKitCommands() {
        UIKitCommandLogging.info("uikit.registrar", "registration started")
        register(TopViewHierarchyCommand())
        register(ViewTargetsCommand())
        register(UIControlSendActionCommand())
        register(UITapCommand())
        UIKitCommandLogging.info("uikit.registrar", "registration completed count=4")
    }
}
#endif
