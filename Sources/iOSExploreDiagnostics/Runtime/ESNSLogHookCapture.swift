import CFishhook
import Foundation
import iOSExploreServer

#if DEBUG
private struct NSLogHookState {
    var installed = false
    var installStatus: ESLogCaptureStatus?
    var activeToken: UUID?
    var activeStore: ESAppLogStore?
}

private let nsLogHookCallback: @convention(c) (UnsafePointer<CChar>?) -> Void = { rawMessage in
    ESNSLogHookCapture.append(rawMessage)
}

/// 基于 fishhook 的 `NSLog` 增强捕获器。
///
/// DoKit 的 NSLog 查看功能也是通过重绑定 `NSLog` 实现：替换函数先记录格式化后的文本，
/// 再调用原始 `NSLog` 保留系统控制台输出。本类型把同样的机制收敛为 Diagnostics 的
/// Objective-C 调用点增强路径；Swift Foundation overlay 不一定经过可重绑定的 C 符号，
/// 因此 runtime 仍保留 stderr 行识别作为可控捕获路径。
final class ESNSLogHookCapture: @unchecked Sendable {
    private static let state = Mutex(NSLogHookState())

    private let token: UUID?
    private let captureStatus: ESLogCaptureStatus

    /// 根据配置安装或激活 `NSLog` hook。
    ///
    /// - Parameters:
    ///   - configuration: Diagnostics 注册配置。
    ///   - store: hook 捕获到的日志写入的统一 store。
    init(configuration: ESDiagnosticsConfiguration, store: ESAppLogStore) {
        guard configuration.captureNSLog else {
            token = nil
            captureStatus = .notCaptured(reason: "NSLog capture is disabled")
            return
        }

        let installStatus = Self.installIfNeeded()
        guard installStatus.state == "enabled" else {
            token = nil
            captureStatus = installStatus
            return
        }

        let token = UUID()
        Self.state.withLock { state in
            state.activeToken = token
            state.activeStore = store
        }
        self.token = token
        captureStatus = .enabled
        ESLogger.emitExtension(level: .info,
                                     category: "diagnostics.nslog",
                                     message: "NSLog hook capture enabled")
    }

    /// 当前 hook 捕获状态。
    var status: ESLogCaptureStatus { captureStatus }

    /// 停止本次 runtime 对 hook 的使用。
    func stop() {
        guard let token else { return }
        Self.state.withLock { state in
            guard state.activeToken == token else { return }
            state.activeToken = nil
            state.activeStore = nil
        }
        ESLogger.emitExtension(level: .info,
                                     category: "diagnostics.nslog",
                                     message: "NSLog hook capture stopped")
    }

    fileprivate static func append(_ rawMessage: UnsafePointer<CChar>?) {
        guard let rawMessage else { return }
        let message = String(cString: rawMessage)
        let store = state.withLock { $0.activeStore }
        store?.append(source: .nslog,
                      level: .info,
                      category: "nslog",
                      message: message,
                      metadata: ["capturePath": "fishhook"])
    }

    private static func installIfNeeded() -> ESLogCaptureStatus {
        state.withLock { state in
            if let installStatus = state.installStatus {
                return installStatus
            }
            let result = ios_explore_install_nslog_hook(nsLogHookCallback)
            if result == 0 {
                state.installed = true
                state.installStatus = .enabled
                ESLogger.emitExtension(level: .info,
                                             category: "diagnostics.nslog",
                                             message: "NSLog hook installed")
            } else {
                state.installStatus = .unavailable(reason: "fishhook rebind NSLog failed code=\(result)")
                ESLogger.emitExtension(level: .error,
                                             category: "diagnostics.nslog",
                                             message: "NSLog hook unavailable code=\(result)")
            }
            return state.installStatus ?? .unavailable(reason: "fishhook rebind NSLog failed")
        }
    }
}
#endif
