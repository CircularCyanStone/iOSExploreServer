import Foundation
import iOSExploreServer

/// snapshot 签发结果到响应字段的统一映射。
///
/// `ui.viewTargets` 与 `ui.topViewHierarchy` 两个查询命令都要把 `UIKitSnapshotStore.insert`
/// 的结果回写响应。本类型把"成功签发 / 超过指纹上限未签发"两种情况映射成统一的两个字段，
/// 避免两个 collector 各写一份导致响应 schema 漂移：超限未签发时显式给出
/// `snapshotUnavailableReason = "fingerprintLimit"`，让调用方明确该轮陈旧校验不可用，而非
/// 悄悄返回空 snapshotID 后静默降级。
///
/// 该类型是 Foundation-only 值类型（仅依赖 core 的 `JSONValue`），可在 macOS `swift test`
/// 覆盖字段映射契约。
enum UIKitSnapshotResponse {
    /// 指纹超限导致 snapshot 未签发时，写入 `snapshotUnavailableReason` 的固定文案。
    static let fingerprintLimitReason = "fingerprintLimit"

    /// 把签发结果映射为响应中 `snapshotID` 与 `snapshotUnavailableReason` 两个字段值。
    ///
    /// - Parameter snapshotID: `UIKitSnapshotStore.insert` 返回的 snapshotID；`nil` 表示超过指纹
    ///   上限未签发。
    /// - Returns: (snapshotID 字段值, 不可用原因字段值)。
    static func fields(for snapshotID: String?) -> (id: JSONValue, unavailableReason: JSONValue) {
        if let snapshotID {
            return (.string(snapshotID), .null)
        }
        return (.null, .string(fingerprintLimitReason))
    }
}
