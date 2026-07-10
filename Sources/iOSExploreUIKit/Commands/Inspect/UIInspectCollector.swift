#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// UIKit 轻量目标采集器。
///
/// 采集器运行在 `MainActor`，从当前顶部控制器根 view 递归读取 canonical interaction target
/// 摘要。它刻意不复用完整层级快照，避免读取颜色、字体、图片等高成本验收字段。
///
/// 重构后的核心不变式（spec §7）：`ui.inspect` 最终返回的 canonical target path 集合
/// **等于** `viewSnapshotID` 内签发 fingerprint 的 path 集合，也**等于** `ui.tap` /
/// `ui.control.sendAction` 允许操作的 path 集合。为此采集器先完成所有筛选与 `maxTargets`
/// 截断，再只为最终返回的 target 逐个采集指纹并签发，禁止签发未返回的 path（否则 Agent 仍
/// 可猜 path 执行）。
@MainActor
enum UIInspectCollector {
    /// 采集当前顶部控制器 view 下的轻量目标列表。
    ///
    /// - Parameter query: 查询参数，控制包含策略、递归深度、identifier 筛选和文本长度。
    /// - Returns: screen、targetCount、visitedNodeCount、targets、viewSnapshotID 的 JSON。
    /// - Throws: `UIKitCommandError.hierarchyUnavailable`——UIKit 上下文不可用时。
    static func collect(query: UIInspectInput) throws -> JSON {
        UIKitCommandLogging.info("command", "ui.inspect collect mainactor start includeHidden=\(query.includeHidden) maxDepth=\(query.maxDepth.map(String.init) ?? "none") hasFilter=\(query.hasIdentifierFilter) textLimit=\(query.textLimit) maxTargets=\(query.maxTargets) maxVisitedNodes=\(query.maxVisitedNodes)")
        let context = try UIKitContextProvider.currentContext(action: InspectCommand.actionName)
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
    static func collect(query: UIInspectInput, context: UIKitContextProvider.Context) -> JSON {
        var visitedNodeCount = 0
        var fullCount = 0
        var collected: [CollectedTarget] = []
        let digest = UIKitFingerprintCollector.digest(topViewController: context.topViewController)
        let truncation = collect(view: context.rootView,
                rootView: context.rootView,
                window: context.window,
                path: [],
                depth: 0,
                query: query,
                visitedNodeCount: &visitedNodeCount,
                fullCount: &fullCount,
                collected: &collected)
        // 截断原因从递归结果传播上来，让响应的 truncationReason 区分 maxTargets / maxVisitedNodes：
        // 否则 maxVisitedNodes 触顶时 fullCount < maxTargets，agent 看到 reason="maxTargets" 会去调
        // 错参数（应调 maxVisitedNodes）。
        let truncated = truncation != .none
        let truncationReason: JSONValue = {
            switch truncation {
            case .none: return .null
            case .maxTargets: return .string("maxTargets")
            case .maxVisitedNodes: return .string("maxVisitedNodes")
            }
        }()

        // 只为最终返回的 full target 签发指纹：returned full paths == viewSnapshotID 签发
        // fingerprint paths == tap/sendAction 可执行集合。minimal 节点不签发（强制 actions=[]、
        // toJSON 只输出 path+type），避免 agent 对不可操作的结构节点发起操作。
        let snapContext = UIKitFingerprintCollector.context(window: context.window,
                                                             topViewController: context.topViewController)
        let fingerprints = Dictionary(
            uniqueKeysWithValues: collected.filter { $0.isFull }.map { target in
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

        let minimalCount = collected.count - fullCount
        var data: JSON = [
            "screen": .object(screenJSON(window: context.window,
                                         rootViewController: context.rootViewController,
                                         topViewController: context.topViewController)),
            "targetCount": .double(Double(collected.count)),
            "fullCount": .double(Double(fullCount)),
            "minimalCount": .double(Double(minimalCount)),
            "visitedNodeCount": .double(Double(visitedNodeCount)),
            "targets": .array(collected.map { .object($0.summary.toJSON()) }),
            "maxTargets": .double(Double(query.maxTargets)),
            "maxVisitedNodes": .double(Double(query.maxVisitedNodes)),
            "truncated": .bool(truncated),
            "truncationReason": truncationReason,
            "viewSnapshotID": snapshotFields.id,
            "viewSnapshotUnavailableReason": snapshotFields.unavailableReason,
        ]
        // 导航栏按钮不是 rootView 子树里的普通 view，单独由 inspector 读 navigationItem 摘要，
        // 让 Agent 在同一份观察结果里既看到普通目标，也看到 UIBarButtonItem 语义目标。
        data["navigationBar"] = .object(
            UINavigationBarInspector.summarize(topViewController: context.topViewController).toJSON()
        )
        // alert 按钮也走单独的 inspector 摘要：它们不在 rootView 子树里被 canonical 收集，
        // 单独由 `UIAlertInspector.summarizeForInspect` 暴露 index/title/role/path 与
        // `availableActions: ["ui.alert.respond"]`。这样 agent 在同一份 inspect 结果里就能
        // 看到按钮，不必再调一次 `ui.alert.respond dryRun=true` 才能列出按钮清单。
        data["alert"] = .object(
            UIAlertInspector.toJSONInspect(
                UIAlertInspector.summarizeForInspect(
                    topViewController: context.topViewController,
                    rootView: context.rootView
                )
            )
        )
        UIKitCommandLogging.info("command", "ui.inspect collect completed visitedNodeCount=\(visitedNodeCount) targetCount=\(collected.count) fullCount=\(fullCount) minimalCount=\(minimalCount) fingerprints=\(fingerprints.count) topViewController=\(String(describing: type(of: context.topViewController)))")
        return data
    }

    /// 一条已采集的节点：summary（跨边界 Sendable）+ 真实 view（仅 MainActor 域内，用于同帧
    /// 采集指纹，不跨边界、不入响应）+ `isFull` 标记。
    ///
    /// `isFull` 决定该节点是否参与指纹签发：只有 full 节点签发 fingerprint 并进入
    /// `viewSnapshotID`，minimal 节点只输出 path+type 维持层级，不签发、不占 `maxTargets` 配额。
    private struct CollectedTarget {
        let summary: UIInspectSummary
        let view: UIView
        let isFull: Bool
    }

    /// 截断原因枚举（替代原 `Bool` 返回值），让顶层响应能区分是 `maxTargets` 还是
    /// `maxVisitedNodes` 触顶——前者提示调用方调大 `maxTargets`，后者调大 `maxVisitedNodes`。
    ///
    /// `.none` 表示本枝未触发截断（含 hidden 剪枝、control 子树剪枝、自然到叶、maxDepth 到顶），
    /// 递归继续探索别的枝；`.maxTargets` / `.maxVisitedNodes` 立即向上传播，让顶层据此设置
    /// 响应的 `truncationReason`，避免 agent 看到 `truncated=true, truncationReason="maxTargets"`
    /// 却 `fullCount < maxTargets` 时被误导去调错参数。
    private enum CollectionTruncation {
        /// 未截断（本枝结束，继续别的枝）：hidden 剪枝、control 子树剪枝、自然到叶、maxDepth 到顶。
        case none
        /// full 输出达 `maxTargets` 上限。
        case maxTargets
        /// 访问节点数达 `maxVisitedNodes` 上限（深树保护）。
        case maxVisitedNodes
    }

    /// 递归遍历 view 树，按 full/minimal 分档收集节点。
    ///
    /// **全节点输出**：full 与 minimal 节点都进 `collected`，让 agent 能看到完整层级结构
    /// （minimal 节点只输出 `{path, type}`，不引诱操作）。
    ///
    /// **分档**：每个节点先用 `makeCandidate(for:)` + `query.isFull` 判定 full/minimal。
    /// full 节点（且通过 identifier 筛选）用完整 `summary(for:)`；minimal 节点用
    /// `minimalSummary(for:)`（强制 `actions=[]`、`isMinimal=true`）。
    ///
    /// **截断只数 full**：`fullCount` 独立于 `collected.count`，只有 full 节点触发 `maxTargets`
    /// 检查。minimal 不占配额——否则一棵 full 稀疏的树会被大量 minimal 提前耗尽配额，
    /// 让真正可操作的深层 full 节点被丢弃。
    ///
    /// **identifier 筛选 §3.10**：筛选只作用于 full 输出（`isFull && matchesId`）；
    /// minimal 节点不受筛选，维持层级结构完整性，让 agent 即便按 identifier 过滤也能看到
    /// 目标所在的父子路径。
    ///
    /// **控件子树剪枝**：`UIControl` 子树内的非 full 节点（rolled-up 展示节点 + 内部结构节点）
    /// 不作为 minimal 输出——其语义已由父 control 的 full target 表达，独立输出只会泄露控件
    /// 渲染细节。整棵子树剪枝（cell 子树不受影响，cell 非 UIControl）。
    ///
    /// **深树保护**：`visitedNodeCount` 超过 `maxVisitedNodes` 时立即停止（含 minimal 与 full），
    /// 防止异常深树让 collector 跑飞。返回 `CollectionTruncation` 区分截断来源：`.none` 本枝无截断
    /// （继续别的枝），`.maxTargets` / `.maxVisitedNodes` 立即向上传播，让顶层据此设 `truncationReason`。
    private static func collect(view: UIView,
                                rootView: UIView,
                                window: UIWindow,
                                path: [Int],
                                depth: Int,
                                query: UIInspectInput,
                                visitedNodeCount: inout Int,
                                fullCount: inout Int,
                                collected: inout [CollectedTarget]) -> CollectionTruncation {
        visitedNodeCount += 1
        if visitedNodeCount > query.maxVisitedNodes { return .maxVisitedNodes }
        if !query.includeHidden, view.isHidden {
            return .none
        }

        let candidate = makeCandidate(for: view)
        let isFull = query.isFull(candidate: candidate)
        // §3.10: identifier 筛选只影响 full 输出；minimal 结构节点不受筛用于维持层级。
        if isFull, matchesIdentifier(view: view, query: query) {
            let summary = summary(for: view, rootView: rootView, window: window, path: path, query: query)
            collected.append(CollectedTarget(summary: summary, view: view, isFull: true))
            fullCount += 1
            if fullCount >= query.maxTargets { return .maxTargets }
        } else if !isFull {
            // 控件子树内的非 full 节点（含 rolled-up 展示节点与内部结构节点）不作为 minimal 输出：
            // 其语义已由父 control 的 full target 表达（semanticText / availableActions），
            // 独立输出控件内部结构对 agent 无层级价值，只会泄露渲染细节并引诱误操作。
            // 由于 control 子树内所有后代都在同一 UIControl 内，整棵子树剪枝（不收集、不递归）。
            // cell 子树不受影响：cell 非 UIControl，cell 内 label 的 isInControlSubtree=false（spec §3.4）。
            guard !candidate.isInControlSubtree else { return .none }
            // minimal 结构节点：维持层级，不签发、强制 actions=[]、toJSON 只输出 path+type。
            let summary = minimalSummary(for: view, path: path, window: window)
            collected.append(CollectedTarget(summary: summary, view: view, isFull: false))
        }

        if let maxDepth = query.maxDepth, depth >= maxDepth {
            return .none
        }

        for (index, child) in view.subviews.enumerated() {
            let result = collect(view: child,
                    rootView: rootView,
                    window: window,
                    path: path + [index],
                    depth: depth + 1,
                    query: query,
                    visitedNodeCount: &visitedNodeCount,
                    fullCount: &fullCount,
                    collected: &collected)
            if result != .none { return result }
        }
        return .none
    }

    /// 从真实 `UIView` 构造 Foundation-only 候选摘要（full/minimal 判定的唯一构造点）。
    ///
    /// `isFull(view:query:)` 与 `collect` 递归共用此入口，保证目标输出与指纹签发用同一份
    /// candidate（Task 8 的 fingerprint collector 亦复用，不重复提取）。`isInControlSubtree`
    /// 在此计算：自身非 `UIControl` 且祖先链含 `UIControl`（`explore_controlAncestor`），
    /// 让 `hasStaticText` 的控件内嵌展示节点 rollup 到父 control。
    static func makeCandidate(for view: UIView) -> UIInspectCandidate {
        // 自身是 UIControl 时不计入 control 子树——它走 isControl 规则独立 full，
        // 不应被 rollup 排除。
        let isInControlSubtree = !(view is UIControl) && view.explore_controlAncestor != nil
        return UIInspectCandidate(
            isHidden: view.isHidden,
            isControl: view is UIControl,
            isUserInteractionEnabled: view.isUserInteractionEnabled,
            hasGestureRecognizers: view.gestureRecognizers?.isEmpty == false,
            hasAccessibilityIdentifier: view.accessibilityIdentifier?.isEmpty == false,
            hasAccessibilityLabel: view.accessibilityLabel?.isEmpty == false,
            hasStaticText: textualValue(from: view)?.isEmpty == false,
            isScrollView: view is UIScrollView,
            isInControlSubtree: isInControlSubtree
        )
    }

    /// 生成 minimal 档摘要（结构节点）：强制 `isMinimal=true`、`availableActions=[]`。
    ///
    /// 即便 `toJSON` 因 `isMinimal=true` 只输出 `{path, type}`，模型仍需完整构造（`frame`/`state`
    /// 是非可选字段）。`indexPath` 对 minimal cell 容器有定位价值，保留；`actions` 强制空避免
    /// 引诱 agent 对不可操作节点发起 `ui.tap`/`ui.control.sendAction`。
    private static func minimalSummary(for view: UIView, path: [Int], window: UIWindow) -> UIInspectSummary {
        UIInspectSummary(
            path: UIKitViewLookupTarget.pathString(from: path),
            type: String(describing: Swift.type(of: view)),
            role: role(for: view),
            accessibilityIdentifier: nil,
            accessibilityLabel: nil,
            title: nil,
            text: nil,
            placeholder: nil,
            value: nil,
            semanticText: nil,
            semanticTextSource: nil,
            frame: UIViewHierarchyRect(rect: view.convert(view.bounds, to: window)),
            state: UIInspectState(isHidden: view.isHidden,
                                     alpha: Double(view.alpha),
                                     isUserInteractionEnabled: view.isUserInteractionEnabled,
                                     isEnabled: nil,
                                     isSelected: nil,
                                     isHighlighted: nil,
                                     hasGestureRecognizers: view.gestureRecognizers?.isEmpty == false),
            availableActions: UIKitActionAvailability(actions: []),
            indexPath: cellIndexPath(for: view),
            isMinimal: true
        )
    }

    /// 判断 view 是否为 full 节点（符合 `UIInspectInput.isFull` 的 canonical 策略）。
    ///
    /// 对 `UIKitFingerprintCollector.collectMatching` 可见：指纹签发必须与目标输出共用同一套
    /// canonical 筛选，保证 `ui.wait(snapshotChanged)` 重采表与 ui.inspect 签发表同口径。
    ///
    /// `isInControlSubtree` 在此计算：自身非 `UIControl` 且祖先链含 `UIControl`
    ///（`explore_controlAncestor`），让 `hasStaticText` 的控件内嵌展示节点（如按钮内部
    /// title label）rollup 到父 control，不独立 full。cell 子树因 cell 非 `UIControl`
    /// 不命中，cell 内 label 仍 full。
    static func isFull(view: UIView, query: UIInspectInput) -> Bool {
        let candidate = makeCandidate(for: view)
        let full = query.isFull(candidate: candidate)
        // rollup 命中日志：控件内嵌展示节点被 rollup 到父 control，不独立 full。
        // 仅在命中 rollup 排除时记录，帮助定位"按钮内 label 为何不在 targets"的疑问。
        if !full, candidate.hasStaticText, candidate.isInControlSubtree {
            UIKitCommandLogging.info("command", "ui.inspect rollup: static-text node in UIControl subtree (\(String(describing: type(of: view)))) rolled up to parent control, not emitted as full target")
        }
        return full
    }

    /// 判断当前 view 是否通过 identifier 输出筛选。
    ///
    /// 对 `UIKitFingerprintCollector.collectMatching` 可见（与 `isFull` 同理）。
    static func matchesIdentifier(view: UIView, query: UIInspectInput) -> Bool {
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
                                query: UIInspectInput) -> UIInspectSummary {
        let control = view as? UIControl
        let frame = view.convert(view.bounds, to: window)
        let semantic = semanticText(for: view, limit: query.textLimit)
        // identifier 完整保留：它是事件下发的稳定定位键，裁断会让后续 tap/sendAction 失配。
        // 仅 title/label/text/placeholder/value/semanticText 这些展示型文本按 textLimit 裁剪。
        return UIInspectSummary(
            path: UIKitViewLookupTarget.pathString(from: path),
            type: String(describing: Swift.type(of: view)),
            role: role(for: view),
            accessibilityIdentifier: view.accessibilityIdentifier,
            accessibilityLabel: UIInspectText.limited(view.accessibilityLabel, limit: query.textLimit),
            title: UIInspectText.limited(title(from: view), limit: query.textLimit),
            text: UIInspectText.limited(textualValue(from: view), limit: query.textLimit),
            placeholder: UIInspectText.limited(placeholder(from: view), limit: query.textLimit),
            value: UIInspectText.limited(value(from: view), limit: query.textLimit),
            semanticText: semantic?.text,
            semanticTextSource: semantic?.source,
            frame: UIViewHierarchyRect(rect: frame),
            state: UIInspectState(isHidden: view.isHidden,
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
    /// 在 `ui.inspect` 响应里给 cell 相关 target 暴露 indexPath，让调用方按 section/item 选行，
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
            return (UIInspectText.limited(identifier, limit: limit) ?? identifier, "accessibilityIdentifier")
        }
        // 优先级 2：accessibilityLabel —— 无障碍名称
        if let label = view.accessibilityLabel, !label.isEmpty {
            return (UIInspectText.limited(label, limit: limit) ?? label, "accessibilityLabel")
        }
        // 优先级 3：accessibilityValue —— 无障碍值
        if let value = view.accessibilityValue, !value.isEmpty {
            return (UIInspectText.limited(value, limit: limit) ?? value, "accessibilityValue")
        }
        // 优先级 4：控件标题
        if let button = view as? UIButton {
            let title = button.title(for: .normal) ?? button.currentTitle
            if let title, !title.isEmpty {
                return (UIInspectText.limited(title, limit: limit) ?? title, "buttonTitle")
            }
        }
        if let segmented = view as? UISegmentedControl, segmented.selectedSegmentIndex >= 0 {
            if let title = segmented.titleForSegment(at: segmented.selectedSegmentIndex), !title.isEmpty {
                return (UIInspectText.limited(title, limit: limit) ?? title, "segmentTitle")
            }
        }
        // 优先级 5：UILabel text 兜底
        if let labelView = view as? UILabel, let text = labelView.text, !text.isEmpty {
            return (UIInspectText.limited(text, limit: limit) ?? text, "labelText")
        }
        // 优先级 6：UITextField.placeholder 兜底
        if let textField = view as? UITextField, let placeholder = textField.placeholder, !placeholder.isEmpty {
            return (UIInspectText.limited(placeholder, limit: limit) ?? placeholder, "placeholder")
        }
        // 优先级 7：UITextView text 兜底
        if let textView = view as? UITextView, let text = textView.text, !text.isEmpty {
            return (UIInspectText.limited(text, limit: limit) ?? text, "textViewText")
        }
        return nil
    }

    /// 识别轻量目标角色，用于给 agent 返回建议动作。
    ///
    /// 对 executor 上的陈旧指纹重采也可见（fingerprint 需要 role 字段），故为模块内可见。
    static func role(for view: UIView) -> UIInspectRole {
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

    /// 提取可见文本，调用方负责按 query 裁剪。
    ///
    /// 包括 UILabel.text、UITextField.text、UITextView.text。
    /// `UIListContentView` / `UITableViewCell` 本身无 text 属性，取首个非空子 UILabel
    /// 文本（如 cell 标题"🔔弹窗测试"），否则这些容器节点文本为空。
    /// `isSecureTextEntry == true` 的输入框（密码等）不返回内容，避免明文泄露；
    /// 其余编辑型控件（含 `_UIAlertControllerTextField`）的 text 字段正常返回，
    /// 让 agent 输入后可通过 ui.inspect 验证结果。
    private static func textualValue(from view: UIView) -> String? {
        if let label = view as? UILabel { return label.text }
        if let textField = view as? UITextField {
            guard !textField.isSecureTextEntry else { return nil }
            return textField.text
        }
        if let textView = view as? UITextView { return textView.text }
        // UIListContentView / UITableViewCell 容器不直接持有 text，遍历直接子 view
        // 取首个非空 UILabel 文本（覆盖 cell 标题等显示文本）。
        // UIListContentView 是 iOS 14+，而 Package.swift 声明 iOS 13 部署目标，必须用
        // `if #available` 隔离类型判断；否则 iOS 模拟器构建失败（macOS SPM 测试因 UIKit
        // 段整体 `#if canImport(UIKit)` 不编译而漏掉此问题）。iOS 13 下降级为只判
        // UITableViewCell——cell 标题仍可从该分支提取，功能不丢。
        let isListContentView: Bool
        if #available(iOS 14.0, *) {
            isListContentView = view is UIListContentView
        } else {
            isListContentView = false
        }
        if isListContentView || view is UITableViewCell {
            for sub in view.subviews {
                if let label = sub as? UILabel, let text = label.text, !text.isEmpty {
                    return text
                }
            }
        }
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
