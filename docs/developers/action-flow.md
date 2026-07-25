# 单次 App Action 端到端数据流

本文拆解一次 action 从 agent 发起，到 App 内执行，再把结果返回给 agent 的完整过程。示例以 MCP 工具 `ui_tap` 映射到 App action `ui.tap` 为主；CLI 和 `call_action` 的差异单独说明。

## 核心概念

系统里有三层“调用名”：

| 名称 | 所在层 | 示例 | 作用 |
| --- | --- | --- | --- |
| MCP tool name | Agent/MCP 客户端 | `ui_tap` | 给 agent 选择工具用，命名保持历史稳定。 |
| Host operation | iOSDriver host | `tap_and_inspect`、`health` | Mac 侧复合能力，不一定对应单个 App action。 |
| Device action | App HTTP 协议 | `ui.tap` | App 内 `Router` 查表执行的真实 action。 |

`ui_tap` 是 MCP 工具名；它通过 `toolMappings.ts` 映射到 device action `ui.tap`。App 端只认识 `ui.tap`，不认识 `ui_tap`。

## 总览链路

```text
Agent
  -> MCP client
    -> iOSDriver MCP adapter
      -> DriverRuntime
        -> HttpActionTransport
          -> HTTP POST /
            -> ExploreServer / HTTPListener
              -> ClientSession
                -> HTTPParser
                  -> Router
                    -> AnyCommand
                      -> CommandInput.parse
                        -> Command.handle
                          -> UIKit / Diagnostics / Core executor
                            -> ExploreResult
                  <- HTTPResponse envelope
        <- InvocationResult
    <- MCP CallToolResult
  <- Agent observes result
```

同一条 App HTTP 协议也可以由 CLI 发起：

```text
Developer / script
  -> iosdriver call ui.tap --data ...
    -> DriverRuntime
      -> HttpActionTransport
        -> App POST /
```

CLI 和 MCP 的分界点在 adapter。adapter 之后都共用 `DriverRuntime`、transport、错误归一化和 artifact 解码。

## 示例输入

一次真实的 `ui.tap` 通常不是第一步。Agent 先调用 `ui_inspect`，拿到目标的 `path` 或 `accessibilityIdentifier`，以及本次 inspect 顶层返回的 `viewSnapshotID`。

MCP 工具调用形态：

```json
{
  "tool": "ui_tap",
  "arguments": {
    "path": "root/0/2",
    "viewSnapshotID": "snapshot-..."
  }
}
```

映射成 App HTTP request 后形态：

```json
{
  "action": "ui.tap",
  "data": {
    "path": "root/0/2",
    "viewSnapshotID": "snapshot-..."
  }
}
```

成功 envelope 形态：

```json
{
  "code": "ok",
  "data": {
    "activated": true,
    "activationRoute": "control.touchUpInside",
    "path": "root/0/2",
    "type": "UIButton",
    "event": "touchUpInside"
  }
}
```

业务失败 envelope 形态：

```json
{
  "code": "stale_locator",
  "message": "..."
}
```

## 第 1 段：Agent 到 MCP Adapter

Agent 不直接访问 App。Agent 通过 MCP 客户端调用一个工具，例如 `ui_tap`。

MCP server 由以下命令启动：

```bash
iosdriver mcp
```

源码本地开发时等价入口：

```bash
node iOSDriver/dist/adapters/cli/main.js mcp
```

启动后，`iOSDriver/src/adapters/mcp/server.ts` 创建 MCP server：

- `ListToolsRequestSchema` 绑定到 `handlers.listTools()`。
- `CallToolRequestSchema` 绑定到 `handlers.callTool(name, args)`。
- stdout 只写 MCP stdio 协议帧。
- 日志写 stderr，避免污染 MCP 协议。

工具列表来自静态目录：

```text
toolMappings.ts
  -> TOOL_MAPPINGS
    -> toolCatalog.ts
      -> TOOL_CATALOG
        -> server.ts listTools()
```

`tools/list` 不访问 App，不调用 `ping`，也不读 App 的 `help`。这样 MCP 客户端看到的 schema 稳定，不会因为当前 App 有没有注册 UIKit/Diagnostics 而变化。

