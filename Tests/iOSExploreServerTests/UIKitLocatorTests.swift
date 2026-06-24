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

    @Test("UIKitLocator 统一 identifier path 和坐标")
    func uikitLocatorParsesAllForms() throws {
        #expect(try UIKitLocator.parse(identifier: "home.submit", path: nil, x: nil, y: nil) ==
            .accessibilityIdentifier("home.submit"))
        #expect(try UIKitLocator.parse(identifier: nil, path: "root/0/2", x: nil, y: nil) ==
            .path([0, 2]))
        #expect(try UIKitLocator.parse(identifier: nil, path: "root", x: nil, y: nil) ==
            .path([]))
        #expect(try UIKitLocator.parse(identifier: nil, path: nil, x: 24, y: 48) ==
            .windowPoint(x: 24, y: 48))
    }

    @Test("view locator 与 window point 互斥")
    func uikitLocatorRejectsMixedLocators() {
        expectQueryFailure("view locator and window point are mutually exclusive") {
            try UIKitLocator.parse(identifier: "home", path: nil, x: 1, y: 2)
        }
        expectQueryFailure("view locator and window point are mutually exclusive") {
            try UIKitLocator.parse(identifier: nil, path: "root/0", x: 1, y: 2)
        }
    }

    @Test("window point 必须成对提供 x 和 y")
    func uikitLocatorRequiresBothCoordinates() {
        expectQueryFailure("x and y must be provided together") {
            try UIKitLocator.parse(identifier: nil, path: nil, x: 1, y: nil)
        }
        expectQueryFailure("x and y must be provided together") {
            try UIKitLocator.parse(identifier: nil, path: nil, x: nil, y: 2)
        }
    }

    @Test("identifier 与 path 互斥且必须提供其一")
    func uikitLocatorEnforcesIdentifierPathExclusivity() {
        expectQueryFailure("accessibilityIdentifier and path are mutually exclusive") {
            try UIKitLocator.parse(identifier: "home", path: "root/0", x: nil, y: nil)
        }
        expectQueryFailure("accessibilityIdentifier must not be empty") {
            try UIKitLocator.parse(identifier: "", path: nil, x: nil, y: nil)
        }
        expectQueryFailure("path must be root or root/<non-negative-index>/...") {
            try UIKitLocator.parse(identifier: nil, path: "bad/path", x: nil, y: nil)
        }
        expectQueryFailure("either accessibilityIdentifier or path is required") {
            try UIKitLocator.parse(identifier: nil, path: nil, x: nil, y: nil)
        }
    }
}

/// 断言 parse 闭包抛出 `QueryParseError` 且对外文案精确匹配。
///
/// 保留对错误消息字符串的断言，确保 `invalid_data` envelope 文案不随重构漂移。
private func expectQueryFailure<T>(_ message: String, _ body: () throws -> T) {
    do {
        _ = try body()
        Issue.record("expected parse failure: \(message)")
    } catch let error as QueryParseError {
        #expect(error.message == message)
    } catch {
        Issue.record("expected QueryParseError, got: \(error)")
    }
}
