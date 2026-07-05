//
//  SPMExampleTests.swift
//  SPMExampleTests
//
//  Created by 李奇奇 on 2026/6/21.
//

import Testing
import UIKit
import iOSExploreServer
import iOSExploreDiagnostics
@testable import SPMExample

struct SPMExampleTests {

    #if DEBUG
    @Test("示例 App 注册 Diagnostics 命令") @MainActor
    func exampleAppRegistersDiagnosticsCommands() async {
        let viewController = ViewController()
        viewController.loadViewIfNeeded()

        let actions = viewController.registeredCommandActionsForTesting()

        #expect(actions.contains("app.logs.mark"))
        #expect(actions.contains("app.logs.read"))
    }

    @Test("示例 App 用代码直配打开 stdout/stderr/NSLog/os_log capture") @MainActor
    func exampleDiagnosticsConfigurationEnablesLogCapture() {
        let configuration = ViewController.exampleDiagnosticsConfiguration()

        #expect(configuration.captureStdout)
        #expect(configuration.captureStderr)
        #expect(configuration.captureNSLog)
        #expect(configuration.captureOSLog)
    }

    @Test("示例 App 注册 stdout/stderr/NSLog/os_log/Logger 调试输出命令") @MainActor
    func exampleAppRegistersStdIODebugCommands() async {
        let viewController = ViewController()
        viewController.loadViewIfNeeded()

        let actions = viewController.registeredCommandActionsForTesting()

        #expect(actions.contains("debug.emitStdout"))
        #expect(actions.contains("debug.emitStderr"))
        #expect(actions.contains("debug.emitNSLog"))
        #expect(actions.contains("debug.emitOSLog"))
        #expect(actions.contains("debug.emitLogger"))
    }

    @Test("debug.emitStdout 返回写入的 message") @MainActor
    func emitStdoutCommandReturnsMessage() async throws {
        let message = "stdout-command-\(UUID().uuidString)"

        let result = ViewController.emitStdIOMessageForTesting(message, source: "stdout")

        let data = try successData(from: result)
        #expect(data["source"]?.stringValue == "stdout")
        #expect(data["message"]?.stringValue == message)
    }

    @Test("debug stdio 输入解析会读取 message 和 token 字段") @MainActor
    func stdIOMessageInputReadsDeclaredFields() throws {
        let message = "stdout-message-\(UUID().uuidString)"

        let parsed = try ViewController.stdIOMessageForTesting(data: [
            "message": .string(message),
            "token": .string("fallback-token"),
        ])

        #expect(parsed == message)
    }

    @Test("debug.emitStderr 返回写入的 message") @MainActor
    func emitStderrCommandReturnsMessage() async throws {
        let message = "stderr-command-\(UUID().uuidString)"

        let result = ViewController.emitStdIOMessageForTesting(message, source: "stderr")

        let data = try successData(from: result)
        #expect(data["source"]?.stringValue == "stderr")
        #expect(data["message"]?.stringValue == message)
    }

    @Test("debug.emitNSLog 返回写入的 message") @MainActor
    func emitNSLogCommandReturnsMessage() async throws {
        let message = "nslog-command-\(UUID().uuidString)"

        let result = ViewController.emitNSLogMessageForTesting(message)

        let data = try successData(from: result)
        #expect(data["source"]?.stringValue == "nslog")
        #expect(data["message"]?.stringValue == message)
    }

    @Test("debug.emitOSLog 返回写入的 message") @MainActor
    func emitOSLogCommandReturnsMessage() async throws {
        let message = "oslog-command-\(UUID().uuidString)"

        let result = ViewController.emitOSLogMessageForTesting(message)

        let data = try successData(from: result)
        #expect(data["source"]?.stringValue == "oslog")
        #expect(data["api"]?.stringValue == "os_log")
        #expect(data["message"]?.stringValue == message)
    }

    @Test("debug.emitLogger 返回写入的 message") @MainActor
    func emitLoggerCommandReturnsMessage() async throws {
        let message = "logger-command-\(UUID().uuidString)"

        let result = ViewController.emitLoggerMessageForTesting(message)

        let data = try successData(from: result)
        #expect(data["source"]?.stringValue == "oslog")
        #expect(data["api"]?.stringValue == "Logger")
        #expect(data["message"]?.stringValue == message)
    }
    #endif

}

private func successData(from result: ExploreResult) throws -> JSON {
    guard case .success(let data) = result else {
        throw TestFailure("expected success")
    }
    return data
}

private struct TestFailure: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
