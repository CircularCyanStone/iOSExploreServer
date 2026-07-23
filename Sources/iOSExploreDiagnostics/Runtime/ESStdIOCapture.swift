import Darwin
import Foundation
import iOSExploreServer

/// 单个标准流的捕获状态。
struct ESLogCaptureStatus {
    let state: String
    let reason: String?

    /// 捕获已安装并正在写入 store。
    static let enabled = ESLogCaptureStatus(state: "enabled", reason: nil)

    /// 捕获被配置关闭。
    ///
    /// - Parameter reason: 关闭原因。
    static func notCaptured(reason: String) -> ESLogCaptureStatus {
        ESLogCaptureStatus(state: "notCaptured", reason: reason)
    }

    /// 捕获请求已打开但安装失败。
    ///
    /// - Parameter reason: 失败原因。
    static func unavailable(reason: String) -> ESLogCaptureStatus {
        ESLogCaptureStatus(state: "unavailable", reason: reason)
    }
}

#if DEBUG
/// stdout/stderr fd 捕获器。
///
/// 该类型只属于 Diagnostics Debug runtime：安装时用 `dup` 保存原 fd、用 `pipe` + `dup2`
/// 把标准流导入后台 `DispatchSourceRead`，读取端按行写入 `ESAppLogStore`。停止时恢复原 fd 并等待
/// cancel handler 完成，确保测试 `resetForTesting()` 后不继续污染后续用例。
final class ESStdIOCapture {
    private let stdoutCapture: ESESStdIOStreamCapture?
    private let stderrCapture: ESESStdIOStreamCapture?
    private let stdoutStatus: ESLogCaptureStatus
    private let stderrStatus: ESLogCaptureStatus
    private let nslogStatus: ESLogCaptureStatus

    /// 根据配置安装 stdout/stderr 捕获。
    ///
    /// - Parameters:
    ///   - configuration: Diagnostics 注册配置。
    ///   - store: 捕获到的日志写入的统一 store。
    ///   - captureNSLogFromStderr: 是否把 stderr 中识别出的 NSLog 行作为 `source=nslog` 写入。
    ///   - suppressNSLogStderrLines: 是否丢弃 stderr 中已由主路径捕获的 NSLog 行，避免重复。
    init(configuration: ESDiagnosticsConfiguration,
         store: ESAppLogStore,
         captureNSLogFromStderr: Bool,
         suppressNSLogStderrLines: Bool) {
        if configuration.captureStdout {
            let result = ESESStdIOStreamCapture.install(stream: .stdout,
                                                    store: store,
                                                    teeToOriginalStream: configuration.teeToOriginalStreams,
                                                    capturePlainStream: true,
                                                    captureNSLog: false,
                                                    suppressNSLogLines: false)
            stdoutCapture = result.capture
            stdoutStatus = result.status
        } else {
            stdoutCapture = nil
            stdoutStatus = .notCaptured(reason: "stdout capture is disabled")
        }

        if configuration.captureStderr || captureNSLogFromStderr || suppressNSLogStderrLines {
            let result = ESESStdIOStreamCapture.install(stream: .stderr,
                                                    store: store,
                                                    teeToOriginalStream: configuration.teeToOriginalStreams,
                                                    capturePlainStream: configuration.captureStderr,
                                                    captureNSLog: captureNSLogFromStderr,
                                                    suppressNSLogLines: suppressNSLogStderrLines)
            stderrCapture = result.capture
            stderrStatus = configuration.captureStderr
                ? result.status
                : .notCaptured(reason: "stderr capture is disabled")
            nslogStatus = captureNSLogFromStderr
                ? result.status
                : .notCaptured(reason: "NSLog capture is disabled")
        } else {
            stderrCapture = nil
            stderrStatus = .notCaptured(reason: "stderr capture is disabled")
            nslogStatus = .notCaptured(reason: "NSLog capture is disabled")
        }
    }

