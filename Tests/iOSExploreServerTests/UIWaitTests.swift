#if canImport(UIKit)
import UIKit
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

/// `ui.wait` 执行核心的 iOS 测试。
///
/// 覆盖 5 种模式的主路径、超时收敛、cancel 收敛（防 CancellationError 泄漏成 internal_error）。
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

@Test("wait idle 连续 stableMs 不变后满足") @MainActor
func waitIdleSatisfiedAfterStableWindow() async throws {
    let context = UIKitTestHost.context { root in
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 20))
        label.text = "稳定"
        root.addSubview(label)
    }
    // view 树不变 → activitySignature 不变 → 连续 stableMs 后满足。
    let input = UIWaitInput(mode: .idle, timeoutMs: 2000, intervalMs: 50, stableMs: 120)
    let data = try await UIWaitExecutor.execute(input: input) { context }
    #expect(data["satisfied"]?.boolValue == true)
    #expect(data["mode"]?.stringValue == "idle")
}

@Test("wait targetGone 目标消失后满足") @MainActor
func waitTargetGoneSatisfiedAfterRemoval() async throws {
    let tempView = UIView()
    tempView.accessibilityIdentifier = "temp"
    let context = UIKitTestHost.context { root in
        root.addSubview(tempView)
    }
    let target = try UIKitViewLookupTarget.parse(identifier: "temp", rawPath: nil)
    // 第二轮移除目标：contextProvider 闭包驱动 view 树变化。
    var callCount = 0
    let input = UIWaitInput(mode: .targetGone, timeoutMs: 2000, intervalMs: 50, target: target)
    let data = try await UIWaitExecutor.execute(input: input) {
        callCount += 1
        if callCount > 1 { tempView.removeFromSuperview() }
        return context
    }
    #expect(data["satisfied"]?.boolValue == true)
}

@Test("wait snapshotChanged 整体指纹表变化后满足") @MainActor
func waitSnapshotChangedSatisfiedOnContentChange() async throws {
    let button = UIButton(type: .system)
    button.accessibilityIdentifier = "btn"
    button.isEnabled = true
    button.frame = CGRect(x: 10, y: 10, width: 100, height: 40)
    let context = UIKitTestHost.context { root in
        root.addSubview(button)
    }
    // 用初始 view 树签发 snapshot（whole table；UIButton 是 control，被 default query 采集）。
    let digest = UIKitFingerprintCollector.digest(topViewController: context.topViewController)
    let initialTable = UIKitFingerprintCollector.collectFingerprints(
        rootView: context.rootView, query: .default, digest: digest)
    let snapshotContext = UIKitFingerprintCollector.context(
        window: context.window, topViewController: context.topViewController)
    let snapshotID = try #require(UIKitSnapshotStore.shared.insert(context: snapshotContext, targets: initialTable, query: .default))

    // 第二轮改 button.enabled → fingerprint 的 isEnabled 字段变化 → whole table 不同 → satisfied。
    // 注意：fingerprint 不含 text（防泄露），text 变化应用 textExists；snapshotChanged 检测结构/控件状态变化。
    var callCount = 0
    let input = UIWaitInput(mode: .snapshotChanged, timeoutMs: 2000, intervalMs: 50, snapshotID: snapshotID)
    let data = try await UIWaitExecutor.execute(input: input) {
        callCount += 1
        if callCount > 1 { button.isEnabled = false }
        return context
    }
    #expect(data["satisfied"]?.boolValue == true)
}

@Test("wait cancel 收敛到 waitTimeout 而非 internal_error") @MainActor
func waitCancellationConvergesToWaitTimeout() async {
    let context = UIKitTestHost.context { _ in }
    let input = UIWaitInput(mode: .textExists, timeoutMs: 10_000, intervalMs: 50, stableMs: 0, text: "不存在")
    let task = Task<JSON, Error> {
        try await UIWaitExecutor.execute(input: input) { context }
    }
    // 让 executor 进入轮询后 cancel，验证收敛到 waitTimeout（不泄漏 CancellationError）。
    let clock = ContinuousClock()
    let start = clock.now
    try? await Task.sleep(nanoseconds: 150_000_000)
    task.cancel()
    do {
        _ = try await task.value
        Issue.record("expected waitTimeout, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .waitTimeout)
        // 关键回归保护：cancel 必须在远小于 timeoutMs(10s) 内收敛，证明是 cancel 短路而非自然
        // deadline。若有人删掉 UIWaitExecutor 的 Task.isCancelled 检查，cancel 被忽略、`try?`
        // 吞掉 CancellationError 后命令会跑满 10s 才靠自然 deadline 抛 waitTimeout——code 仍是
        // waitTimeout 但耗时接近 10s，本断言会失败。
        let elapsed = start.duration(to: clock.now)
        #expect(elapsed < .seconds(2), "cancel should short-circuit within 2s, took \(elapsed)")
    } catch {
        Issue.record("unexpected error (expected waitTimeout): \(error)")
    }
}

@Test("wait idle stableMs=0 稳定两帧后满足") @MainActor
func waitIdleStableMsZeroSatisfiedWhenStable() async throws {
    let context = UIKitTestHost.context { root in
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 20))
        label.text = "稳定"
        root.addSubview(label)
    }
    // view 树不变：首轮写入签名，第二轮 signature 一致 → stableMs=0 也满足，但需 attempts>=2。
    let input = UIWaitInput(mode: .idle, timeoutMs: 2000, intervalMs: 50, stableMs: 0)
    let data = try await UIWaitExecutor.execute(input: input) { context }
    #expect(data["satisfied"]?.boolValue == true)
    #expect((data["attempts"]?.doubleValue ?? 0) >= 2)
}

@Test("wait idle stableMs=0 每轮变化永不满足") @MainActor
func waitIdleStableMsZeroChangingNeverSatisfied() async {
    let context = UIKitTestHost.context { root in
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 20))
        label.text = "初始"
        root.addSubview(label)
    }
    // 每轮改文本 → activitySignature 每轮变 → 变化当轮不算稳定，stableMs=0 也不应 satisfied。
    let label = context.rootView.subviews.first as? UILabel
    var callCount = 0
    let input = UIWaitInput(mode: .idle, timeoutMs: 400, intervalMs: 50, stableMs: 0)
    do {
        _ = try await UIWaitExecutor.execute(input: input) {
            callCount += 1
            label?.text = "变\(callCount)"
            return context
        }
        Issue.record("expected waitTimeout, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .waitTimeout)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}
#endif
