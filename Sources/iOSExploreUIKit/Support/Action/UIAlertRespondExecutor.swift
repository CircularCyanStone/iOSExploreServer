#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.alert.respond` 的执行核心。
///
/// 在 `MainActor` 上 query-first：定位当前 `UIAlertController` → 返回标题/消息/按钮列表。
/// 第一版 `dryRun=false` 不直接点击 `UIAlertAction`——其内部点击依赖 UIKit 私有路径，
/// 在 logic test 与真机上稳定性未经 spike 验证，统一抛 `alertButtonRequired` 提示调用方
/// 先用 `dryRun=true` 查询按钮、再决定后续处理。失败由 command adapter 顶层 catch 转 envelope。
@MainActor
enum UIAlertRespondExecutor {
    /// 执行一次 alert 查询/响应。
    ///
    /// - Parameters:
    ///   - input: 已通过 typed schema 校验的 alert respond 参数。
    ///   - context: 当前 MainActor 查询上下文。
    /// - Returns: dryRun=true 时返回 dryRun/title/message/buttons；dryRun=false 不返回（抛错）。
    /// - Throws: `UIKitCommandError.alertUnavailable`——无 alert；`.alertButtonRequired`——dryRun=false（点击未实现）。
    static func execute(input: UIAlertRespondInput, context: UIKitContextProvider.Context) throws -> JSON {
        let action = AlertRespondCommand.actionName
        guard let alert = UIAlertInspector.findAlert(in: context) else {
            throw UIKitCommandError.alertUnavailable(action: action)
        }

        if !input.dryRun {
            // 第一版不直接点击（spike 未验证）；提示调用方用 dryRun 查询。
            throw UIKitCommandError.alertButtonRequired(action: action)
        }

        let summary = UIAlertInspector.summarize(alert)
        UIKitCommandLogging.info("command", "ui alert respond complete dryRun=true buttons=\(summary.buttons.count)")
        return [
            "dryRun": .bool(true),
            "title": summary.title.map(JSONValue.string) ?? .null,
            "message": summary.message.map(JSONValue.string) ?? .null,
            "buttons": .array(summary.buttons.map { buttonJSON($0) }),
        ]
    }

    /// 构造单个按钮的 JSON 值。
    private static func buttonJSON(_ button: UIAlertInspector.Button) -> JSONValue {
        .object(JSON([
            "index": .double(Double(button.index)),
            "title": button.title.map(JSONValue.string) ?? .null,
            "role": .string(button.role.rawValue),
        ]))
    }
}
#endif