    /// 当前 stdout 捕获状态。
    var stdout: ESLogCaptureStatus { stdoutStatus }

    /// 当前 stderr 捕获状态。
    var stderr: ESLogCaptureStatus { stderrStatus }

    /// 当前 NSLog 捕获状态。
    var nslog: ESLogCaptureStatus { nslogStatus }

    /// 恢复已重定向的 fd 并等待后台读取端退出。
    func stop() {
        stdoutCapture?.stop()
        stderrCapture?.stop()
    }
}

private enum ESStdIOStream {
    case stdout
    case stderr

    var descriptor: Int32 {
        switch self {
        case .stdout: return STDOUT_FILENO
        case .stderr: return STDERR_FILENO
        }
    }

    var source: ESAppLogSource {
        switch self {
        case .stdout: return .stdout
        case .stderr: return .stderr
        }
    }

    var level: ESAppLogLevel {
        switch self {
        case .stdout: return .info
        case .stderr: return .error
        }
    }

    var name: String {
        switch self {
        case .stdout: return "stdout"
        case .stderr: return "stderr"
        }
    }

    /// 当前标准流对应的 C `FILE*`。
    ///
    /// Swift `print()` 会经过 C `stdout` 的用户态缓冲；fd 重定向完成后需要同步调整该
    /// `FILE*` 的缓冲模式，避免日志长时间停在进程内缓冲区而没有进入 pipe。
    var filePointer: UnsafeMutablePointer<FILE> {
        switch self {
        case .stdout: return Darwin.stdout
        case .stderr: return Darwin.stderr
        }
    }

    /// 捕获安装后的 C 标准流缓冲模式。
    ///
    /// stdout 使用行缓冲，让 `print(...)\n` 及时进入 fd；stderr 保持无缓冲语义，贴近系统默认错误流行为。
    var captureBufferMode: Int32 {
        switch self {
        case .stdout: return _IOLBF
        case .stderr: return _IONBF
        }
    }
}

private final class ESESStdIOStreamCapture {
    private let stream: ESStdIOStream
    private let originalFD: Int32
    private let readSource: DispatchSourceRead
    private let reader: ESStdIOReadBuffer
    private let cancelSemaphore: DispatchSemaphore
    private let stopped = Mutex(false)

    private init(stream: ESStdIOStream,
                 originalFD: Int32,
                 readSource: DispatchSourceRead,
                 reader: ESStdIOReadBuffer,
                 cancelSemaphore: DispatchSemaphore) {
        self.stream = stream
        self.originalFD = originalFD
        self.readSource = readSource
        self.reader = reader
        self.cancelSemaphore = cancelSemaphore
    }

    deinit {
        stop()
    }

