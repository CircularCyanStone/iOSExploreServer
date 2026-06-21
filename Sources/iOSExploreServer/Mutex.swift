import Foundation
#if canImport(os.lock)
import os.lock
#endif

/// 基于 os_unfair_lock 的轻量互斥锁,兼容 iOS 13+。
/// 内部手动保证线程安全,故 @unchecked —— 这是【全库唯一的不安全边界】。
/// Router / ExploreServer 依赖它即可获得真 Sendable,无需各自再标 @unchecked。
public final class Mutex<Value>: @unchecked Sendable {
    private let storage: UnsafeMutablePointer<os_unfair_lock>
    private var value: Value

    public init(_ initial: Value) {
        self.value = initial
        self.storage = .allocate(capacity: 1)
        self.storage.initialize(to: os_unfair_lock())
    }

    deinit {
        storage.deinitialize(count: 1)
        storage.deallocate()
    }

    @discardableResult
    public func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
        os_unfair_lock_lock(storage)
        defer { os_unfair_lock_unlock(storage) }
        return try body(&value)
    }
}