## 第 2 段：MCP Tool 到 Device Action

`server.ts` 收到 `tools/call` 后执行：

```text
callTool(name,args)
  -> entries.get(name)
  -> invokeEntry(entry,args)
```

`ui_tap` 在 `toolMappings.ts` 中是：

```ts
{ toolName: "ui_tap", kind: "deviceAction", action: "ui.tap" }
```

因此 `invokeEntry` 走 device action 分支：

```text
runtime.invoke("ui.tap", args)
```

如果是 `health_check`，走 host operation `health`，由 `CapabilityProbe` 执行连接/能力检查。

如果是 `wait_and_inspect` 或 `ui_tap_and_inspect`，走 `WorkflowRunner`，它会按 deadline 串行调用多个 device action。

如果是 `call_action`，MCP 参数必须包含：

```json
{
  "action": "ui.tap",
  "data": {
    "path": "root/0/2",
    "viewSnapshotID": "snapshot-..."
  }
}
```

`call_action` 是兜底入口：agent 可以用它调用任意 App action，但常规 action 优先使用专门 MCP 工具。

## 第 3 段：DriverRuntime 归一化调用

`DriverRuntime.invoke(action, data)` 是 CLI 和 MCP 共用的 host 运行时入口。

它做这些事：

1. 从 generated device contracts 查 `action` 的 `idempotency` 和 `timeoutClass`。
2. 根据 `timeoutClass` 计算 request timeout。`wait` 类 action 会在业务 `timeoutMs` 外加 transport 余量。
3. 调用 `HttpActionTransport.execute({ action, data })`。
4. 如果 transport 在安全阶段失败，且 action 是 `readOnly` 或 `idempotent`，最多做一次安全重试。
5. 校验 HTTP status 和 App envelope。
6. 对截图等 artifact 做解码。
7. 返回统一 `InvocationResult`。

错误来源分层：

| source | 代表含义 |
| --- | --- |
| `transport` | 连接失败、超时、abort、socket reset。 |
| `http` | App 返回非 2xx HTTP status。 |
| `protocol` | HTTP body 不是合法 JSON 或不是 envelope 对象。 |
| `appEnvelope` | App action 业务失败，HTTP 成功但 envelope code 不是 `ok`。 |
| `artifact` | 截图等产物解码失败。 |
| `workflow` | host workflow 总 deadline 或编排失败。 |

## 第 4 段：HTTP Transport 发出请求

`HttpActionTransport` 是当前唯一 HTTP transport。它只做一件事：向 `baseURL` 发送 JSON `POST`。

```http
POST / HTTP/1.1
Content-Type: application/json

{"action":"ui.tap","data":{"path":"root/0/2","viewSnapshotID":"snapshot-..."}}
```

默认 `baseURL` 是 `http://localhost:38321/`。模拟器时 Mac 可以直接访问这个地址。真机时 Mac 的 `localhost:38321` 通常通过 `iproxy 38321 38321` 转发到手机端同端口。

transport 负责：

- 设置 `Content-Type: application/json`。
- 序列化 `{ action, data }`。
- 用 `AbortController` 执行 timeout 或外部取消。
- 读取完整响应 body。
- 对非 2xx、非 JSON、非对象 envelope 转成 `DriverFailure`。

transport 不理解 `ui.tap` 的业务字段，也不解析 `viewSnapshotID`。

## 第 5 段：App 端连接进入 HTTPListener

App 内 `ExploreServer.start()` 创建 `HTTPListener`。`ExploreServer` 初始化时已经创建 `Router` 并注册 core commands；UIKit 和 Diagnostics 由宿主显式注册。

```text
ExploreServer
  port: 38321
  router: Router
  listener: HTTPListener
```

新连接进入后：

```text
HTTPListener accept
  -> ClientSession(sessionID, connection, router, configuration)
  -> session.start()
```

`ClientSession` 是一请求一响应模型：读完整 HTTP 请求，处理一次 action，发送响应，然后关闭连接。

## 第 6 段：ClientSession 读取和解析 HTTP

`ClientSession.run()` 先套读请求超时：

```text
withTimeout(readTimeout)
  -> readRequest()
```

