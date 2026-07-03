#if canImport(UIKit)
import Foundation
import UIKit

/// UIKit 指纹采集器。
///
/// 负责把真实的 `UIView` 转换成可跨并发域传递的 `UIKitTargetFingerprint`。
///
/// 这个类型只运行在 `MainActor`：
/// - 可以安全读取 UIView / UIViewController 的属性；
/// - 产出的 fingerprint 是值类型，不会把 UIView 泄漏到非主线程；
/// - ViewHierarchy、ViewTargets collector 与 UIKitActionExecutor 都应复用这里的逻辑，
///   避免三处各自拼字段，最终出现 fingerprint 字段漂移。
@MainActor
enum UIKitFingerprintCollector {

    // MARK: - 单节点 Fingerprint

    /// 为某个目标 view 构造 fingerprint。
    ///
    /// 这个版本要求调用方显式传入 `rootView`。
    ///
    /// `rootView` 表示本次 snapshot 的根边界：
    /// - 祖先摘要只计算 `view` 到 `rootView` 之间的层级；
    /// - 不会继续把 UIWindow、系统私有容器等更外层节点算进去；
    /// - 同一份 snapshot 中，所有节点应使用同一个 rootView。
    ///
    /// - Parameters:
    ///   - view: 当前要采集的目标 view。
    ///   - path: 当前 view 在 rootView 下的结构路径，例如 `root/0/2`。
    ///   - rootView: 当前 snapshot 的根 view。
    ///   - digest: 当前 UI 上下文摘要，通常为顶部控制器类型名。
    /// - Returns: 可 Sendable 传递的轻量 fingerprint。
    static func fingerprint(
        for view: UIView,
        path: String,
        rootView: UIView,
        digest: String
    ) -> UIKitTargetFingerprint {
        let control = view as? UIControl

        return UIKitTargetFingerprint(
            // 用于判断当前 fingerprint 属于哪个页面语义。
            contextDigest: digest,

            // view 在当前 rootView 内的结构位置。
            //
            // 它不是永久稳定 ID。
            // subviews 顺序变化后，path 可能改变。
            path: path,

            // UIView 的运行时具体类型。
            //
            // 例如 UIButton、UILabel、UITableViewCell、自定义 UIView。
            viewType: String(describing: Swift.type(of: view)),

            // 不直接保存 accessibilityIdentifier 原文，
            // 只保存稳定 hash，避免 snapshot 暴露可能带业务语义的字符串。
            identifierHash: UIKitTargetFingerprint.stableHash(
                view.accessibilityIdentifier ?? ""
            ),

            // 只有 UIControl 才有 enabled / selected；
            // 非 UIControl 使用默认值，保证 fingerprint 字段始终完整。
            isEnabled: control?.isEnabled ?? true,
            isSelected: control?.isSelected ?? false,

            // 当前 view 自身的显示与交互状态。
            isHidden: view.isHidden,
            alpha: Double(view.alpha),
            isUserInteractionEnabled: view.isUserInteractionEnabled,

            // 描述 view 所处父容器环境。
            //
            // 例如按钮自身没变，但被移动到另一个容器、
            // 某个父容器 hidden、alpha 接近 0、禁止交互，
            // 这个值会变化。
            ancestorDigest: ancestorDigest(
                for: view,
                rootView: rootView
            ),

            // 与动作路由相关的语义摘要哈希（类型 / role / a11y label·value / 按钮标题 /
            // 输入占位 / switch isOn / slider value / segment 选择 / 默认激活路由）。
            //
            // 即使 path、类型、frame 都没变，按钮标题从「提交」变「删除」、switch 状态翻转、
            // segment 选择变化也会让本字段变化，触发陈旧校验拒绝旧 locator，迫使重新 observe。
            // 只存哈希，不存业务明文。
            semanticDigest: UIKitTargetSemanticDigest.digest(for: view)
        )
    }

    // MARK: - Snapshot Context

