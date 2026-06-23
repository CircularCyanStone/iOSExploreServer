#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// UIKit 轻量目标采集器。
///
/// 采集器运行在 `MainActor`，从当前顶部控制器根 view 递归读取事件下发需要的目标摘要。
/// 它刻意不复用完整层级快照，避免读取颜色、字体、图片等高成本验收字段。
@MainActor
enum UIViewTargetsCollector {
    /// 采集当前顶部控制器 view 下的轻量目标列表。
    ///
    /// - Parameter query: 查询参数，控制包含策略、递归深度、identifier 筛选和文本长度。
    /// - Returns: 成功时返回 screen、targetCount、visitedNodeCount 与 targets；失败时返回业务失败 envelope。
    static func collect(query: UIViewTargetsQuery) -> ExploreResult {
        ExploreLogger.info(.command, "ui view targets collect mainactor start includeHidden=\(query.includeHidden) includeDisabled=\(query.includeDisabled) includeStaticText=\(query.includeStaticText) includeContainers=\(query.includeContainers) maxDepth=\(query.maxDepth.map(String.init) ?? "none") hasFilter=\(query.hasIdentifierFilter) textLimit=\(query.textLimit)")

        let context: UIKitViewLookup.Context
        switch UIKitViewLookup.currentContext() {
        case .success(let value):
            context = value
        case .failure(let reason):
            let error = ExploreServerError.uiHierarchyUnavailable(action: ViewTargetsCommand.actionName,
                                                                  reason: reason)
            ExploreLogger.error(.command, error.logMessage)
            return .failure(code: error.code, message: error.message)
        }

        var visitedNodeCount = 0
        var targets: [UIViewTargetSummary] = []
        collect(view: context.rootView,
                window: context.window,
                path: [],
                depth: 0,
                query: query,
                visitedNodeCount: &visitedNodeCount,
                targets: &targets)

        let data: JSON = [
            "screen": .object(screenJSON(window: context.window,
                                         rootViewController: context.rootViewController,
                                         topViewController: context.topViewController)),
            "targetCount": .double(Double(targets.count)),
            "visitedNodeCount": .double(Double(visitedNodeCount)),
            "targets": .array(targets.map { .object($0.toJSON()) }),
        ]
        ExploreLogger.info(.command, "ui view targets collect completed visitedNodeCount=\(visitedNodeCount) targetCount=\(targets.count) topViewController=\(String(describing: type(of: context.topViewController)))")
        return .success(data)
    }

    /// 递归遍历 view 树，并把符合输出策略和筛选条件的节点加入 targets。
    ///
    /// identifier 筛选只影响当前节点是否输出，不会提前剪枝子树，避免漏掉深层控件。
    /// 隐藏节点在 `includeHidden=false` 时会剪枝整棵子树，避免隐藏容器下的控件被误返回。
    private static func collect(view: UIView,
                                window: UIWindow,
                                path: [Int],
                                depth: Int,
                                query: UIViewTargetsQuery,
                                visitedNodeCount: inout Int,
                                targets: inout [UIViewTargetSummary]) {
        visitedNodeCount += 1
        if !query.includeHidden, view.isHidden {
            return
        }

        if shouldInclude(view: view, query: query),
           matchesIdentifier(view: view, query: query) {
            targets.append(summary(for: view, window: window, path: path, query: query))
        }

        if let maxDepth = query.maxDepth, depth >= maxDepth {
            return
        }

        for (index, child) in view.subviews.enumerated() {
            collect(view: child,
                    window: window,
                    path: path + [index],
                    depth: depth + 1,
                    query: query,
                    visitedNodeCount: &visitedNodeCount,
                    targets: &targets)
        }
    }

    /// 判断 view 是否符合默认或可选输出策略。
    private static func shouldInclude(view: UIView, query: UIViewTargetsQuery) -> Bool {
        let control = view as? UIControl
        let candidate = UIViewTargetCandidate(
            isHidden: view.isHidden,
            isControl: control != nil,
            isEnabled: control?.isEnabled ?? true,
            isUserInteractionEnabled: view.isUserInteractionEnabled,
            hasGestureRecognizers: view.gestureRecognizers?.isEmpty == false,
            hasAccessibilityIdentifier: view.accessibilityIdentifier?.isEmpty == false,
            hasAccessibilityLabel: view.accessibilityLabel?.isEmpty == false,
            hasStaticText: textualValue(from: view)?.isEmpty == false,
            hasSubviews: !view.subviews.isEmpty
        )
        return query.shouldInclude(candidate: candidate)
    }

