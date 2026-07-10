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

#### N2（已修）：alert button path 是无消费者的 dead feature，已移除

原状：P0-4（`16fefb1`）给 inspect 的 alert buttons 注入了 `path`，commit message 称「agent 可直接用 path 上 `ui.tap` 关 alert」，但实测 button path 调 `ui.tap` 返回 `unsupported_target`（alert button 视图无 tap 路由），且 `ui.alert.respond` 用 buttonIndex/title/role（不读 path）——path 完全无消费者，是没兑现承诺的 dead feature。

**已修**：移除 `alert.buttons[].path` + 整个 `UIAlertButtonPathResolver`。agent 点 alert 按钮照旧用 `ui.alert.respond`（按 buttonIndex/title/role），不受影响。N3 给 textFields 加的 path 保留（`ui.input` 真在用）。真实闭环：simple / loginInput alert 的 buttons 均无 path（keys 仅 `index`/`title`/`role`/`availableActions`），textField path 仍在。

#### N3（已修 `a75df74`）：alert block 的 textFields 不暴露 path / accessibilityIdentifier

原状：`ui.inspect` 的 `alert.textFields[]` 只有 `{isSecure, placeholder}`，无 `path` / `accessibilityIdentifier`，agent 要给 alert 输入框做 `ui.input` 只能深层挖 `_UIAlertControllerTextField`。

**已修 `a75df74`**：`alert.textFields[]` 现在每个带 `path` + `accessibilityIdentifier` + `availableActions:["ui.input"]`，与 `alert.buttons[]` 对齐。新增 `UIAlertTextFieldPathResolver`（对象身份 `===` DFS 解析，用公开 `UITextField` 类型收集、抗版本漂移）。真实闭环验证：用 alert 区块的 path 直连 `ui.input` 写入读回成功（`username.text="N3Verify"`，password secure 仍 null）。

#### N4（已修）：ui.alert.respond 的 dryRun 已移除

原状：不传 `dryRun` 时默认 `true`（查询模式），agent 若不显式传 `dryRun:false` 会误以为点了按钮实则没点。

**已修**：dryRun=true 的查询功能已被 `ui.inspect` 的 alert 区块完全替代（inspect 含 path/availableActions/identifier，更全），故直接**移除 dryRun**——ui.alert.respond 职责单一为「触发按钮」，查询走 ui.inspect。selector 逻辑已保证安全（单按钮 alert 默认点、多按钮强制指定）。顺带清理移除 dryRun 后的 dead code（`TextFieldSummary` / `Summary.textFields`）。

### N3 修复过程新挖出的 pre-existing 问题（`a75df74` / `c5a1c1f` 顺带修）

修 N3 时又挖出几个此前被掩盖的问题（再次印证「只跑 macOS swift test、不跑 iOS framework 测试 / 真实闭环」会藏 bug）：

- **topViewHierarchy alert 注入遗漏（已修 `a75df74`）**：`16fefb1` 声称给 inspect 和 topViewHierarchy 都注入 alert 区块，实际只注入了 inspect（topViewHierarchy 只有注释没代码）。补齐 else 分支注入。
- **3 个测试文件编译错误（已修 `a75df74`）**：`0936b2e` 把 `UIViewTargetsCollector` 改名 `UIInspectCollector` 时漏改 `UIInspectCollectorTests` / `UIKitCollectorTests` / `UINavigationBarButtonTests` 的部分方法，外加 `collectTopViewHierarchy` 变 throws 后漏 `try`。这些测试在 `#if canImport(UIKit)` 内——macOS `swift test` 不编译而漏掉，iOS framework 测试里一直编译失败从未真正运行。
- **Release 构建隐患（已修 `a75df74`）**：`UIAlertInspector.resolveButtonPaths` 返回类型是 `#if DEBUG` 保护的 `ResolvedButton`，Release 分支引用它会导致 framework Release 构建失败（Debug-only 测试一直没暴露）。改为返回 `[String?]`。
- **5 个 ui.input / staleLocator 断言过时（已修 `c5a1c1f`）**：P0-2 改了 viewSnapshotID 语义、`10ca9a1` 给 staleLocator 消息加了 TTL 插值后，测试断言没跟上。更新断言匹配新语义，staleLocator 改用 `contains` 关键短语（消息从 `ttlSeconds` 插值，TTL 调整时精确匹配会断）。

### 仍未处理的 pre-existing

- **2 个 stderr/NSLog capture flaky 失败（Diagnostics 模块）**：iOS framework 测试里 `stderr capture` / `NSLog capture` 间歇性失败（同一次跑过、下一次失败），`71ce37a` 已标注「stderr capture 间歇性」属预存。与 UIKit 改动无关，属 Diagnostics capture 时序稳定性问题，建议单独排查。
- **N2（已修）**：alert button path 无消费者，已移除（agent 用 ui.alert.respond 按 index/title/role 点按钮）。
- **N4（已修）**：`ui.alert.respond` 的 dryRun 已移除（查询走 ui.inspect）。
- **P1-5 Fix A**：暂缓（见上）。