    /// 生成“当前进程内”的 snapshot 上下文身份。
    ///
    /// 这里使用 ObjectIdentifier，只用于同一次 App 运行期间：
    /// - 不可持久化；
    /// - 不可跨 App 启动比较；
    /// - 不代表业务身份；
    /// - 目的只是防止旧 snapshot 在另一个 window / 顶部 VC 上被误用。
    static func context(
        window: UIWindow,
        topViewController: UIViewController
    ) -> UIKitSnapshotContext {
        UIKitSnapshotContext(
            windowIdentity: String(describing: ObjectIdentifier(window)),
            topViewControllerIdentity: String(
                describing: ObjectIdentifier(topViewController)
            )
        )
    }

    /// 生成当前页面的轻量上下文摘要。
    ///
    /// 当前实现使用顶部控制器类型名，例如：
    /// `CheckoutViewController`
    ///
    /// 它不是唯一 ID，只用于辅助判断“是否仍处于同类页面上下文”。
    static func digest(
        topViewController: UIViewController
    ) -> String {
        String(describing: Swift.type(of: topViewController))
    }

    // MARK: - Ancestor Digest

    /// 计算目标 view 在当前 rootView 范围内的祖先链摘要。
    ///
    /// 它不是为了唯一标识一个 UIView，而是为了回答：
    ///
    /// “这个目标当前处于怎样的父容器结构和交互环境中？”
    ///
    /// 例如：
    ///
    /// rootView
    ///   └── CheckoutView
    ///         └── PaymentContainer
    ///               └── ConfirmButton
    ///
    /// 对 ConfirmButton 来说，祖先链是：
    ///
    /// rootView -> CheckoutView -> PaymentContainer
    ///
    /// 若 ConfirmButton 自身属性完全没变，但发生以下任一变化：
    /// - 被移动到另一个容器；
    /// - 中间多插入一层容器；
    /// - 某个父容器被隐藏；
    /// - 某个父容器 alpha 接近 0；
    /// - 某个父容器禁止用户交互；
    ///
    /// 那么 ancestorDigest 会变化。
    ///
    /// 这样 executor 在重采 fingerprint 时，就能发现：
    /// “这不是 snapshot 当时那个结构环境中的目标了。”
    private static func ancestorDigest(
        for view: UIView,
        rootView: UIView
    ) -> UInt64 {
        // 保存 target view 的所有祖先。
        //
        // 注意：不包含 view 自己。
        //
        // 假设：
        //
        // rootView
        //   └── containerA
        //         └── containerB
        //               └── targetView
        //
        // 则 nodes 初始收集顺序为：
        //
        // [containerB, containerA, rootView]
        var nodes: [UIView] = []

        // 从目标的直接父节点开始向上走。
        var current = view.superview

        while let node = current {
            nodes.append(node)

            // 到达本次 snapshot 的根节点后停止。
            //
            // 不继续走到 UIWindow 或系统容器，
            // 避免外部环境变化让 fingerprint 无谓失效。
            if node === rootView {
                break
            }

            current = node.superview
        }

        // FNV-1a 风格的初始值。
        //
        // 这里不追求密码学安全，
        // 目标只是以低成本把多个字段稳定地混合成 UInt64。
        var digest: UInt64 = 0xcbf29ce484222325

        // nodes 当前是“离目标最近 -> 离 root 最近”：
        //
        // [containerB, containerA, rootView]
        //
        // 反转后按“root -> target”顺序混合：
        //
        // [rootView, containerA, containerB]
        //
        // 层级顺序本身有语义：
        //
        // root -> A -> B
        //
        // 与：
        //
        // root -> B -> A
        //
        // 不应得到相同结果。
        for node in nodes.reversed() {

            // 1. 混入祖先节点的类型。
            //
            // 例如 UIView、UIStackView、UIScrollView、
            // UITableViewCell、自定义容器等。
            digest ^= UIKitTargetFingerprint.stableHash(
                String(describing: Swift.type(of: node))
            )
            digest &*= 0x100000001b3

            // 2. 混入 accessibilityIdentifier。
            //
            // 如果容器显式设置了 identifier，
            // 它通常能提供较稳定的结构语义。
            digest ^= UIKitTargetFingerprint.stableHash(
                node.accessibilityIdentifier ?? ""
            )
            digest &*= 0x100000001b3

            // 3. 混入 hidden。
            //
            // 即使 targetView 自己 isHidden == false，
            // 父节点 hidden 后，它实际也不可见。
            digest ^= node.isHidden ? 1 : 0
            digest &*= 0x100000001b3

            // 4. 混入 alpha 的“是否接近不可见”状态。
            //
            // 不直接把完整 alpha 数值算进去，
            // 因为动画过程中的 1.0 -> 0.95 -> 0.9
            // 很容易造成无意义的 fingerprint 失效。
            //
            // 这里采用 UIKit 常见可见性阈值 0.01：
            // alpha < 0.01 视为实际不可见。
            let isEffectivelyInvisible = node.alpha < 0.01
            digest ^= isEffectivelyInvisible ? 1 : 0
            digest &*= 0x100000001b3

            // 5. 混入祖先交互开关。
            //
            // 某个父容器禁止交互后，
            // 后代即使自身是 enabled，也无法正常接收触摸事件。
            digest ^= node.isUserInteractionEnabled ? 1 : 0
            digest &*= 0x100000001b3
        }

        return digest
    }

