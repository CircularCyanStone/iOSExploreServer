//
//  AppDelegate.swift
//  SPMExample
//
//  Created by 李奇奇 on 2026/6/21.
//

import UIKit
import OSLog
import iOSExploreServer
import iOSExploreUIKit
import iOSExploreDiagnostics

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    /// 全局 ExploreServer 实例
    static var shared: AppDelegate {
        return UIApplication.shared.delegate as! AppDelegate
    }

    /// ExploreServer 实例（全局单例）
    let server = ExploreServer()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // 启用日志
        ExploreLogging.setEnabled(true)

        // 注册所有命令
        registerCommands()

        #if DEBUG
        // DEBUG 环境自动启动 server
        Task {
            do {
                try await server.start()
                print("✅ iOSExplore server started on port 38321")
            } catch {
                print("❌ Failed to start iOSExplore server: \(error)")
            }
        }
        #endif

        return true
    }

    /// 注册所有命令
    private func registerCommands() {
        // 示例命令：greet
        server.register(action: "greet", description: "按 name 打招呼", input: ExampleGreetingInput.self) { input in
            .success(["message": .string("Hello, \(input.name)")])
        }

        // 示例命令：device（UIKit 注入）
        server.register(action: "device", description: "返回设备机型与名称(UIKit 注入)", input: EmptyCommandInput.self) { _ in
            return await MainActor.run {
                .success(["model": .string(UIDevice.current.model),
                          "name": .string(UIDevice.current.name)])
            }
        }

        // 注册 UIKit 命令
        server.registerUIKitCommands()

        // 注册 Diagnostics 命令
        #if DEBUG
        server.registerDiagnosticsCommands(exampleDiagnosticsConfiguration())
        #else
        server.registerDiagnosticsCommands(.init(captureStdout: false, captureStderr: false))
        #endif

        // Debug 命令
        server.register(action: "debug.probe",
                        description: "alive probe (非 DEBUG, 验证新 binary)",
                        input: EmptyCommandInput.self) { _ in
            .success(["alive": .bool(true), "build": .string("gesture-adapter-2026-07-04")])
        }

        server.register(action: "debug.emitAppLog",
                        description: "写入一条 SPMExample bridge 诊断日志",
                        input: ExampleStdIOMessageInput.self) { input in
            ExploreAppLog.emit(.info,
                               category: "spm.example",
                               message: input.message)
            return .success(["emitted": .bool(true)])
        }

        #if DEBUG
        // Debug stdio 命令
        server.register(action: "debug.emitStdout",
                        description: "向 stdout 写入一条 SPMExample 诊断文本",
                        input: ExampleStdIOMessageInput.self) { input in
            Self.emitStdIOMessage(input.message, source: "stdout")
        }
        server.register(action: "debug.emitStderr",
                        description: "向 stderr 写入一条 SPMExample 诊断文本",
                        input: ExampleStdIOMessageInput.self) { input in
            Self.emitStdIOMessage(input.message, source: "stderr")
        }
        server.register(action: "debug.emitNSLog",
                        description: "通过 NSLog 写入一条 SPMExample 诊断文本",
                        input: ExampleStdIOMessageInput.self) { input in
            Self.emitNSLogMessage(input.message)
        }
        server.register(action: "debug.emitOSLog",
                        description: "通过 os_log 写入一条 SPMExample 诊断文本",
                        input: ExampleStdIOMessageInput.self) { input in
            Self.emitOSLogMessage(input.message)
        }
        server.register(action: "debug.emitLogger",
                        description: "通过 Swift Logger 写入一条 SPMExample 诊断文本",
                        input: ExampleStdIOMessageInput.self) { input in
            Self.emitLoggerMessage(input.message)
        }
        #endif
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
}

// MARK: - 辅助类型

/// 示例命令输入：greeting
private struct ExampleGreetingInput: CommandInput {
    static let nameField = CommandFields.optionalString("name", description: "名字；缺省时返回 world")
    static let inputSchema = CommandInputSchema(fields: [nameField.erased])

    let name: String

    static func parse(decoding decoder: inout CommandInputDecoder) throws -> ExampleGreetingInput {
        ExampleGreetingInput(name: try decoder.read(nameField) ?? "world")
    }
}

#if DEBUG
/// 示例命令输入：stdio message
private struct ExampleStdIOMessageInput: CommandInput {
    static let messageField = CommandFields.optionalString("message", description: "写入 stdout/stderr 的文本（注意字段名是 message 不是 text）；缺省时使用默认诊断 marker。")
    static let tokenField = CommandFields.optionalString("token", description: "兼容测试脚本的短 token；未传 message 时作为写入文本。")
    static let inputSchema = CommandInputSchema(fields: [messageField.erased, tokenField.erased])

    let message: String

    static func parse(decoding decoder: inout CommandInputDecoder) throws -> ExampleStdIOMessageInput {
        let messageValue = try decoder.read(messageField)
        let tokenValue = try decoder.read(tokenField)
        let message = messageValue ?? tokenValue ?? "SPMExample stdio diagnostic marker"
        return ExampleStdIOMessageInput(message: message)
    }
}
#endif

// MARK: - Diagnostics 配置

extension AppDelegate {
    #if DEBUG
    func exampleDiagnosticsConfiguration() -> DiagnosticsConfiguration {
        DiagnosticsConfiguration(captureStdout: true,
                                 captureStderr: true,
                                 captureNSLog: true,
                                 captureOSLog: true)
    }

    nonisolated static func emitStdIOMessage(_ message: String, source: String) -> ExploreResult {
        let line = message + "\n"
        let data = Data(line.utf8)
        switch source {
        case "stdout":
            FileHandle.standardOutput.write(data)
        case "stderr":
            FileHandle.standardError.write(data)
        default:
            return .failure(code: .invalidData, message: "unsupported stdio source")
        }
        ExploreAppLog.emit(.info,
                           category: "spm.example.stdio",
                           message: "SPMExample \(source) debug command wrote bytes=\(data.count)")
        return .success([
            "source": .string(source),
            "message": .string(message),
            "bytes": .double(Double(data.count)),
        ])
    }

    nonisolated static func emitNSLogMessage(_ message: String) -> ExploreResult {
        NSLog("%@", message)
        ExploreAppLog.emit(.info,
                           category: "spm.example.nslog",
                           message: "SPMExample NSLog debug command emitted")
        return .success([
            "source": .string("nslog"),
            "message": .string(message),
        ])
    }

    nonisolated static func emitOSLogMessage(_ message: String) -> ExploreResult {
        os_log("%{public}@", log: OSLog(subsystem: "com.coo.SPMExample",
                                        category: "diagnostics"),
               type: .error,
               message)
        return .success([
            "source": .string("oslog"),
            "message": .string(message),
            "api": .string("os_log"),
        ])
    }

    nonisolated static func emitLoggerMessage(_ message: String) -> ExploreResult {
        if #available(iOS 14.0, macOS 11.0, *) {
            let logger = Logger(subsystem: "com.coo.SPMExample", category: "diagnostics")
            logger.error("\(message, privacy: .public)")
            return .success([
                "source": .string("oslog"),
                "message": .string(message),
                "api": .string("Logger"),
            ])
        }
        return .failure(code: .unsupportedTarget,
                        message: "Swift Logger requires iOS 14 or newer.")
    }

    /// 测试入口：解析 stdio 命令的 message 字段
    static func stdIOMessageForTesting(data: JSON) throws -> String {
        try ExampleStdIOMessageInput.parse(from: data).message
    }
    #endif
}


