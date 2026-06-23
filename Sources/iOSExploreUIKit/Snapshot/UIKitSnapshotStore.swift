import Foundation

// MARK: - UIKitTargetFingerprint

/// UIKit 目标的轻量指纹。
///
/// 陈旧检测的关键值类型：只保存"判断两次调用间的同一 path 是否仍指向同一 view"所需的
/// 最少信息——context 类型摘要、path、view 类型名、identifier 的**稳定哈希**、role、基础
/// 状态布尔。**绝不保存** `UIView`、文本内容或完整 identifier，因此：
///
/// - 不泄露用户输入全文或大块 payload（只存哈希/摘要）；
/// - 哈希自实现（FNV-1a），跨进程稳定，**不使用** `Hashable.hashValue`（后者每次运行随机）；
/// - 保持 Foundation-only、`Sendable`、`Equatable`，可在 macOS 测试覆盖。
///
/// executor 在交互命令携带 snapshotID 时，会把当前 view 树重新采集的指纹与 store 中保存
/// 的指纹逐字段比对，任一字段不同即判定陈旧（`.stale`），避免 path 指向错误 view 导致误操作。
public struct UIKitTargetFingerprint: Sendable, Equatable {
    /// context 类型摘要（如顶部控制器类型名），用于检测页面整体是否切换。
    public let contextDigest: String
    /// 目标 path（`root/0/2`），指纹归属的键。
    public let path: String
    /// view 类型名（`String(describing: type(of:))`），不持引用。
    public let viewType: String
    /// accessibilityIdentifier 的稳定哈希；无 identifier 时为 0。
    public let identifierHash: UInt64
    /// 目标角色（button/switch/...），用于检测结构变化。
    public let role: String
    /// 控件是否可用（UIControl.isEnabled，非控件视为 true）。
    public let isEnabled: Bool
    /// 控件是否选中（UIControl.isSelected，非控件视为 false）。
    public let isSelected: Bool

    /// 创建一个目标指纹。
    ///
    /// - Parameters:
    ///   - contextDigest: context 类型摘要。
    ///   - path: 目标 path。
    ///   - viewType: view 类型名。
    ///   - identifierHash: identifier 的稳定哈希（调用方负责用 `stableHash` 计算）。
    ///   - role: 目标角色。
    ///   - isEnabled: 是否可用。
    ///   - isSelected: 是否选中。
    public init(contextDigest: String,
                path: String,
                viewType: String,
                identifierHash: UInt64,
                role: String,
                isEnabled: Bool,
                isSelected: Bool) {
        self.contextDigest = contextDigest
        self.path = path
        self.viewType = viewType
        self.identifierHash = identifierHash
        self.role = role
        self.isEnabled = isEnabled
        self.isSelected = isSelected
    }

    /// 仅供测试的固定指纹 fixture。
    ///
    /// 所有字段取稳定占位值，使 snapshot store 的 macOS 测试不依赖 UIKit。测试推进时间即可
    /// 触发 TTL 过期，无需构造真实 view。
    public static let test = UIKitTargetFingerprint(contextDigest: "test-context",
                                                    path: "root/0",
                                                    viewType: "TestView",
                                                    identifierHash: Self.stableHash("test-id"),
                                                    role: "button",
                                                    isEnabled: true,
                                                    isSelected: false)

    /// 字符串的稳定哈希（FNV-1a，64 位）。
    ///
    /// - Parameter value: 待哈希的字符串（如 identifier）。
    /// - Returns: 跨进程稳定的 64 位哈希；空串返回 0。
    public static func stableHash(_ value: String) -> UInt64 {
        guard !value.isEmpty else { return 0 }
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }
}

// MARK: - UIKitSnapshotContext

