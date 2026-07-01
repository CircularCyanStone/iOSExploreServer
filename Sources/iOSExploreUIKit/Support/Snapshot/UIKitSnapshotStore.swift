import Foundation

/// UIKit snapshot 的 Foundation-only 容量常量。
///
/// 查询模型也需要读取 fingerprint 上限，因此常量不能放在 `@MainActor` store 的静态成员上；
/// 该类型不持有 UIKit 对象，可安全供 Foundation-only 参数解析复用。
enum UIKitSnapshotLimits {
    /// 单条 snapshot 最多保存的 target fingerprint 数。
    static let maxFingerprints = 512
}

// MARK: - UIKitTargetFingerprint

/// UIKit 目标的轻量指纹。
///
/// 陈旧检测的关键值类型：只保存"判断两次调用间的同一 path 是否仍指向同一 view"所需的
/// 最少信息——context 类型摘要、path、view 类型名、identifier 的**稳定哈希**、基础状态布尔
/// 与祖先结构摘要。**绝不保存** `UIView`、文本内容或完整 identifier，因此：
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
    /// 控件是否可用（UIControl.isEnabled，非控件视为 true）。
    public let isEnabled: Bool
    /// 控件是否选中（UIControl.isSelected，非控件视为 false）。
    public let isSelected: Bool
    /// view 是否隐藏；隐藏后不应继续把旧 path 视为可操作目标。
    public let isHidden: Bool
    /// view 透明度；低透明度会影响 hit-test，必须参与陈旧校验。
    public let alpha: Double
    /// 是否允许用户交互；关闭后不能沿用查询时的动作能力。
    public let isUserInteractionEnabled: Bool
    /// 从 root 到目标父节点的结构与交互状态摘要。
    public let ancestorDigest: UInt64

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
    ///   - isHidden: 是否隐藏。
    ///   - alpha: 透明度。
    ///   - isUserInteractionEnabled: 是否允许用户交互。
    public init(contextDigest: String,
                path: String,
                viewType: String,
                identifierHash: UInt64,
                isEnabled: Bool,
                isSelected: Bool,
                isHidden: Bool = false,
                alpha: Double = 1,
                isUserInteractionEnabled: Bool = true,
                ancestorDigest: UInt64 = 0) {
        self.contextDigest = contextDigest
        self.path = path
        self.viewType = viewType
        self.identifierHash = identifierHash
        self.isEnabled = isEnabled
        self.isSelected = isSelected
        self.isHidden = isHidden
        self.alpha = alpha
        self.isUserInteractionEnabled = isUserInteractionEnabled
        self.ancestorDigest = ancestorDigest
    }

    /// 仅供测试的固定指纹 fixture。
    ///
    /// 所有字段取稳定占位值，使 snapshot store 的 macOS 测试不依赖 UIKit。测试推进时间即可
    /// 触发 TTL 过期，无需构造真实 view。
    public static let test = UIKitTargetFingerprint(contextDigest: "test-context",
                                                    path: "root/0",
                                                    viewType: "TestView",
                                                    identifierHash: Self.stableHash("test-id"),
                                                    isEnabled: true,
                                                    isSelected: false,
                                                    isHidden: false,
                                                    alpha: 1,
                                                    isUserInteractionEnabled: true,
                                                    ancestorDigest: 0)

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

/// snapshot 所属的查询上下文身份。
///
/// window 或顶部控制器换成同类型的新实例时，旧 path 也不能继续使用。两个 identity 只在
/// store 内比较，绝不写入 HTTP 响应或日志。
public struct UIKitSnapshotContext: Sendable, Equatable {
    /// 当前 window 的进程内实例标识。
    public let windowIdentity: String
    /// 当前顶部控制器的进程内实例标识。
    public let topViewControllerIdentity: String

    /// 兼容既有诊断调用的摘要。
    ///
    /// 新实现不得把实例 identity 写入日志；该属性仅保留旧 collector 在迁移到新 context
    /// 构造方式前的编译兼容，返回顶部控制器 identity。
    public var digest: String { topViewControllerIdentity }

    /// 创建一个上下文摘要。
    ///
    /// - Parameters:
    ///   - windowIdentity: 当前 window 的进程内实例标识。
    ///   - topViewControllerIdentity: 当前顶部控制器的进程内实例标识。
    public init(windowIdentity: String, topViewControllerIdentity: String) {
        self.windowIdentity = windowIdentity
        self.topViewControllerIdentity = topViewControllerIdentity
    }

    /// 兼容旧调用方提供的单一上下文摘要。
    ///
    /// - Parameter digest: 旧版调用方提供的上下文摘要。
    public init(digest: String) {
        self.init(windowIdentity: digest, topViewControllerIdentity: digest)
    }

    /// 仅供测试的固定上下文 fixture。
    public static let test = UIKitSnapshotContext(windowIdentity: "test-window",
                                                  topViewControllerIdentity: "test-controller")
}

// MARK: - UIKitSnapshotStore

