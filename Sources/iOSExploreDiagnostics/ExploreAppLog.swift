import Foundation

/// 宿主 App 主动写入 Diagnostics store 的业务日志入口。
///
/// 它用于记录认证、网络、路由、支付、风控等高信号业务事件。Runtime 未安装或 bridge 未启用时，
/// 该入口为 no-op，不会自动安装 stdout/stderr 或其它 hook。
public enum ExploreAppLog {
    /// 写入一条宿主业务日志。
    ///
    /// - Parameters:
    ///   - level: 日志等级。
    ///   - category: 宿主分类。
    ///   - message: 日志正文，只有 Runtime 已安装且 bridge 启用时才会构造。
    ///   - metadata: 轻量上下文。
    public static func emit(_ level: AppLogLevel,
                            category: String,
                            message: @autoclosure () -> String,
                            metadata: [String: String]? = nil) {
        ProcessDiagnosticsRuntime.shared.appendBridge(level: level,
                                                      category: category,
                                                      message: message,
                                                      metadata: metadata)
    }
}
