#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// UIKit 视图层级采集器。
///
/// 所有 UIKit 访问都限制在 `MainActor`，避免在 network queue 或后台线程读取 UI 状态。
/// 采集器只读取 view 属性并生成快照，不修改业务 UI。
@MainActor
enum UIViewHierarchyCollector {
    /// 采集当前顶部控制器 view 层级并转换为命令响应。
    ///
    /// - Parameter query: 采集和筛选参数。
    /// - Returns: 层级 JSON。
    /// - Throws: `UIKitCommandError.hierarchyUnavailable`——UIKit 上下文不可用时。
    static func collectTopViewHierarchy(query: UIViewHierarchyQuery) throws -> JSON {
        UIKitCommandLogging.info("command", "ui hierarchy collect mainactor start detailLevel=\(query.detailLevel.rawValue) maxDepth=\(query.maxDepth.map(String.init) ?? "none") includeHidden=\(query.includeHidden) hasFilter=\(query.hasIdentifierFilter)")
        let context = try UIKitContextProvider.currentContext(action: TopViewHierarchyCommand.actionName)
        return collectTopViewHierarchy(query: query, context: context)
    }

    /// 采集顶部控制器 view 层级（注入入口：测试与内部复用）。
    ///
    /// 与 `collectTopViewHierarchy(query:)` 的唯一区别是上下文由调用方提供，使采集流程可在
    /// 测试里用可控 view 树驱动。其余逻辑完全一致。
    ///
    /// - Parameters:
    ///   - query: 采集和筛选参数。
    ///   - context: 当前 UIKit 查询上下文。
    /// - Returns: 层级 JSON。
    static func collectTopViewHierarchy(query: UIViewHierarchyQuery, context: UIKitContextProvider.Context) -> JSON {
        let element = UIKitViewElement(view: context.rootView)
        let root = UIViewHierarchyBuilder.build(from: element, query: query)
        let digest = UIKitFingerprintCollector.digest(topViewController: context.topViewController)
        let fingerprints = UIKitFingerprintCollector.fingerprints(in: context.rootView,
                                                                  includeHidden: query.includeHidden,
                                                                  digest: digest)
        let snapshotID = UIKitSnapshotStore.shared.insert(context: UIKitFingerprintCollector.context(window: context.window, topViewController: context.topViewController),
                                                          targets: fingerprints)
        let snapshotFields = UIKitSnapshotResponse.fields(for: snapshotID)
        var data: JSON = [
            "screen": .object(screenJSON(window: context.window,
                                         rootViewController: context.rootViewController,
                                         topViewController: context.topViewController)),
            "nodeCount": .double(Double(root.nodeCount)),
            "detailLevel": .string(query.detailLevel.rawValue),
            "snapshotID": snapshotFields.id,
            "snapshotUnavailableReason": snapshotFields.unavailableReason,
        ]

        if query.hasIdentifierFilter {
            let matches = UIViewHierarchyBuilder.matches(in: element, query: query)
            data["matches"] = .array(matches.map { .object($0.toJSON()) })
            data["matchCount"] = .double(Double(matches.count))
            UIKitCommandLogging.info("command", "ui hierarchy collect completed mode=matches nodeCount=\(root.nodeCount) matchCount=\(matches.count)")
        } else {
            data["root"] = .object(root.toJSON())
            UIKitCommandLogging.info("command", "ui hierarchy collect completed mode=root nodeCount=\(root.nodeCount) rootType=\(root.type)")
        }
        return data
    }

    /// 生成屏幕和控制器上下文。
    private static func screenJSON(window: UIWindow,
                                   rootViewController: UIViewController,
                                   topViewController: UIViewController) -> JSON {
        [
            "windowType": .string(String(describing: type(of: window))),
            "windowFrame": .object(UIViewHierarchyRect(rect: window.frame).toJSON()),
            "rootViewController": .string(String(describing: type(of: rootViewController))),
            "topViewController": .string(String(describing: type(of: topViewController))),
        ]
    }
}

