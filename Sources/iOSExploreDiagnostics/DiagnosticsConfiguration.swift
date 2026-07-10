import Foundation

/// Diagnostics 注册配置。
///
/// `explore` 与 `bridge` 默认启用；stdout/stderr、NSLog 与 Apple Unified Logging 需要宿主
/// 显式打开 capture，避免示例或业务 App 在无意中接管进程级日志路径。
public struct DiagnosticsConfiguration: Sendable, Equatable {
    /// 是否捕获 iOSExplore 内部日志。
    public let captureExploreLogs: Bool
    /// 是否启用宿主业务日志 bridge。
    public let enableBridge: Bool
    /// 是否尝试捕获 stdout fd；成功后每行以 `source=stdout`、`level=info` 写入 store。
    public let captureStdout: Bool
    /// 是否尝试捕获 stderr fd；成功后每行以 `source=stderr`、`level=error` 写入 store。
    public let captureStderr: Bool
    /// 是否尝试捕获 `NSLog` 输出；stderr 行识别或 `OSLogStore` 读取成功后以 `source=nslog`、`level=info` 写入 store。
    public let captureNSLog: Bool
    /// 是否尝试通过 `OSLogStore` 读取当前进程的 Apple Unified Logging entry。
    ///
    /// 该来源覆盖系统允许读取到的 `os_log` 与 Swift `Logger` 输出。注意该来源会过滤
    /// `subsystem` 以 `com.apple.` 开头的系统框架 entry（如 Foundation、UIKit、CFNetwork
    /// 等），避免宿主调试视图被系统日志淹没。仅宿主自行写入的 `os_log` / Logger entry
    /// （subsystem 不以 `com.apple.` 开头）会被捕获。如果当前 OS 或沙箱不允许读取
    /// `OSLogStore`，状态会返回 `unavailable`，不会静默伪装为已捕获。
    public let captureOSLog: Bool
    /// 是否把捕获到的 stdout/stderr 字节同步写回原始 fd，便于保留宿主原有控制台输出。
    public let teeToOriginalStreams: Bool
    /// 日志 store 最多保留 entry 数量。
    public let bufferCapacity: Int
    /// 单条 message 最大 UTF-8 字节数。
    public let maximumEntryBytes: Int
    /// 单条 entry 最多保留的 metadata 键值对数量。
    public let maximumMetadataEntries: Int
    /// 单个 metadata key 最大 UTF-8 字节数。
    public let maximumMetadataKeyBytes: Int
    /// 单个 metadata value 最大 UTF-8 字节数。
    public let maximumMetadataValueBytes: Int
    /// 写入前使用的脱敏器。
    public let redaction: LogRedactor

    /// 默认配置。
    public static let `default` = DiagnosticsConfiguration()

    /// 创建 Diagnostics 配置。
    ///
    /// - Parameters:
    ///   - captureExploreLogs: 是否捕获 iOSExplore 内部日志。
    ///   - enableBridge: 是否启用宿主业务日志 bridge。
    ///   - captureStdout: 是否尝试捕获 stdout。
    ///   - captureStderr: 是否尝试捕获 stderr。
    ///   - captureNSLog: 是否尝试捕获 `NSLog` 输出。
    ///   - captureOSLog: 是否尝试读取当前进程 Apple Unified Logging。
    ///   - teeToOriginalStreams: 是否 tee 回原始 stdout/stderr。
    ///   - bufferCapacity: 日志 store 容量。
    ///   - maximumEntryBytes: 单条 message 最大 UTF-8 字节数。
    ///   - maximumMetadataEntries: 单条 entry 最多保留的 metadata 键值对数量。
    ///   - maximumMetadataKeyBytes: 单个 metadata key 最大 UTF-8 字节数。
    ///   - maximumMetadataValueBytes: 单个 metadata value 最大 UTF-8 字节数。
    ///   - redaction: 写入前使用的脱敏器。
    public init(captureExploreLogs: Bool = true,
                enableBridge: Bool = true,
                captureStdout: Bool = false,
                captureStderr: Bool = false,
                captureNSLog: Bool = false,
                captureOSLog: Bool = false,
                teeToOriginalStreams: Bool = true,
                bufferCapacity: Int = 2_000,
                maximumEntryBytes: Int = 8 * 1024,
                maximumMetadataEntries: Int = 32,
                maximumMetadataKeyBytes: Int = 128,
                maximumMetadataValueBytes: Int = 1024,
                redaction: LogRedactor = .standard) {
        self.captureExploreLogs = captureExploreLogs
        self.enableBridge = enableBridge
        self.captureStdout = captureStdout
        self.captureStderr = captureStderr
        self.captureNSLog = captureNSLog
        self.captureOSLog = captureOSLog
        self.teeToOriginalStreams = teeToOriginalStreams
        self.bufferCapacity = bufferCapacity
        self.maximumEntryBytes = maximumEntryBytes
        self.maximumMetadataEntries = maximumMetadataEntries
        self.maximumMetadataKeyBytes = maximumMetadataKeyBytes
        self.maximumMetadataValueBytes = maximumMetadataValueBytes
        self.redaction = redaction
    }
}

/// Diagnostics 注册结果。
///
/// 该值让宿主能知道日志能力是否实际启用，以及当前 capture session 是哪一个。
public struct DiagnosticsRegistration: Sendable, Equatable {
    /// 是否启用 Diagnostics Runtime。
    public let enabled: Bool
    /// 当前 capture session id；未启用时为 nil。
    public let captureSessionID: String?
    /// 未启用或降级原因。
    public let reason: String?

    /// 创建启用结果。
    ///
    /// - Parameter captureSessionID: 当前 capture session id。
    public static func enabled(captureSessionID: String) -> DiagnosticsRegistration {
        DiagnosticsRegistration(enabled: true, captureSessionID: captureSessionID, reason: nil)
    }

    /// 创建禁用结果。
    ///
    /// - Parameter reason: 禁用原因。
    public static func disabled(reason: String) -> DiagnosticsRegistration {
        DiagnosticsRegistration(enabled: false, captureSessionID: nil, reason: reason)
    }
}
