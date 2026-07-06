# Mac 侧 MCP Server 设计

> 日期：2026-07-06
> 状态：设计已确认并经 subagent 评审修订，等待用户审阅后进入实施计划
> 关联：[Agent MCP 应用探索服务改造地图](../agent-mcp-exploration/README.md) · [curl/JSON 闭环操作协议](../agent-mcp-exploration/curl-json-loop-protocol.md) · [final observation 归属评估](./2026-07-03-final-observation-after-action.md)

## 1. 本次目标

本次目标是给当前项目补一个 **Mac 本机运行的 MCP server**，让 Agent 通过标准 MCP tools 调用 App 内已经存在的 iOSExplore HTTP action，而不是继续手写 `curl`。

第一版不改变 iPhone 端 `ExploreServer`、`iOSExploreUIKit`、`iOSExploreDiagnostics` 的协议和模块边界。它只在 Mac 侧做包装、工具发现、错误映射和少量固定编排。

第一版完成后，开发者的真实使用路径应从：

```text
Agent / 人工读协议 → 手写 curl → POST localhost:38321 → App
```

变成：

```text
Agent → MCP tool call → Mac MCP server → POST localhost:38321 → App
```

这不是完整测试平台。它只解决“Agent 如何可靠地调用现有 App 探索能力”这个问题。

## 2. 范围与路线图

### 2.1 第一版范围：A，本机 MCP 包装器

第一版选择 **A：本机 Mac 侧 MCP 包装器**。

具体含义：

- MCP server 在 Mac 本机运行。
- 默认连接 `http://localhost:38321/`。
- 模拟器场景直接连 localhost。
- 真机场景继续复用已有 `iproxy 38321 38321`，第一版不负责启动或管理 `iproxy`。
- MCP server 把当前 App 已注册 action 暴露成 MCP tools，并提供少量更适合 Agent 的组合工具。

选择 A 的原因是：当前 iPhone 端已有 core、UIKit、Diagnostics 能力和调用协议，缺的是“Agent 通过 MCP 访问这些能力”的最后一层。先把这层做稳，比同时接管设备、端口、用例平台更容易验证真实价值。

### 2.2 后续拓展：B，设备管理层

B 不进入第一版实现，但必须保留为明确后续方向。

B 负责：

- 发现连接的真机和可用模拟器。
- 管理或启动 `iproxy`。
- 多设备选择。
- 端口占用检查。
- 残留模拟器 App 监听 38321 时的提示或清理建议。
- 设备 ID 映射提示：CoreDevice identifier 与 USB UDID 不能混用。

B 的价值是减少开发者手工准备环境的成本。它应在第一版 MCP tool 调用闭环稳定后再做。

### 2.3 后续拓展：C，测试编排层

C 不进入第一版实现，但必须保留为明确后续方向。

C 负责：

- 自然语言用例拆解。
- 步骤状态管理。
- 失败截图、日志、页面证据归档。
- 结果报告。
- 批量执行和历史记录。

C 已接近“测试平台”。只有在第一版 MCP server 已能稳定支撑单条自然语言测试案例的 `observe → act → wait → re-observe → verify` 闭环后，才值得继续设计。

## 3. 技术选型

第一版使用 **TypeScript / Node**。

原因：

- MCP 生态更贴近 Node/TypeScript，适合快速做 stdio MCP server 和 JSON schema 工具定义。
- 该 server 是 Mac 侧开发工具，不需要进入 iOS framework 构建链。
- TypeScript 比 Swift CLI 更容易对接 MCP SDK 和常见 Agent 客户端。
- Python 虽然能快速写脚本，但当前仓库没有 Python 工程基础，维护风格会更割裂。

落点定为仓库根目录下的独立目录：

```text
MCPServer/
```

该目录不放进 `Sources/`，因为 `Sources/` 是 iPhone 端 Swift SPM 与 framework 工程共享源码。

## 3.1 实施前置契约修复

MCP server 会直接消费 `help` 返回的 action description 和 `inputSchema`。因此实施前必须先处理三处调用契约问题，否则动态工具会把错误或过弱的说明交给 Agent。

