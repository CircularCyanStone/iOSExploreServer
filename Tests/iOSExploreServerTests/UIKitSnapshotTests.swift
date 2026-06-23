import Foundation
import Testing
@testable import iOSExploreUIKit

// MARK: - Snapshot store 陈旧检测测试（macOS 可编译）

/// `UIKitSnapshotStore` 与 `UIKitTargetFingerprint` 是纯计算的 Foundation-only 类型（store
/// 虽 `@MainActor` 但无 UIKit 调用），可在 macOS 测试覆盖。这组测试验证容量/TTL/LRU 与
/// query 解析，对应 brief Task 6。

@Test("超过 TTL 的 snapshot 被判定陈旧") @MainActor
func expiredSnapshotIsStale() {
    let store = UIKitSnapshotStore(now: { Date(timeIntervalSince1970: 100) })
    guard let id = store.insert(context: .test, targets: ["root/0": .test]) else {
        Issue.record("small snapshot should be stored"); return
    }
    store.setNow(Date(timeIntervalSince1970: 111))
    #expect(store.validation(snapshotID: id, path: "root/0", current: .test) == .stale)
}

@Test("超过 512 条指纹时不签发 snapshot") @MainActor
func oversizedSnapshotIsNotStored() {
    let store = UIKitSnapshotStore()
    let targets = Dictionary(uniqueKeysWithValues: (0...512).map { ("root/\($0)", UIKitTargetFingerprint.test) })
    #expect(store.insert(context: .test, targets: targets) == nil)
}

@Test("交互命令解析可选 snapshotID")
func actionQueriesParseSnapshotID() {
    #expect(UITapQuery.parse(from: ["path": "root/0", "snapshotID": "s1"]).snapshotID == "s1")
    #expect(UIControlSendActionQuery.parse(from: ["path": "root/0", "event": "touchUpInside", "snapshotID": "s1"]).snapshotID == "s1")
}