/// snapshot 所属的查询上下文摘要。
///
/// 仅保存"判断页面是否切换"所需的稳定信息：顶部控制器类型摘要。它配合每个 target 的
/// `contextDigest` 字段，使一次查询签发的所有指纹共享同一页面身份。
public struct UIKitSnapshotContext: Sendable, Equatable {
    /// 顶部控制器类型摘要（类型名等稳定标识）。
    public let digest: String

    /// 创建一个上下文摘要。
    ///
    /// - Parameter digest: 顶部控制器类型摘要。
    public init(digest: String) {
        self.digest = digest
    }

    /// 仅供测试的固定上下文 fixture。
    public static let test = UIKitSnapshotContext(digest: "test-context")
}

// MARK: - UIKitSnapshotStore

/// UIKit 视图树指纹快照存储。
///
/// 解决"path 陈旧"问题：`ui.viewTargets`/`ui.topViewHierarchy` 查询时对当前 view 树生成
/// 轻量指纹并签发一个 snapshotID 返回给调用方；交互命令（tap/control.sendAction）携带该
/// snapshotID 时，executor 在执行前校验对应 path 的指纹是否仍匹配，不匹配则返回
/// `invalid_data`（"locator is stale; re-query"），避免页面变化后 path 指向错误 view 造成误操作。
///
/// 容量与淘汰策略：
/// - 最多 **8 条**快照（不同 snapshotID）；
/// - 每条快照最多 **512** 条指纹（path→fingerprint）；超过 512 不签发（返回 nil）；
/// - **TTL 10 秒**：查询时先清过期，再按 LRU 淘汰至容量上限。
///
/// 该类型是 `@MainActor`：与 UIKit collector/executor 同一隔离域，避免并发读写。但其内部逻辑
/// 是纯计算（无 UIKit 调用），所以 **macOS 下可测**（测试函数标 `@MainActor`）。时间通过注入
/// 的 `now` 控制，提供 `setNow` 便于测试推进时间触发 TTL。
///
/// 日志点：签发（含指纹数/是否超限）、淘汰（先过期后 LRU）、校验命中/陈旧/未知 snapshotID，
/// 均只记录数量与摘要，不写完整 identifier。
@MainActor
public final class UIKitSnapshotStore {
    /// 快照最大条数。
    static let maxSnapshots = 8
    /// 单条快照最大指纹数；超过则不签发。
    static let maxFingerprints = 512
    /// 快照存活秒数。
    static let ttlSeconds: TimeInterval = 10

    /// 单条快照记录。
    private struct Entry {
        /// 签发时间（用于 TTL 判断）。
        let createdAt: Date
        /// 最近访问时间（用于 LRU 判断）。
        var lastAccessedAt: Date
        /// 该快照的指纹表（path → fingerprint）。
        var fingerprints: [String: UIKitTargetFingerprint]
    }

    /// snapshotID → 快照记录。
    private var entries: [String: Entry] = [:]
    /// 当前时间提供者，测试可注入。
    private var now: () -> Date
    /// 自增计数器，保证 snapshotID 唯一。
    private var counter = 0

    /// 进程内共享的单一 store 实例。
    ///
    /// collector 签发与 executor 校验必须走同一个实例，否则指纹无法关联。该实例与 UIKit
    /// 命令同处 `MainActor` 隔离域，无需额外同步。
    static let shared = UIKitSnapshotStore()

    /// 创建一个 snapshot store。
    ///
    /// - Parameter now: 当前时间提供者；测试可注入固定/可控时间。默认取系统时间。
    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// 推进 store 的当前时间，仅用于测试触发 TTL。
    ///
    /// - Parameter date: 新的当前时间。
    public func setNow(_ date: Date) {
        now = { date }
    }