1. **修正 `ui.input` 的 `viewSnapshotID` 说明。** 当前运行时契约是：`accessibilityIdentifier` 与 `path` 二选一；`viewSnapshotID` 只允许和 `path` 搭配，用于可选陈旧校验；identifier 定位不能带 `viewSnapshotID`。实施计划必须同步修正 `docs/uikit/agent-command-protocol.md`、`UIInputCommand.description` 和相关 schema/文档测试，避免 `help` 暴露“必须传 viewSnapshotID”的旧说法。
2. **补强 `ui.waitAny.conditions` 给 MCP 的说明。** 当前 `help.inputSchema` 只能把 `conditions` 暴露成 array，复杂约束靠扩展文本表达。MCP server 第一版不改 iPhone 端协议，但必须为 `wait_and_observe` 提供手写输入 schema 或 description 模板，写明 `conditions` 数量 1...16、每项必填 `id/mode`、各 mode 的必填字段、未知字段会触发 `invalid_data`。
3. **修正调用方错误表格。** `docs/superpowers/agent-mcp-exploration/curl-json-loop-protocol.md` 的错误表必须保持 Markdown 列数正确，避免 `alert_button_required` / `alert_release_unsupported` 的处理建议错位。

## 4. 组件边界

第一版拆成以下模块，避免把 MCP 协议、HTTP 转发、动态工具注册和错误处理混在一个文件里。

### 4.1 `server`

职责：

- 启动 MCP stdio server。
- 注册固定工具。
- 暴露动态工具。
- 接收 MCP `tools/call` 并分发到固定工具或动态 action。

它不直接拼 HTTP 请求；HTTP 访问全部交给 `iosExploreClient`。

### 4.2 `iosExploreClient`

职责：

- 向 `POST /` 发送 `{action,data}`。
- 默认 base URL 为 `http://localhost:38321/`。
- 解析 iPhone 端统一 envelope：
  - `{"code":"ok","data":{...}}`
  - `{"code":"...","message":"..."}`
- 区分 HTTP 通信错误、连接错误、业务 envelope 错误。

它不理解 MCP tool 名，也不负责动态工具注册。

### 4.3 `toolRegistry`

职责：

- 调用 `help` 获取当前已注册命令。
- 读取 `commands[].action`、`description`、`inputSchema`。
- 把 action 映射成 MCP tool。
- 维护 MCP tool 名到原始 action 的可逆映射。
- 支持 `refresh_tools` 后重新生成动态工具列表。

动态工具发现失败不能让 MCP server 崩溃。App 未启动或 `help` 不可达时，固定工具仍应可用，尤其是 `health_check`。

### 4.4 `staticTools`

职责：

- 提供第一版固定工具。
- 固定工具用于诊断、兜底和固化 Agent 应该遵守的调用顺序。

第一版固定工具：

| tool | 作用 |
|---|---|
| `health_check` | 检查 MCP server 是否能连到 App 的 `ping` / `help`，返回 base URL、连接状态、动态工具数量。 |
| `refresh_tools` | 重新调用 `help` 并刷新动态工具。 |
| `call_action` | 通用兜底工具，输入 `{action,data}`，直接转发到 iPhone HTTP server。 |
| `observe` | 默认调用 `ui.viewTargets`，返回 targets、navigationBar、`viewSnapshotID`。 |
| `wait_and_observe` | 先调用 `ui.waitAny`，再调用 `ui.viewTargets`，把等待结果和最新观察合并返回。 |

### 4.5 `schemaMapper`

职责：

- 把 iOSExplore `inputSchema` 映射成 MCP tool input schema。
- 保留标准 JSON Schema 字段。
- 对未知 `x-iosExplore-*` 扩展字段保持透传或忽略，不因不认识扩展字段而注册失败。
- 如果 MCP 客户端或 SDK 不接受 `x-iosExplore-*` 扩展字段，MCP server 必须把这些扩展约束追加进 tool description 或 metadata，不能静默丢掉互斥关系、模式说明和调用顺序提示。
- 如果某个动态 action 的 schema 无法可靠转换，应让该 action 降级到 `call_action` 可用，而不是阻断整个 MCP server。

### 4.6 `errorMapper`

职责：

- 把各种失败统一成 Agent 可理解的结构化结果。
- 保留 `source`、`code`、`action`、`message`、必要上下文。
- 不把可恢复业务错误压缩成普通文本。

错误分层见第 7 节。

## 5. 工具设计

### 5.1 固定工具优先级

Agent 日常优先使用固定组合工具：

```text
health_check
→ observe
→ 动作工具
→ wait_and_observe
→ 根据最新 observation 判断结果
```