`readRequest()` 循环调用 `NWConnection.receive`，把收到的 bytes 追加到 buffer，然后交给 `HTTPParser.parseRequestResult`：

```text
Data buffer
  -> HTTPParser.parseRequestResult
    -> incomplete | invalid(error) | complete(HTTPRequest)
```

如果 HTTP 报文不完整，继续读。如果非法，立即返回 HTTP 400/500 类型响应并关闭连接。如果完整，进入 `process(request:)`。

## 第 7 段：HTTP 层校验 endpoint 和 body

`ClientSession.process(request:)` 做 endpoint 校验：

```swift
guard request.method == "POST", request.path == "/" else {
    // HTTP 400
}
```

然后解析 body：

```text
request.body
  -> HTTPParser.exploreRequest(from:)
    -> ExploreRequest(action, data)
```

此时数据从原始 JSON 进入 App 协议对象：

```swift
ExploreRequest(
    action: "ui.tap",
    data: JSON.object([
        "path": .string("root/0/2"),
        "viewSnapshotID": .string("snapshot-...")
    ])
)
```

body 不是 JSON、`action` 缺失、`data` 不是对象等，属于通信/协议层问题，返回 HTTP 400。已经成功解析出 action 后，后续业务失败都走 HTTP 200 + failure envelope。

## 第 8 段：命令超时和 Router 分发

进入 route 前，`ClientSession` 先问 router 该 action 有没有自声明命令超时：

```text
router.commandTimeout(for: "ui.tap")
  -> command timeout or global default
```

然后套命令执行超时：

```text
withTimeout(commandTimeout)
  -> router.route(exploreReq)
```

`Router` 内部维护：

```text
handlers: [String: AnyCommand]
```

`Router.route` 做：

```text
handlers["ui.tap"]
  -> missing: ExploreResult.failure("unknown_action")
  -> exists: command.handle(request)
```

这里的 `unknown_action` 是业务失败，不是 HTTP 404。常见原因是 App 端没有调用 `registerUIKitCommands()` 或 action 名写错。

## 第 9 段：AnyCommand 解析 typed input

`Router` 不知道 `ui.tap` 的具体 Swift 输入类型，只保存类型擦除后的 `AnyCommand`。

`AnyCommand.handle(request)` 做：

```text
request.data
  -> UITapInput.parse(from:)
    -> typed input
      -> UITapCommand.handle(input)
```

如果缺少必需的 `viewSnapshotID`，`UITapInput.parse` 会失败。`AnyCommand` 把它转成：

```json
{
  "code": "invalid_data",
  "message": "..."
}
```

这一步的意义是：wire 层仍是动态 JSON，但进入业务 executor 前已经变成 Swift typed input。UIKit 类型不会穿过 public input 边界。

## 第 10 段：Command.handle 进入具体模块

以 `ui.tap` 为例：

```text
UITapCommand.handle(UITapInput)
  -> UIKitActionPlan.tap(locator, viewSnapshotID)
  -> await UIKitActionExecutor.execute(plan)
```

`UITapCommand` 本身只做 adapter：

- 记录命令日志。
- 把 typed input 转成 `UIKitActionPlan`。
- 调用 executor。
- 捕获 `UIKitCommandError` 并返回业务 failure envelope。

它不直接做 hit-test、不直接遍历 view 树、不执行控件事件。

## 第 11 段：UIKit Executor 在 MainActor 执行

UIKit 操作必须在 MainActor 上执行。`UIKitActionExecutor.execute` 的固定流程：

```text
UIKitContextProvider.currentContext
  -> current window / rootViewController / topViewController / rootView
  -> UIKitLocatorResolver.locate
  -> validateViewSnapshot
  -> UIKitDefaultActivationResolver.route
  -> execute UIKit action
  -> JSON result
```

详细拆解：

