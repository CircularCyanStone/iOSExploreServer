import Testing
import Foundation
import iOSExploreServer
@testable import iOSExploreUIKit

/// `ui.waitAny` 的 typed input 解析与执行测试。
///
/// parse/schema 部分纯 Foundation（不依赖 UIKit），macOS SPM 与 iOS framework 均运行；
/// executor 部分用 `UIKitTestHost` 注入上下文，仅 iOS 运行，覆盖优先级、超时收敛、cancel 收敛、
/// 瞬时层级不可用容忍。

// MARK: - parse / schema（Foundation-only）

@Test("waitAny 合法多条件解析并填充共享字段默认值")
func waitAnyParsesMultipleConditions() throws {
    let data = JSON([
        "conditions": .array([
            .object(JSON(["id": "home", "mode": "targetExists", "accessibilityIdentifier": "home_tab"])),
            .object(JSON(["id": "err", "mode": "textExists", "text": "密码错误"])),
        ]),
        "timeoutMs": 8000,
    ])
    let input = try UIWaitAnyInput.parse(from: data)
    #expect(input.conditions.count == 2)
    #expect(input.conditions[0].id == "home")
    #expect(input.conditions[0].mode == .targetExists)
    #expect(input.conditions[0].target != nil)
    #expect(input.conditions[1].text == "密码错误")
    #expect(input.timeoutMs == 8000)
    #expect(input.intervalMs == 100)
    #expect(input.stableMs == 300)
    #expect(input.includeHidden == false)
}

@Test("waitAny conditions 缺失抛 invalid_data")
func waitAnyRejectsMissingConditions() {
    #expect(throws: CommandInputParseError.self) {
        try UIWaitAnyInput.parse(from: JSON([:]))
    }
}

@Test("waitAny conditions 非数组抛 invalid_data")
func waitAnyRejectsNonArrayConditions() {
    #expect(throws: CommandInputParseError.self) {
        try UIWaitAnyInput.parse(from: JSON(["conditions": "home"]))
    }
}

@Test("waitAny conditions 空数组抛 invalid_data")
func waitAnyRejectsEmptyConditions() {
    #expect(throws: CommandInputParseError.self) {
        try UIWaitAnyInput.parse(from: JSON(["conditions": .array([])]))
    }
}

@Test("waitAny conditions 超过上限(16)抛 invalid_data")
func waitAnyRejectsTooManyConditions() {
    var elements: [JSONValue] = []
    for index in 0..<17 {
        elements.append(.object(JSON(["id": .string("c\(index)"), "mode": "idle"])))
    }
    #expect(throws: CommandInputParseError.self) {
        try UIWaitAnyInput.parse(from: JSON(["conditions": .array(elements)]))
    }
}

@Test("waitAny 条件缺 id 抛 invalid_data")
func waitAnyRejectsMissingID() {
    let data = JSON(["conditions": .array([.object(JSON(["mode": "idle"]))])])
    #expect(throws: CommandInputParseError.self) {
        try UIWaitAnyInput.parse(from: data)
    }
}

@Test("waitAny 条件 id 为空抛 invalid_data")
func waitAnyRejectsEmptyID() {
    let data = JSON(["conditions": .array([.object(JSON(["id": "", "mode": "idle"]))])])
    #expect(throws: CommandInputParseError.self) {
        try UIWaitAnyInput.parse(from: data)
    }
}

@Test("waitAny 重复 id 抛 invalid_data")
func waitAnyRejectsDuplicateID() {
    let data = JSON(["conditions": .array([
        .object(JSON(["id": "dup", "mode": "idle"])),
        .object(JSON(["id": "dup", "mode": "idle"])),
    ])])
    #expect(throws: CommandInputParseError.self) {
        try UIWaitAnyInput.parse(from: data)
    }
}

@Test("waitAny 未知 mode 抛 invalid_data")
func waitAnyRejectsUnknownMode() {
    let data = JSON(["conditions": .array([.object(JSON(["id": "x", "mode": "nope"]))])])
    #expect(throws: CommandInputParseError.self) {
        try UIWaitAnyInput.parse(from: data)
    }
}

@Test("waitAny textExists 缺 text 抛 invalid_data")
func waitAnyRejectsTextExistsWithoutText() {
    let data = JSON(["conditions": .array([.object(JSON(["id": "x", "mode": "textExists"]))])])
    #expect(throws: CommandInputParseError.self) {
        try UIWaitAnyInput.parse(from: data)
    }
}

@Test("waitAny targetExists 缺定位字段抛 invalid_data")
func waitAnyRejectsTargetExistsWithoutLocator() {
    let data = JSON(["conditions": .array([.object(JSON(["id": "x", "mode": "targetExists"]))])])
    #expect(throws: CommandInputParseError.self) {
        try UIWaitAnyInput.parse(from: data)
    }
}

@Test("waitAny snapshotChanged 缺 viewSnapshotID 抛 invalid_data")
func waitAnyRejectsSnapshotChangedWithoutSnapshotID() {
    let data = JSON(["conditions": .array([.object(JSON(["id": "x", "mode": "snapshotChanged"]))])])
    #expect(throws: CommandInputParseError.self) {
        try UIWaitAnyInput.parse(from: data)
    }
}

