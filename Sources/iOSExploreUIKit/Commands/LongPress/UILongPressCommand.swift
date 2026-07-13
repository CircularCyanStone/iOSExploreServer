#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// 在 view 上执行长按操作的命令。
///
/// action 为 `ui.longPress`。触发 `UILongPressGestureRecognizer`，支持：
/// - Context Menu（上下文菜单）
/// - 长按拖拽排序
/// - 3D Touch / Haptic Touch 预览
///
/// adapter 只负责切到 MainActor 取上下文并调用 async executor，失败由 executor 顶层抛出的
/// `UIKitCommandError` 在此 catch 并转为业务 envelope。executor 内部长按等待用 `await Task.sleep`
/// yield MainActor，因此并发到达的其它 `ui.*` 命令能插队执行，不会被 longPress 的 duration 阻塞。
struct LongPressCommand: Command {
    /// typed 输入模型，负责 schema 暴露和 data 解析。
    typealias Input = UILongPressInput

    /// 固定 action 名。
    static let actionName = "ui.longPress"

    /// 命令名。
    let action = LongPressCommand.actionName

    /// `help` 命令展示的说明。
    let description = "在 view 上触发长按手势(UILongPressGestureRecognizer), 用于触发 context menu、长按拖拽等"

    /// 执行长按操作。
    ///
    /// 通过 `@MainActor` 方法 `executeOnMainActor(input:)` hop 到 MainActor 并调用 async executor。
    /// 不用 `MainActor.run { async body }`：Xcode 工程的编译器在 sync/async body 两个重载之间
    /// 歧义选中 sync 重载导致编译失败。独立 `@MainActor async throws` 方法功能等价——`handle`
    /// 里 `await executeOnMainActor(...)` hop 到 MainActor，方法内部的 `await Task.sleep` 挂起时
    /// yield MainActor，让并发到达的其它 `ui.*` 命令插队执行。executor 抛出的 `UIKitCommandError`
    /// 在此 catch。
    ///
    /// - Parameter input: 已通过 typed schema 校验的 longPress 输入。
    /// - Returns: 成功时返回长按结果；失败时返回业务失败 envelope。
    func handle(_ input: UILongPressInput) async -> ExploreResult {
        let durationDescription = input.duration.map { String(format: "%.2f", $0) } ?? "default"
        UIKitCommandLogging.info("command", "command \(action) start duration=\(durationDescription) target=\(input.locator?.logSummary ?? "keyWindow")")
        do {
            let data = try await executeOnMainActor(input: input)
            UIKitCommandLogging.info("command", "command \(action) completed path=\(data["path"]?.stringValue ?? "nil") route=\(data["route"]?.stringValue ?? "unknown")")
            return .success(data)
        } catch let error as UIKitCommandError {
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        } catch {
            let wrapped = UIKitCommandError.hierarchyUnavailable(action: LongPressCommand.actionName, reason: "\(error)")
            UIKitCommandLogging.error("command", wrapped.failure.logMessage)
            return wrapped.result
        }
    }

    /// 在 MainActor 上取上下文并执行 longPress executor。
    ///
    /// 独立 `@MainActor async throws` 方法：`handle`（非隔离）里 `await` 调用时自动 hop 到
    /// MainActor。executor 内部的 `await Task.sleep` 挂起时会 yield MainActor（让出 actor），
    /// 使并发到达的其它 `ui.*` 命令能插队执行，不被 longPress 的 duration 同步阻塞。
    ///
    /// - Parameter input: 已通过 typed schema 校验的 longPress 输入。
    /// - Returns: 长按结果 JSON。
    /// - Throws: 定位/陈旧等 `UIKitCommandError`，以及 `Task.sleep` 的 `CancellationError`。
    @MainActor
    private func executeOnMainActor(input: UILongPressInput) async throws -> JSON {
        let context = try UIKitContextProvider.currentContext(action: LongPressCommand.actionName)
        return try await UILongPressExecutor.execute(input: input, context: context)
    }
}
#endif
