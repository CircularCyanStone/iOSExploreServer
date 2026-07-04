import Foundation
import Testing
@testable import iOSExploreUIKit

@Suite
struct UIKitLocatorTests {

    @Test("identifier 日志摘要不泄露原始值")
    func identifierLogSummaryIsRedacted() {
        let identifier = "secret.identifier.9F8E7D"
        let summary = UIKitViewLookupTarget.accessibilityIdentifier(identifier).logSummary
        #expect(summary.contains(identifier) == false)
        #expect(summary.contains("length=24"))
    }

    @Test("UIKitLocator 解析 identifier 与 path")
    func uikitLocatorParsesIdentifierAndPath() throws {
        #expect(try UIKitLocator.parse(identifier: "home.submit", rawPath: nil) ==
            .accessibilityIdentifier("home.submit"))
        #expect(try UIKitLocator.parse(identifier: nil, rawPath: "root/0/2") ==
            .path([0, 2]))
        #expect(try UIKitLocator.parse(identifier: nil, rawPath: "root") ==
            .path([]))
    }

    @Test("identifier 与 path 互斥且必须提供其一")
    func uikitLocatorEnforcesIdentifierPathExclusivity() {
        expectQueryFailure("accessibilityIdentifier and path are mutually exclusive") {
            try UIKitLocator.parse(identifier: "home", rawPath: "root/0")
        }
        expectQueryFailure("accessibilityIdentifier must not be empty") {
            try UIKitLocator.parse(identifier: "", rawPath: nil)
        }
        expectQueryFailure("path must be root or root/<non-negative-index>/...") {
            try UIKitLocator.parse(identifier: nil, rawPath: "bad/path")
        }
        expectQueryFailure("either accessibilityIdentifier or path is required") {
            try UIKitLocator.parse(identifier: nil, rawPath: nil)
        }
    }
}

/// 断言 parse 闭包抛出 `UIKitLocatorParseError` 且对外文案精确匹配。
///
/// 保留对错误消息字符串的断言，确保 `invalid_data` envelope 文案不随重构漂移。
private func expectQueryFailure<T>(_ message: String, _ body: () throws -> T) {
    do {
        _ = try body()
        Issue.record("expected parse failure: \(message)")
    } catch let error as UIKitLocatorParseError {
        #expect(error.message == message)
    } catch {
        Issue.record("expected UIKitLocatorParseError, got: \(error)")
    }
}
