#if canImport(UIKit)
import iOSExploreServer
import UIKit

/// UIKit 命令显式注册入口。
///
/// 重构后 core 不再自动注册 UIKit 命令；宿主 App 在初始化 `ExploreServer` 后，
/// 调用 `server.registerUIKitCommands()` 把 `ui.topViewHierarchy`、`ui.inspect`、
/// `ui.control.sendAction`、`ui.tap`、`ui.screenshot`、`ui.input`、`ui.keyboard.dismiss`、
/// `ui.scroll`、`ui.navigation.back`、`ui.navigation.tapBarButton`、`ui.wait`、`ui.waitAny`、`ui.scrollToElement`、`ui.alert.respond`、`ui.controllers` 十五个命令显式挂到 router 上。
///
/// 该扩展整体位于 `#if canImport(UIKit)` 内：macOS 下不参与编译，iOS 下提供注册
/// 实现。注册前会在 Debug 构建中安装 alert action handler 捕获；注册前后通过
/// `UIKitCommandLogging` 记录进入与完成（含注册数量），便于排查「UIKit 命令未注册」类问题。
public extension ExploreServer {
    /// 注册全部 UIKit 命令。
    ///
    /// 幂等调用安全：重复注册同一 action 会覆盖旧 handler，不会报错。建议在
    /// `ExploreServer.init` 之后、`start()` 之前调用一次。
    ///
    /// - Parameter maxResponseBodyBytes: 响应 body 字节上限，透传给 `ui.screenshot`，
    ///   截图 base64 估算超限即返回 `responseTooLarge`。默认 6MB，与 `ExploreServer` 默认一致。
    func registerUIKitCommands(maxResponseBodyBytes: Int = 6 * 1024 * 1024) {
        UIKitCommandLogging.info("uikit.registrar", "registration started")
        #if DEBUG
        do {
            try UIAlertAction.explore_installHandlerCapture()
        } catch {
            UIKitCommandLogging.error("uikit.registrar", "alert action handler capture install failed error=\(error)")
        }
        #endif
        register(TopViewHierarchyCommand(), logCategory: .extensionCommand(category: "command"))
        register(InspectCommand(), logCategory: .extensionCommand(category: "command"))
        register(UIControlSendActionCommand(), logCategory: .extensionCommand(category: "command"))
        register(UITapCommand(), logCategory: .extensionCommand(category: "command"))
        register(ScreenshotCommand(maxResponseBodyBytes: maxResponseBodyBytes),
                 logCategory: .extensionCommand(category: "command"))
        register(InputCommand(), logCategory: .extensionCommand(category: "command"))
        register(KeyboardDismissCommand(), logCategory: .extensionCommand(category: "command"))
        register(ScrollCommand(), logCategory: .extensionCommand(category: "command"))
        register(NavigationBackCommand(), logCategory: .extensionCommand(category: "command"))
        register(NavigationBarButtonCommand(), logCategory: .extensionCommand(category: "command"))
        register(WaitCommand(), logCategory: .extensionCommand(category: "command"))
        register(WaitAnyCommand(), logCategory: .extensionCommand(category: "command"))
        register(ScrollToElementCommand(), logCategory: .extensionCommand(category: "command"))
        register(AlertRespondCommand(), logCategory: .extensionCommand(category: "command"))
        register(ControllersCommand(), logCategory: .extensionCommand(category: "command"))
        UIKitCommandLogging.info("uikit.registrar", "registration completed count=15")
    }
}
#endif
