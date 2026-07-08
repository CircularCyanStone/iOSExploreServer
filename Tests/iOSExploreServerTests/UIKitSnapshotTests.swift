import Foundation
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Snapshot store 陈旧检测测试（macOS 可编译）

/// `UIKitSnapshotStore` 与 `UIKitTargetFingerprint` 是纯计算的 Foundation-only 类型（store
/// 虽 `@MainActor` 但无 UIKit 调用），可在 macOS 测试覆盖。这组测试验证容量/TTL/LRU 与
/// viewSnapshotID 陈旧检测。

@Test("snapshot TTL=30s：25s 仍有效，35s 过期") @MainActor
func snapshotTTL30sBoundary() {
    // spec §3.6：TTL 30s 匹配 LLM 推理节奏。25s 不应过期、35s 必须过期。
    let store = UIKitSnapshotStore(now: { Date(timeIntervalSince1970: 100) })
    guard let id = store.insert(context: .test, targets: ["root/0": .test], query: .default) else {
        Issue.record("small snapshot should be stored"); return
    }
    // 25s：仍在 TTL 窗口内，指纹匹配 → 非陈旧
    store.setNow(Date(timeIntervalSince1970: 125))
    #expect(store.isStale(viewSnapshotID: id, path: "root/0", current: .test) == false)

    // 35s：超过 30s TTL → 陈旧
    store.setNow(Date(timeIntervalSince1970: 135))
    #expect(store.isStale(viewSnapshotID: id, path: "root/0", current: .test))
}

@Test("超过 TTL 的 snapshot 被判定陈旧") @MainActor
func expiredSnapshotIsStale() {
    let store = UIKitSnapshotStore(now: { Date(timeIntervalSince1970: 100) })
    guard let id = store.insert(context: .test, targets: ["root/0": .test], query: .default) else {
        Issue.record("small snapshot should be stored"); return
    }
    store.setNow(Date(timeIntervalSince1970: 131))
    #expect(store.isStale(viewSnapshotID: id, path: "root/0", current: .test))
}

@Test("超过 512 条指纹时不签发 snapshot") @MainActor
func oversizedSnapshotIsNotStored() {
    let store = UIKitSnapshotStore()
    let targets = Dictionary(uniqueKeysWithValues: (0...512).map { ("root/\($0)", UIKitTargetFingerprint.test) })
    #expect(store.insert(context: .test, targets: targets, query: .default) == nil)
}

@Test("snapshot context 或祖先摘要变化必须判定陈旧") @MainActor
func snapshotRejectsChangedContextOrAncestorDigest() {
    let store = UIKitSnapshotStore()
    let context = UIKitSnapshotContext(windowIdentity: "window-A", topViewControllerIdentity: "controller-A")
    let original = UIKitTargetFingerprint(contextDigest: "SettingsViewController",
                                          path: "root/0",
                                          viewType: "UIButton",
                                          identifierHash: UIKitTargetFingerprint.stableHash("settings.save"),
                                          isEnabled: true,
                                          isSelected: false,
                                          ancestorDigest: 10)
    guard let id = store.insert(context: context, targets: [original.path: original], query: .default) else {
        Issue.record("small snapshot should be stored")
        return
    }

    #expect(store.isStale(viewSnapshotID: id,
                          path: original.path,
                          context: UIKitSnapshotContext(windowIdentity: "window-B", topViewControllerIdentity: "controller-A"),
                          current: original))

    let changedAncestor = UIKitTargetFingerprint(contextDigest: original.contextDigest,
                                                 path: original.path,
                                                 viewType: original.viewType,
                                                 identifierHash: original.identifierHash,
                                                 isEnabled: original.isEnabled,
                                                 isSelected: original.isSelected,
                                                 ancestorDigest: 11)
    #expect(store.isStale(viewSnapshotID: id,
                          path: original.path,
                          context: context,
                          current: changedAncestor))
}

