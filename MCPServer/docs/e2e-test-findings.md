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

### ~~P1-6: Snapshot TTL（30s）对 MCP 自动化场景太短~~（**已修；常量已是 120s / 32 槽**）

原报告：`maxSnapshots=8`、`ttlSeconds=30`，多步调用间容易淘汰旧 snapshot 触发 `stale_locator`。

**复核（2026-07-10）**：已修复。`UIKitSnapshotStore.swift` 现状：
- `maxSnapshots = 32`（L184）
- `ttlSeconds = 120`（L194，`isStale` 单 path 校验用）
- `wholeTableTtlSeconds = 300`（L201，`ui.wait(snapshotChanged)` 全表比对用）

L171-173 注释明确写「原 30s/8 在慢 LLM 推理链下会触发 stale_locator，改为 120s 给慢推理 4x 余量，32 槽覆盖多子树交叉 inspect」。本条保留旧值属文档滞后，撤销。

### ~~P1-7: `wait_and_inspect` 的 observation 字段没剥 envelope~~（**复核后撤销**）

原报告：observation 是 inspect 原始返回，若 inspect 返回 error envelope，observation 会是错误结构而非 targets 数组。

**复核（2026-07-10）**：不成立。`iosExploreClient.ts:59-68` 的 `client.call` 对 failure envelope 是 **throw `IOSExploreStructuredError`**，对 success 才 `return envelope.data ?? {}`。`staticTools.ts:122` 的 `observation = await client.call("ui.inspect", ...)` 因此只可能是成功 data（`{viewSnapshotID, targets:[...]}`），或 throw 被外层 catch 捕获（L124）——**根本不会进入返回值**。与 P0-1 同类误判：把 `client.call` 的「throw on failure envelope」错记成「透传原始 envelope」。撤销。

### ~~P1-8: `mcp-inspector.mjs` 多 call 场景下响应可能乱序~~（**复核后撤销**）

原报告：`setTimeout` 发多个 `tools/call`，响应到达时间不固定，按行解析可能错位，无法一对一匹配请求和响应。

**复核（2026-07-10）**：不成立。`mcp-inspector.mjs:21-48` 用 JSON-RPC **id 精确匹配**：`send` 分配递增 id 存入 `pending` map（L24），响应到达按 `msg.id` 匹配并取出 method 名打印 `=== ${method} (id=${msg.id}) ===`（L38-41）。buffer 按 `\n` 切分（L30-34）也正确处理了 chunk 边界。每个响应都带 id 标注，不存在「无法匹配」。唯一的非 bug 现象是响应打印顺序为到达顺序而非发送顺序，但 id 标注足以辨认。撤销。

### ~~P1-9: `call_action` 透传的 `action` 字段可能被 App 误解析~~（**复核后撤销**）

原报告：`call_action` handler 把整个 `arguments` 对象传给 App 作为 `data`，若 arguments 含 `action` 字段会被 App 当成命令输入字段解析。

**复核（2026-07-10）**：不成立。`staticTools.ts:87-94` 的 handler 已分离：action 从 `input.action` 取，data 从 `input.data` 取（`objectValue(input.data)`）。`iosExploreClient.ts:18` 的请求 body 是 `{ action, data }`，App 顶层取 action、取 data 对象；data 内即便存在同名子键也是 data 的子字段，不会被当成命令 action。原描述的「整个 arguments 当 data」实现已不存在。若调用方故意把含 `action` 键的对象塞进 data，App 报 `unknown command input field 'action'` 是对非法字段的合理拒绝，非 MCP server bug。撤销。

## 2026-07-10 复核总结

逐条核到源码后，9 项里真实剩余 **1 项**：

| 条目 | 状态 | 依据 |
|---|---|---|
| P0-1 | 撤销（原报告） | `client.call` 已剥 envelope |
| P0-2 | 已修 fe48071 | `ui.input` 接受 viewSnapshotID |
| P0-3 | 已修 71ce37a | alert text field 读取 |
| P0-4 | 已修 16fefb1 | inspect 注入 `alert` 区块 |
| P1-5 Fix B | 已修 8727eb8 | code 白名单升格 isError |
| P1-5 Fix A | **真实待办** | MCP 层 JSON Schema 校验（见下） |
| P1-6 | 已修 | `UIKitSnapshotStore.swift` 120s/32 槽 |
| P1-7 | 撤销 | `client.call` throw on failure envelope |
| P1-8 | 撤销 | JSON-RPC id 精确匹配 |
| P1-9 | 撤销 | handler 已分离 action / data |

### 唯一真实待办：P1-5 Fix A（MCP 层 JSON Schema 前置校验）

**现状**：MCP server 不校验入参，直接转发给 App，由 App 的 typed factory（`CommandInputSchema`）返回 `invalid_data`。Fix B 已把 `invalid_data` / `stale_locator` / `unknown_action` 升格为 `isError:true`，Agent 已能区分「业务失败」与「正常状态反馈」。

