import Testing
@testable import iOSExploreServer

/// `ExploreCommandFailure` 值类型测试。
///
/// 原本同文件的 `extensionLogUsesCoreSink` 会 touch `ESLogger` 全局 sink,已移入
/// `ESLoggerTests`(与所有 touch-sink 测试同处一个 `.serialized` suite)以消除跨 suite
/// 并行竞态。本 suite 只剩不依赖全局 sink 的纯值类型测试。
struct ExploreCommandSupportTests {
    @Test("扩展 command failure 保留 envelope 与日志语义")
    func commandFailureMapsToResult() {
        let failure = ExploreCommandFailure(code: .invalidData,
                                            message: "target not found",
                                            logMessage: "uikit locator missing kind=path")
        #expect(failure.result == .failure(code: .invalidData, message: "target not found"))
    }
}