@Test("semanticDigest 变化必须判定陈旧") @MainActor
func snapshotRejectsChangedSemanticDigest() {
    let store = UIKitSnapshotStore()
    let context = UIKitSnapshotContext.test
    let original = UIKitTargetFingerprint(contextDigest: "VC",
                                          path: "root/0",
                                          viewType: "UIButton",
                                          identifierHash: 0,
                                          isEnabled: true,
                                          isSelected: false,
                                          semanticDigest: 100)
    guard let id = store.insert(context: context, targets: [original.path: original], query: .default) else {
        Issue.record("small snapshot should be stored")
        return
    }
    // path/类型/context 都没变，仅 semanticDigest 变化（按钮标题从「提交」变「删除」的等价）→ 陈旧。
    let changedSemantic = UIKitTargetFingerprint(contextDigest: original.contextDigest,
                                                 path: original.path,
                                                 viewType: original.viewType,
                                                 identifierHash: original.identifierHash,
                                                 isEnabled: original.isEnabled,
                                                 isSelected: original.isSelected,
                                                 semanticDigest: 999)
    #expect(store.isStale(viewSnapshotID: id,
                          path: original.path,
                          context: context,
                          current: changedSemantic))
}

#if !canImport(UIKit)
@Test("未知 viewSnapshotID 必须被判定为陈旧") @MainActor
func unknownSnapshotIsStale() {
    let store = UIKitSnapshotStore()
    #expect(store.isStale(viewSnapshotID: "evicted-snapshot",
                          path: "root/0",
                          current: .test))
}
#endif

@Test("交互命令解析必填 viewSnapshotID")
func actionQueriesParseViewSnapshotID() throws {
    #expect(try UITapInput.parse(from: ["path": "root/0", "viewSnapshotID": "vs1"]).viewSnapshotID == "vs1")
    #expect(try UIControlSendActionInput.parse(from: ["path": "root/0", "event": "touchUpInside", "viewSnapshotID": "vs1"]).viewSnapshotID == "vs1")
}

@Test("snapshot 签发成功映射 viewSnapshotID 字段且原因为 null")
func snapshotResponseFieldsForIssuedID() {
    let fields = UIKitSnapshotResponse.fields(for: "snap-1")
    #expect(fields.id == .string("snap-1"))
    #expect(fields.unavailableReason == .null)
}

@Test("snapshot 超限未签发时原因为 fingerprintLimit")
func snapshotResponseFieldsForOverLimit() {
    let fields = UIKitSnapshotResponse.fields(for: nil)
    #expect(fields.id == .null)
    #expect(fields.unavailableReason == .string(UIKitSnapshotResponse.fingerprintLimitReason))
}

// MARK: - isPathSigned 三态查询测试（Task 5）
//
// `isPathSigned` 用于区分 not_actionable 与 stale_locator：executor 收到交互命令携带的
// viewSnapshotID 时，先用它判断 path 是否在快照指纹表内，再决定错误码语义。
// 三态：unknown/expired id → true（交 isStale 裁决 stale_locator）；有效 id 但 path 缺失 →
// false（minimal 结构节点，返回 not_actionable）。

@Test("isPathSigned: id 有效且 path 在指纹表 → true") @MainActor
func isPathSignedTrueForSignedPath() {
    let store = UIKitSnapshotStore(now: { Date(timeIntervalSince1970: 100) })
    guard let id = store.insert(context: .test, targets: ["root/1": .test], query: .default) else {
        Issue.record("small snapshot should be stored"); return
    }
    #expect(store.isPathSigned(viewSnapshotID: id, path: "root/1") == true)
}

@Test("isPathSigned: id 有效但 path 不在指纹表 → false（not_actionable 判据）") @MainActor
func isPathSignedFalseForUnsignedPath() {
    let store = UIKitSnapshotStore(now: { Date(timeIntervalSince1970: 100) })
    guard let id = store.insert(context: .test, targets: ["root/1": .test], query: .default) else {
        Issue.record("small snapshot should be stored"); return
    }
    // root/9 是 minimal 结构节点，未签发指纹 → executor 应返回 not_actionable
    #expect(store.isPathSigned(viewSnapshotID: id, path: "root/9") == false)
}

@Test("isPathSigned: unknown id → true（交 isStale 裁决，不误报 not_actionable）") @MainActor
func isPathSignedTrueForUnknownSnapshotID() {
    let store = UIKitSnapshotStore(now: { Date(timeIntervalSince1970: 100) })
    // entries 无该 id → 视为「可能签发过」，交 isStale 裁决 stale_locator
    #expect(store.isPathSigned(viewSnapshotID: "snap-nonexistent", path: "root/1") == true)
}