/// UIKit view 的值快照。
///
/// 该类型在 MainActor 上从真实 `UIView` 递归读取属性，然后交给 Foundation-only builder
/// 生成 path、过滤和 JSON 节点。
private struct UIKitViewElement: UIViewHierarchyElement {
    let type: String
    let accessibility: UIViewHierarchyAccessibility
    let frame: UIViewHierarchyRect
    let bounds: UIViewHierarchyRect
    let state: UIViewHierarchyState
    let text: UIViewHierarchyText?
    let appearance: UIViewHierarchyAppearance?
    let control: UIViewHierarchyControl?
    let image: UIViewHierarchyImage?
    let scroll: UIViewHierarchyScroll?
    let subviews: [UIKitViewElement]

    /// 从 UIKit view 创建完整值快照。
    @MainActor
    init(view: UIView) {
        self.type = String(describing: Swift.type(of: view))
        self.accessibility = UIViewHierarchyAccessibility(
            identifier: view.accessibilityIdentifier,
            label: view.accessibilityLabel,
            value: view.accessibilityValue,
            hint: view.accessibilityHint
        )
        self.frame = UIViewHierarchyRect(rect: view.frame)
        self.bounds = UIViewHierarchyRect(rect: view.bounds)
        self.state = UIViewHierarchyState(isHidden: view.isHidden,
                                          alpha: Double(view.alpha),
                                          isOpaque: view.isOpaque,
                                          isUserInteractionEnabled: view.isUserInteractionEnabled)
        self.text = Self.textInfo(from: view)
        self.appearance = UIViewHierarchyAppearance(
            backgroundColor: view.backgroundColor?.hierarchyHexString,
            tintColor: view.tintColor.hierarchyHexString,
            cornerRadius: Double(view.layer.cornerRadius),
            borderWidth: Double(view.layer.borderWidth),
            borderColor: view.layer.borderColor.flatMap { UIColor(cgColor: $0).hierarchyHexString }
        )
        self.control = Self.controlInfo(from: view)
        self.image = Self.imageInfo(from: view)
        self.scroll = Self.scrollInfo(from: view)
        self.subviews = view.subviews.map { UIKitViewElement(view: $0) }
    }

    /// 提取文本验收信息。
    @MainActor
    private static func textInfo(from view: UIView) -> UIViewHierarchyText? {
        if let label = view as? UILabel {
            return UIViewHierarchyText(value: label.text,
                                       fontName: label.font.fontName,
                                       fontSize: Double(label.font.pointSize),
                                       textColor: label.textColor.hierarchyHexString,
                                       textAlignment: label.textAlignment.hierarchyDescription,
                                       numberOfLines: label.numberOfLines)
        }
        if let button = view as? UIButton {
            let label = button.titleLabel
            return UIViewHierarchyText(value: button.title(for: .normal) ?? button.currentTitle,
                                       fontName: label?.font.fontName,
                                       fontSize: label.map { Double($0.font.pointSize) },
                                       textColor: (button.titleColor(for: .normal) ?? button.currentTitleColor)?.hierarchyHexString,
                                       textAlignment: label?.textAlignment.hierarchyDescription,
                                       numberOfLines: label?.numberOfLines)
        }
        if let textField = view as? UITextField {
            return UIViewHierarchyText(value: textField.text,
                                       fontName: textField.font?.fontName,
                                       fontSize: textField.font.map { Double($0.pointSize) },
                                       textColor: textField.textColor?.hierarchyHexString,
                                       textAlignment: textField.textAlignment.hierarchyDescription,
                                       numberOfLines: 1)
        }
        if let textView = view as? UITextView {
            return UIViewHierarchyText(value: textView.text,
                                       fontName: textView.font?.fontName,
                                       fontSize: textView.font.map { Double($0.pointSize) },
                                       textColor: textView.textColor?.hierarchyHexString,
                                       textAlignment: textView.textAlignment.hierarchyDescription,
                                       numberOfLines: nil)
        }
        return nil
    }

    /// 提取 UIControl 状态。
    @MainActor
    private static func controlInfo(from view: UIView) -> UIViewHierarchyControl? {
        guard let control = view as? UIControl else { return nil }
        return UIViewHierarchyControl(isEnabled: control.isEnabled,
                                      isSelected: control.isSelected,
                                      isHighlighted: control.isHighlighted,
                                      horizontalAlignment: control.contentHorizontalAlignment.hierarchyDescription,
                                      verticalAlignment: control.contentVerticalAlignment.hierarchyDescription)
    }

