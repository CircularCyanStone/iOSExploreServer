import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

@Test("scrollToElement 默认 match text 且 value 必填")
func scrollToElementDefaults() throws {
    let input = try UIScrollToElementInput.parse(from: ["value": "订单"])
    #expect(input.match == .text)
    #expect(input.value == "订单")
    #expect(input.container == nil)
    #expect(input.animated == false)
}

@Test("scrollToElement 缺 value 抛错")
func scrollToElementRequiresValue() {
    #expect(throws: Error.self) {
        try UIScrollToElementInput.parse(from: ["match": "text"])
    }
}

@Test("scrollToElement 接受 identifier 容器")
func scrollToElementAcceptsContainer() throws {
    let input = try UIScrollToElementInput.parse(from: [
        "match": "accessibilityIdentifier",
        "value": "submit",
        "accessibilityIdentifier": "list",
    ])
    #expect(input.match == .accessibilityIdentifier)
    #expect(input.container != nil)
}
