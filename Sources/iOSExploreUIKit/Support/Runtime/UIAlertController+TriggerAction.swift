#if DEBUG
#if canImport(UIKit)
import Foundation
import ObjectiveC
import UIKit

/// `UIAlertController` action 触发入口。
///
/// 公开 API 没有「触发某个 `UIAlertAction`」的方法，但 Debug 探索工具需要让 `ui.alert.respond`
/// 在不模拟真实手指点击的情况下响应弹窗按钮。本扩展把「调用系统私有 `_dismissWithAction:` 入口」
/// 封装在 `UIAlertController` 自己身上；命令 executor 只表达「让系统触发并关闭这个 action」，不
/// 直接接触私有 selector。
extension UIAlertController {
    /// 让 UIKit 像真人点按钮一样触发指定 action：系统自动 dismiss 当前 alert 并调用该 action 的 handler。
    ///
    /// 走私有方法 `_dismissWithAction:`——系统点击 alert 按钮时的内部入口之一，由系统本身同时完成
    ///「dismiss 当前 alert」与「调用该 action 的 handler」。这样 executor 不手动 dismiss，也就不会
    /// 出现「手动 dismiss 与 handler 内 present 新 alert 抢转场」的嵌套冲突；dismiss、handler、嵌套
    /// present 全交给 UIKit 在同一套点击流程里协调，与真人点按钮一致。simple / 三按钮 / 输入框 /
    /// actionSheet / 嵌套（第二层可正常弹出并响应）五个案例已实测全部通过。
    ///
    /// 该方法要求 alert 已在控制器层级中 present（用 `perform(_:with:)` 调用，单参数、不会 crash）；
    /// 未 present 的 alert（典型是 logic test 构造的对象）请改用 `UIAlertAction.explore_performHandler()`
    /// 直接调用 handler block。
    ///
    /// 备选方案及放弃原因：私有 `_performAction:invokeActionBlock:dismissAndPerformActionIfNotAlreadyPerformed:`
    /// 用 IMP 直接调用会 crash（多 BOOL 参数 ABI/内部断言）；`sendActions(for:.touchUpInside)`
    /// 对 `_UIAlertControllerActionView` 也无效——该类型是 `UIView` 子类、非 `UIControl`，
    /// `sendActions(for:)` 只对 UIControl 生效，对 UIView 调用无任何反应。
    /// 虽然 iOS 26 上从 `alertVC.view` 走公开 `subviews` DFS 可正常抵达按钮 view（深度约 9-11），
    /// 但抵达后的触发仍需私有 API，故仍用 `_dismissWithAction:` 统一处理。
    /// 这是三者里唯一在真实 App 验证可行的入口。selector 名随
    /// iOS 版本漂移属正常维护成本，失效时需重新枚举 `UIAlertController` 方法表并降级。
    ///
    /// - Parameter action: 要触发并关闭的 action，必须是 `self.actions` 中的某个。
    /// - Throws: 当前 iOS 版本找不到该私有 selector 时抛 `ExploreActionDismissFailure.methodUnavailable`。
    func explore_dismissWithAction(_ action: UIAlertAction) throws {
        let selector = NSSelectorFromString("_dismissWithAction:")
        guard responds(to: selector) else {
            throw ExploreActionDismissFailure.methodUnavailable
        }
        perform(selector, with: action)
        UIKitCommandLogger.info("command",
            "ui alert dismissed with action via system entry title=\(action.title ?? "nil")")
    }
}

/// `UIAlertController.explore_dismissWithAction` 的失败原因。
///
/// 只用于 Debug 工具内部日志和错误码包装；命令层会转成稳定的业务错误码
/// `alert_button_trigger_failed`，不对外暴露 Objective-C runtime 细节。
enum ExploreActionDismissFailure: Error, CustomStringConvertible {
    /// 当前 iOS 版本缺少私有 selector `_dismissWithAction:`，需重新枚举系统内部入口名。
    case methodUnavailable

    var description: String {
        switch self {
        case .methodUnavailable:
            return "ui alert dismissWithAction system entry unavailable on this iOS version"
        }
    }
}
#endif
#endif
