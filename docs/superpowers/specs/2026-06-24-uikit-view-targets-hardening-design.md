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

`targetCount` 始终等于返回数组长度，不再暗示全页面总数。采集器在添加第 `maxTargets` 个目标后不再递归后续子树；`visitedNodeCount` 是实际访问数。

## 快照投影与陈旧校验

快照不再对输出范围之外的整棵树生成指纹。collector 在生成每个返回 target 时保留该 target 和从 root 到它的祖先链的 fingerprint；去重后最多由 `maxTargets` 和树深度决定。若该投影超过 store 的硬上限，响应仍成功，但 `snapshotID` 为 null，`snapshotUnavailableReason` 为 `fingerprintLimit`。

`UIKitSnapshotContext` 必须进入 `Entry`，并持有不暴露给 HTTP/日志的当前 window 与顶部控制器实例标识。执行时先比较实例标识，再比较目标 fingerprint；同类 VC 实例替换必须判 stale。现有 10 秒 TTL、8 条 LRU 和未知 snapshot fail-closed 语义保持不变。

## 能力语义

`availableActions` 只表示当前可能执行的动作。resolver 除 `UIControl.isEnabled` 外还检查从目标到 root 的 `isHidden`、`alpha <= 0.01` 与 `isUserInteractionEnabled`。这不能预知 z-order 覆盖，`ui.tap` 仍以实时 hit-test 作最终判断。

## Listener 生命周期

`HTTPListener` 的状态 handler 使用弱捕获，`stop()` 取消时清理 handler，避免 `HTTPListener -> NWListener -> closure -> HTTPListener` 环。

新增内部异步停止完成路径：停止后等待 listener `.cancelled`（或已终止状态）才允许同一 `ExploreServer` 的下一次 `start()` 绑定端口。对外 `stop()` 保持兼容地触发停止；`start()` 负责等待尚未完成的停止，消除快速 stop/start 和 Simulator 用例之间的端口竞态。测试 helper 的 retry 保留为环境兜底，不作为正确性机制。

## 日志与文档

所有 locator 日志改为 kind、path 或 identifier 的稳定 hash/长度，不写完整 identifier。目标查询日志增加 `maxTargets`、truncated、returned/visited 数及 snapshot 不可用原因；不逐目标输出 info 日志。

更新 command help、architecture、network tools、build/debugging runbook 和 `AGENTS.md` 的测试数量/端口竞态说明。

## Verification

先新增并观察失败测试：`maxTargets` 解析、截断元数据、快照上下文实例变化、能力的祖先可交互性、listener handler 生命周期和快速 restart。随后运行 macOS `swift test`、iOS Simulator framework 测试，并重复集成测试验证端口复用。

## Self-review

范围不引入分页或新动作；所有协议新增字段向后兼容；快照仅保存 Foundation 值，不返回 UIKit 对象；停止等待不阻塞 network queue。
