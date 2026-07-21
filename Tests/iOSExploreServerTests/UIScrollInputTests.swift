import Testing
@testable import iOSExploreServer
@testable import iOSExploreUIKit

/// `UIScrollInput` 的 schema/parse 测试。
///
/// `UIScrollInput`（含 `ScrollDirection` / `ScrollExtent`）保持 Foundation-only
/// （无 `#if canImport(UIKit)`），因此本测试在 macOS SPM 与 iOS framework 工程下均可运行，
/// 覆盖 direction 必填、amount 必须 > 0、定位字段可缺省以及 viewSnapshotID 可选陈旧校验规则。

@Test("UIScrollInput: direction 必填；amount>0；target 可缺；animated 默认 false")
func scrollInputParse() throws {
    let input = try UIScrollInput.parse(from: JSON(["direction": "down"]))
    #expect(input.direction == .down)
    #expect(input.amount == nil)
    #expect(input.locator == nil)
    #expect(input.animated == false)
}

@Test("UIScrollInput: amount<=0 抛解析错误")
func scrollInputRejectsNonPositiveAmount() {
    #expect(throws: CommandInputParseError.self) {
        _ = try UIScrollInput.parse(from: JSON(["direction": "down", "amount": -1]))
    }
    #expect(throws: CommandInputParseError.self) {
        _ = try UIScrollInput.parse(from: JSON(["direction": "down", "amount": 0]))
    }
}

@Test("UIScrollInput: 缺 direction 抛解析错误")
func scrollInputRejectsMissingDirection() {
    #expect(throws: CommandInputParseError.self) {
        _ = try UIScrollInput.parse(from: JSON([:]))
    }
}

@Test("UIScrollInput: viewSnapshotID 搭配 identifier 合法（与 ui.tap 一致）")
func scrollInputAcceptsViewSnapshotIDWithIdentifier() throws {
    let input = try UIScrollInput.parse(from: [
        "accessibilityIdentifier": "field.test",
        "direction": "down",
        "viewSnapshotID": "test_snapshot",
    ])
    #expect(input.viewSnapshotID == "test_snapshot")
    #expect(input.locator == .accessibilityIdentifier("field.test"))
}

@Test("UIScrollInput: path 定位 + viewSnapshotID 合法解析")
func scrollInputParsesPathWithViewSnapshotID() throws {
    let input = try UIScrollInput.parse(from: [
        "path": "root/0",
        "direction": "up",
        "viewSnapshotID": "view_snapshot_test",
        "animated": true,
    ])
    #expect(input.direction == .up)
    #expect(input.locator == .path([0]))
    #expect(input.viewSnapshotID == "view_snapshot_test")
    #expect(input.animated == true)
}

@Test("UIScrollInput schema 声明字段顺序与方向枚举值")
func scrollInputSchemaFieldsAndDirectionValues() {
    #expect(UIScrollInput.inputSchema.fields.map(\.name) == [
        "direction",
        "amount",
        "accessibilityIdentifier",
        "path",
        "viewSnapshotID",
        "animated",
    ])
    // ScrollDirection 与 ScrollExtent 各自独立枚举，rawValue 集合互相对应四向。
    #expect(Set(ScrollDirection.allCases.map(\.rawValue)) == ["up", "down", "left", "right"])
}