    // MARK: - Query-driven Fingerprint Collection

    /// 按 `UIViewTargetsInput` 筛选条件遍历 rootView，生成 canonical 目标的指纹表
    /// （`path → fingerprint`），供 `ui.wait(snapshotChanged)` 重采 whole-table 与签发表比对。
    ///
    /// 重构后的口径（spec §7）：
    /// - `ui.viewTargets` 不再用本方法签发——它遍历时累积 `(summary, view)`，maxTargets 截断后
    ///   只为最终返回的 canonical target 逐个 `fingerprint(for:)` 签发（returned paths == signed paths）；
    /// - 本方法现在主要服务 `ui.wait(snapshotChanged)`：用签发时同一 query 重采当前表，再与
    ///   `UIKitSnapshotStore.matchesWholeTable` 整体比对；
    /// - `ui.screenshot` 不再签发 viewSnapshotID（结构化 freshness / locator 由 ui.viewTargets 负责）。
    ///
    /// 筛选规则与 `UIViewTargetsCollector.shouldInclude` 逐字对齐（canonical-only：UIControl 系 +
    /// UIScrollView 系），保证 wait 重采表与 viewTargets 签发表同口径：
    /// - `includeHidden=false` 时 hidden 节点整棵子树剪枝；
    /// - 通过 `query.shouldInclude` + `matchesIdentifier` 的节点才签发指纹；
    /// - `maxDepth` 限制递归深度（`nil` 不限）；
    /// - 不受 `maxTargets` 约束（whole-table 重采需要完整 canonical 集合）。
    ///
    /// - Parameters:
    ///   - rootView: 本次 snapshot 的根节点。
    ///   - query: 与签发同口径的筛选参数。
    ///   - digest: 顶部控制器等页面上下文摘要。
    /// - Returns: 命中 canonical 筛选的节点的 `path → fingerprint` 表。
    static func collectFingerprints(
        rootView: UIView,
        query: UIViewTargetsInput,
        digest: String
    ) -> [String: UIKitTargetFingerprint] {
        var result: [String: UIKitTargetFingerprint] = [:]
        collectMatching(
            view: rootView,
            rootView: rootView,
            path: [],
            depth: 0,
            query: query,
            digest: digest,
            result: &result
        )
        return result
    }