固定工具不是为了隐藏底层能力，而是把最容易漏掉的调用规则写进工具层。

例如 `wait_and_observe` 固化的是：

```text
ui.waitAny
→ ui.viewTargets
```

它不会伪造 `viewSnapshotID`。新的 `viewSnapshotID` 仍由 iPhone 端 `ui.viewTargets` 签发。

### 5.2 动态原子工具

MCP server 启动或刷新时调用 `help`，把当前 App 已注册 action 动态注册成原子工具。

当前项目基础 action 包括：

- core 4 个：`ping`、`echo`、`info`、`help`
- UIKit 14 个：`ui.topViewHierarchy`、`ui.viewTargets`、`ui.tap`、`ui.control.sendAction`、`ui.screenshot`、`ui.input`、`ui.keyboard.dismiss`、`ui.scroll`、`ui.navigation.back`、`ui.navigation.tapBarButton`、`ui.wait`、`ui.waitAny`、`ui.scrollToElement`、`ui.alert.respond`
- Diagnostics 2 个：`app.logs.mark`、`app.logs.read`

因此当前基础能力是 **20 个 action**。旧文档里“18 个 action”是 Diagnostics 加入前的旧数字，实施时应以当前 `help` 输出为准。

动态工具命名规则必须稳定、可读、可逆。第一版采用以下规则：

```text
<action> → "ios_" + action.replace(/[^A-Za-z0-9_]/g, "_")

ui.viewTargets         → ios_ui_viewTargets
ui.navigation.back     → ios_ui_navigation_back
app.logs.read          → ios_app_logs_read
```

大小写保持原 action 原样，`.` 等非法字符替换为 `_`。如果映射后与固定工具名或其它动态工具冲突，该 action 不注册独立 MCP tool，必须在 `refresh_tools` 结果中报告冲突并继续允许通过 `call_action` 调用原始 action。

该规则还必须满足：

- MCP tool 名合法。
- 原始 action 保留在 description 或 metadata 中。
- 工具名到 action 可逆。
- 不同 action 映射后不能冲突。

### 5.3 `call_action` 兜底

`call_action` 输入：

```json
{
  "action": "ui.viewTargets",
  "data": {}
}
```

它的作用是保证动态工具转换或命名有问题时，Agent 仍能调用 iPhone 端已有能力。

`call_action` 不是推荐日常入口。工具描述里应明确：优先使用固定工具和动态原子工具；只有排障、未知命令或 schema 转换失败时才用 `call_action`。

## 6. 数据流

标准数据流：

```text
Agent
→ MCP tool call
→ Mac MCP server 校验参数 / 补默认值
→ iosExploreClient POST http://localhost:38321/
→ iPhone ExploreServer 执行 action
→ Mac MCP server 解析 envelope
→ MCP tool result 返回给 Agent
```

`wait_and_observe` 数据流：

```text
Agent
→ wait_and_observe({conditions, timeoutMs, intervalMs, viewTargetsOptions?})
→ POST action=ui.waitAny
→ 得到 matchedID / matchedIndex / matchedMode 或 wait_timeout
→ POST action=ui.viewTargets
→ 得到最新 targets / navigationBar / viewSnapshotID
→ 合并 wait 与 observation 返回
```

如果 `ui.waitAny` 返回 `wait_timeout`，`wait_and_observe` 仍应尽量调用 `ui.viewTargets`。原因是业务超时后 Agent 最需要知道当前页面停在哪，而不是只拿到“超时”二字。

## 7. 错误处理

错误分四层。

### 7.1 MCP server 自身错误

例子：

- base URL 配置非法。
- 工具名映射冲突。
- schema 转换内部异常。

返回结构：

```json
{
  "source": "mcp_server",
  "code": "schema_mapping_failed",
  "message": "...",
  "action": "ui.viewTargets"
}
```

这类错误说明 Mac 侧包装器自身有问题，Agent 通常不能通过业务重试解决。

### 7.2 连接 / 传输错误

例子：

- App 没启动。
- `iproxy` 没起。
- 端口被模拟器残留 App 占用。
- HTTP 请求超时。

返回结构：

```json
{
  "source": "transport",
  "code": "connection_failed",
  "baseURL": "http://localhost:38321/",
  "action": "ping",
  "timeoutMs": 5000,
  "message": "..."
}
```

