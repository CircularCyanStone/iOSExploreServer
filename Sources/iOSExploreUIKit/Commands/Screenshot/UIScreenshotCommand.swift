#if canImport(UIKit)
import Foundation
import iOSExploreServer

/// 截屏命令（`ui.screenshot`）。
///
/// adapter 只负责解析 typed input、在 `MainActor.run` 内委托给 `UIScreenshotCollector`、
/// 顶层 catch 把 `UIKitCommandError` 转 `ExploreResult` envelope。UIKit 渲染/编码逻辑全部
/// 收敛在 collector，本命令不再内联 UIKit 调用。
///
/// 截图是高耗时命令（渲染 + PNG 编码 + base64），自声明 30s 超时覆盖全局上限，避免被
/// 默认 commandTimeout 提前打断。
struct ScreenshotCommand: Command {
    /// typed 输入模型，负责 schema 暴露与 data 解析（Foundation-only）。
    typealias Input = UIScreenshotInput

    /// 固定 action 名，供注册、日志和错误工厂复用。
    static let actionName = "ui.screenshot"

    /// 命令名。
    let action = ScreenshotCommand.actionName

    /// `help` 命令展示的说明。
    ///
    /// 说明里刻意不提"签发 snapshot"：`ui.screenshot` 只是可选视觉证据，不再签发、不刷新、
    /// 不返回 `viewSnapshotID`（viewSnapshotID 唯一签发来源是 `ui.inspect`），与
    /// `UIScreenshotCollector` 的实际返回一致，避免 help schema 误导调用方。
    let description = "截屏 (PNG base64) + 降采样（可选视觉证据，不签发 viewSnapshotID）"

    /// 截图高耗时，自声明 30s 超时（覆盖全局 commandTimeout）。
    var timeoutNanoseconds: UInt64? { 30_000_000_000 }

    /// 响应 body 字节上限，由注册方注入，透传给 collector 做体积前置检查。
    private let maxResponseBodyBytes: Int

    /// 创建截屏命令。
    ///
    /// - Parameter maxResponseBodyBytes: 响应 body 字节上限，base64 估算超限即返回 `responseTooLarge`。
    init(maxResponseBodyBytes: Int) {
        self.maxResponseBodyBytes = maxResponseBodyBytes
    }

    /// 执行截屏。
    ///
    /// `UIKitContextProvider` 与 collector 均 `@MainActor`，必须在 `MainActor.run` 内调用；
    /// 返回值为纯 `JSON`（不含 UIKit 对象），可安全跨 actor。
    ///
    /// - Parameter input: 已通过 typed schema 校验的截图参数。
    /// - Returns: 成功时返回 base64 图像与像素尺寸；失败时返回明确原因 envelope。
    func handle(_ input: UIScreenshotInput) async -> ExploreResult {
        UIKitCommandLogger.info("command", "command \(action) start maxDimension=\(input.maxDimension)")
        do {
            let data = try await MainActor.run {
                try UIScreenshotCollector.collect(input: input, maxResponseBodyBytes: maxResponseBodyBytes)
            }
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogger.error("command", error.failure.logMessage)
            return error.result
        } catch {
            let wrapped = UIKitCommandError.renderingFailed(action: action, reason: "\(error)")
            UIKitCommandLogger.error("command", wrapped.failure.logMessage)
            return wrapped.result
        }
    }
}
#endif
