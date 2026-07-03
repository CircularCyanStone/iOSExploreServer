import Foundation
import iOSExploreServer

/// snapshot 签发结果到响应字段的统一映射。
///
/// `ui.viewTargets` 查询命令把 `UIKitSnapshotStore.insert` 的结果回写响应。本类型把
/// "成功签发 / 超过指纹上限未签发"两种情况映射成统一的两段值，由 collector 赋给响应字段
/// （`viewSnapshotID` / `viewSnapshotUnavailableReason`），避免漂移：超限未签发时显式给出
/// `viewSnapshotUnavailableReason = "fingerprintLimit"`，让调用方明确该轮陈旧校验不可用，
/// 而非悄悄返回空 viewSnapshotID 后静默降级。
///
/// **只有 `ui.viewTargets` 使用本映射**：它是唯一签发 `viewSnapshotID` 的命令。`ui.screenshot`
/// 不签发、不返回 viewSnapshotID。
///
/// 该类型是 Foundation-only 值类型（仅依赖 core 的 `JSONValue`），可在 macOS `swift test`
/// 覆盖字段映射契约。
enum UIKitSnapshotResponse {
    /// 指纹超限导致 snapshot 未签发时，写入 `viewSnapshotUnavailableReason` 的固定文案。
    static let fingerprintLimitReason = "fingerprintLimit"

    /// 把签发结果映射为响应字段值。
    ///
    /// - Parameter viewSnapshotID: `UIKitSnapshotStore.insert` 返回的 viewSnapshotID；`nil` 表示
    ///   超过指纹上限未签发。
    /// - Returns: (viewSnapshotID 字段值, 不可用原因字段值)。
    static func fields(for viewSnapshotID: String?) -> (id: JSONValue, unavailableReason: JSONValue) {
        if let viewSnapshotID {
            return (.string(viewSnapshotID), .null)
        }
        return (.null, .string(fingerprintLimitReason))
    }
}
