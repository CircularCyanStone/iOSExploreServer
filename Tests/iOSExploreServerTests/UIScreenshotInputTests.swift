import Testing
@testable import iOSExploreServer
@testable import iOSExploreUIKit

/// `UIScreenshotInput` 的 schema/parse 测试。
///
/// `UIScreenshotInput` 保持 Foundation-only（无 `#if canImport(UIKit)`），因此本测试在
/// macOS SPM 与 iOS framework 工程下均可运行，覆盖默认值、合法值与越界拒绝。
@Test("UIScreenshotInput: maxDimension 默认 1280，范围 1-4096")
func screenshotInputDefaults() throws {
    #expect(try UIScreenshotInput.parse(from: JSON([:])).maxDimension == 1280)
    #expect(try UIScreenshotInput.parse(from: JSON(["maxDimension": 2000])).maxDimension == 2000)
    #expect(throws: CommandInputParseError.self) {
        _ = try UIScreenshotInput.parse(from: JSON(["maxDimension": 0]))
    }
    #expect(throws: CommandInputParseError.self) {
        _ = try UIScreenshotInput.parse(from: JSON(["maxDimension": 99999]))
    }
}

@Test("UIScreenshotInput schema 暴露 maxDimension 的默认值与 1-4096 范围")
func screenshotInputSchemaMatchesParserRange() throws {
    let schema = UIScreenshotInput.inputSchema.toJSON()
    guard case .object(let properties)? = schema["properties"],
          case .object(let maxDimension)? = properties["maxDimension"] else {
        Issue.record("maxDimension schema missing")
        return
    }

    #expect(maxDimension["default"]?.doubleValue == 1280)
    #expect(maxDimension["minimum"]?.doubleValue == 1)
    #expect(maxDimension["maximum"]?.doubleValue == 4096)
}