    static func install(stream: ESStdIOStream,
                        store: ESAppLogStore,
                        teeToOriginalStream: Bool,
                        capturePlainStream: Bool,
                        captureNSLog: Bool,
                        suppressNSLogLines: Bool) -> (capture: ESESStdIOStreamCapture?, status: ESLogCaptureStatus) {
        fflush(nil)

        let originalFD = dup(stream.descriptor)
        guard originalFD >= 0 else {
            return failure(stream: stream, reason: "dup failed errno=\(errno)")
        }

        var pipeFDs: [Int32] = [0, 0]
        guard pipe(&pipeFDs) == 0 else {
            let currentErrno = errno
            close(originalFD)
            return failure(stream: stream, reason: "pipe failed errno=\(currentErrno)")
        }

        guard dup2(pipeFDs[1], stream.descriptor) >= 0 else {
            let currentErrno = errno
            close(pipeFDs[0])
            close(pipeFDs[1])
            close(originalFD)
            return failure(stream: stream, reason: "dup2 failed errno=\(currentErrno)")
        }
        if setvbuf(stream.filePointer, nil, stream.captureBufferMode, 0) != 0 {
            ESLogger.emitExtension(level: .error,
                                         category: "diagnostics.stdio",
                                         message: "\(stream.name) capture setvbuf failed errno=\(errno)")
        }
        close(pipeFDs[1])

        let flags = fcntl(pipeFDs[0], F_GETFL)
        guard flags >= 0, fcntl(pipeFDs[0], F_SETFL, flags | O_NONBLOCK) >= 0 else {
            let currentErrno = errno
            _ = dup2(originalFD, stream.descriptor)
            close(pipeFDs[0])
            close(originalFD)
            return failure(stream: stream, reason: "fcntl nonblock failed errno=\(currentErrno)")
        }

        let reader = ESStdIOReadBuffer(pipeReadFD: pipeFDs[0],
                                     originalFD: originalFD,
                                     stream: stream,
                                     store: store,
                                     teeToOriginalStream: teeToOriginalStream,
                                     capturePlainStream: capturePlainStream,
                                     captureNSLog: captureNSLog,
                                     suppressNSLogLines: suppressNSLogLines)
        let queue = DispatchQueue(label: "com.coo.iOSExploreDiagnostics.stdio.\(stream.name)")
        let source = DispatchSource.makeReadSource(fileDescriptor: pipeFDs[0], queue: queue)
        let cancelSemaphore = DispatchSemaphore(value: 0)
        source.setEventHandler {
            reader.drainAvailableBytes()
        }
        source.setCancelHandler {
            reader.flushPendingLine()
            close(pipeFDs[0])
            cancelSemaphore.signal()
        }
        source.resume()

        ESLogger.emitExtension(level: .info,
                                     category: "diagnostics.stdio",
                                     message: "\(stream.name) capture enabled tee=\(teeToOriginalStream) plain=\(capturePlainStream) nslog=\(captureNSLog) suppressNSLog=\(suppressNSLogLines)")
        return (ESESStdIOStreamCapture(stream: stream,
                                   originalFD: originalFD,
                                   readSource: source,
                                   reader: reader,
                                   cancelSemaphore: cancelSemaphore), .enabled)
    }

    func stop() {
        let shouldStop = stopped.withLock { stopped -> Bool in
            if stopped { return false }
            stopped = true
            return true
        }
        guard shouldStop else { return }

        fflush(nil)
        if dup2(originalFD, stream.descriptor) < 0 {
            ESLogger.emitExtension(level: .error,
                                         category: "diagnostics.stdio",
                                         message: "\(stream.name) capture restore failed errno=\(errno)")
        }
        reader.drainAvailableBytes()
        close(originalFD)
        readSource.cancel()
        if cancelSemaphore.wait(timeout: .now() + .seconds(2)) == .timedOut {
            ESLogger.emitExtension(level: .error,
                                         category: "diagnostics.stdio",
                                         message: "\(stream.name) capture cancel timed out")
        }
        ESLogger.emitExtension(level: .info,
                                     category: "diagnostics.stdio",
                                     message: "\(stream.name) capture stopped")
    }

    private static func failure(stream: ESStdIOStream,
                                reason: String) -> (capture: ESESStdIOStreamCapture?, status: ESLogCaptureStatus) {
        ESLogger.emitExtension(level: .error,
                                     category: "diagnostics.stdio",
                                     message: "\(stream.name) capture unavailable reason=\(reason)")
        return (nil, .unavailable(reason: reason))
    }
}

private final class ESStdIOReadBuffer: Sendable {
    private let pipeReadFD: Int32
    private let originalFD: Int32
    private let stream: ESStdIOStream
    private let store: ESAppLogStore
    private let teeToOriginalStream: Bool
    private let capturePlainStream: Bool
    private let captureNSLog: Bool
    private let suppressNSLogLines: Bool
    private let pending = Mutex<[UInt8]>([])

