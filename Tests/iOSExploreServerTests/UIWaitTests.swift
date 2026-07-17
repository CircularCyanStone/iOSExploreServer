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
    let snapshotStore = UIKitSnapshotStore()
    let snapshotID = try #require(snapshotStore.insert(context: snapshotContext, targets: initialTable, query: .default))

    // 第二轮改 button.enabled → fingerprint 的 isEnabled 字段变化 → whole table 不同 → satisfied。
    // 注意：fingerprint 不含 text（防泄露），text 变化应用 textExists；snapshotChanged 检测结构/控件状态变化。
    var callCount = 0
    let input = UIWaitInput(mode: .snapshotChanged, timeoutMs: 2000, intervalMs: 50, viewSnapshotID: snapshotID)
    let data = try await UIWaitExecutor.execute(input: input, snapshotStore: snapshotStore) {
        callCount += 1
        if callCount > 1 { button.isEnabled = false }
        return context
    }
    #expect(data["satisfied"]?.boolValue == true)
}

@Test("wait snapshotChanged 视图树不变时超时不满足（无假阳性）") @MainActor
func waitSnapshotChangedUnchangedWhenViewTreeStable() async throws {
    let button = UIButton(type: .system)
    button.accessibilityIdentifier = "stable-btn"
    button.isEnabled = true
    button.frame = CGRect(x: 10, y: 10, width: 100, height: 40)
    let context = UIKitTestHost.context { root in
        root.addSubview(button)
    }
    // 用初始 view 树签发 snapshot（whole table）。
    let digest = UIKitFingerprintCollector.digest(topViewController: context.topViewController)
    let initialTable = UIKitFingerprintCollector.collectFingerprints(
        rootView: context.rootView, query: .default, digest: digest)
    let snapshotContext = UIKitFingerprintCollector.context(
        window: context.window, topViewController: context.topViewController)
    let snapshotStore = UIKitSnapshotStore()
    let snapshotID = try #require(snapshotStore.insert(context: snapshotContext, targets: initialTable, query: .default))

    // 不改任何东西 → 重采 whole table 与签发表逐字相等 → matchesWholeTable 返回 true（未变化）
    // → executor 永远不 satisfied → 超时收敛 waitTimeout。这条保护「未变化」负样本，
    // 防止 collectMatching 与签发口径意外漂移导致首轮即误报 changed。
    let input = UIWaitInput(mode: .snapshotChanged, timeoutMs: 300, intervalMs: 50, viewSnapshotID: snapshotID)
    do {
        _ = try await UIWaitExecutor.execute(input: input, snapshotStore: snapshotStore) { context }
        Issue.record("expected waitTimeout (table unchanged), got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .waitTimeout)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("wait snapshotChanged 检测 full 节点 UILabel 状态变化（v1 漏掉场景）") @MainActor
func waitSnapshotChangedDetectsFullNodeLabelTextChange() async throws {
    // UILabel 自身非 UIControl：v1（shouldInclude 3 条白名单）不会把它采集进指纹表，
    // 故 cell / 容器内 UILabel 的任何变化在 v1 下都检测不到；v2 isFull 六条里 hasStaticText
    // 命中 → label 进入签发表，其状态变化（isHidden / alpha / 显式 a11y label 等）被指纹字段
    // 捕获 → whole table 不一致被检出。本测试锁定该 v2 修复不被回退。
    //
    // 注意触发方式：用 `isHidden`（fingerprint 顶层字段，稳定可检测）。**不**用 `label.text`：
    // fingerprint 出于隐私不存文本，且 UILabel.accessibilityLabel 在未显式赋值时 getter 返回
    // nil（iOS 的「文本兜底」发生在 UIAccessibility 解析层，不进属性 getter），故 text 变化
    // 不会让 semanticDigest 变化——纯文本内容变化应走 textExists 模式（见同文件既有注释）。
    let label = UILabel(frame: CGRect(x: 10, y: 10, width: 200, height: 30))
    label.text = "提交"
    let context = UIKitTestHost.context { root in
        root.addSubview(label)
    }
    let digest = UIKitFingerprintCollector.digest(topViewController: context.topViewController)
    let initialTable = UIKitFingerprintCollector.collectFingerprints(
        rootView: context.rootView, query: .default, digest: digest)
    // 回归保护：带静态文本的 UILabel 必须被签发进 whole table（v1 漏掉的就是它根本不在表里）。
    #expect(!initialTable.isEmpty, "UILabel with non-empty text must be a full node (hasStaticText)")

    let snapshotContext = UIKitFingerprintCollector.context(
        window: context.window, topViewController: context.topViewController)
    let snapshotStore = UIKitSnapshotStore()
    let snapshotID = try #require(snapshotStore.insert(context: snapshotContext, targets: initialTable, query: .default))

    // 第二轮隐藏 label → fingerprint 的 isHidden 字段从 false 变 true → whole table 不同 → satisfied。
    var callCount = 0
    let input = UIWaitInput(mode: .snapshotChanged, timeoutMs: 2000, intervalMs: 50, viewSnapshotID: snapshotID)
    let data = try await UIWaitExecutor.execute(input: input, snapshotStore: snapshotStore) {
        callCount += 1
        if callCount > 1 { label.isHidden = true }
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
    // 用 systemUptime(monotonic, iOS 2+)替代 ContinuousClock(iOS 16+),保持部署目标 iOS 13 可编译
    let start = ProcessInfo.processInfo.systemUptime
    try? await Task.sleep(nanoseconds: 150_000_000)
    task.cancel()
    do {
        _ = try await task.value
        Issue.record("expected waitTimeout, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .waitTimeout)
        // 关键回归保护：cancel 必须在远小于 timeoutMs(10s) 内收敛，证明是 cancel 短路而非自然
        // deadline。iOS 模拟器全量测试时 MainActor 负载会带来秒级抖动，因此阈值保留到
        // 6s：若有人删掉 UIWaitExecutor 的 Task.isCancelled 检查，cancel 被忽略、`try?`
        // 吞掉 CancellationError 后命令会跑满 10s 才靠自然 deadline 抛 waitTimeout，仍会失败。
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        #expect(elapsed < 6, "cancel should short-circuit well before 10s, took \(elapsed)s")
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
