import Foundation
import Testing
@testable import iOSExploreUIKit

@Suite
struct UIKitLocatorTests {
    @Test("UIKitLocator 统一 identifier path 和坐标")
    func uikitLocatorParsesAllForms() {
        #expect(UIKitLocator.parse(identifier: "home.submit", path: nil, x: nil, y: nil) ==
            .success(.accessibilityIdentifier("home.submit")))
        #expect(UIKitLocator.parse(identifier: nil, path: "root/0/2", x: nil, y: nil) ==
            .success(.path([0, 2])))
        #expect(UIKitLocator.parse(identifier: nil, path: "root", x: nil, y: nil) ==
            .success(.path([])))
        #expect(UIKitLocator.parse(identifier: nil, path: nil, x: 24, y: 48) ==
            .success(.windowPoint(x: 24, y: 48)))
    }

    @Test("view locator 与 window point 互斥")
    func uikitLocatorRejectsMixedLocators() {
        #expect(UIKitLocator.parse(identifier: "home", path: nil, x: 1, y: 2) ==
            .failure("view locator and window point are mutually exclusive"))
        #expect(UIKitLocator.parse(identifier: nil, path: "root/0", x: 1, y: 2) ==
            .failure("view locator and window point are mutually exclusive"))
    }

    @Test("window point 必须成对提供 x 和 y")
    func uikitLocatorRequiresBothCoordinates() {
        #expect(UIKitLocator.parse(identifier: nil, path: nil, x: 1, y: nil) ==
            .failure("x and y must be provided together"))
        #expect(UIKitLocator.parse(identifier: nil, path: nil, x: nil, y: 2) ==
            .failure("x and y must be provided together"))
    }

    @Test("identifier 与 path 互斥且必须提供其一")
    func uikitLocatorEnforcesIdentifierPathExclusivity() {
        #expect(UIKitLocator.parse(identifier: "home", path: "root/0", x: nil, y: nil) ==
            .failure("accessibilityIdentifier and path are mutually exclusive"))
        #expect(UIKitLocator.parse(identifier: "", path: nil, x: nil, y: nil) ==
            .failure("accessibilityIdentifier must not be empty"))
        #expect(UIKitLocator.parse(identifier: nil, path: "bad/path", x: nil, y: nil) ==
            .failure("path must be root or root/<non-negative-index>/..."))
        #expect(UIKitLocator.parse(identifier: nil, path: nil, x: nil, y: nil) ==
            .failure("either accessibilityIdentifier or path is required"))
    }
}
