#if canImport(UIKit)
import Foundation

/// UIKit 内置命令注册入口。
///
/// 该文件只在 UIKit 可用的平台编译。它把所有 UIKit 相关命令集中注册到同一个
/// `Router`，避免基础网络层直接依赖 UIKit。
enum UIKitHandlers {
    /// 注册 UIKit 命令。
    ///
    /// - Parameter router: 命令路由器。
    static func registerAll(into router: Router) {
        ExploreLogger.info(.command, "uikit handlers register all")
        router.register(TopViewHierarchyCommand())
        router.register(ViewTargetsCommand())
        router.register(UIControlSendActionCommand())
        router.register(UITapCommand())
    }
}
#endif
