#if canImport(UIKit)
import UIKit
import iOSExploreServer

/// canonical target 的稳定语义摘要哈希构造器。
///
/// 按固定字段顺序收集与动作路由相关的稳定语义（类型、role、a11y label/value、按钮标题、
/// 输入占位、switch isOn、slider value、segment 选择、默认激活路由），用 FNV-1a 混合成单个
/// `UInt64`，写入 `UIKitTargetFingerprint.semanticDigest`。
///
/// 设计目标（spec §9.1 / final-refactor-plan §7.1）：
/// - **只存哈希，不存业务明文**——snapshot store 与日志都不接触原文；
/// - **会改变 Agent 对目标含义或默认激活风险的字段才纳入**：按钮标题从「提交」变「删除」、
///   switch 状态翻转、segment 选择变化都会改变 digest；
/// - **高频瞬态视觉状态不纳入**：highlighted、tracking 等不进 digest，避免无谓 stale；
/// - **相同语义重复采集必须稳定**——同 view 同状态多次采集得到相同 digest。
///
/// 该类型是 `@MainActor`（读取 UIView 属性），只在 UIKit 隔离域调用。
@MainActor
enum UIKitTargetSemanticDigest {
    /// 计算 view 的语义摘要哈希。
    ///
    /// - Parameter view: canonical target 真实 view。
    /// - Returns: 稳定的 64 位语义摘要哈希。
    static func digest(for view: UIView) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325

        func mix(_ part: String) {
            for byte in part.utf8 {
                hash ^= UInt64(byte)
                hash &*= 0x100000001b3
            }
        }

        mix("type=\(String(describing: Swift.type(of: view)))")
        mix("role=\(UIViewTargetsCollector.role(for: view).rawValue)")
        mix("id=\(UIKitTargetFingerprint.stableHash(view.accessibilityIdentifier ?? ""))")
        mix("label=\(UIKitTargetFingerprint.stableHash(view.accessibilityLabel ?? ""))")
        mix("value=\(UIKitTargetFingerprint.stableHash(view.accessibilityValue ?? ""))")

        if let button = view as? UIButton {
            let title = button.title(for: .normal) ?? button.currentTitle ?? ""
            mix("buttonTitle=\(UIKitTargetFingerprint.stableHash(title))")
        }
        if let field = view as? UITextField {
            mix("placeholder=\(UIKitTargetFingerprint.stableHash(field.placeholder ?? ""))")
        }
        if let textView = view as? UITextView {
            mix("textViewEditable=\(textView.isEditable)")
        }
        if let switchView = view as? UISwitch {
            mix("switchOn=\(switchView.isOn)")
        }
        if let slider = view as? UISlider {
            // 有限精度摘要：千分位四舍五入，吸收微小浮点抖动。
            let rounded = (Double(slider.value) * 1000.0).rounded() / 1000.0
            mix("sliderValue=\(rounded)")
        }
        if let segmented = view as? UISegmentedControl {
            mix("segmentIndex=\(segmented.selectedSegmentIndex)")
        }

        if let route = UIKitDefaultActivationResolver.route(for: view) {
            mix("activationRoute=\(route.rawValue)")
        } else {
            mix("activationRoute=none")
        }
        return hash
    }
}
#endif