| 步骤 | 做什么 | 失败码示例 |
| --- | --- | --- |
| 获取 context | 找当前前台 window、root view、top controller。 | `hierarchy_unavailable` |
| resolve locator | 用 `accessibilityIdentifier` 或 `path` 找 view。 | `target_not_found`、`target_ambiguous` |
| freshness 校验 | 用 `viewSnapshotID` 对比 path/context/fingerprint/semantic digest。 | `stale_locator` |
| actionable 校验 | 判断目标是否由 inspect 签发，minimal 节点不可操作。 | `not_actionable` |
| capability/route | 判断目标是否有默认激活路线。 | `unsupported_target` |
| 执行动作 | UIButton、UISwitch、文本输入、gesture/cell fallback 等。 | 具体 UIKit command error |
| 组装结果 | 返回 `JSON`，例如 activated/route/type/path。 | - |

`ui.tap` 的默认激活路线：

| 目标 | 路线 | 行为 |
| --- | --- | --- |
| `UIButton` 等 control | `control.touchUpInside` | `sendActions(for: .touchUpInside)` |
| `UISwitch` | `switch.toggle` | 翻转 `isOn` 并发送 `.valueChanged` |
| 文本输入 | `input.focus` | `becomeFirstResponder()` |
| cell 子树 | cell selection fallback | 调用 table/collection selection 路线 |
| 自定义 gesture view | `gesture.targetAction` fallback | Debug 下读取 gesture target-action 并派发 |

如果这些路线都不适用，就返回 `unsupported_target`。

## 第 12 段：ExploreResult 到 HTTP envelope

Command 返回 `ExploreResult`：

```swift
.success(JSON)
```

或：

```swift
.failure(code: ExploreError, message: String, data: JSON?)
```

`ClientSession.process` 把它交给：

```text
HTTPParser.response(for: result)
```

成功变成：

```json
{
  "code": "ok",
  "data": {}
}
```

失败变成：

```json
{
  "code": "unsupported_target",
  "message": "..."
}
```

如果响应 body 超过 `maxResponseBodyBytes`，`ClientSession.send` 不会直接发送超大 body，而会替换成 `response_too_large` failure envelope。

最后：

```text
connection.send(response.serialized())
  -> close(reason: "response_sent")
```

## 第 13 段：Host Runtime 读取响应

`HttpActionTransport` 收到 HTTP response 后：

1. 读取完整 body 文本。
2. 非 2xx 转 `http_error`。
3. body 不是 JSON 转 `protocol_error`。
4. JSON 不是对象 envelope 转 `protocol_error`。
5. 返回 `{ httpStatus, envelope }` 给 `DriverRuntime`。

`DriverRuntime.fromEnvelope` 再处理：

| App envelope | Host 结果 |
| --- | --- |
| `{"code":"ok","data":{...}}` | `InvocationResult.ok=true` |
| `{"code":"stale_locator","message":"..."}` | `InvocationResult.ok=false`, `source=appEnvelope` |
| `{"code":"ok","data":"not-object"}` | `protocol_error` |
| failure envelope 的 `message` 不是 string | `protocol_error` |

这一步会统一附加 `elapsedMs`、`attempts`、decoded artifacts 和 normalized error fields。

## 第 14 段：MCP Adapter 渲染给 Agent

MCP adapter 不直接把原始 HTTP response 丢给 agent，而是通过 `resultRenderer.ts` 把 `InvocationResult` 转成 MCP `CallToolResult`。

一般规则：

- 成功：`isError` 不为 true，内容里包含 JSON 数据或 artifact。
- 业务失败、transport 失败、protocol 失败：`isError: true`，内容里包含结构化错误摘要。
- 截图等 artifact 会按 MCP 内容格式渲染，或由 CLI `--output` 写文件。

Agent 最终看到的是 MCP 工具结果，而不是裸 HTTP response。

## CLI 直调的差异

CLI 从 `iOSDriver/src/adapters/cli/main.ts` 开始：

```text
parseArguments
  -> resolveCLIConfig
  -> DriverRuntime / CapabilityProbe / WorkflowRunner
  -> executeCLICommand
```

`iosdriver call ui.tap --data ...` 进入：

```text
runCall
  -> parseData
  -> runtime.invoke(action,data)
  -> printInvocationSuccess / printInvocationFailure
  -> exit code
```

CLI 与 MCP 的相同点：

- 都使用 `DriverRuntime`。
- 都使用 `HttpActionTransport`。
- 都走 App `POST /`。
- 都得到同一种 `InvocationResult`。

