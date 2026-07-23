import iOSExploreServer

private struct ProcessDiagnosticsTestGateState {
    var isAvailable: Bool = true
    var waiters: [CheckedContinuation<Void, Never>] = []
}

/// 串行化会修改进程级 Diagnostics runtime 的测试。
///
/// Swift Testing 的 `.serialized` 只保证同一 suite 内串行，不保证不同 suite 之间串行。
/// Diagnostics runtime、stdout/stderr fd capture 和 `ESLogger` observer 都是进程级资源，
/// 因此相关测试需要共享同一个异步 gate，避免一个 suite 在另一个 suite 读取时 reset runtime。
final class ProcessDiagnosticsTestGate: Sendable {
    private let state = Mutex(ProcessDiagnosticsTestGateState())

    /// 等待独占执行权。
    func wait() async {
        await withCheckedContinuation { continuation in
            let shouldResume = state.withLock { state -> Bool in
                if state.isAvailable {
                    state.isAvailable = false
                    return true
                }
                state.waiters.append(continuation)
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }

    /// 释放独占执行权，并唤醒下一位等待者。
    func signal() {
        let waiter = state.withLock { state -> CheckedContinuation<Void, Never>? in
            if state.waiters.isEmpty {
                state.isAvailable = true
                return nil
            }
            return state.waiters.removeFirst()
        }
        waiter?.resume()
    }
}

let processDiagnosticsTestGate = ProcessDiagnosticsTestGate()

/// 在异步测试中独占进程级 Diagnostics runtime。
///
/// - Parameter body: 需要独占执行的测试主体。
/// - Returns: 测试主体返回值。
func withProcessDiagnosticsTestIsolation<T>(_ body: () async throws -> T) async rethrows -> T {
    await processDiagnosticsTestGate.wait()
    defer { processDiagnosticsTestGate.signal() }
    return try await body()
}
