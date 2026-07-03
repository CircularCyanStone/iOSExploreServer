#if canImport(UIKit)
import Testing
import UIKit
@testable import iOSExploreUIKit

/// `UIAlertAction` handler 正式触发能力的回归测试。
///
/// spike 已证明当前 iOS 26.x 可以通过关联对象和 KVC 两条路径拿到 handler。
/// 这些测试不再探测私有结构，而是约束正式 `iOSExploreUIKit` runtime 层应提供的行为：
/// 注册 UIKit 命令后创建的 action 走捕获路径；注册前或第三方提前创建的 action 仍可走 KVC 兜底。
@MainActor
@Suite("UIAlertAction handler trigger", .serialized)
struct UIAlertActionTriggerTests {
    @Test("安装捕获后创建的 action 可以触发 handler")
    func capturedHandlerCanBePerformed() throws {
        try UIAlertAction.explore_installHandlerCapture()
        var performedTitle: String?
        let action = UIAlertAction(title: "确认", style: .default) { selected in
            performedTitle = selected.title
        }

        try action.explore_performHandler()

        #expect(performedTitle == "确认")
    }

    @Test("安装捕获前创建的 action 仍可通过 KVC 兜底触发 handler")
    func existingActionCanBePerformedViaFallback() throws {
        var performedTitle: String?
        let action = UIAlertAction(title: "继续", style: .default) { selected in
            performedTitle = selected.title
        }
        try UIAlertAction.explore_installHandlerCapture()

        try action.explore_performHandler()

        #expect(performedTitle == "继续")
    }
}
#endif