    /// 签发一条快照。
    ///
    /// 当指纹数超过 512 时不签发（返回 nil）：collector 仍正常返回采集数据，但响应中的
    /// `snapshotID` 为 JSON null，调用方该轮不带 snapshotID 执行（不阻断功能）。
    ///
    /// - Parameters:
    ///   - context: 查询上下文摘要。
    ///   - targets: path → 指纹表。
    /// - Returns: 签发的 snapshotID；超过上限时返回 nil。
    @discardableResult
    public func insert(context: UIKitSnapshotContext,
                       targets: [String: UIKitTargetFingerprint]) -> String? {
        if targets.count > Self.maxFingerprints {
            UIKitCommandLogging.info("command", "ui snapshot skipped oversized fingerprints=\(targets.count) max=\(Self.maxFingerprints)")
            return nil
        }
        evictIfNeeded()
        counter += 1
        let id = "snap-\(counter)"
        let stamp = now()
        entries[id] = Entry(createdAt: stamp,
                            lastAccessedAt: stamp,
                            fingerprints: targets)
        UIKitCommandLogging.info("command", "ui snapshot insert id=\(id) fingerprints=\(targets.count) digest=\(context.digest)")
        return id
    }

    /// 校验某 path 在某 snapshotID 下是否仍与当前指纹一致。
    ///
    /// - Parameters:
    ///   - snapshotID: 调用方携带的快照标识。
    ///   - path: 要交互的目标 path。
    ///   - current: 当前重新采集的该 path 指纹。
    /// - Returns:
    ///   - `.valid`：snapshot 存在、未过期且指纹一致；
    ///   - `.stale`：TTL 过期或指纹不匹配（需重新查询）；
    ///   - `.unknown`：snapshotID 不存在（不应阻断交互，仅记录）。
    public func validation(snapshotID: String,
                           path: String,
                           current: UIKitTargetFingerprint) -> UIKitSnapshotValidation {
        guard var entry = entries[snapshotID] else {
            UIKitCommandLogging.info("command", "ui snapshot unknown id=\(snapshotID) path=\(path)")
            return .unknown
        }
        if isExpired(entry: entry) {
            entries.removeValue(forKey: snapshotID)
            UIKitCommandLogging.info("command", "ui snapshot expired id=\(snapshotID) path=\(path)")
            return .stale
        }
        entry.lastAccessedAt = now()
        entries[snapshotID] = entry
        guard let stored = entry.fingerprints[path] else {
            UIKitCommandLogging.info("command", "ui snapshot path missing id=\(snapshotID) path=\(path)")
            return .stale
        }
        if stored == current {
            return .valid
        }
        UIKitCommandLogging.info("command", "ui snapshot fingerprint mismatch id=\(snapshotID) path=\(path)")
        return .stale
    }

    /// 判断快照是否超过 TTL。
    private func isExpired(entry: Entry) -> Bool {
        now().timeIntervalSince(entry.createdAt) > Self.ttlSeconds
    }

    /// 淘汰至容量上限：先清过期，再按 LRU（最久未访问）逐出。
    private func evictIfNeeded() {
        if entries.count < Self.maxSnapshots { return }
        let stamp = now()
        for (id, entry) in entries where isExpired(entry: entry) {
            entries.removeValue(forKey: id)
        }
        while entries.count >= Self.maxSnapshots {
            guard let lru = entries.min(by: { $0.value.lastAccessedAt < $1.value.lastAccessedAt }) else {
                break
            }
            entries.removeValue(forKey: lru.key)
            UIKitCommandLogging.info("command", "ui snapshot evict lru id=\(lru.key) lastAccessedAgo=\(stamp.timeIntervalSince(lru.value.lastAccessedAt))")
        }
    }
}

/// snapshot 校验结果。
///
/// executor 仅在 `.stale` 时通过 `UIKitCommandError.staleLocator` 返回 `invalid_data`；
/// `.unknown` 不阻断（snapshotID 可能因容量淘汰消失，按无 snapshotID 处理）。
public enum UIKitSnapshotValidation: Sendable, Equatable {
    /// snapshot 存在、未过期且指纹一致。
    case valid
    /// TTL 过期或指纹不匹配，需重新查询。
    case stale
    /// snapshotID 未知（已淘汰或从未签发）。
    case unknown
}