@Test("waitAny 未知顶层字段拒绝")
func waitAnyRejectsUnknownTopLevelField() {
    let data = JSON([
        "conditions": .array([.object(JSON(["id": "x", "mode": "idle"]))]),
        "bogus": "x",
    ])
    #expect(throws: CommandInputParseError.self) {
        try UIWaitAnyInput.parse(from: data)
    }
}

@Test("waitAny condition 内未知字段拒绝（与顶层严格策略一致）")
func waitAnyRejectsUnknownConditionField() {
    let data = JSON([
        "conditions": .array([.object(JSON(["id": "x", "mode": "idle", "bogus": "v"]))]),
    ])
    #expect(throws: CommandInputParseError.self) {
        try UIWaitAnyInput.parse(from: data)
    }
}

#if canImport(UIKit)
import UIKit

// MARK: - executor（iOS）

@Test("waitAny textExists 与 targetExists 中先命中者优先返回") @MainActor
func waitAnyReturnsFirstMatched() async throws {
    let context = UIKitTestHost.context { root in
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 20))
        label.text = "密码错误"
        root.addSubview(label)
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = "home_tab"
        button.frame = CGRect(x: 10, y: 10, width: 100, height: 40)
        root.addSubview(button)
    }
    let homeTarget = try UIKitViewLookupTarget.parse(identifier: "home_tab", rawPath: nil)
    let input = UIWaitAnyInput(conditions: [
        UIWaitAnyCondition(id: "home", mode: .targetExists, target: homeTarget),
        UIWaitAnyCondition(id: "err", mode: .textExists, text: "密码错误"),
    ], timeoutMs: 1000, intervalMs: 50)
    let data = try await UIWaitAnyExecutor.execute(input: input) { context }
    #expect(data["satisfied"]?.boolValue == true)
    #expect(data["matchedID"]?.stringValue == "home")
    #expect(data["matchedIndex"]?.doubleValue == 0)
    #expect(data["matchedMode"]?.stringValue == "targetExists")
}

@Test("waitAny 两条件同时满足时返回靠前者(优先级稳定)") @MainActor
func waitAnyPriorityIsStableWhenBothSatisfied() async throws {
    let context = UIKitTestHost.context { root in
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 20))
        label.text = "同时存在"
        root.addSubview(label)
    }
    let input = UIWaitAnyInput(conditions: [
        UIWaitAnyCondition(id: "first", mode: .textExists, text: "同时存在"),
        UIWaitAnyCondition(id: "second", mode: .textExists, text: "存在"),
    ], timeoutMs: 500, intervalMs: 50)
    let data = try await UIWaitAnyExecutor.execute(input: input) { context }
    #expect(data["matchedID"]?.stringValue == "first")
    #expect(data["matchedIndex"]?.doubleValue == 0)
}

@Test("waitAny 超时返回 waitTimeout") @MainActor
func waitAnyTimeoutReturnsWaitTimeout() async {
    let context = UIKitTestHost.context { _ in }
    let input = UIWaitAnyInput(conditions: [
        UIWaitAnyCondition(id: "never", mode: .textExists, text: "不存在"),
    ], timeoutMs: 100, intervalMs: 50)
    do {
        _ = try await UIWaitAnyExecutor.execute(input: input) { context }
        Issue.record("expected waitTimeout, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .waitTimeout)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("waitAny cancel 收敛到 waitTimeout 而非 internal_error") @MainActor
func waitAnyCancellationConvergesToWaitTimeout() async {
    let context = UIKitTestHost.context { _ in }
    let input = UIWaitAnyInput(conditions: [
        UIWaitAnyCondition(id: "never", mode: .textExists, text: "不存在"),
    ], timeoutMs: 10_000, intervalMs: 50)
    let task = Task<JSON, Error> {
        try await UIWaitAnyExecutor.execute(input: input) { context }
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
        // deadline。iOS 模拟器全量测试时 MainActor 负载会带来秒级抖动，因此阈值保留到 6s；
        // 若取消检查被删掉，命令会跑满 10s 才靠自然 deadline 抛 waitTimeout，仍会失败。
        let elapsed = start.duration(to: clock.now)
        #expect(elapsed < .seconds(6), "cancel should short-circuit well before 10s, took \(elapsed)")
    } catch {
        Issue.record("unexpected error (expected waitTimeout): \(error)")
    }
}

@Test("waitAny contextProvider 瞬时失败当未满足继续轮询") @MainActor
func waitAnyToleratesTransientContextFailure() async throws {
    let context = UIKitTestHost.context { root in
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 20))
        label.text = "终于出现"
        root.addSubview(label)
    }
    // 首轮 contextProvider 抛 hierarchyUnavailable（模拟转场瞬态），后续返回正常 context，应最终命中。
    var callCount = 0
    let input = UIWaitAnyInput(conditions: [
        UIWaitAnyCondition(id: "ok", mode: .textExists, text: "终于出现"),
    ], timeoutMs: 2000, intervalMs: 50)
    let data = try await UIWaitAnyExecutor.execute(input: input) {
        callCount += 1
        if callCount == 1 {
            throw UIKitCommandError.hierarchyUnavailable(action: WaitAnyCommand.actionName, reason: "transient")
        }
        return context
    }
    #expect(data["satisfied"]?.boolValue == true)
    #expect(data["matchedID"]?.stringValue == "ok")
    #expect((data["attempts"]?.doubleValue ?? 0) >= 2)
}
#endif
