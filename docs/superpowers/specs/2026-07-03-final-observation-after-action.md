# 动作后轻量 final observation 归属评估

> 日期：2026-07-03
>
> 本文不实现任何命令，只评估一个归属问题：`ui.waitAny`（以及未来的 `ui.wait`）命中后，Agent 还需要的那一次「重新观察页面」应该由 iPhone 端在 wait 响应里直接带回，还是继续由 Mac 侧 MCP 层用 `ui.viewTargets` 单独组合。结论先放在前面：**当前阶段不改动 iPhone 端命令，把「命中后观察」固定为 Mac MCP 层的 `waitAny → ui.viewTargets` 编排**；只有当真机实测证明这次额外 round trip 真的成为 Agent 闭环延迟瓶颈时，才考虑给 `ui.waitAny` 增加可选 `returnObservation`，且必须先完成响应大小、字段范围、日志、测试的设计。

## 1. 问题是什么

当前标准闭环（[curl-json-loop-protocol.md](../agent-mcp-exploration/curl-json-loop-protocol.md)）：

```text
observe → action → ui.wait / ui.waitAny → re-observe → verify
```

`ui.waitAny` 命中后，响应只回业务摘要：

```json
{"satisfied":true, "matchedID":"pwd_error", "matchedIndex":1, "matchedMode":"textExists", "elapsedMs":120, "attempts":3}
```

它**不带回任何页面证据**。Agent 要判断「命中后页面到底变成什么样」，必须再发一次 `ui.viewTargets`（或 `ui.topViewHierarchy`），才能拿到 targets / navigationBar / viewSnapshotID。这就是「多一次 round trip」的来源：

```text
action ──► waitAny(命中) ──► viewTargets(re-observe)
                            └─ 这一次当前必须，但能不能省？
```

[agent-usage-protocol.md](../agent-mcp-exploration/agent-usage-protocol.md) §6.1 已写死这个立场：「`ui.waitAny` 默认不返回页面快照，只告诉你命中了哪个条件。命中后仍要重新 `ui.viewTargets` 观察页面。」本文评估这个立场现在是否还成立，以及如果要松动，最小代价是什么。

## 2. 方案 A：final observation 由 iPhone 端在 waitAny 响应里带回

命中后直接在 waitAny 响应里附一份页面摘要（targets 或轻量页面指纹）。

### 2.1 好处

- 省掉命中后那次 HTTP round trip；Mac 侧编排少一拍。
- 命中瞬间与观察瞬间同帧，不存在「命中后到 re-observe 之间页面又变」的窗口（实践中这个窗口极小）。

### 2.2 代价

- **响应放大**：`ui.viewTargets` 响应在 `maxTargets=200` 时可能很大（每个 target 含 `path`/`type`/`role`/`accessibilityIdentifier`/`label`/`title`/`text`/`placeholder`/`value`/`semanticText`/`frame`/`state`/`availableActions` 等十几个字段，外加 `navigationBar` 区块）。塞进每次 waitAny 响应会让一个本该几百字节的「等待结果」膨胀到几 KB～几十 KB，即使命中模式是 `idle`（根本不需要页面证据）也要付这个成本。
- **职责漂移**：wait 命令的本职是「轮询到条件满足就返回」，变成「等待 + 观察器」后，它要复刻 `UIViewTargetsCollector.collect` 的 canonical 筛选、指纹签发、navigationBar 摘要逻辑。`Support/Wait/` 与 `Support/Action/`、`Commands/ViewTargets/` 的边界被打破。
- **陈旧语义复杂化**：`ui.viewTargets` 是 `viewSnapshotID` 的唯一签发来源；若 waitAny 也带回 targets，它要不要也签发 `viewSnapshotID`？签发就会让「快照来源」从 1 个变 2 个，后续 `ui.tap` / `ui.control.sendAction` 的陈旧比对口径要同步两处；不签发则带回来的 targets 不能直接用于下一步动作，Agent 还是要再 `ui.viewTargets` 拿 snapshotID——round trip 没真省。
- **Agent 选择权丢失**：命中后 Agent 有时想要 targets，有时想要完整 hierarchy，有时想要 screenshot。iPhone 端硬塞一种，和 Agent 实际需求错配时反而更浪费。

## 3. 方案 B：final observation 由 Mac MCP 层组合（当前立场）

iPhone 端命令保持小而稳；Mac 侧 MCP 层在 waitAny 返回 `matchedID` 后，立即发起 `ui.viewTargets`。

### 3.1 好处

- **端命令职责单一**：waitAny 只管「等到哪个条件」，viewTargets 只管「观察页面」，各自可独立演进与测试。
- **复用现有 observe 通道**：不重复 canonical 筛选 / 指纹 / navigationBar 逻辑，零新增 UIKit 代码。
- **Agent 按需选观察方式**：命中后想要 targets 就 `ui.viewTargets`，想要树就 `ui.topViewHierarchy`，想要截图就 `ui.screenshot`，navigationBar 也在 viewTargets 里。
- **viewSnapshotID 来源不增**：仍只有 viewTargets 签发，陈旧比对口径不变。