`health_check` 必须把这类错误翻译成诊断结果，不得让 MCP server 崩溃。

### 7.3 iPhone HTTP 通信错误

例子：

- HTTP 400。
- HTTP 500。
- 非 JSON 响应。

返回结构：

```json
{
  "source": "http",
  "status": 400,
  "action": "ui.tap",
  "bodySnippet": "..."
}
```

这类错误通常表示 MCP server 组包有问题，或底层 HTTP server 通信层异常。

### 7.4 iPhone envelope 业务错误

例子：

- `invalid_data`
- `timeout`
- `response_too_large`
- `stale_locator`
- `wait_timeout`
- `unsupported_target`
- `alert_button_required`
- `alert_release_unsupported`

返回结构：

```json
{
  "source": "ios_envelope",
  "code": "stale_locator",
  "action": "ui.tap",
  "message": "..."
}
```

这些错误必须保留原始 `code/message`，因为 Agent 要按 code 决策：

| code | Agent 处理 |
|---|---|
| `invalid_data` | 参数字段、类型或组合不符合命令 schema；优先检查 tool schema / description，必要时用 `call_action` 排查原始 payload。 |
| `timeout` | 命令级超时，区别于业务等待 `wait_timeout`；不要当作页面条件未满足，应检查命令耗时、HTTP timeout 配置和 App 状态。 |
| `response_too_large` | 响应体超过 iPhone 端上限；截图或大结构响应应缩小范围、降低质量或改用更窄的查询。 |
| `stale_locator` | 重新 `observe`，不要重试旧 path / 旧 `viewSnapshotID`。 |
| `wait_timeout` | 重新观察页面，判断业务失败、条件写错、目标不可见或网络慢。 |
| `unsupported_target` | 改用专用命令或 `ui.control.sendAction`。 |
| `alert_button_required` | 先 `ui.alert.respond dryRun=true` 查按钮，再明确选择。 |
| `alert_release_unsupported` | Release 构建不能真实触发 alert 按钮，改查询或人工处理。 |

### 7.5 MCP tool result 形态

普通工具失败时可以返回 `isError:true`，但 content 内必须包含结构化 JSON。

`wait_and_observe` 特殊处理：

- 如果 `ui.waitAny` 命中，返回 `isError:false`，包含 `wait` 与 `observation`。
- 如果 `ui.waitAny` 超时，但随后 `ui.viewTargets` 成功，返回 `isError:false`，包含 `wait.code:"wait_timeout"` 与最新 `observation`。这样 Agent 可以继续判断当前页面。
- 如果 `ui.waitAny` 或 `ui.viewTargets` 因 transport / HTTP / MCP server 错误失败，按实际错误源返回结构化错误。

## 8. 配置

第一版配置保持最小。

| 配置 | 默认值 | 说明 |
|---|---|---|
| `IOS_EXPLORE_BASE_URL` | `http://localhost:38321/` | iPhone ExploreServer 的 HTTP 地址。 |
| `IOS_EXPLORE_REQUEST_TIMEOUT_MS` | `10000` | 普通 action 的单次 HTTP 请求超时。 |

等待类工具需要按业务 timeout 放宽 HTTP 超时：`ui.wait`、`ui.waitAny`、`wait_and_observe` 的 HTTP 请求超时应取 `max(IOS_EXPLORE_REQUEST_TIMEOUT_MS, data.timeoutMs + 5000)`。这样 Agent 传入 `timeoutMs:8000` 时，Mac 侧 HTTP 客户端不会在 iPhone 端等待结束前先断开。

第一版不管理 `iproxy`，不选择设备，不保存用例状态。

## 9. 日志

MCP server 应记录：

- action / tool 名。
- 耗时。
- HTTP status。
- envelope code。
- payload 大小。
- dynamic tools 刷新数量。
- transport 错误摘要。

不得记录：

- 大块截图 base64。
- auth token。
- 完整用户输入文本。
- 大块业务 payload。

日志只用于排障，不改变 iPhone 端日志规则。

## 10. 验证计划

### 10.1 单元测试

覆盖：

