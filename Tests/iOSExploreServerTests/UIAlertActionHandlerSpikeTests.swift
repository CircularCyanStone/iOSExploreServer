#if canImport(UIKit)
import ObjectiveC
import Testing
import UIKit

private var spikeCapturedHandlerKey: UInt8 = 0

/// `UIAlertAction` handler 触发路线的临时 spike。
///
/// 这些测试不落生产能力，只回答当前系统版本下 runtime 结构是否可用：
/// 1. action 内部是否能找到可调用 block；
/// 2. `@convention(block) (UIAlertAction) -> Void` 调用是否真正跑 handler；
/// 3. hook `initWithTitle:style:handler:` 后，关联对象捕获是否可用。
@MainActor
@Suite("UIAlertAction handler spike", .serialized)
struct UIAlertActionHandlerSpikeTests {
    @Test("KVC/ivar 兜底路径能取到并调用 handler block")
    func kvcFallbackFindsAndCallsHandler() throws {
        let cases = SpikeAlertFactory.makeCases()
        var conclusions: [String] = []

        for spikeCase in cases {
            guard let action = spikeCase.alert.actions.first(where: { $0.title == spikeCase.buttonTitle }) else {
                Issue.record("missing action \(spikeCase.buttonTitle) in \(spikeCase.name)")
                continue
            }

            let probe = UIAlertActionPrivateProbe.findHandlerBlock(in: action)
            print("UIAlertAction spike case=\(spikeCase.name) paths=\(probe.tracedPaths.joined(separator: " | "))")
            guard let block = probe.block else {
                Issue.record("handler block not found for \(spikeCase.name)")
                continue
            }

            if probe.path == "action._handler",
               let kvcBlock = action.value(forKey: "handler") as AnyObject? {
                print("UIAlertAction spike KVC key=handler type=\(type(of: kvcBlock))")
            } else {
                Issue.record("KVC key handler did not resolve for \(spikeCase.name)")
            }

            let handler = unsafeBitCast(block, to: SpikeAlertFactory.HandlerBlock.self)
            handler(action)
            conclusions.append("\(spikeCase.name): \(probe.path ?? "(unknown)")")
        }

        #expect(SpikeAlertFactory.events.contains("simple:确认"))
        #expect(SpikeAlertFactory.events.contains("threeButtons:收藏"))
        #expect(SpikeAlertFactory.events.contains("loginInput:登录 user=codex"))
        #expect(SpikeAlertFactory.events.contains("actionSheet:拍照"))
        #expect(SpikeAlertFactory.events.contains("nested:步骤1 继续"))
        try triggerNestedSecondAlert()
        #expect(SpikeAlertFactory.events.contains("nested:步骤2 完成"))
        print("UIAlertAction spike KVC conclusions=\(conclusions.joined(separator: "; "))")
    }

    @Test("swizzle init 后能用关联对象触发 handler")
    func swizzleCaptureStoresHandler() throws {
        try UIAlertActionSpikeSwizzler.install()
        var calledTitle: String?
        let action = UIAlertAction(title: "确认", style: .default) { selected in
            calledTitle = selected.title
        }

        guard let captured = objc_getAssociatedObject(action, &spikeCapturedHandlerKey) else {
            Issue.record("associated handler not captured")
            return
        }

        let capturedObject = captured as AnyObject
        let handler = unsafeBitCast(capturedObject, to: SpikeAlertFactory.HandlerBlock.self)
        handler(action)
        #expect(calledTitle == "确认")
        print("UIAlertAction spike swizzle captured handler type=\(type(of: capturedObject))")
    }

    private func triggerNestedSecondAlert() throws {
        let second = try #require(SpikeAlertFactory.nestedSecondAlert)
        let action = try #require(second.actions.first(where: { $0.title == "完成" }))
        let probe = UIAlertActionPrivateProbe.findHandlerBlock(in: action)
        let block = try #require(probe.block)
        let handler = unsafeBitCast(block, to: SpikeAlertFactory.HandlerBlock.self)
        handler(action)
        print("UIAlertAction spike nested second path=\(probe.path ?? "(unknown)")")
    }
}

private enum UIAlertActionPrivateProbe {
    struct Result {
        let path: String?
        let block: AnyObject?
        let tracedPaths: [String]
    }

    static func findHandlerBlock(in action: UIAlertAction) -> Result {
        var traces: [String] = []
        var visited = Set<ObjectIdentifier>()
        if let found = inspect(object: action, path: "action", depth: 0, traces: &traces, visited: &visited) {
            return Result(path: found.path, block: found.block, tracedPaths: traces)
        }
        return Result(path: nil, block: nil, tracedPaths: traces)
    }

    private static func inspect(object: AnyObject,
                                path: String,
                                depth: Int,
                                traces: inout [String],
                                visited: inout Set<ObjectIdentifier>) -> (path: String, block: AnyObject)? {
        guard depth <= 3 else { return nil }
        let identity = ObjectIdentifier(object)
        guard !visited.contains(identity) else { return nil }
        visited.insert(identity)

        var currentClass: AnyClass? = object_getClass(object)
        while let cls = currentClass {
            var count: UInt32 = 0
            guard let ivars = class_copyIvarList(cls, &count) else {
                currentClass = class_getSuperclass(cls)
                continue
            }
            defer { free(ivars) }

            for index in 0..<Int(count) {
                let ivar = ivars[index]
                guard let cName = ivar_getName(ivar) else { continue }
                let name = String(cString: cName)
                let encoding = ivar_getTypeEncoding(ivar).map { String(cString: $0) } ?? "?"
                let nextPath = "\(path).\(name)"
                guard encoding.hasPrefix("@"), let rawValue = object_getIvar(object, ivar) else {
                    traces.append("\(nextPath): \(encoding)")
                    continue
                }
                let value = rawValue as AnyObject

                let valueClass = NSStringFromClass(type(of: value))
                traces.append("\(nextPath): \(encoding) -> \(valueClass)")
                if isBlock(value, encoding: encoding, className: valueClass) {
                    return (nextPath, value)
                }
                if shouldRecurse(into: valueClass),
                   let nested = inspect(object: value, path: nextPath, depth: depth + 1, traces: &traces, visited: &visited) {
                    return nested
                }
            }
            currentClass = class_getSuperclass(cls)
        }
        return nil
    }

