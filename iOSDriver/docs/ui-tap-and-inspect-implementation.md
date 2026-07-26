# ui_tap_and_inspect

`ui_tap_and_inspect` 是 iOSDriver 的 MCP workflow 工具，对应 host operation `tap_and_inspect`。它把一次 tap、可选等待和随后的 `ui.inspect` 合并到一个工具调用中，减少调用方在交互后手动补 inspect 的重复步骤。

## 当前位置

- 合同：`contracts/host-operations/tap-and-inspect.json`
- Workflow：`iOSDriver/src/workflows/tapAndInspect.ts`
- MCP 映射：`iOSDriver/src/adapters/mcp/toolMappings.ts`
- MCP 执行：`iOSDriver/src/adapters/mcp/server.ts`

## 输入

目标定位仍遵循 `ui.tap` 规则：

```json
{
  "path": "<path-from-ui.inspect>",
  "viewSnapshotID": "<snapshot-id>",
  "wait": {
    "mode": "idle",
    "timeoutMs": 1000
  },
  "inspectOptions": {
    "mode": "minimal"
  }
}
```

`accessibilityIdentifier` 与 `path` 按合同互斥；`viewSnapshotID` 来自同一 UI 稳定状态下的 `ui.inspect`。

## 执行语义

1. 调用 App action `ui.tap`。
2. 如果配置了 wait，则调用 `ui.wait`。
3. 调用 `ui.inspect` 获取操作后的最新 UI 状态。
4. 返回每一步结果和 timing。

Tap 失败时 workflow 短路，不继续 wait/inspect。Wait 超时可以作为结果的一部分返回，是否继续 inspect 以当前合同和 WorkflowRunner 实现为准；不要在文档里复制一份独立业务规则。

## 验证

```bash
cd iOSDriver
npm run contracts:check
npm test
node scripts/mcp-inspector.mjs ui_tap_and_inspect '{"path":"<path>","viewSnapshotID":"<snapshot-id>"}'
```

最后一条需要真实 App 已启动，并且 `<path>` / `<snapshot-id>` 来自最新 `ui.inspect`。