### 3.2 代价

- 多一次 HTTP round trip（USB 经 iproxy，实测延迟在毫秒级，远小于一次轮询 wait 的百毫秒～秒级）。
- Mac MCP 层必须有固定编排策略（「waitAny 命中后无条件跟一次 viewTargets」），否则不同 Agent 实现可能漏掉 re-observe。这个策略已经在 [agent-usage-protocol.md](../agent-mcp-exploration/agent-usage-protocol.md) §6.1 写死，代价是协议约束而非代码。

## 4. 推荐方案

**当前阶段：方案 B，不改 iPhone 端命令。**

理由：

1. waitAny 多出来那次 round trip 走 USB，延迟与一次 wait 轮询的 `intervalMs` 相比可忽略，不是当前闭环瓶颈；真正的延迟在 wait 本身的 `timeoutMs` 与页面转场耗时。
2. 方案 A 的「响应放大 + 陈旧语义复杂化 + 职责漂移」三笔代价都落在库 core/UIKit 边界上，是结构性成本；方案 B 的代价只是「多一次毫秒级 HTTP + 一条协议约束」，是运维成本。结构性成本远高于运维成本。
3. 协议层已经把「命中后必须 re-observe」写死（§6.1、§1.4、curl 协议 §1.4），方案 B 与现有协议零冲突；方案 A 反而要改协议。

**协议层动作（零代码）：** 在 Mac MCP 层把「`ui.waitAny` 命中后立即调用 `ui.viewTargets`」固化成默认编排，等价于：

```text
ui.waitAny(命中 matchedID) → ui.viewTargets(拿页面证据 + 新 viewSnapshotID)
```

这已经是 curl-json-loop-protocol.md §1.3→§1.4 的标准闭环，本文只是把它从「建议」升格为「MCP 层默认行为」。

## 5. 如果未来要减这次 round trip：最小可行下一步

只有当**真机实测**（闭环计时）证明命中后那次 `ui.viewTargets` 的 HTTP 往返真的成为 Agent 决策延迟瓶颈时，才进入这一节。届时不要直接把整个 viewTargets 塞进 waitAny，而是：

- 给 `ui.waitAny` 增加可选顶层字段 `returnObservation`（默认 `false`，保持当前行为与响应大小）。
- `returnObservation=true` 时，命中后**在同一次 MainActor 切换里**采集一份**轻量**页面摘要，字段范围必须先设计清楚，二选一：
  - 只回 `viewSnapshotID` + `targetCount` + 极简 target 列表（只 `path`/`accessibilityIdentifier`/`role`/`isEnabled`，不带 `frame`/`state` 全量）；或
  - 只回 `viewSnapshotID` + `navigationBar` 摘要（命中后 Agent 最常需要的往往是「进了哪个页面、标题是什么、导航栏有什么按钮」）。
- **必须先签发 viewSnapshotID**：观察字段与 viewTargets 同口径签发，保证带回来的 target 可直接用于下一步 `ui.tap` / `ui.control.sendAction`，真正省掉 round trip。
- **日志**：waitAny 命中分支要单独记一条 `returnObservation=true bytes=N targetCount=M`，便于追踪响应放大。
- **测试**：命中 + `returnObservation=true` 的响应大小上限要有断言（防止未来字段 creep）。

即使走到这一步，也仍然是「可选 opt-in」，默认行为不变。

## 6. 不做什么

- **不把 screenshot / base64 塞进 waitAny 默认响应**：截图是字节大户，且 agent-usage-protocol.md §3.3 已明确「截图不是默认观察方式」。
- **不让 waitAny 自动执行动作**：waitAny 是只读等待，命中不触发任何 tap/input；动作仍由 Agent 显式发起。
- **不改 HTTP envelope**：waitAny 仍回 `{"code":"ok","data":{...}}`，失败仍回业务码；不增加新错误码。
- **不把 UIKit 依赖放进 core**：任何观察逻辑都在 `iOSExploreUIKit`，core 仍只依赖 Foundation + Network。
- **不在本期实现 `returnObservation`**：先留协议层编排，把「是否需要」交给真机闭环计时数据决定。

## 7. 落地清单（本期）

- [x] 评估文档：本文。
- [x] 协议层已固化：[agent-usage-protocol.md](../agent-mcp-exploration/agent-usage-protocol.md) §6.1、[curl-json-loop-protocol.md](../agent-mcp-exploration/curl-json-loop-protocol.md) §1.3→§1.4 已写「命中后重新 observe」。
- [x] `ui.waitAny` 默认响应保持只含 `matchedID` / `matchedIndex` / `matchedMode` / `elapsedMs` / `attempts`（本节确认现状即可）。
- [ ] （未来，可选）真机闭环计时：测量命中后 `ui.viewTargets` 的 HTTP 往返 P50/P95，作为是否启动第 5 节的依据。