    private static func isBlock(_ value: AnyObject, encoding: String, className: String) -> Bool {
        encoding == "@?" || className.contains("Block")
    }

    private static func shouldRecurse(into className: String) -> Bool {
        className.contains("UIAlert")
            || className.contains("Action")
            || className.contains("Controller")
    }
}

private enum UIAlertActionSpikeSwizzler {
    private static var installed = false
    private static var replacementIMP: IMP?

    static func install() throws {
        guard !installed else { return }
        let original = NSSelectorFromString("actionWithTitle:style:handler:")
        guard let originalMethod = class_getClassMethod(UIAlertAction.self, original) else {
            throw SpikeFailure("missing original actionWithTitle:style:handler:")
        }
        let originalIMP = method_getImplementation(originalMethod)
        typealias OriginalFactory = @convention(c) (AnyClass, Selector, NSString?, Int, AnyObject?) -> AnyObject
        let originalFunction = unsafeBitCast(originalIMP, to: OriginalFactory.self)
        let replacement: @convention(block) (AnyClass, NSString?, Int, AnyObject?) -> AnyObject = { actionClass, title, style, handler in
            let action = originalFunction(actionClass, original, title, style, handler)
            if let handler {
                objc_setAssociatedObject(action,
                                         &spikeCapturedHandlerKey,
                                         handler,
                                         .OBJC_ASSOCIATION_COPY_NONATOMIC)
            }
            return action
        }
        replacementIMP = imp_implementationWithBlock(replacement)
        guard let replacementIMP else {
            throw SpikeFailure("failed to create replacement IMP")
        }
        method_setImplementation(originalMethod, replacementIMP)
        installed = true
    }
}

private struct SpikeFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private enum SpikeAlertFactory {
    typealias HandlerBlock = @convention(block) (UIAlertAction) -> Void

    struct SpikeCase {
        let name: String
        let alert: UIAlertController
        let buttonTitle: String
    }

    private(set) static var events: [String] = []
    private(set) static var nestedSecondAlert: UIAlertController?

    static func makeCases() -> [SpikeCase] {
        events = []
        nestedSecondAlert = nil
        return [
            makeSimple(),
            makeThreeButtons(),
            makeLoginInput(),
            makeActionSheet(),
            makeNested(),
        ]
    }

    private static func makeSimple() -> SpikeCase {
        let alert = UIAlertController(title: "确认操作", message: "是否继续执行此操作？", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in events.append("simple:取消") })
        alert.addAction(UIAlertAction(title: "确认", style: .default) { _ in events.append("simple:确认") })
        return SpikeCase(name: "simple", alert: alert, buttonTitle: "确认")
    }

    private static func makeThreeButtons() -> SpikeCase {
        let alert = UIAlertController(title: "文件操作", message: "选择对当前文件的操作", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { _ in events.append("threeButtons:删除") })
        alert.addAction(UIAlertAction(title: "收藏", style: .default) { _ in events.append("threeButtons:收藏") })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in events.append("threeButtons:取消") })
        return SpikeCase(name: "threeButtons", alert: alert, buttonTitle: "收藏")
    }

    private static func makeLoginInput() -> SpikeCase {
        let alert = UIAlertController(title: "登录", message: "请输入账号和密码", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "用户名"
            textField.text = "codex"
        }
        alert.addTextField { textField in
            textField.placeholder = "密码"
            textField.isSecureTextEntry = true
            textField.text = "secret"
        }
        alert.addAction(UIAlertAction(title: "登录", style: .default) { _ in
            let user = alert.textFields?[0].text ?? ""
            events.append("loginInput:登录 user=\(user)")
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in events.append("loginInput:取消") })
        return SpikeCase(name: "loginInput", alert: alert, buttonTitle: "登录")
    }

    private static func makeActionSheet() -> SpikeCase {
        let sheet = UIAlertController(title: "选择图片来源", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "拍照", style: .default) { _ in events.append("actionSheet:拍照") })
        sheet.addAction(UIAlertAction(title: "从相册选择", style: .default) { _ in events.append("actionSheet:从相册选择") })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in events.append("actionSheet:取消") })
        return SpikeCase(name: "actionSheet", alert: sheet, buttonTitle: "拍照")
    }

    private static func makeNested() -> SpikeCase {
        let first = UIAlertController(title: "步骤 1 / 2", message: "点击继续弹出第二个 alert", preferredStyle: .alert)
        first.addAction(UIAlertAction(title: "继续", style: .default) { _ in
            events.append("nested:步骤1 继续")
            let second = UIAlertController(title: "步骤 2 / 2", message: "这是第二个 alert", preferredStyle: .alert)
            second.addAction(UIAlertAction(title: "完成", style: .default) { _ in events.append("nested:步骤2 完成") })
            nestedSecondAlert = second
        })
        first.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in events.append("nested:步骤1 取消") })
        return SpikeCase(name: "nested", alert: first, buttonTitle: "继续")
    }
}
#endif