/// UIKit 视图树指纹快照存储。
///
/// 解决"path 陈旧"问题：`ui.viewTargets`/`ui.topViewHierarchy` 查询时对当前 view 树生成
/// 轻量指纹并签发一个 snapshotID 返回给调用方；交互命令（tap/control.sendAction）携带该
/// snapshotID 时，executor 在执行前校验对应 path 的指纹是否仍匹配，不匹配则返回
/// `stale_locator`（"snapshot expired or target changed; call ui.screenshot first..."），避免页面
/// 变化后 path 指向错误 view 造成误操作。
///
/// 容量与淘汰策略：
/// - 最多 **8 条**快照（不同 snapshotID）；
/// - 每条快照最多 **512** 条指纹（path→fingerprint）；超过 512 不签发（返回 nil）；
/// - **TTL 30 秒**（spec §3.6：匹配 LLM 推理节奏）：查询时先清过期，再按 LRU 淘汰至容量上限。
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
    static let maxFingerprints = UIKitSnapshotLimits.maxFingerprints
    /// 快照存活秒数。
    ///
    /// spec §3.6：30s 匹配 LLM 推理节奏（agent 在 viewTargets/screenshot 与 tap 之间常需 3-30s
    /// 思考），原 10s 易在推理期间过期导致 snapshotID 失效。
    static let ttlSeconds: TimeInterval = 30

    /// 单条快照记录。
    private struct Entry {
        /// 签发时间（用于 TTL 判断）。
        let createdAt: Date
        /// 最近访问时间（用于 LRU 判断）。
        var lastAccessedAt: Date
        /// 该快照的指纹表（path → fingerprint）。
        var fingerprints: [String: UIKitTargetFingerprint]
        /// 签发查询时的 window 与顶部控制器实例身份。
        let context: UIKitSnapshotContext
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
                            fingerprints: targets,
                            context: context)
        UIKitCommandLogging.info("command", "ui snapshot insert id=\(id) fingerprints=\(targets.count)")
        return id
    }

    /// 校验 snapshot 是否陈旧（snapshot 不存在、TTL 过期、context 变化、path 缺失或指纹不匹配）。
    ///
    /// executor 对携带 snapshotID 的交互在陈旧时 throw `staleLocator`；所有无法验证的情况均
    /// 返回 `true`，防止 LRU 淘汰后的旧 path 静默退化为无防护执行。
    ///
    /// - Parameters:
    ///   - snapshotID: 调用方携带的快照标识。
    ///   - path: 要交互的目标 path。
    ///   - context: 当前查询上下文身份。
    ///   - current: 当前重新采集的该 path 指纹。
    /// - Returns: `true` 表示陈旧（需重新查询）；`false` 表示有效。
    public func isStale(snapshotID: String,
                        path: String,
                        context: UIKitSnapshotContext,
                        current: UIKitTargetFingerprint) -> Bool {
        guard var entry = entries[snapshotID] else {
            UIKitCommandLogging.info("command", "ui snapshot unknown id=\(snapshotID) path=\(path)")
            return true
        }
        if isExpired(entry: entry) {
            entries.removeValue(forKey: snapshotID)
            UIKitCommandLogging.info("command", "ui snapshot expired id=\(snapshotID) path=\(path)")
            return true
        }
        entry.lastAccessedAt = now()
        entries[snapshotID] = entry
        guard entry.context == context else {
            UIKitCommandLogging.info("command", "ui snapshot context mismatch id=\(snapshotID) path=\(path)")
            return true
        }
        guard let stored = entry.fingerprints[path] else {
            UIKitCommandLogging.info("command", "ui snapshot path missing id=\(snapshotID) path=\(path)")
            return true
        }
        if stored == current { return false }
        UIKitCommandLogging.info("command", "ui snapshot fingerprint mismatch id=\(snapshotID) path=\(path)")
        return true
    }

    /// 兼容未传实例上下文的既有调用方（Foundation 测试）。
    public func isStale(snapshotID: String,
                        path: String,
                        current: UIKitTargetFingerprint) -> Bool {
        isStale(snapshotID: snapshotID, path: path, context: .test, current: current)
    }

    /// 比较指定 snapshot 的页面身份是否与当前一致（供 `ui.wait` 的 snapshotChanged）。
    ///
    /// 与单 path 的 `isStale` 不同：本方法只比较签发时记录的 `UIKitSnapshotContext`（window +
    /// 顶部控制器实例身份）与当前 context，用于检测"页面是否切换"，不比较指纹表内容变化。
    /// snapshot 未知或过期返回 nil，调用方据 `snapshotUnavailableReason` 决定继续等待或失败。
    ///
    /// - Parameters:
    ///   - snapshotID: 参照快照标识。
    ///   - context: 当前页面身份摘要。
    /// - Returns: nil=snapshot 未知/过期；true=页面身份一致（未变化）；false=身份变化（已切换）。
    func contextMatches(snapshotID: String, context: UIKitSnapshotContext) -> Bool? {
        guard var entry = entries[snapshotID] else { return nil }
        if isExpired(entry: entry) {
            entries.removeValue(forKey: snapshotID)
            UIKitCommandLogging.info("command", "ui snapshot expired id=\(snapshotID) wait=snapshotChanged")
            return nil
        }
        entry.lastAccessedAt = now()
        entries[snapshotID] = entry
        let matches = entry.context == context
        if !matches {
            UIKitCommandLogging.info("command", "ui snapshot context changed id=\(snapshotID) wait=snapshotChanged")
        }
        return matches
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
