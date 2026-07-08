#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// UIKit 轻量目标采集器。
///
/// 采集器运行在 `MainActor`，从当前顶部控制器根 view 递归读取 canonical interaction target
/// 摘要。它刻意不复用完整层级快照，避免读取颜色、字体、图片等高成本验收字段。
///
/// 重构后的核心不变式（spec §7）：`ui.viewTargets` 最终返回的 canonical target path 集合
/// **等于** `viewSnapshotID` 内签发 fingerprint 的 path 集合，也**等于** `ui.tap` /
/// `ui.control.sendAction` 允许操作的 path 集合。为此采集器先完成所有筛选与 `maxTargets`
/// 截断，再只为最终返回的 target 逐个采集指纹并签发，禁止签发未返回的 path（否则 Agent 仍
/// 可猜 path 执行）。
@MainActor
enum UIViewTargetsCollector {
    /// 采集当前顶部控制器 view 下的轻量目标列表。
    ///
    /// - Parameter query: 查询参数，控制包含策略、递归深度、identifier 筛选和文本长度。
    /// - Returns: screen、targetCount、visitedNodeCount、targets、viewSnapshotID 的 JSON。
    /// - Throws: `UIKitCommandError.hierarchyUnavailable`——UIKit 上下文不可用时。
    static func collect(query: UIViewTargetsInput) throws -> JSON {
        UIKitCommandLogging.info("command", "ui view targets collect mainactor start includeHidden=\(query.includeHidden) maxDepth=\(query.maxDepth.map(String.init) ?? "none") hasFilter=\(query.hasIdentifierFilter) textLimit=\(query.textLimit)")
        let context = try UIKitContextProvider.currentContext(action: ViewTargetsCommand.actionName)
        return collect(query: query, context: context)
    }

    /// 采集轻量目标列表（注入入口：测试与内部复用）。
    ///
    /// 与 `collect(query:)` 的唯一区别是上下文由调用方提供，使采集流程可在测试里用可控
    /// view 树驱动。其余逻辑（遍历、canonical 筛选、maxTargets 截断、按返回集合签发指纹）
    /// 完全一致。
    ///
    /// - Parameters:
    ///   - query: 查询参数。
    ///   - context: 当前 UIKit 查询上下文。
    /// - Returns: targets 列表 JSON（含 viewSnapshotID）。
    static func collect(query: UIViewTargetsInput, context: UIKitContextProvider.Context) -> JSON {
        var visitedNodeCount = 0
        var collected: [CollectedTarget] = []
        let digest = UIKitFingerprintCollector.digest(topViewController: context.topViewController)
        let truncated = collect(view: context.rootView,
                rootView: context.rootView,
                window: context.window,
                path: [],
                depth: 0,
                query: query,
                visitedNodeCount: &visitedNodeCount,
                collected: &collected)

        // 只为最终返回（含 maxTargets 截断）的 canonical target 签发指纹：
        // returned target paths == viewSnapshotID 签发 fingerprint paths == tap/sendAction 可执行集合。
        let snapContext = UIKitFingerprintCollector.context(window: context.window,
                                                             topViewController: context.topViewController)
        let fingerprints = Dictionary(
            uniqueKeysWithValues: collected.map { target in
                (target.summary.path,
                 UIKitFingerprintCollector.fingerprint(for: target.view,
                                                        path: target.summary.path,
                                                        rootView: context.rootView,
                                                        digest: digest))
            }
        )
        let viewSnapshotID = UIKitSnapshotStore.shared.insert(context: snapContext,
                                                              targets: fingerprints,
                                                              query: query)
        let snapshotFields = UIKitSnapshotResponse.fields(for: viewSnapshotID)

        var data: JSON = [
            "screen": .object(screenJSON(window: context.window,
                                         rootViewController: context.rootViewController,
                                         topViewController: context.topViewController)),
            "targetCount": .double(Double(collected.count)),
            "visitedNodeCount": .double(Double(visitedNodeCount)),
            "targets": .array(collected.map { .object($0.summary.toJSON()) }),
            "maxTargets": .double(Double(query.maxTargets)),
            "truncated": .bool(truncated),
            "truncationReason": truncated ? .string("maxTargets") : .null,
            "viewSnapshotID": snapshotFields.id,
            "viewSnapshotUnavailableReason": snapshotFields.unavailableReason,
        ]
        // 导航栏按钮不是 rootView 子树里的普通 view，单独由 inspector 读 navigationItem 摘要，
        // 让 Agent 在同一份观察结果里既看到普通目标，也看到 UIBarButtonItem 语义目标。
        data["navigationBar"] = .object(
            UINavigationBarInspector.summarize(topViewController: context.topViewController).toJSON()
        )
        UIKitCommandLogging.info("command", "ui view targets collect completed visitedNodeCount=\(visitedNodeCount) targetCount=\(collected.count) fingerprints=\(fingerprints.count) topViewController=\(String(describing: type(of: context.topViewController)))")
        return data
    }