@Test("isPathSigned: 过期 id（超 TTL）→ true（交 isStale 裁决）") @MainActor
func isPathSignedTrueForExpiredSnapshotID() {
    let store = UIKitSnapshotStore(now: { Date(timeIntervalSince1970: 100) })
    guard let id = store.insert(context: .test, targets: ["root/1": .test], query: .default) else {
        Issue.record("small snapshot should be stored"); return
    }
    // 推进时间超过 30s TTL → id 失效，视为「可能签发过」
    store.setNow(Date(timeIntervalSince1970: 131))
    #expect(store.isPathSigned(viewSnapshotID: id, path: "root/1") == true)
}

#if canImport(UIKit)
// MARK: - semanticDigest 语义变化测试（Task 5，需 UIKit）

@Test("隐藏状态变化必须使目标指纹失效") @MainActor
func hiddenStateChangesFingerprint() {
    let button = UIButton(type: .system)
    button.accessibilityIdentifier = "settings.save"
    let visible = UIKitFingerprintCollector.fingerprint(for: button,
                                                        path: "root/0",
                                                        rootView: button,
                                                        digest: "SettingsViewController")
    button.isHidden = true
    let hidden = UIKitFingerprintCollector.fingerprint(for: button,
                                                       path: "root/0",
                                                       rootView: button,
                                                       digest: "SettingsViewController")
    #expect(visible != hidden)
}

@Test("按钮标题变化使 semanticDigest 变化") @MainActor
func semanticDigestChangesWhenButtonTitleChanges() {
    let button = UIButton(type: .system)
    button.setTitle("提交", for: .normal)
    let d1 = UIKitFingerprintCollector.fingerprint(for: button, path: "root/0", rootView: button, digest: "VC").semanticDigest
    button.setTitle("删除", for: .normal)
    let d2 = UIKitFingerprintCollector.fingerprint(for: button, path: "root/0", rootView: button, digest: "VC").semanticDigest
    #expect(d1 != d2)
}

@Test("accessibilityLabel 变化使 semanticDigest 变化") @MainActor
func semanticDigestChangesWhenAccessibilityLabelChanges() {
    let button = UIButton(type: .system)
    button.accessibilityLabel = "保存"
    let d1 = UIKitFingerprintCollector.fingerprint(for: button, path: "root/0", rootView: button, digest: "VC").semanticDigest
    button.accessibilityLabel = "确认"
    let d2 = UIKitFingerprintCollector.fingerprint(for: button, path: "root/0", rootView: button, digest: "VC").semanticDigest
    #expect(d1 != d2)
}

@Test("UISwitch isOn 变化使 semanticDigest 变化") @MainActor
func semanticDigestChangesWhenSwitchValueChanges() {
    let toggle = UISwitch()
    toggle.isOn = false
    let d1 = UIKitFingerprintCollector.fingerprint(for: toggle, path: "root/0", rootView: toggle, digest: "VC").semanticDigest
    toggle.isOn = true
    let d2 = UIKitFingerprintCollector.fingerprint(for: toggle, path: "root/0", rootView: toggle, digest: "VC").semanticDigest
    #expect(d1 != d2)
}

@Test("UISegmentedControl 选择变化使 semanticDigest 变化") @MainActor
func semanticDigestChangesWhenSegmentedSelectionChanges() {
    let segmented = UISegmentedControl(items: ["一", "二"])
    segmented.selectedSegmentIndex = 0
    let d1 = UIKitFingerprintCollector.fingerprint(for: segmented, path: "root/0", rootView: segmented, digest: "VC").semanticDigest
    segmented.selectedSegmentIndex = 1
    let d2 = UIKitFingerprintCollector.fingerprint(for: segmented, path: "root/0", rootView: segmented, digest: "VC").semanticDigest
    #expect(d1 != d2)
}

@Test("相同语义重复采集 semanticDigest 稳定") @MainActor
func semanticDigestIsStableForSameSemantics() {
    let button = UIButton(type: .system)
    button.setTitle("提交", for: .normal)
    button.accessibilityIdentifier = "submit"
    let d1 = UIKitFingerprintCollector.fingerprint(for: button, path: "root/0", rootView: button, digest: "VC").semanticDigest
    let d2 = UIKitFingerprintCollector.fingerprint(for: button, path: "root/0", rootView: button, digest: "VC").semanticDigest
    #expect(d1 == d2)
}
#endif
