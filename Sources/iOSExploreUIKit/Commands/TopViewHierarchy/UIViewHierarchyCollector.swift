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
    static func collectTopViewHierarchy(query: UIViewHierarchyInput) throws -> JSON {
        UIKitCommandLogging.info("command", "ui hierarchy collect mainactor start detailLevel=\(query.detailLevel.rawValue) maxDepth=\(query.maxDepth.map(String.init) ?? "none") includeHidden=\(query.includeHidden) hasFilter=\(query.hasIdentifierFilter)")
        let context = try UIKitContextProvider.currentContext(action: TopViewHierarchyCommand.actionName)
        return try collectTopViewHierarchy(query: query, context: context)
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
    static func collectTopViewHierarchy(query: UIViewHierarchyInput, context: UIKitContextProvider.Context) throws -> JSON {
        let targetController: UIViewController
        let controllerLog: String
        let isControllerOverride: Bool
        if let controllerPath = query.controller {
            guard let parsed = parseControllerPath(controllerPath) else {
                UIKitCommandLogging.error("command", "ui hierarchy collect controller path parse failed path=\(controllerPath)")
                throw UIKitCommandError.invalidData(
                    action: TopViewHierarchyCommand.actionName,
                    message: "invalid controller path: \(controllerPath)"
                )
            }
            do {
                targetController = try UIControllerResolver.resolve(from: context.rootViewController, path: parsed)
                if !targetController.isViewLoaded {
                    UIKitCommandLogging.info("command", "ui hierarchy collect controller view not loaded, calling loadViewIfNeeded() path=\(controllerPath)")
                    targetController.loadViewIfNeeded()
                }
                controllerLog = controllerPath
                isControllerOverride = true
            } catch let resolveError as UIKitCommandError {
                UIKitCommandLogging.error("command", resolveError.failure.logMessage)
                throw resolveError
            } catch {
                UIKitCommandLogging.error("command", "ui hierarchy collect controller resolve failed path=\(controllerPath) error=\(error)")
                throw UIKitCommandError.targetNotFound(
                    action: TopViewHierarchyCommand.actionName,
                    message: "controller path not found: \(controllerPath)",
                    logMessage: "ui hierarchy collect controller resolve unexpected action=\(TopViewHierarchyCommand.actionName) path=\(controllerPath) error=\(error)"
                )
            }
        } else {
            targetController = context.topViewController
            controllerLog = "default"
            isControllerOverride = false
        }
        guard let rootView = targetController.view else {
            UIKitCommandLogging.error("command", "ui hierarchy collect controller view is nil path=\(controllerLog)")
            throw UIKitCommandError.hierarchyUnavailable(
                action: TopViewHierarchyCommand.actionName,
                reason: "controller view is nil (path=\(controllerLog))"
            )
        }
        UIKitCommandLogging.info("command", "ui hierarchy collect start controller=\(controllerLog) detailLevel=\(query.detailLevel.rawValue) maxDepth=\(query.maxDepth.map(String.init) ?? "none") includeHidden=\(query.includeHidden) hasFilter=\(query.hasIdentifierFilter)")

        let element = UIKitViewElement(view: rootView)

        var data: JSON = [
            "screen": .object(screenJSON(window: context.window,
                                         rootViewController: context.rootViewController,
                                         topViewController: context.topViewController)),
            "detailLevel": .string(query.detailLevel.rawValue),
        ]
        // 带 controller 参数时只输出元信息和 matches，不输出 root 树中的 path（路径文案已在描述、controllerNote
        // 和 controller 参数名中说明），因为路径相对于目标 controller view，与 ui.inspect / ui.tap 以当前栈顶
        // view 为根的语义不匹配。其余结构 / color / font / indexPath 等观察字段全部保留。
        if isControllerOverride {
            let root = UIViewHierarchyBuilder.build(from: element, query: query)
            data["controller"] = .string(controllerLog)
            data["controllerNote"] = .string("传入 controller 参数采集的视图层级来自非栈顶控制器，节点 path 相对于该控制器 view 而非当前栈顶 view，不可用于 ui.tap / ui.inspect / ui.control.sendAction 等操作的定位。要获取可操作 target 请用不带 controller 参数的 ui.inspect。")
            data["root"] = .object(root.toJSON(includePath: false))
            data["nodeCount"] = .double(Double(root.nodeCount))
            UIKitCommandLogging.info("command", "ui hierarchy collect completed mode=controllerNote nodeCount=\(root.nodeCount) controllerPath=\(controllerLog)")
        } else {
            let root = UIViewHierarchyBuilder.build(from: element, query: query)
            // topViewHierarchy 不签发 viewSnapshotID：结构化 freshness / locator 签发是 ui.inspect
            // 的专属职责（spec §1.2）。这里只输出页面结构供观察/排障，不参与 tap/sendAction 陈旧校验。
            data["nodeCount"] = .double(Double(root.nodeCount))
            // 与 ui.inspect 同口径暴露 navigationBar 摘要，避免出现「viewTargets 看得到、
            // topViewHierarchy 看不到」的分叉；深度排查与普通观察用同一份导航栏语义。
            data["navigationBar"] = .object(
                UINavigationBarInspector.summarize(topViewController: context.topViewController).toJSON()
            )
            if query.hasIdentifierFilter {
                let matches = UIViewHierarchyBuilder.matches(in: element, query: query)
                data["matches"] = .array(matches.map { .object($0.toJSON()) })
                data["matchCount"] = .double(Double(matches.count))
                UIKitCommandLogging.info("command", "ui hierarchy collect completed mode=matches nodeCount=\(root.nodeCount) matchCount=\(matches.count)")
            } else {
                data["root"] = .object(root.toJSON())
                UIKitCommandLogging.info("command", "ui hierarchy collect completed mode=root nodeCount=\(root.nodeCount) rootType=\(root.type)")
            }
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
    /// 子元素，顺序与真实 `subviews` 顺序一致。
    let subviews: [UIKitViewElement]
    /// cell 的 indexPath（仅 `UITableViewCell`/`UICollectionViewCell` 节点有效）。
    let _indexPath: IndexPathSummary?

    /// 实现 `UIViewHierarchyElement.indexPath`，返回 cell 的 indexPath。
    var indexPath: IndexPathSummary? { _indexPath }

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
            // `UIView.tintColor` 在 UIKit 中的声明类型是 `UIColor!`（隐式解包可选），
            // 当 view 处于 tintColorDidChange 传播/动画过渡/脱离 window 等情况时会返回 nil，
            // 直接 `.hierarchyHexString` 会触发 `Fatal error: Unexpectedly found nil while
            // implicitly unwrapping an Optional value`，导致 App 整个 hang。这里强制走
            // optional unwrap → nil 即写 `tintColor: null`，避免崩溃。
            // 见 docs/investigations/mcp-spim-example-e2e-issues.md P2。
            tintColor: view.tintColor?.hierarchyHexString,
            cornerRadius: Double(view.layer.cornerRadius),
            borderWidth: Double(view.layer.borderWidth),
            borderColor: view.layer.borderColor.flatMap { UIColor(cgColor: $0).hierarchyHexString }
        )
        self.control = Self.controlInfo(from: view)
        self.image = Self.imageInfo(from: view)
        self.scroll = Self.scrollInfo(from: view)
        // 采集子视图前先做 window 归属守卫：sendAction (UISegmentedControl/UIStepper 等)
        // 之后短暂窗口内 subviews 数组可能含已脱离层级的过渡 view，对它们继续递归会读到
        // 不一致的 superview/window 状态、放大 nil-unwrap 风险。仍把这种 view 作为节点
        // 计入根（保持 nodeCount），但它不进入 window 层级时子树标空，避免错误的子树快照。
        let isInWindowHierarchy = Self.isAttachedToWindow(view)
        let subviews: [UIView]
        if isInWindowHierarchy {
            subviews = view.subviews
        } else {
            UIKitCommandLogging.info("command", "ui hierarchy collect skip detached subtree type=\(self.type) reason=nil-window")
            subviews = []
        }
        self.subviews = subviews.map { UIKitViewElement(view: $0) }
        self._indexPath = Self.cellIndexPath(from: view)
    }

    /// 提取 `UITableViewCell` / `UICollectionViewCell` 的 indexPath。
    ///
    /// 通过 `tableView.indexPath(for:)` / `collectionView.indexPath(for:)` 公有 API 定位。
    /// cell 正在动画、不在 visibleCells 内、或不是 cell 时返回 `nil`（不报错）。
    @MainActor
    private static func cellIndexPath(from view: UIView) -> IndexPathSummary? {
        if let cell = view as? UITableViewCell, let tv = cell.superview as? UITableView {
            guard let ip = tv.indexPath(for: cell) else { return nil }
            return IndexPathSummary(section: ip.section, item: ip.row)
        }
        if let cell = view as? UICollectionViewCell, let cv = cell.superview as? UICollectionView {
            guard let ip = cv.indexPath(for: cell) else { return nil }
            return IndexPathSummary(section: ip.section, item: ip.item)
        }
        return nil
    }

    /// 判断一个 view 是否仍处在 window 层级之中（superview 链可达 keyWindow）。
    ///
    /// 用于在 `init(view:)` 采集子树前做守卫：`UIControl.sendAction` 之后某些控件（如
    /// `UISegmentedControl` 切段、`UIStepper` 加减、`UITextField` 切 first responder）的
    /// 子视图会短暂进入"已从父节点取下但 superview 引用还没 nil 化"的过渡态，继续递归会
    /// 读到不一致的属性。这里不阻断根节点本身（根节点一定是 rootView 的祖先链上的某个真实
    /// view），但避免对"已脱离 window 的过渡 view"再向下采集子树，把它们的 subviews 强制写空。
    ///
    /// - Parameter view: 待采集的 view。
    /// - Returns: `true` 当 view 仍在 window 层级中或本身就是 keyWindow；`false` 表示脱离。
    @MainActor
    private static func isAttachedToWindow(_ view: UIView) -> Bool {
        // 沿 superview 链向上走直到找到 `window != nil` 的祖先（含自身是 keyWindow 的情况，
        // 因为 UIWindow.window 返回 self，永远非 nil）。整条链都 window==nil 才视为脱离。
        // 比 `viewIfLoaded.window != nil` 更严：能覆盖 rootVC.view 已 viewDidLoad 但还未
        // 被 add 到 window 的过渡场景，但此时该 view 本也不会出现在 context.rootView 里。
        var current: UIView? = view
        while let candidate = current {
            if candidate.window != nil { return true }
            current = candidate.superview
        }
        return false
    }

    /// 提取文本验收信息。
    @MainActor
    private static func textInfo(from view: UIView) -> UIViewHierarchyText? {
        if let label = view as? UILabel {
            // `UILabel.textColor` 在 UIKit 中声明为 `UIColor!`（隐式解包可选）。某些过渡态
            // （如 UIStepper value 切换触发 cell 复用、UISegmentedControl 重置 segment）下
            // label.textColor 可能短暂为 nil，直接 `.hierarchyHexString` 会崩溃。改走
            // optional unwrap，nil 时写 textColor=null。见 P2。
            return UIViewHierarchyText(value: label.text,
                                       fontName: label.font.fontName,
                                       fontSize: Double(label.font.pointSize),
                                       textColor: label.textColor?.hierarchyHexString,
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
