import Testing
@testable import iOSExploreServer
@testable import iOSExploreUIKit

/// `UIInspectSummary.isMinimal` + `toJSON` 分档测试。
///
/// minimal 档仅输出 `{path, type}`，用于 collector 把无识别信息的结构节点（如
/// `UITableViewCell` 内层 `UIView`）暴露给 agent 做结构遍历，但不签 fingerprint、
/// 不引诱 agent 对其执行 tap 等操作；full 档输出全部字段，行为与改造前完全一致。
@Suite("UIInspectSummary isMinimal 分档")
struct UIInspectSummaryTests {
    @Test("minimal 档 toJSON 只含 path + type")
    func minimalToJSONOnlyPathAndType() throws {
        let summary = Self.makeSummary(path: "root/5/0", type: "UITableViewCell", isMinimal: true)
        let json = summary.toJSON()

        let keys = Set(json.storage.keys)
        #expect(keys == ["path", "type"], "minimal 档只应输出 path 与 type，实际: \(keys)")
        #expect(json["path"]?.stringValue == "root/5/0")
        #expect(json["type"]?.stringValue == "UITableViewCell")
        // minimal 档必须缺席 full 档的字段（不是 null，是完全不出现）
        #expect(json["frame"] == nil)
        #expect(json["role"] == nil)
        #expect(json["availableActions"] == nil)
        #expect(json["isHidden"] == nil)
    }

    @Test("full 档 toJSON 输出全部字段（与现状一致，无回归）")
    func fullToJSONIncludesAllFields() throws {
        let summary = Self.makeSummary(path: "root/1", type: "UILabel",
                                       text: "hello",
                                       accessibilityIdentifier: "label.title",
                                       isMinimal: false)
        let json = summary.toJSON()
        let keys = Set(json.storage.keys)

        // 结构字段
        #expect(keys.contains("path"))
        #expect(keys.contains("type"))
        #expect(keys.contains("role"))
        #expect(keys.contains("frame"))
        // 语义字段
        #expect(keys.contains("accessibilityIdentifier"))
        #expect(keys.contains("text"))
        // 状态字段
        #expect(keys.contains("isHidden"))
        #expect(keys.contains("alpha"))
        #expect(keys.contains("isUserInteractionEnabled"))
        // 动作字段
        #expect(keys.contains("availableActions"))
        // 值抽检
        #expect(json["path"]?.stringValue == "root/1")
        #expect(json["type"]?.stringValue == "UILabel")
        #expect(json["text"]?.stringValue == "hello")
        #expect(json["accessibilityIdentifier"]?.stringValue == "label.title")
        #expect(json["role"]?.stringValue == "container")
    }

    @Test("isMinimal 默认 false（现有构造点不传仍 full）")
    func isMinimalDefaultsFalse() {
        // 不传 isMinimal —— 模拟 collector 现有所有构造点
        let summary = UIInspectSummary(
            path: "root/2",
            type: "UIView",
            role: .container,
            accessibilityIdentifier: nil,
            accessibilityLabel: nil,
            title: nil,
            text: nil,
            placeholder: nil,
            value: nil,
            frame: UIViewHierarchyRect(x: 0, y: 0, width: 100, height: 50),
            state: UIInspectState(isHidden: false,
                                     alpha: 1,
                                     isUserInteractionEnabled: true,
                                     isEnabled: true,
                                     isSelected: false,
                                     isHighlighted: false,
                                     hasGestureRecognizers: false)
        )
        #expect(summary.isMinimal == false, "isMinimal 必须默认 false，否则破坏现有 collector 行为")
        // 默认 full：toJSON 必须含 frame（minimal 档会缺席的字段）
        #expect(summary.toJSON()["frame"] != nil, "默认 full 档必须输出 frame")
    }

    // MARK: - Fixture

    /// 构造测试用 summary。`isMinimal` 默认 false 与生产 init 一致；显式传 true 走 minimal 档。
    static func makeSummary(path: String,
                            type: String,
                            text: String? = "hello",
                            accessibilityIdentifier: String? = "label.title",
                            isMinimal: Bool = false) -> UIInspectSummary {
        UIInspectSummary(
            path: path,
            type: type,
            role: .container,
            accessibilityIdentifier: accessibilityIdentifier,
            accessibilityLabel: nil,
            title: nil,
            text: text,
            placeholder: nil,
            value: nil,
            frame: UIViewHierarchyRect(x: 0, y: 0, width: 100, height: 50),
            state: UIInspectState(isHidden: false,
                                     alpha: 1,
                                     isUserInteractionEnabled: true,
                                     isEnabled: true,
                                     isSelected: false,
                                     isHighlighted: false,
                                     hasGestureRecognizers: false),
            isMinimal: isMinimal
        )
    }
}
