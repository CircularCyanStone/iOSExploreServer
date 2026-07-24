#if canImport(UIKit)
import Foundation
import iOSExploreServer

/// `ui.tabBar.selectTab` 命令的输入模型。
///
/// 该命令通过 controller 层操作 UITabBarController,直接设置 selectedIndex 或按 title 定位。
/// 支持手动触发 delegate 回调,覆盖业务逻辑中挂在 tabBarController(_:didSelect:) 上的埋点/刷新。
public struct UITabBarSelectInput: CommandInput, Sendable, Equatable {
    /// 可选的 UITabBarController 路径(controller path 格式,如 "root.presented")。
    ///
    /// 省略时自动查找当前 controller 层级中最外层的 UITabBarController(从
    /// rootViewController 沿 presentedViewController 链走到头,若是 UITabBarController 即用;
    /// 否则从 topViewController 向上找最近的 UITabBarController 容器)。
    public let tabBarControllerPath: String?

    /// tab 索引(0-based),与 title 二选一。
    public let index: Int?

    /// tab 标题,与 index 二选一。
    public let title: String?

    /// 是否手动触发 delegate 回调(默认 true)。
    ///
    /// 为 true 时,在设置 selectedIndex 后补调
    /// `tabBarController.delegate?.tabBarController(_:didSelect:)`,确保业务逻辑中挂在 delegate
    /// 上的埋点/刷新/选中态同步等代码被执行。为 false 时只设值、不触发回调(等价纯
    /// `selectedIndex` 赋值)。
    public let triggerDelegate: Bool

    /// 创建 TabBar 选择输入。
    ///
    /// - Parameters:
    ///   - tabBarControllerPath: 可选的 UITabBarController 路径。
    ///   - index: tab 索引。
    ///   - title: tab 标题。
    ///   - triggerDelegate: 是否触发 delegate。
    public init(tabBarControllerPath: String?,
                index: Int?,
                title: String?,
                triggerDelegate: Bool) {
        self.tabBarControllerPath = tabBarControllerPath
        self.index = index
        self.title = title
        self.triggerDelegate = triggerDelegate
    }

    /// 输入 schema(暴露给 MCP 客户端)。
    public static let inputSchema = UIKitActionContracts.uiTabBarSelectTabInputSchema

    /// 从声明式 decoder 解析输入。
    ///
    /// - Parameter decoder: 字段读取器。
    /// - Returns: 已校验的输入模型。
    /// - Throws: 字段校验或互斥约束失败时抛出 `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UITabBarSelectInput {
        let tabBarControllerPath = try decoder.read(UIKitActionContracts.uiTabBarSelectTabTabBarControllerPathField)
        let index = try decoder.read(UIKitActionContracts.uiTabBarSelectTabIndexField)
        let title = try decoder.read(UIKitActionContracts.uiTabBarSelectTabTitleField)
        let triggerDelegate = try decoder.read(UIKitActionContracts.uiTabBarSelectTabTriggerDelegateField)

        // 手写互斥约束校验:index 与 title 必须且只能提供一个(schema constraints 只用于文档,不强制)
        let hasIndex = (index != nil)
        let hasTitle = (title != nil)
        if hasIndex == hasTitle {
            throw CommandInputParseError("index 和 title 必须且只能提供一个")
        }

        return UITabBarSelectInput(tabBarControllerPath: tabBarControllerPath,
                                   index: index,
                                   title: title,
                                   triggerDelegate: triggerDelegate)
    }
}
#endif