    /// 一条已采集的 canonical target：summary（跨边界 Sendable）+ 真实 view（仅 MainActor 域内，
    /// 用于同帧采集指纹，不跨边界、不入响应）。
    private struct CollectedTarget {
        let summary: UIViewTargetSummary
        let view: UIView
    }

    /// 递归遍历 view 树，并把符合 canonical 策略和筛选条件的节点收集进 `collected`。
    ///
    /// identifier 筛选只影响当前节点是否输出，不会提前剪枝子树，避免漏掉深层控件。
    /// 隐藏节点在 `includeHidden=false` 时会剪枝整棵子树。`maxTargets` 截断后立即停止，
    /// 保证签发集合 == 返回集合。
    private static func collect(view: UIView,
                                rootView: UIView,
                                window: UIWindow,
                                path: [Int],
                                depth: Int,
                                query: UIViewTargetsInput,
                                visitedNodeCount: inout Int,
                                collected: inout [CollectedTarget]) -> Bool {
        visitedNodeCount += 1
        if !query.includeHidden, view.isHidden {
            return false
        }

        if isFull(view: view, query: query),
           matchesIdentifier(view: view, query: query) {
            let summary = summary(for: view, rootView: rootView, window: window, path: path, query: query)
            collected.append(CollectedTarget(summary: summary, view: view))
            if collected.count >= query.maxTargets { return true }
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
                    collected: &collected) { return true }
        }
        return false
    }

    /// 判断 view 是否为 full 节点（符合 `UIViewTargetsInput.isFull` 的 canonical 策略）。
    ///
    /// 对 `UIKitFingerprintCollector.collectMatching` 可见：指纹签发必须与目标输出共用同一套
    /// canonical 筛选，保证 `ui.wait(snapshotChanged)` 重采表与 viewTargets 签发表同口径。
    static func isFull(view: UIView, query: UIViewTargetsInput) -> Bool {
        let candidate = UIViewTargetCandidate(
            isHidden: view.isHidden,
            isControl: view is UIControl,
            isUserInteractionEnabled: view.isUserInteractionEnabled,
            hasGestureRecognizers: view.gestureRecognizers?.isEmpty == false,
            hasAccessibilityIdentifier: view.accessibilityIdentifier?.isEmpty == false,
            hasAccessibilityLabel: view.accessibilityLabel?.isEmpty == false,
            hasStaticText: textualValue(from: view)?.isEmpty == false,
            isScrollView: view is UIScrollView
        )
        return query.isFull(candidate: candidate)
    }

    /// 判断当前 view 是否通过 identifier 输出筛选。
    ///
    /// 对 `UIKitFingerprintCollector.collectMatching` 可见（与 `isFull` 同理）。
    static func matchesIdentifier(view: UIView, query: UIViewTargetsInput) -> Bool {
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
                                query: UIViewTargetsInput) -> UIViewTargetSummary {
        let control = view as? UIControl
        let frame = view.convert(view.bounds, to: window)
        let semantic = semanticText(for: view, limit: query.textLimit)
        // identifier 完整保留：它是事件下发的稳定定位键，裁断会让后续 tap/sendAction 失配。
        // 仅 title/label/text/placeholder/value/semanticText 这些展示型文本按 textLimit 裁剪。
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
            semanticText: semantic?.text,
            semanticTextSource: semantic?.source,
            frame: UIViewHierarchyRect(rect: frame),
            state: UIViewTargetState(isHidden: view.isHidden,
                                     alpha: Double(view.alpha),
                                     isUserInteractionEnabled: view.isUserInteractionEnabled,
                                     isEnabled: control?.isEnabled,
                                     isSelected: control?.isSelected,
                                     isHighlighted: control?.isHighlighted,
                                     hasGestureRecognizers: view.gestureRecognizers?.isEmpty == false),
            availableActions: availableActions(for: view, rootView: rootView),
            indexPath: cellIndexPath(for: view)
        )
    }

    /// 提取 cell 的 indexPath（与 `UIViewHierarchyCollector.cellIndexPath(from:)` 同口径）。
    ///
    /// 在 `ui.viewTargets` 响应里给 cell 相关 target 暴露 indexPath，让调用方按 section/item 选行，
    /// 不再依赖 subviews 物理顺序或 frame.y 猜——cell 的 subview 顺序由 z-order 决定，与行号无关。
    /// target 本身可能不是 cell 而是其子 view（如 `UIListContentView`），此时向上找最近的 cell。
    @MainActor
    private static func cellIndexPath(for view: UIView) -> IndexPathSummary? {
        if let cell = view as? UITableViewCell, let tv = cell.superview as? UITableView {
            guard let ip = tv.indexPath(for: cell) else { return nil }
            return IndexPathSummary(section: ip.section, item: ip.row)
        }
        if let cell = view as? UICollectionViewCell, let cv = cell.superview as? UICollectionView {
            guard let ip = cv.indexPath(for: cell) else { return nil }
            return IndexPathSummary(section: ip.section, item: ip.item)
        }
        // target 是 cell 的子 view（如 `UIListContentView`、accessory button 等）时，
        // 向上找最近祖先 cell，再向 tableView/collectionView 反查 indexPath。
        var current: UIView? = view.superview
        while let ancestor = current {
            if let cell = ancestor as? UITableViewCell, let tv = cell.superview as? UITableView {
                guard let ip = tv.indexPath(for: cell) else { return nil }
                return IndexPathSummary(section: ip.section, item: ip.row)
            }
            if let cell = ancestor as? UICollectionViewCell, let cv = cell.superview as? UICollectionView {
                guard let ip = cv.indexPath(for: cell) else { return nil }
                return IndexPathSummary(section: ip.section, item: ip.item)
            }
            current = ancestor.superview
        }
        return nil
    }

    /// 计算 path-target 的可执行动作，供 `summary` 与可测入口共用。
    ///
    /// 与 `UIKitActionExecutor` 的语义保持一致：`tap` 只在存在默认激活路由
    /// （`UIKitDefaultActivationResolver`）时声明；`control.*`/`input`/`scroll` 按真实控件类型
    /// 与状态声明。collector 与 executor 共用 resolver/capability，保证"声明可执行"与"实际派发"
    /// 不分叉。
    ///
    /// - Parameters:
    ///   - view: 被采集/点击的目标 view。
    ///   - rootView: 当前查询上下文的根 view，用于祖先交互性校验。
    /// - Returns: 目标当前可执行的动作集合；非 canonical、不可交互或 disabled 时为空。
    static func availableActions(for view: UIView, rootView: UIView) -> UIKitActionAvailability {
        UIKitActionCapabilityResolver.resolve(view: view, rootView: rootView)
    }

    /// 提取 canonical target 的稳定语义文本（按钮内部 label/image 不再作为独立 target，
    /// 其文本汇总到父 target）。优先级：accessibilityIdentifier（最稳定）→ a11y label → a11y value → 控件标题（button/segmented）→ label text → placeholder → textView text。
    /// 不记录明文到日志；返回文本按 `limit` 裁剪。
    private static func semanticText(for view: UIView, limit: Int) -> (text: String, source: String)? {
        // 优先级 1：accessibilityIdentifier —— UI 自动化专用，最稳定
        if let identifier = view.accessibilityIdentifier, !identifier.isEmpty {
            return (UIViewTargetText.limited(identifier, limit: limit) ?? identifier, "accessibilityIdentifier")
        }
        // 优先级 2：accessibilityLabel —— 无障碍名称
        if let label = view.accessibilityLabel, !label.isEmpty {
            return (UIViewTargetText.limited(label, limit: limit) ?? label, "accessibilityLabel")
        }
        // 优先级 3：accessibilityValue —— 无障碍值
        if let value = view.accessibilityValue, !value.isEmpty {
            return (UIViewTargetText.limited(value, limit: limit) ?? value, "accessibilityValue")
        }
        // 优先级 4：控件标题
        if let button = view as? UIButton {
            let title = button.title(for: .normal) ?? button.currentTitle
            if let title, !title.isEmpty {
                return (UIViewTargetText.limited(title, limit: limit) ?? title, "buttonTitle")
            }
        }
        if let segmented = view as? UISegmentedControl, segmented.selectedSegmentIndex >= 0 {
            if let title = segmented.titleForSegment(at: segmented.selectedSegmentIndex), !title.isEmpty {
                return (UIViewTargetText.limited(title, limit: limit) ?? title, "segmentTitle")
            }
        }
        // 优先级 5：UILabel text 兜底
        if let labelView = view as? UILabel, let text = labelView.text, !text.isEmpty {
            return (UIViewTargetText.limited(text, limit: limit) ?? text, "labelText")
        }
        // 优先级 6：UITextField.placeholder 兜底
        if let textField = view as? UITextField, let placeholder = textField.placeholder, !placeholder.isEmpty {
            return (UIViewTargetText.limited(placeholder, limit: limit) ?? placeholder, "placeholder")
        }
        // 优先级 7：UITextView text 兜底
        if let textView = view as? UITextView, let text = textView.text, !text.isEmpty {
            return (UIViewTargetText.limited(text, limit: limit) ?? text, "textViewText")
        }
        return nil
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