    /// 判断当前 view 是否通过 identifier 输出筛选。
    private static func matchesIdentifier(view: UIView, query: UIViewTargetsQuery) -> Bool {
        guard query.hasIdentifierFilter else { return true }
        let identifier = view.accessibilityIdentifier
        if let expected = query.accessibilityIdentifier, identifier == expected {
            return true
        }
        if let prefix = query.accessibilityIdentifierPrefix, identifier?.hasPrefix(prefix) == true {
            return true
        }
        return false
    }

    /// 从 UIKit view 生成轻量目标摘要。
    private static func summary(for view: UIView,
                                window: UIWindow,
                                path: [Int],
                                query: UIViewTargetsQuery) -> UIViewTargetSummary {
        let control = view as? UIControl
        let frame = view.convert(view.bounds, to: window)
        return UIViewTargetSummary(
            path: UIKitViewLookupTarget.pathString(from: path),
            type: String(describing: Swift.type(of: view)),
            role: role(for: view),
            accessibilityIdentifier: UIViewTargetText.limited(view.accessibilityIdentifier, limit: query.textLimit),
            accessibilityLabel: UIViewTargetText.limited(view.accessibilityLabel, limit: query.textLimit),
            title: UIViewTargetText.limited(title(from: view), limit: query.textLimit),
            text: UIViewTargetText.limited(textualValue(from: view), limit: query.textLimit),
            placeholder: UIViewTargetText.limited(placeholder(from: view), limit: query.textLimit),
            value: UIViewTargetText.limited(value(from: view), limit: query.textLimit),
            frame: UIViewHierarchyRect(rect: frame),
            state: UIViewTargetState(isHidden: view.isHidden,
                                     alpha: Double(view.alpha),
                                     isUserInteractionEnabled: view.isUserInteractionEnabled,
                                     isEnabled: control?.isEnabled,
                                     isSelected: control?.isSelected,
                                     isHighlighted: control?.isHighlighted,
                                     hasGestureRecognizers: view.gestureRecognizers?.isEmpty == false)
        )
    }

    /// 识别轻量目标角色，用于给 agent 返回建议动作。
    private static func role(for view: UIView) -> UIViewTargetRole {
        if view is UIButton { return .button }
        if view is UISwitch { return .switch }
        if view is UISlider { return .slider }
        if view is UISegmentedControl { return .segmentedControl }
        if view is UITextField { return .textField }
        if view is UITextView { return .textView }
        if view is UILabel { return .label }
        if view is UIImageView { return .imageView }
        if !view.subviews.isEmpty { return .container }
        return .view
    }

    /// 提取控件标题，不记录完整内容到日志。
    private static func title(from view: UIView) -> String? {
        if let button = view as? UIButton {
            return button.title(for: .normal) ?? button.currentTitle
        }
        if let segmented = view as? UISegmentedControl, segmented.selectedSegmentIndex >= 0 {
            return segmented.titleForSegment(at: segmented.selectedSegmentIndex)
        }
        return nil
    }

    /// 提取非编辑型可见文本，调用方负责按 query 裁剪。
    ///
    /// `UITextField` 与 `UITextView` 可能承载密码或用户输入，默认目标发现不返回其内容。
    private static func textualValue(from view: UIView) -> String? {
        if let label = view as? UILabel { return label.text }
        return nil
    }

    /// 提取输入占位文本，调用方负责按 query 裁剪。
    private static func placeholder(from view: UIView) -> String? {
        (view as? UITextField)?.placeholder
    }

    /// 提取控件当前值，避免返回可编辑输入内容或大块用户输入。
    private static func value(from view: UIView) -> String? {
        if view is UITextField || view is UITextView { return nil }
        if let switchView = view as? UISwitch { return switchView.isOn ? "on" : "off" }
        if let slider = view as? UISlider { return String(Double(slider.value)) }
        if let segmented = view as? UISegmentedControl { return String(segmented.selectedSegmentIndex) }
        return view.accessibilityValue
    }

    /// 生成屏幕上下文摘要。
    private static func screenJSON(window: UIWindow,
                                   rootViewController: UIViewController,
                                   topViewController: UIViewController) -> JSON {
        [
            "windowType": .string(String(describing: type(of: window))),
            "rootViewController": .string(String(describing: type(of: rootViewController))),
            "topViewController": .string(String(describing: type(of: topViewController))),
        ]
    }
}

private extension UIViewHierarchyRect {
    /// 从 UIKit 矩形转换为协议矩形。
    init(rect: CGRect) {
        self.init(x: Double(rect.origin.x),
                  y: Double(rect.origin.y),
                  width: Double(rect.size.width),
                  height: Double(rect.size.height))
    }
}
#endif
