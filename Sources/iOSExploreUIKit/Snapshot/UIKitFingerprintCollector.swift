#if canImport(UIKit)
import Foundation
import UIKit

/// UIKit 指纹采集器。
///
/// 把"从真实 UIView 构造 `UIKitTargetFingerprint`"的逻辑集中到一处，供 ViewHierarchy、
/// ViewTargets 两个 collector（签发 snapshot）与 `UIKitActionExecutor`（重采比对）共用，
/// 避免三处各写一份导致字段漂移。它运行在 `MainActor`，读取少量 view 属性后产出 Sendable
/// 值类型，不把 UIView 返回到非隔离域。
@MainActor
enum UIKitFingerprintCollector {
    /// 从单个 view 构造指纹。
    ///
    /// - Parameters:
    ///   - view: 目标 view。
    ///   - path: 该 view 的路径字符串（`root/0/2`）。
    ///   - digest: 所属查询上下文摘要（顶部控制器类型名）。
    /// - Returns: 该 view 的轻量指纹（identifier 仅存稳定哈希）。
    static func fingerprint(for view: UIView, path: String, digest: String) -> UIKitTargetFingerprint {
        fingerprint(for: view, path: path, rootView: view, digest: digest)
    }

    /// 从目标及其祖先链构造固定预算 fingerprint。
    static func fingerprint(for view: UIView, path: String, rootView: UIView, digest: String) -> UIKitTargetFingerprint {
        let control = view as? UIControl
        return UIKitTargetFingerprint(
            contextDigest: digest,
            path: path,
            viewType: String(describing: Swift.type(of: view)),
            identifierHash: UIKitTargetFingerprint.stableHash(view.accessibilityIdentifier ?? ""),
            isEnabled: control?.isEnabled ?? true,
            isSelected: control?.isSelected ?? false,
            isHidden: view.isHidden,
            alpha: Double(view.alpha),
            isUserInteractionEnabled: view.isUserInteractionEnabled,
            ancestorDigest: ancestorDigest(for: view, rootView: rootView)
        )
    }

    /// 生成当前 window 与顶部控制器的进程内 context 身份。
    static func context(window: UIWindow, topViewController: UIViewController) -> UIKitSnapshotContext {
        UIKitSnapshotContext(windowIdentity: String(describing: ObjectIdentifier(window)),
                             topViewControllerIdentity: String(describing: ObjectIdentifier(topViewController)))
    }

    private static func ancestorDigest(for view: UIView, rootView: UIView) -> UInt64 {
        var nodes: [UIView] = []
        var current = view.superview
        while let node = current {
            nodes.append(node)
            if node === rootView { break }
            current = node.superview
        }
        var digest: UInt64 = 0xcbf29ce484222325
        for node in nodes.reversed() {
            digest ^= UIKitTargetFingerprint.stableHash(String(describing: type(of: node)))
            digest &*= 0x100000001b3
            digest ^= UIKitTargetFingerprint.stableHash(node.accessibilityIdentifier ?? "")
            digest &*= 0x100000001b3
            digest ^= node.isHidden ? 1 : 0
            digest &*= 0x100000001b3
            digest ^= UInt64((Double(node.alpha) * 1000).rounded())
            digest &*= 0x100000001b3
            digest ^= node.isUserInteractionEnabled ? 1 : 0
            digest &*= 0x100000001b3
        }
        return digest
    }

    /// 递归遍历 view 树，生成 path→fingerprint 表。
    ///
    /// 隐藏节点在 `includeHidden=false` 时整棵剪枝（与 collector 的可见性策略一致），避免
    /// 给隐藏分支签发指纹造成容量浪费。
    ///
    /// - Parameters:
    ///   - rootView: 根 view。
    ///   - includeHidden: 是否包含隐藏节点。
    ///   - digest: 上下文摘要。
    /// - Returns: path 字符串 → 指纹。
    static func fingerprints(in rootView: UIView,
                             includeHidden: Bool,
                             digest: String) -> [String: UIKitTargetFingerprint] {
        var result: [String: UIKitTargetFingerprint] = [:]
        collect(view: rootView, rootView: rootView, path: [], includeHidden: includeHidden, digest: digest, result: &result)
        return result
    }

    /// 递归收集指纹。
    private static func collect(view: UIView,
                                rootView: UIView,
                                path: [Int],
                                includeHidden: Bool,
                                digest: String,
                                result: inout [String: UIKitTargetFingerprint]) {
        if !includeHidden, view.isHidden { return }
        let pathString = UIKitViewLookupTarget.pathString(from: path)
        result[pathString] = fingerprint(for: view, path: pathString, rootView: rootView, digest: digest)
        for (index, child) in view.subviews.enumerated() {
            collect(view: child,
                    rootView: rootView,
                    path: path + [index],
                    includeHidden: includeHidden,
                    digest: digest,
                    result: &result)
        }
    }

    /// 生成上下文摘要（顶部控制器类型名）。
    static func digest(topViewController: UIViewController) -> String {
        String(describing: Swift.type(of: topViewController))
    }
}
#endif
