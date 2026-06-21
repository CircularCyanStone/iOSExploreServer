import Testing
@testable import iOSExploreServer

@Test("withLock 串行化并发递增,不丢更新")
func mutexSerializesConcurrentIncrement() async {
    let mutex = Mutex(0)
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<1000 {
            group.addTask { mutex.withLock { $0 += 1 } }
        }
    }
    #expect(mutex.withLock { $0 } == 1000)
}

@Test("withLock 支持读取并返回变换值")
func withLockReturnsValue() {
    let mutex = Mutex(42)
    let doubled = mutex.withLock { $0 * 2 }
    #expect(doubled == 84)
    #expect(mutex.withLock { $0 } == 42)
}