    /// 递归遍历并按 query 筛选签发指纹。
    ///
    /// 与 `UIViewTargetsCollector.collect` 共用同一套 `shouldInclude` / `matchesIdentifier` /
    /// `includeHidden` / `maxDepth` 决策，确保指纹表与目标输出**逐字同筛选**。`maxTargets` 在此
    /// 不参与（指纹签发独立于响应规模限制）。
    private static func collectMatching(
        view: UIView,
        rootView: UIView,
        path: [Int],
        depth: Int,
        query: UIViewTargetsInput,
        digest: String,
        result: inout [String: UIKitTargetFingerprint]
    ) {
        // includeHidden=false 时 hidden 节点整棵子树剪枝（与 collector 一致）。
        if !query.includeHidden, view.isHidden {
            return
        }

        // 只为命中筛选的节点签发指纹；筛选逻辑与 UIViewTargetsCollector 完全相同。
        if UIViewTargetsCollector.shouldInclude(view: view, query: query),
           UIViewTargetsCollector.matchesIdentifier(view: view, query: query) {
            let pathString = UIKitViewLookupTarget.pathString(from: path)
            result[pathString] = fingerprint(
                for: view,
                path: pathString,
                rootView: rootView,
                digest: digest
            )
        }

        if let maxDepth = query.maxDepth, depth >= maxDepth {
            return
        }

        for (index, child) in view.subviews.enumerated() {
            collectMatching(
                view: child,
                rootView: rootView,
                path: path + [index],
                depth: depth + 1,
                query: query,
                digest: digest,
                result: &result
            )
        }
    }

    // MARK: - Tree Traversal

    /// 递归遍历 rootView 下的 view 树，生成：
    ///
    ///     path -> UIKitTargetFingerprint
    ///
    /// path 由每层 `subviews` 下标组成，例如：
    ///
    /// rootView
    /// ├── subviews[0]
    /// │   └── subviews[0].subviews[2]
    /// └── subviews[1]
    ///
    /// 对应 path 可以是：
    ///
    /// root
    /// root/0
    /// root/0/2
    /// root/1
    ///
    /// 注意：
    /// path 是当前 view tree 的结构位置，不是稳定业务 ID。
    /// 因此后续执行动作时，应同时比较：
    /// - context；
    /// - path；
    /// - fingerprint；
    ///
    /// 不能只依赖 path。
    ///
    /// - Parameters:
    ///   - rootView: 本次 snapshot 的根节点。
    ///   - includeHidden: 是否包含 hidden 节点。
    ///   - digest: 顶部控制器等页面上下文摘要。
    /// - Returns: 当前 rootView 下所有已采集节点的 fingerprint 表。
    static func fingerprints(
        in rootView: UIView,
        includeHidden: Bool,
        digest: String
    ) -> [String: UIKitTargetFingerprint] {
        var result: [String: UIKitTargetFingerprint] = [:]

        collect(
            view: rootView,
            rootView: rootView,
            path: [],
            includeHidden: includeHidden,
            digest: digest,
            result: &result
        )

        return result
    }

    /// 递归收集当前节点及其子树的 fingerprint。
    private static func collect(
        view: UIView,
        rootView: UIView,
        path: [Int],
        includeHidden: Bool,
        digest: String,
        result: inout [String: UIKitTargetFingerprint]
    ) {
        // 当 includeHidden == false 时：
        //
        // 某个节点一旦 hidden，其整棵子树在视觉上都不可见，
        // 也通常不应被签发为可执行目标。
        //
        // 因此直接剪枝，不继续遍历后代。
        if !includeHidden, view.isHidden {
            return
        }

        // 把 [0, 2] 转为类似 "root/0/2" 的字符串。
        let pathString = UIKitViewLookupTarget.pathString(from: path)

        // 为当前节点创建 fingerprint。
        result[pathString] = fingerprint(
            for: view,
            path: pathString,
            rootView: rootView,
            digest: digest
        )

        // 按 subviews 中的下标顺序递归。
        //
        // 因为 path 依赖 index，
        // 所以 sibling 顺序变化会导致 path 改变。
        for (index, child) in view.subviews.enumerated() {
            collect(
                view: child,
                rootView: rootView,
                path: path + [index],
                includeHidden: includeHidden,
                digest: digest,
                result: &result
            )
        }
    }
}
#endif
