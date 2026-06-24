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
        UIKitCommandLogging.info("command", "ui view targets collect mainactor start includeHidden=\(query.includeHidden) includeDisabled=\(query.includeDisabled) includeStaticText=\(query.includeStaticText) includeContainers=\(query.includeContainers) maxDepth=\(query.maxDepth.map(String.init) ?? "none") hasFilter=\(query.hasIdentifierFilter) textLimit=\(query.textLimit)")

        let context: UIKitContextProvider.Context
        switch UIKitContextProvider.currentContext() {
        case .success(let value):
            context = value
        case .failure(let reason):
            let error = UIKitCommandError.hierarchyUnavailable(action: ViewTargetsCommand.actionName,
                                                               reason: reason)
            UIKitCommandLogging.error("command", error.failure.logMessage)
            return error.result
        }

        var visitedNodeCount = 0
        var targets: [UIViewTargetSummary] = []
        var fingerprints: [String: UIKitTargetFingerprint] = [:]
        let digest = UIKitFingerprintCollector.digest(topViewController: context.topViewController)
        let truncated = collect(view: context.rootView,
                rootView: context.rootView,
                window: context.window,
                path: [],
                depth: 0,
                query: query,
                visitedNodeCount: &visitedNodeCount,
                targets: &targets,
                fingerprints: &fingerprints,
                digest: digest)

        let snapshotID = UIKitSnapshotStore.shared.insert(context: UIKitFingerprintCollector.context(window: context.window, topViewController: context.topViewController),
                                                          targets: fingerprints)
        let snapshotFields = UIKitSnapshotResponse.fields(for: snapshotID)
        let data: JSON = [
            "screen": .object(screenJSON(window: context.window,
                                         rootViewController: context.rootViewController,
                                         topViewController: context.topViewController)),
            "targetCount": .double(Double(targets.count)),
            "visitedNodeCount": .double(Double(visitedNodeCount)),
            "targets": .array(targets.map { .object($0.toJSON()) }),
            "maxTargets": .double(Double(query.maxTargets)),
            "truncated": .bool(truncated),
            "truncationReason": truncated ? .string("maxTargets") : .null,
            "snapshotID": snapshotFields.id,
            "snapshotUnavailableReason": snapshotFields.unavailableReason,
        ]
        UIKitCommandLogging.info("command", "ui view targets collect completed visitedNodeCount=\(visitedNodeCount) targetCount=\(targets.count) topViewController=\(String(describing: type(of: context.topViewController)))")
        return .success(data)
    }

    /// 递归遍历 view 树，并把符合输出策略和筛选条件的节点加入 targets。
    ///
    /// identifier 筛选只影响当前节点是否输出，不会提前剪枝子树，避免漏掉深层控件。
    /// 隐藏节点在 `includeHidden=false` 时会剪枝整棵子树，避免隐藏容器下的控件被误返回。
    private static func collect(view: UIView,
                                rootView: UIView,
                                window: UIWindow,
                                path: [Int],
                                depth: Int,
                                query: UIViewTargetsQuery,
                                visitedNodeCount: inout Int,
                                targets: inout [UIViewTargetSummary],
                                fingerprints: inout [String: UIKitTargetFingerprint],
                                digest: String) -> Bool {
        visitedNodeCount += 1
        if !query.includeHidden, view.isHidden {
            return false
        }

        if shouldInclude(view: view, query: query),
           matchesIdentifier(view: view, query: query) {
            let summary = summary(for: view, rootView: rootView, window: window, path: path, query: query)
            targets.append(summary)
            fingerprints[summary.path] = UIKitFingerprintCollector.fingerprint(for: view, path: summary.path, rootView: rootView, digest: digest)
            if targets.count >= query.maxTargets { return true }
        }

        if let maxDepth = query.maxDepth, depth >= maxDepth {
            return false
        }

        for (index, child) in view.subviews.enumerated() {
            if collect(view: child,
                    rootView: rootView,
                    window: window,
                    path: path + [index],
                    depth: depth + 1,
                    query: query,
                    visitedNodeCount: &visitedNodeCount,
                    targets: &targets,
                    fingerprints: &fingerprints,
                    digest: digest) { return true }
        }
        return false
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
                                rootView: UIView,
                                window: UIWindow,
                                path: [Int],
                                query: UIViewTargetsQuery) -> UIViewTargetSummary {
        let control = view as? UIControl
        let frame = view.convert(view.bounds, to: window)
        // identifier 完整保留：它是事件下发的稳定定位键，裁断会让后续 tap/sendAction 失配。
        // 仅 title/label/text/placeholder/value 这些展示型文本按 textLimit 裁剪。
        return UIViewTargetSummary(
            path: UIKitViewLookupTarget.pathString(from: path),
            type: String(describing: Swift.type(of: view)),
            role: role(for: view),
            accessibilityIdentifier: view.accessibilityIdentifier,
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
                                     hasGestureRecognizers: view.gestureRecognizers?.isEmpty == false),
            availableActions: availableActions(for: view, rootView: rootView)
        )
    }

    /// 计算 path-target 的可执行动作，供 `summary` 与可测入口共用。
    ///
    /// 与 `UIKitActionExecutor` 的 view-tap 语义保持一致是本方法的核心约束：第一版 executor 只
    /// 对目标自身为 `UIControl` 的 path 派发事件，因此能力声明只认目标自身的 control 身份，
    /// 不向上借用祖先 control——否则会出现 collector 声明可 tap、executor 按 path 派发却返回
    /// `unsupportedTarget` 的分叉。
    ///
    /// - Parameters:
    ///   - view: 被采集/点击的目标 view。
    ///   - rootView: 当前查询上下文的根 view，用于祖先交互性校验。
    /// - Returns: 目标当前可执行的动作集合；非 control、不可交互或 disabled 时为空。
    static func availableActions(for view: UIView, rootView: UIView) -> UIKitActionAvailability {
        UIKitActionCapabilityResolver.resolve(view: view,
                                              rootView: rootView,
                                              nearestControl: view as? UIControl)
    }

    /// 识别轻量目标角色，用于给 agent 返回建议动作。
    ///
    /// 对 executor 上的陈旧指纹重采也可见（fingerprint 需要 role 字段），故为模块内可见。
    static func role(for view: UIView) -> UIViewTargetRole {
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
