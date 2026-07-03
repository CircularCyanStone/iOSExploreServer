# Mac 侧 MCP server：范围与已定约束

> 日期：2026-07-03　状态：**待启动**（本文是起点记录，当前不实现）
> 关联：[README §6.1](../agent-mcp-exploration/README.md) · [final-observation 方案 B](./2026-07-03-final-observation-after-action.md) · [真机计时](../agent-mcp-exploration/runtime-validation-2026-07-03.md)

## 为什么建

iPhone 端库（18 个 HTTP action：4 内置 + 14 个 `ui.*`）已就绪，agent 现在用 `curl` 裸打 HTTP 调用。问题：协议约束（每步先 observe、动作后 re-observe、`viewSnapshotID` 从 `ui.viewTargets` 来、命中后必须重新观察）全靠 agent 读 `agent-usage-protocol.md` 自觉，没有代码强制，容易漏。

建一个 Mac 侧 MCP server，把这 18 个 action 包装成标准 MCP 工具，agent 通过 MCP 协议调用；固定编排（如 `waitAny → viewTargets`）在这一层用代码固化。

## 已定约束（开建时直接用，不要推翻）

1. **不做 `ui.waitAny returnObservation`**。真机 USB 实测 viewTargets 往返 **~10ms**（连续 8 次 8.7–14.5ms），相对 waitAny 秒级 `timeoutMs` 占比 <1%，re-observe 不是瓶颈。iPhone 端 waitAny 响应保持只返回 `matchedID / matchedIndex / matchedMode / elapsedMs / attempts`，不带页面。
2. **编排放 Mac 侧**。"waitAny 命中后自动 viewTargets"在 MCP 包装层做，iPhone 端一行不改。暂名组合工具 `wait_and_observe`：内部先 waitAny，命中后自动 viewTargets，合并返回给 agent。
3. **`viewSnapshotID` 签发源不增加**。只 iPhone 端 `ui.viewTargets` 签发；MCP 包装层只转发 + 组合，不伪造快照（否则 freshness 比对要分叉，违背"唯一签发源"不变式）。
4. **iPhone 端库边界不动**。core/UIKit 分层、typed factory、错误工厂单一来源——不能因接 MCP 而破坏。

## 开建时要决的问题

- **语言/运行时**：Swift NIO / Node FastMCP / Python FastMCP——优先选 Claude Code MCP 生态成熟、SDK 支持好的。
- **工具粒度**：18 个 action 1:1 转发（全暴露，agent 能精细控制）+ 额外组合工具（`wait_and_observe` 等，固化协议里的固定序列）。
- **transport**：复用 `iproxy 38321`（server 只管 HTTP↔MCP 包装），还是 server 自己管 USB 转发。倾向复用 iproxy。
- **设备选择**：多台 iPhone 同时连时怎么选（udid 参数 / 默认第一台 / 列设备让 agent 选）。
- **鉴权**：USB 物理隔离当前不校验 token；MCP 层（多用户机 / 远程场景）要不要加。
- **错误映射**：iPhone envelope 的业务 code（`stale_locator` / `wait_timeout` / `unsupported_target` / `alert_button_required` / ...）→ MCP 工具错误返回，让 agent 能按 code 分支决策，而不是只能看 message。

## 起点 checklist

- [ ] 选语言/框架，起 server 项目骨架。
- [ ] 18 个 action 的 1:1 MCP 工具转发（HTTP ↔ MCP）。
- [ ] 组合工具 `wait_and_observe`（waitAny 命中后自动 viewTargets，合并返回）。
- [ ] envelope code 透传 / 映射到 MCP 错误。
- [ ] 用 Example App（真机 + iproxy）跑通 agent 经 MCP 的完整闭环：`observe → act → wait_and_observe → 判断`。
