#if canImport(UIKit)
import UIKit
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

/// `ui.wait` 执行核心的 iOS 测试。
///
/// 覆盖 textExists 命中、textExists 超时收敛到 waitTimeout、targetExists 命中三条主路径。
/// executor 通过注入 `contextProvider` 闭包驱动，不依赖真实 App scene。

@Test("wait textExists 找到 UILabel 文本") @MainActor
func waitTextExistsFindsLabel() async throws {
    let context = UIKitTestHost.context { root in
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 20))
        label.text = "订单详情"
        root.addSubview(label)
    }
    let input = UIWaitInput(mode: .textExists, timeoutMs: 1000, intervalMs: 50, stableMs: 100, text: "订单")
    let data = try await UIWaitExecutor.execute(input: input) { context }
    #expect(data["satisfied"]?.boolValue == true)
    #expect(data["mode"]?.stringValue == "textExists")
}

@Test("wait textExists 超时返回 waitTimeout") @MainActor
func waitTextExistsTimeoutReturnsWaitTimeout() async {
    let context = UIKitTestHost.context { _ in }
    let input = UIWaitInput(mode: .textExists, timeoutMs: 100, intervalMs: 50, stableMs: 0, text: "不存在")
    do {
        _ = try await UIWaitExecutor.execute(input: input) { context }
        Issue.record("expected waitTimeout, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .waitTimeout)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("wait targetExists 找到 view") @MainActor
func waitTargetExistsFindsView() async throws {
    let context = UIKitTestHost.context { root in
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = "submit"
        button.frame = CGRect(x: 10, y: 10, width: 100, height: 40)
        root.addSubview(button)
    }
    let target = try UIKitViewLookupTarget.parse(identifier: "submit", rawPath: nil)
    let input = UIWaitInput(mode: .targetExists, timeoutMs: 500, intervalMs: 50, target: target)
    let data = try await UIWaitExecutor.execute(input: input) { context }
    #expect(data["satisfied"]?.boolValue == true)
}
#endif