CLI 与 MCP 的不同点：

| 项 | CLI | MCP |
| --- | --- | --- |
| 输入 | shell argv、`--data JSON`、`--data @file` | MCP tool name + arguments |
| 输出 | stdout JSON 或 artifact 文件，stderr 日志 | MCP `CallToolResult`，stderr 日志 |
| 失败表达 | 固定 exit code + stdout/stderr | `isError` + 内容 |
| 使用者 | 人类、脚本、CI smoke | agent/MCP 客户端 |

## Workflow 的差异

Workflow 是 Mac 侧 host operation，不是 App 内 action。以 `ui_tap_and_inspect` 为例：

```text
Agent calls ui_tap_and_inspect
  -> MCP mapping: hostOperation tap_and_inspect
  -> WorkflowRunner.run("tap_and_inspect", input, deadline)
    -> runtime.invoke("ui.tap", tapData)
    -> optional stable wait
    -> runtime.invoke("ui.inspect", inspectData)
  -> aggregate result
```

Workflow 的关键区别：

- 它有一个总 deadline。
- 每个子阶段仍然是普通 device action。
- 任一阶段失败会被包装成 workflow 结果。
- App 端不知道自己处在 workflow 里，只看到多次独立 `POST /`。

因此排查 workflow 时，要把它拆成子 action 分别验证。例如先用 `iosdriver call ui.tap ...`，再用 `iosdriver call ui.inspect ...`。

## 常见失败在哪一层

| 现象 | 可能层级 | 先查什么 |
| --- | --- | --- |
| MCP 客户端看不到 `ui_tap` | MCP client / MCP server 启动 | 客户端配置是否启动 `iosdriver mcp`，`npm run build` 是否已执行。 |
| `health_check` 连接失败 | transport / 端口 / App server | `curl ping`、`iproxy`、App 是否启动 server。 |
| `ui_tap` 返回 `unknown_action` | App router 注册 | App 是否调用 `registerUIKitCommands()`，`help` 是否列出 `ui.tap`。 |
| 返回 `invalid_data` | CommandInput 解析 | 参数字段名、类型、必填项是否符合 `docs/generated/contracts.md`。 |
| 返回 `stale_locator` | UIKit snapshot | 重新调用 `ui.inspect`，使用最新 `viewSnapshotID`。 |
| 返回 `not_actionable` | UIKit inspect 签发策略 | 目标是 minimal/展示节点，不应直接操作，换可操作 target。 |
| 返回 `unsupported_target` | UIKit action route | 当前 view 没有确定默认激活路线，改用更具体 action 或补能力。 |
| HTTP 400 | HTTP/parser 层 | method/path/body 是否是 `POST /` 和合法 JSON 对象。 |
| `protocol_error` | App response / host parsing | App 返回是否符合 envelope，是否被非业务日志污染 stdout。 |

## 用最短路径定位问题

按从低到高的顺序验证：

```bash
curl -s -X POST http://localhost:38321/ -d '{"action":"ping"}'
iosdriver doctor
iosdriver call ping
iosdriver call ui.inspect --data '{"mode":"minimal"}'
```

如果 `ui.inspect` 成功，再用返回的 `path` 和 `viewSnapshotID` 调：

```bash
iosdriver call ui.tap --data '{"path":"root/0/2","viewSnapshotID":"snapshot-..."}'
```

如果 CLI 成功但 MCP 失败，问题多半在 MCP 客户端配置、工具参数或 MCP result 渲染。
如果 curl 失败，先不要看 MCP，先处理 App server、端口或真机转发。

## 维护边界

- 新增 App 能力时，优先新增 device action contract 和 Swift command，不改 HTTP endpoint。
- 新增 agent 工具时，优先映射到已有 device action 或 host operation，不复制执行逻辑。
- CLI/MCP adapter 不解析 UIKit 业务字段，只做参数投影和结果渲染。
- Runtime 不关心 UIKit、Diagnostics 或 core 业务，只处理 transport/envelope/artifact。
- App command 不关心 MCP 工具名，只关心 `ExploreRequest.action`。
- 字段、默认值、错误码以 `contracts/` 和 generated 文档为准。
