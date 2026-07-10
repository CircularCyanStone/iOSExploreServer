import Foundation
#if canImport(os.lock)
import os.lock
#endif

/// 基于 `os_unfair_lock` 的轻量互斥锁。
///
/// Swift 6 严格并发要求共享可变状态跨边界时是安全的。本库把唯一的 `@unchecked`
/// 边界收敛在这里：`Mutex` 手动保证内部值的互斥访问，库内 `Router` / `ExploreServer` /
/// `HTTPListener` / `ClientSession` / `ExploreLogging` 等共享可变状态全部通过
/// `withLock` 读写，从而保持各自的 `Sendable` 语义。
///
/// 使用约束：传入 `withLock` 的闭包必须是同步闭包，锁内禁止 `await`，也不应执行耗时 I/O。
public final class Mutex<Value>: @unchecked Sendable {
    /// 底层 unfair lock 指针。
    private let storage: UnsafeMutablePointer<os_unfair_lock>

    /// 被保护的值。只能在持锁状态下访问。
    private var value: Value

    /// 创建一个互斥保护的值。
    public init(_ initial: Value) {
        self.value = initial
        self.storage = .allocate(capacity: 1)
        self.storage.initialize(to: os_unfair_lock())
    }

    /// 释放底层锁内存。
    deinit {
        storage.deinitialize(count: 1)
        storage.deallocate()
    }

    /// 在持锁状态下同步访问被保护的值。
    ///
    /// - Parameter body: 对内部值的同步读写闭包。
    /// - Returns: 闭包返回值。
    /// - Throws: 原样转发闭包抛出的错误。
    @discardableResult
    public func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
        os_unfair_lock_lock(storage)
        defer { os_unfair_lock_unlock(storage) }
        return try body(&value)
    }
}
