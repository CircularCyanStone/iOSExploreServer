# UIKit View Targets Hardening Design

**Goal:** 让 `ui.viewTargets` 的输出、MainActor 工作量和 path 快照保护均有确定上限，并消除 listener 快速停启的生命周期竞态。

## Scope

本次只修复已确认的问题：目标数上限、快照投影/上下文、真实可执行能力、listener 停止完成、日志脱敏及其测试和文档。不新增分页、输入、截图、滚动或通用事件协议。

## 方案选择

备选方案：

1. 仅给 `targets` 数组做最终截断。实现最小，但仍会遍历整棵树和构造全部摘要，不能解决 MainActor 成本。
2. 使用 cursor 分页。可枚举全部目标，但 UIKit 树是实时变化的，cursor 与 snapshot 的一致性复杂，首版收益不足。
3. **推荐：有界单次查询。** `maxTargets` 默认 200、允许 1...512；采集到上限即停止遍历，返回明确截断元数据。调用方以 `accessibilityIdentifier`、prefix 或 `maxDepth` 缩小后重新查询。

采用方案 3。它和单次短连接 HTTP/MCP 工具发现的使用方式匹配，不伪造跨请求的稳定分页语义。

## `ui.viewTargets` 协议

`UIViewTargetsQuery` 新增 `maxTargets`。缺省为 200，范围为 1...512，非整数、越界、NaN 或无穷返回 `invalid_data`。

成功响应保留现有 `targetCount` 和 `targets`，并新增：

- `maxTargets`：本次生效上限；
- `truncated`：是否因上限停止；
- `truncationReason`：截断时为 `maxTargets`，否则为 JSON null；
- `snapshotUnavailableReason`：无法签发 path 快照时为稳定枚举，否则为 JSON null。

`targetCount` 始终等于返回数组长度，不再暗示全页面总数。采集器在添加第 `maxTargets` 个目标后不再递归后续子树；`visitedNodeCount` 是实际访问数。`truncated=true` 的保守含义是“枚举因到达上限而停止，结果不保证完整”，不承诺已经确认存在第 `maxTargets + 1` 个匹配项。`maxTargets` 追加在 public initializer 的末尾并带默认值 200，保持既有源调用兼容。

## 快照投影与陈旧校验

快照不再对输出范围之外的整棵树生成指纹。每个返回 target 只占用**一条**固定预算 fingerprint，因此 `maxTargets <= 512` 时必然可签发 snapshot。该 fingerprint 除自身 type、identifier hash 和状态外，包含从 root 到 target 的祖先状态摘要；摘要按 path 顺序汇入父节点的 type、identifier hash、hidden、alpha、user-interaction 状态。执行时对当前定位 view 重算完全相同的 fingerprint，任一祖先变化都会判 stale。这样无需在 store 内另存祖先节点，固定保持 `returnedTargetCount <= maxFingerprints`。

`UIKitSnapshotContext` 必须进入 `Entry`，含不暴露给 HTTP 或日志的 window 实例标识与顶部 VC 实例标识（进程内 `ObjectIdentifier` 值的字符串摘要）。`validation` 接收当前 context 和当前完整 fingerprint，先比较实例标识，再比较 fingerprint；同类 VC 实例替换必须判 stale。`ui.topViewHierarchy` 与 `ui.viewTargets` 都使用这套接口。现有 10 秒 TTL、8 条 LRU 和未知 snapshot fail-closed 语义保持不变。

## 能力语义

`availableActions` 只表示当前可能执行的动作。resolver 除 `UIControl.isEnabled` 外还检查从目标到 root 的 `isHidden`、`alpha <= 0.01` 与 `isUserInteractionEnabled`。这不能预知 z-order 覆盖，`ui.tap` 仍以实时 hit-test 作最终判断。

## Listener 生命周期

`HTTPListener` 的状态 handler 使用弱捕获，`stop()` 取消时清理 handler，避免 `HTTPListener -> NWListener -> closure -> HTTPListener` 环。

`ExploreServer` 拥有 `idle → starting → running → stopping → idle` 状态机，状态和 stop waiter 由现有 `Mutex` 原子保护，锁内不 await。`stop()` 保持同步：转入 `stopping`、发起 cancel 并立即返回；listener 的状态 handler 在收到 `.cancelled`/`.failed` 后先通知 waiter、转回 idle，再解绑 handler。handler 在终态前不得清理，因此不会丢失停止信号。

新增内部/测试可用的 `stopAndWait()` 完成屏障；同一 server 的 `start()` 发现 stopping 时等待屏障。集成测试不再靠 retry 掩盖共享端口问题：每个用例在退出前 await `stopAndWait()`，下一例创建新 server 前端口已释放。对外 `stop()` 仍兼容，真实 App 的同一实例快速 stop/start 由 `start()` 自动等待。停止失败、start 中 stop、重复 stop、重复 start 都要求终态仅通知一次。

## 日志与文档

新增唯一的日志专用 locator 摘要入口：仅输出 kind、path，或 identifier 的稳定 hash 与长度；executor、command adapter 和所有 `UIKitCommandError` 工厂均只接收该摘要，不写完整 identifier。HTTP 响应维持既有完整 identifier 协议。目标查询日志增加 `maxTargets`、truncated、returned/visited 数及 snapshot 不可用原因；不逐目标输出 info 日志。

更新 command help、architecture、network tools、build/debugging runbook 和 `AGENTS.md` 的测试数量/端口竞态说明。

## Verification

先新增并观察失败测试，分三层执行：

- Foundation-only：`maxTargets` 解析、默认值/边界、截断元数据、context 不同即 stale、祖先摘要不同即 stale、日志摘要不含原 identifier；
- `#if canImport(UIKit)` framework：父节点 hidden/alpha/interaction 变化使 availableActions 为空，两个同类 VC 实例产生不同 context；
- 真实 TCP 集成：`stopAndWait()` 后新 server 立即复用 38399，重复 start/stop 和 start 中 stop 都只产生一个终态；
- `@testable` 生命周期测试：停止终态后 state handler 已解绑，释放最后一个强引用后 listener/transport 探针可释放。端口复用只验证 socket 释放，不能替代这项保留环断言。

随后运行 macOS `swift test`、framework iOS Simulator build/test，并重复集成测试验证端口复用。实现只能使用当前已兼容 Swift 5 framework 与 Swift 6.2 SPM 的 `Mutex`、`Task`、continuation 和 `@Sendable` 闭包；不得新增 `@unchecked Sendable` 边界或 Swift-6-only 语法。

## Self-review

范围不引入分页或新动作；所有协议新增字段向后兼容；快照仅保存 Foundation 值，不返回 UIKit 对象；停止等待不阻塞 network queue；每个返回 target 恰好占一条快照预算，祖先状态通过摘要被实际校验。