    /// 提取图片验收信息。
    @MainActor
    private static func imageInfo(from view: UIView) -> UIViewHierarchyImage? {
        if let imageView = view as? UIImageView {
            return UIViewHierarchyImage(width: imageView.image.map { Double($0.size.width) },
                                        height: imageView.image.map { Double($0.size.height) },
                                        renderingMode: imageView.image?.renderingMode.hierarchyDescription,
                                        isHighlighted: imageView.isHighlighted)
        }
        if let button = view as? UIButton, let image = button.image(for: .normal) ?? button.currentImage {
            return UIViewHierarchyImage(width: Double(image.size.width),
                                        height: Double(image.size.height),
                                        renderingMode: image.renderingMode.hierarchyDescription,
                                        isHighlighted: button.isHighlighted)
        }
        return nil
    }

    /// 提取滚动容器信息。
    @MainActor
    private static func scrollInfo(from view: UIView) -> UIViewHierarchyScroll? {
        guard let scroll = view as? UIScrollView else { return nil }
        return UIViewHierarchyScroll(
            contentSize: UIViewHierarchyRect(x: 0,
                                             y: 0,
                                             width: Double(scroll.contentSize.width),
                                             height: Double(scroll.contentSize.height)),
            contentOffset: UIViewHierarchyRect(x: Double(scroll.contentOffset.x),
                                               y: Double(scroll.contentOffset.y),
                                               width: 0,
                                               height: 0),
            contentInset: scroll.contentInset.hierarchyJSON,
            isScrollEnabled: scroll.isScrollEnabled
        )
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

private extension UIColor {
    /// 转成 `#RRGGBB` 或 `#RRGGBBAA`。
    var hierarchyHexString: String? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return Self.hex(red: red, green: green, blue: blue, alpha: alpha)
        }
        var white: CGFloat = 0
        if getWhite(&white, alpha: &alpha) {
            return Self.hex(red: white, green: white, blue: white, alpha: alpha)
        }
        return nil
    }

    /// 生成 hex 字符串。
    private static func hex(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> String {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        let a = Int((alpha * 255).rounded())
        if a >= 255 {
            return String(format: "#%02X%02X%02X", r, g, b)
        }
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
}

private extension NSTextAlignment {
    /// 人类可读的文本对齐方式。
    var hierarchyDescription: String {
        switch self {
        case .left: return "left"
        case .center: return "center"
        case .right: return "right"
        case .justified: return "justified"
        case .natural: return "natural"
        @unknown default: return "unknown"
        }
    }
}

private extension UIControl.ContentHorizontalAlignment {
    /// 人类可读的水平内容对齐方式。
    var hierarchyDescription: String {
        switch self {
        case .center: return "center"
        case .left: return "left"
        case .right: return "right"
        case .fill: return "fill"
        case .leading: return "leading"
        case .trailing: return "trailing"
        @unknown default: return "unknown"
        }
    }
}

private extension UIControl.ContentVerticalAlignment {
    /// 人类可读的垂直内容对齐方式。
    var hierarchyDescription: String {
        switch self {
        case .center: return "center"
        case .top: return "top"
        case .bottom: return "bottom"
        case .fill: return "fill"
        @unknown default: return "unknown"
        }
    }
}

private extension UIImage.RenderingMode {
    /// 人类可读的图片渲染模式。
    var hierarchyDescription: String {
        switch self {
        case .automatic: return "automatic"
        case .alwaysOriginal: return "alwaysOriginal"
        case .alwaysTemplate: return "alwaysTemplate"
        @unknown default: return "unknown"
        }
    }
}

private extension UIEdgeInsets {
    /// 转为 JSON，保留 top/left/bottom/right。
    var hierarchyJSON: JSON {
        [
            "top": .double(Double(top)),
            "left": .double(Double(left)),
            "bottom": .double(Double(bottom)),
            "right": .double(Double(right)),
        ]
    }
}
#endif
