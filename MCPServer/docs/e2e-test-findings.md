# MCP 端到端测试发现清单

2026-07-10，用 `mcp-inspector.mjs` + 真实 `SPMExample` App 做全流程端到端测试，
覆盖 `ui.inspect`、`ui_tap`（动态工具）、`call_action`（兜底工具）、`ui_alert_respond`、
`ui_input`、`wait_and_inspect`。

## Baseline（修任何东西之前）

- vitest: 8 个测试文件 / 45 个测试全部通过，无 fail。
- mcp-inspector + 真实 App 端到端：inspect→tap→alert.respond→input 全流程可走通，
  但有下列 9 项「能跑但不合理」的观察。

## 问题列表（按严重程度排序）

### ~~P0-1: `call_action` 不剥 envelope，与动态工具返回结构不一致~~（**复核后撤销**）

复核 `iosExploreClient.ts:68` 行：`return envelope.data ?? {}`——`client.call` 自身已剥 envelope；
`call_action` 与动态工具都用 `client.call`，行为一致。实测对照 `ui_inspect` 与 `call_action` 调
`ui.inspect`，返回 keys 完全相同。原报告误将 `client.call` 的 "throw on failure envelope" 机制
错记为 "透传原始 envelope"，撤销。

### ~~P0-2: `ui.input` identifier 定位不允许 `viewSnapshotID`，与 `ui.tap` 的行为不一致~~（**已修 `fe48071`，含 `ui.scroll` 同款**）

`ui.tap` 的 identifier 定位支持 `viewSnapshotID` 陈旧校验，而 `ui.input` 明确拒绝：
```
viewSnapshotID is valid only with path
```
agent 习惯用 identifier + viewSnapshotID 两路派发，`ui.input` 的特殊约束打破了统一调用习惯。

- **影响**：Agent 对 `ui.input` 不能复用跟 `ui.tap` 相同的参数模式
- **涉及**：`Sources/iOSExploreUIKit/Commands/Input/UIInputModels.swift`

### ~~P0-3: `_UIAlertControllerTextField` 的 `text` 字段永远为 null~~（**已修 `71ce37a`**）

往 `alert.input.username` 输入 "AgentName42" 后重新 inspect，该 text field 的
`text` 字段仍是 `null`。`ui.inspect` 无法读取输入框的当前文本。

- **影响**：Agent 输入文字后无法通过 inspect 验证输入结果
- **涉及**：`Sources/iOSExploreUIKit/Commands/Inspect/` 里的文本采集逻辑

### ~~P0-4: inspect 与 alert respond 之间缺少按钮映射~~（**已修 `16fefb1`**）

`ui.alert.respond dryRun=true` 返回 `buttons[].title`，而 `ui.inspect` 视野里
alert button 是 `_UIAlertControllerActionView` → `UIView` → `UILabel` 深层结构，
agent 无法知道哪些 inspect 节点对应哪些 alert button。

- **影响**：Agent 点击 alert button 只能靠 `ui.alert.respond`，无法通过
  `ui.tap` 在 inspect 结果里直接 tap
- **涉及**：`Sources/iOSExploreUIKit/Commands/Inspect/` / `Sources/iOSExploreUIKit/Commands/Alert/`

**修复**：`ui.inspect` / `ui.topViewHierarchy` 顶层注入 `alert` 区块（仿 `navigationBar` 块格局），
每按钮带 `index`/`title`/`role`/`path`/`availableActions: ["ui.alert.respond"]`。
路径通过 DFS `_UIAlertControllerActionView` 子视图树+UILabel.text 匹配 `alert.actions[i].title`
解析。LLDB 实测确认 iOS 26 上公开 `subviews` 可正常抵达按钮视图。

### ~~P1-5: MCP server 不自己做参数校验，靠 App 业务错误返回~~（**Fix B 已修 `8727eb8`**）

`ui_tap` 不带 `viewSnapshotID` 时，MCP server 直接转发给 App，App 返回
`{"code":"invalid_data","message":"viewSnapshotID is required"}`。
MCP server 应该自己做输入校验并返回清晰的 JSON-RPC error，而不是让 App 的
业务错误当作正常响应透传。

- **影响**：Agent 收到 `isError=false` 但业务失败，容易混淆
- **涉及**：`MCPServer/src/server.ts`（handler 调用层，缺少参数预校验）

**Fix B（已修 `8727eb8`）**：`normalizedResult` / `resultForFailure` 加 code 白名单，
`invalid_data` / `stale_locator` / `unknown_action`（动态工具路径）升格 `isError:true`，
其余 `wait_timeout` / `alert_unavailable` 等保持 `isError:false`。

**Fix A（待做，L 工作量）**：MCP 层加 JSON Schema 校验——需改 Swift `CommandInputSchema.toJSON()`
把条件约束翻译成 `allOf.if/then`、改 `schemaMapper.ts` 传递条件约束到 `inputSchema`、
加 `ajv` 或手写 validator、补测试矩阵。可开独立 issue。

### P1-6: Snapshot TTL（30s）对 MCP 自动化场景太短

`maxSnapshots=8`、`ttlSeconds=30`。每次 `mcp-inspector.mjs` 启动跑
`initialize`+`tools/list` 已经消耗一次 help，多步调用间容易淘汰旧 snapshot，
触发 `stale_locator`。Mac 侧 agent 的思考间隙远超 30 秒。

- **影响**：Agent 做的 inspect → 分析 → tap 流程经常因为 snapshot 过期失败
- **涉及**：`Sources/iOSExploreUIKit/Support/Snapshot/UIKitSnapshotStore.swift`
  （第 180, 187 行的 TTL 和容量常数）

### P1-7: `wait_and_inspect` 的 observation 字段没剥 envelope

`wait_and_inspect` 响应的 `observation` 字段直接是 inspect 的原始返回。
若 inspect 返回 error envelope，observation 会是错误结构而非 targets 数组。

- **影响**：Agent 解析 observation 时不能假设其结构
- **涉及**：`MCPServer/src/staticTools.ts`

### P1-8: `mcp-inspector.mjs` 多 call 场景下响应可能乱序

脚本用 `setTimeout` 固定间隔发送多个 `tools/call`，但 JSON-RPC 响应到达时间
不固定，`stdout.on("data")` 按行解析。响应行跨越 `=== tools/call (id=N) ===` 标记
可能错位——无法一对一匹配请求和响应。

- **影响**：调试时难以辨认哪个响应对应哪个请求
- **涉及**：`MCPServer/scripts/mcp-inspector.mjs`

### P1-9: `call_action` 透传的 `action` 字段可能被 App 误解析

`call_action` handler 把整个 `arguments` 对象传给 App 作为 `data`，但如果
`arguments` 里包含 `action` 字段（从外部传入的结构），会被 App 当成命令输入
字段解析，报 `unknown command input field 'action'`。

- **影响**：Agent 通过 `call_action` 调某些 action 时莫名失败
- **涉及**：`MCPServer/src/staticTools.ts`