- `iosExploreClient`：请求组包、超时、envelope 成功/失败解析、HTTP 错误解析。
- `iosExploreClient` 等待超时策略：`ui.wait` / `ui.waitAny` / `wait_and_observe` 的 HTTP timeout 必须使用 `max(IOS_EXPLORE_REQUEST_TIMEOUT_MS, data.timeoutMs + 5000)`，不能在 iPhone 端返回 `wait_timeout` 前先断开。
- `schemaMapper`：`inputSchema` 到 MCP input schema 的映射，未知扩展字段不导致失败。
- `schemaMapper` 扩展约束保留：不接受 `x-iosExplore-*` 的 MCP SDK 路径也必须把扩展约束写入 description 或 metadata。
- `errorMapper`：`stale_locator`、`wait_timeout`、`alert_button_required`、连接失败等结构化输出。
- `errorMapper` 高频 code：`invalid_data`、`timeout`、`response_too_large` 必须和 `wait_timeout` 区分。
- `toolRegistry`：action 到 MCP tool 名映射稳定、可逆、无冲突。
- `toolRegistry` 命名冲突：冲突 action 不注册动态工具，但必须报告冲突并保留 `call_action` 兜底。

### 10.2 本地集成测试

用 mock HTTP server 模拟：

- `ping`
- `help`
- `ui.viewTargets`
- `ui.waitAny`

验证：

- App 不在线时 MCP server 仍能启动。
- `health_check` 能返回不可达状态。
- `refresh_tools` 能从 `help` 生成动态工具。
- `call_action` 能直接转发 action。
- `wait_and_observe` 会按顺序调用 `ui.waitAny` 再调用 `ui.viewTargets`。
- `wait_and_observe` 的 mock 用例必须覆盖 `ui.waitAny` 命中和 `wait_timeout` 两种结果；两种结果都要验证随后会尝试 `ui.viewTargets`。
- mock server 延迟返回 `wait_timeout` 时，HTTP 客户端不得早于 `timeoutMs + 5000` 断开。

### 10.3 真实 App 闭环验证

使用 `Examples/SPMExample`。

模拟器：

```text
如果 App 已经由 build_run_sim 或 Xcode 首启过，先 stop_app_sim，再 launch_app_sim 注入 env。
launch_app_sim(env={"IOS_EXPLORE_AUTOSTART":"1"})
MCP server → http://localhost:38321/
```

真机：

```text
如果 App 已经由 build_run_device 或 Xcode 首启过，先 stop_app_device，再 launch_app_device 注入 env。
launch_app_device(env={"IOS_EXPLORE_AUTOSTART":"1"})
iproxy 38321 38321
lsof -iTCP:38321 -sTCP:LISTEN  # COMMAND 必须是 iproxy，不能是残留 SPMExampl
MCP server → http://localhost:38321/
```

真机验收前的 `lsof` 检查是第一版验收要求，不等 B 设备管理层实现。原因是残留模拟器 App 也可能监听 Mac 本机 38321，导致 MCP 真实打到模拟器旧进程而不是真机。

真实闭环至少跑通：

```text
health_check
→ observe
→ 动态 ui.tap 或 call_action(ui.tap)
→ wait_and_observe
→ 根据最新 observation 判断结果
```

如果只跑单元测试，不能宣称真实 Agent 闭环完成。真实闭环必须经过：

```text
MCP → HTTP → App → HTTP response → MCP result
```

## 11. 文档更新要求

实施第一版时应同步更新：

- `docs/superpowers/agent-mcp-exploration/README.md`：入口地图中标记第一版 A 的实施状态，并保留 B/C 后续路线。
- MCP server 自身 README：写清启动方式、环境变量、真机需要先起 `iproxy`、推荐工具调用顺序。
- `docs/uikit/agent-command-protocol.md`：如工具名或推荐调用顺序影响调用方，应补充 MCP 工具对应关系。

## 12. 已确认决策

- 第一版做 A：本机 Mac MCP 包装器。
- B 设备管理层、C 测试编排层保留为显眼后续路线，但不进入第一版。
- 使用 TypeScript / Node。
- 使用混合动态发现：固定工具 + `help` 动态生成原子工具 + `call_action` 兜底。
- 第一版不改 iPhone 端协议，不新增 `ui.waitAny returnObservation`。
- `viewSnapshotID` 仍只由 iPhone 端 `ui.viewTargets` 签发。
- `wait_and_observe` 命中或超时后都尽量重新 `ui.viewTargets`。
- 当前基础 action 数量按 `help` 为准；README 当前列出 core 4 + UIKit 14 + Diagnostics 2，即 20 个基础 action。
