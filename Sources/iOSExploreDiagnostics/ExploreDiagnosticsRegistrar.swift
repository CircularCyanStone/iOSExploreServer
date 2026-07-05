import Foundation
import iOSExploreServer

public extension ExploreServer {
    /// 注册进程日志诊断命令。
    ///
    /// 该方法显式安装 Diagnostics Runtime 并注册 `app.logs.mark` / `app.logs.read`。core 初始化
    /// 不会自动开启日志捕获，宿主必须像 `registerUIKitCommands()` 一样主动调用。
    ///
    /// - Parameter configuration: Diagnostics 配置。
    /// - Returns: 注册结果，包含当前 capture session id。
    @discardableResult
    func registerDiagnosticsCommands(_ configuration: DiagnosticsConfiguration = .default) -> DiagnosticsRegistration {
#if DEBUG
        return ProcessDiagnosticsRuntime.shared.register(on: self, configuration: configuration)
#else
        return .disabled(reason: "iOSExploreDiagnostics is disabled in non-Debug builds.")
#endif
    }
}