**Fix A 要做什么**：在 MCP 层用 App 同款的 inputSchema 做前置校验，需——Swift `CommandInputSchema.toJSON()` 把条件约束（identifier/path 二选一等）翻译成 JSON Schema `allOf.if/then`；`schemaMapper.ts` 把条件约束透传进 `inputSchema`；引入 `ajv` 或手写 validator；补测试矩阵。

**建议：暂缓**。理由：
1. App 端 typed factory 已是参数校验的**单一来源**，MCP 层再做一遍是重复校验，Swift schema 演进时翻译层要同步维护，脆弱；
2. Fix B 已解决对 Agent 最关键的 `isError` 语义问题，Fix A 的边际收益主要是「省一次 round-trip、错误更早返回」，与维护成本不成正比；
3. 当前 `invalid_data` 文案已足够 Agent 理解（如 `viewSnapshotID is valid only with path`）。

若日后 Agent 频繁因「参数组合约束」踩坑（而非字段缺失），再启动 Fix A。届时建议直接让 App 在 `help`/`inspectSchema` 输出里带上可执行的条件约束描述，MCP 层复用，而不是在 TS 侧重写一套翻译。

## 2026-07-11 真实端到端验证（SPMExample 模拟器闭环）

用 XcodeBuildMCP `sim-app` profile + `IOS_EXPLORE_AUTOSTART=1` + `IOS_EXPLORE_OPEN_ALERT_TEST=1`，对 4 个「已修」修复做**首次真实 App + curl 闭环验证**（此前全部只有单元测试 / LLDB）。**4 个修复本身全部通过**，但验证过程暴露了 4 个此前未知的问题。

### 验证结果（全通过）

| 修复 | 验证方式 | 真实结果 |
|---|---|---|
| P0-4 `16fefb1` alert 区块 | tap 触发 alert → inspect → ui.alert.respond 关闭 | alert 区块注入 `buttons[].path/role` + `availableActions:["ui.alert.respond"]` ✅；`dryRun:false` → `performed/dismissed/button`，alert 关闭 ✅ |
| P0-3 `71ce37a` text 字段 | ui.input 写 username → inspect 读回 | `username.text="AgentName42"`（修复前 null）✅；password secure `text=null` ✅ |
| P0-2 `fe48071` input freshness | ui.input `accessibilityIdentifier+viewSnapshotID` | 不再返回 `invalid_data`，`finalText` 正确 ✅ |
| P1-5 Fix B `8727eb8` isError | 经真实 MCP server（mcp-inspector） | `invalid_data`/`stale_locator` → `isError:true` ✅；`unknown_action`(call_action) → `isError:false` ✅ |

### 验证中暴露的新问题

#### N1（已修 `62f6690`）：main 上 iOS 构建阻断

`UIInspectCollector.textualValue` 用 `view is UIListContentView` 未加 `if #available`，而 `Package.swift` 声明 iOS 13、`UIListContentView` 是 iOS 14+，SPMExample iOS 模拟器构建直接失败（`'UIListContentView' is only available in iOS 14.0 or newer`）。macOS `swift test` 因 UIKit 段 `#if canImport(UIKit)` 不编译而一直没暴露。**根因：4 个修复都没做真实 iOS 构建 / 端到端，只跑 macOS 单元测试。** 已加 `if #available(iOS 14, *)` 修复，iOS 模拟器构建 + macOS 273 测试全过。

#### N2：P0-4 commit message 与实现不一致（alert button path 不可 ui.tap）

`16fefb1` message 称「agent 可直接用 path 上 `ui.tap` 关 alert」，但实测用 button path 调 `ui.tap` 返回 `unsupported_target: target has no default activation route (UIButton / UISwitch / text input only)`——alert button 视图（`_UIAlertControllerActionView` 系）无 tap 激活路由。`availableActions` 只列 `["ui.alert.respond"]` 是**正确**的，agent 应按它走 `ui.alert.respond`。建议：修正 commit message / 文档措辞；若要支持 path tap，需 executor 识别 alert action view（单独工作项）。

#### N3：alert block 的 textFields 不暴露 path / accessibilityIdentifier

`ui.inspect` 的 `alert.textFields[]` 只有 `{isSecure, placeholder}`，没有 `path` 和 `accessibilityIdentifier`。agent 要给 alert 输入框做 `ui.input`，必须从 inspect targets 里深层定位 `_UIAlertControllerTextField`（实测 path 如 `root/0/0/1/0/0/4/0/0/0/0/0/0/0/0`）。建议：`alert.textFields[]` 补 `path` + `accessibilityIdentifier`，与 `alert.buttons[]` 对齐。

#### N4：ui.alert.respond 的 dryRun 默认 true

不传 `dryRun` 时默认 `true`（查询模式，返回 buttons 列表但不点）。agent 若不显式传 `dryRun:false` 会误以为点了按钮实则没点（实测 `{"buttonIndex":1}` 返回的仍是 `dryRun:true`）。建议：默认改为 `false`（执行），或在响应里强提示当前为查询模式。
