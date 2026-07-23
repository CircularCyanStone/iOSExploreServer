#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// 查询/响应弹窗的命令。
///
/// action 为 `ui.alert.respond`。adapter 只负责解析后的日志、切到 `MainActor` 取上下文并
/// 调用同步 executor；查询逻辑（定位 alert、列出按钮）和响应逻辑（选择按钮、触发 handler、
/// 请求关闭 alert）收敛在 `UIAlertInspector`/executor。
struct AlertRespondCommand: Command {
    /// typed 输入模型。
    typealias Input = UIAlertRespondInput

    /// 固定 action 名。
    static let actionName = "ui.alert.respond"

    /// 命令名。
    let action = AlertRespondCommand.actionName

    /// `help` 命令展示的说明。
    let description = "响应当前 UIAlertController：按 buttonTitle/buttonIndex/role 触发按钮并关闭。查询 alert 结构（标题/按钮/输入框）用 ui.inspect。"

    /// 执行 alert 查询/响应。
    ///
    /// - Parameter input: 已通过 typed schema 校验的 alert respond 输入。
    /// - Returns: 成功时返回 alert 信息或已触发按钮；失败返回业务失败 envelope。
    func handle(_ input: UIAlertRespondInput) async -> ExploreResult {
        UIKitCommandLogger.info("command", "command \(action) start")
        do {
            // 第一阶段（同步）：在 MainActor 上选择按钮、触发 dismiss/handler。
            // dismiss 已启动但转场动画还没结束。同步块同时把「正在 dismiss 的那个 alert」
            // 的弱引用带出来——async 阶段用它做身份比较，避免被「handler 立即弹的新 alert」
            // 干扰（嵌套 alert 场景）。
            let (data, dismissed, dismissedAlertRef): (JSON, Bool, WeakAlertRef?) = try await MainActor.run {
                let context = try UIKitContextProvider.currentContext(action: AlertRespondCommand.actionName)
                guard let alert = UIAlertInspector.findAlert(in: context) else {
                    // execute 内部会再查一次并抛 alertUnavailable；让原逻辑接管。
                    let result = try UIAlertRespondExecutor.execute(input: input, context: context)
                    return (result, false, nil as WeakAlertRef?)
                }
                let ref = WeakAlertRef(alert)
                let result = try UIAlertRespondExecutor.execute(input: input, context: context)
                let isDismissed = result["dismissed"]?.boolValue ?? false
                return (result, isDismissed, ref)
            }

            var finalData = data
            if dismissed, let ref = dismissedAlertRef {
                // 第二阶段（async 等待）：用身份比较检查「正在 dismiss 的那个 alert」是否已从
                // presenting chain 上消失。dismiss 触发后 MainActor.run 闭包退出，调用栈释放，
                // UIKit 可推进转场动画。每个 await Task.sleep 让出 MainActor 一个 runloop
                // 周期，CADisplayLink 推进动画；动画完成后
                // presentingViewController.presentedViewController 不再 === 该 alert。
                //
                // 用身份比较（===）而非通用「链上是否有 alert」检查，是为了让 handler 内立即
                // present 的新 alert（嵌套 alert 第二步）不被误认为「dismiss 未完成」——
                // 新 alert 是不同对象，=== 立即返回 false，wait 提前退出。
                let start = ProcessInfo.processInfo.systemUptime
                var stillPresented = true
                while ProcessInfo.processInfo.systemUptime - start < 1.5 {
                    stillPresented = await MainActor.run { ref.isStillInPresentationChain() }
                    if !stillPresented { break }
                    try? await Task.sleep(nanoseconds: 8_000_000)
                }
                let elapsedMs = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
                finalData["dismissWaitMs"] = .double(Double(min(elapsedMs, 1500)))
                finalData["presentedAfterDismiss"] = .bool(stillPresented)
                UIKitCommandLogger.info("command", "ui alert respond part2 async-wait performed=true dismissed=true dismissWaitMs=\(min(elapsedMs, 1500)) presentedAfter=\(stillPresented)")
            }
            return .success(finalData)
        } catch let error as UIKitCommandError {
            UIKitCommandLogger.error("command", error.failure.logMessage)
            return error.result
        } catch {
            let wrapped = UIKitCommandError.hierarchyUnavailable(action: AlertRespondCommand.actionName, reason: "\(error)")
            UIKitCommandLogger.error("command", wrapped.failure.logMessage)
            return wrapped.result
        }
    }
}

/// 跨 actor 边界持有 `UIAlertController` 弱引用，仅用于 `===` 身份比较。
///
/// `UIViewController` 不是 `Sendable`，不能直接跨 actor 传递；但这里只持有引用做指针相等
/// 比较、不读任何属性，跨边界传引用是安全的，故标 `@unchecked Sendable`。弱引用是为了避免
/// alert 被 dismiss 后引用链断开造成内存泄漏（dismiss 完成后 alert vc 会被释放）。
private final class WeakAlertRef: @unchecked Sendable {
    private weak var alert: UIViewController?

    init(_ alert: UIViewController) {
        self.alert = alert
    }

    /// 主线程上检查「正在 dismiss 的 alert」是否还在 presenting chain 上。
    ///
    /// - Returns: alert 仍被某个 vc present 返回 true；已脱离（或已释放）返回 false。
    @MainActor
    func isStillInPresentationChain() -> Bool {
        guard let alert = alert else { return false }
        return alert.presentingViewController?.presentedViewController === alert
    }
}
#endif