    init(pipeReadFD: Int32,
         originalFD: Int32,
         stream: ESStdIOStream,
         store: ESAppLogStore,
         teeToOriginalStream: Bool,
         capturePlainStream: Bool,
         captureNSLog: Bool,
         suppressNSLogLines: Bool) {
        self.pipeReadFD = pipeReadFD
        self.originalFD = originalFD
        self.stream = stream
        self.store = store
        self.teeToOriginalStream = teeToOriginalStream
        self.capturePlainStream = capturePlainStream
        self.captureNSLog = captureNSLog
        self.suppressNSLogLines = suppressNSLogLines
    }

    func drainAvailableBytes() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = buffer.withUnsafeMutableBufferPointer { pointer in
                read(pipeReadFD, pointer.baseAddress, pointer.count)
            }
            if count > 0 {
                let bytes = Array(buffer.prefix(count))
                if teeToOriginalStream {
                    writeAll(bytes)
                }
                append(bytes)
            } else if count == 0 || errno == EAGAIN || errno == EWOULDBLOCK {
                break
            } else if errno == EINTR {
                continue
            } else {
                ESLogger.emitExtension(level: .error,
                                             category: "diagnostics.stdio",
                                             message: "\(stream.name) capture read failed errno=\(errno)")
                break
            }
        }
    }

    func flushPendingLine() {
        let line = pending.withLock { pending -> [UInt8] in
            let line = pending
            pending.removeAll(keepingCapacity: false)
            return line
        }
        if line.isEmpty == false {
            appendLine(line)
        }
    }

    private func append(_ bytes: [UInt8]) {
        pending.withLock { pending in
            for byte in bytes {
                if byte == 10 {
                    appendLine(pending)
                    pending.removeAll(keepingCapacity: true)
                } else {
                    pending.append(byte)
                }
            }
        }
    }

    private func appendLine(_ bytes: [UInt8]) {
        var lineBytes = bytes
        if lineBytes.last == 13 {
            lineBytes.removeLast()
        }
        let line = String(decoding: lineBytes, as: UTF8.self)
        if stream == .stderr, Self.looksLikeNSLogLine(line) {
            if captureNSLog {
                store.append(source: .nslog,
                             level: .info,
                             category: "nslog",
                             message: line,
                             metadata: ["capturePath": "stderr"])
                return
            }
            if suppressNSLogLines {
                return
            }
        }
        guard capturePlainStream else { return }
        store.append(source: stream.source,
                     level: stream.level,
                     category: "stdio",
                     message: line)
    }

    /// 判断一行 stderr 输出是否是 `NSLog` 产生的。
    ///
    /// NSLog 行的固定骨架为 `YYYY-MM-DD HH:MM:SS.<小数秒>`，其后跟时区/进程名/消息。骨架前 20
    /// 个字符（到 `.` 为止，含）在所有 iOS 版本稳定；小数秒位数会变——旧版为 3 位毫秒 `mmm`，
    /// iOS 26 改为 6 位微秒 `mmmmmm`。因此只校验到秒级骨架（含 `.`），并要求其后紧跟至少一位数字，
    /// 不再硬编码 `prefix[23] == " "`（该写法在 6 位微秒下会把索引 23 指到微秒第 4 位数字，
    /// 误判为非 NSLog 行，导致 captureNSLog 打开后 NSLog 输出被当作普通 stderr 丢弃）。
    private static func looksLikeNSLogLine(_ line: String) -> Bool {
        // 骨架 "YYYY-MM-DD HH:MM:SS." 长度 20，小数秒至少 1 位，故整行至少 21 字符。
        guard line.count >= 21 else { return false }
        let chars = Array(line)
        return chars[4] == "-"
            && chars[7] == "-"
            && chars[10] == " "
            && chars[13] == ":"
            && chars[16] == ":"
            && chars[19] == "."
            && chars[20].isNumber
    }

    private func writeAll(_ bytes: [UInt8]) {
        bytes.withUnsafeBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress else { return }
            var written = 0
            while written < pointer.count {
                let count = write(originalFD, baseAddress.advanced(by: written), pointer.count - written)
                if count > 0 {
                    written += count
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    break
                }
            }
        }
    }
}
#endif
