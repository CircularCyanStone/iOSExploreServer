# iOSDriver Contract Runtime Refactor Design

- 日期: 2026-07-24
- 状态: 设计已批准，待实施计划
- 关联决策: [`docs/cli/README.md`](../../cli/README.md)

## 1. 目标

将当前由 Swift typed input、Node `staticTools.ts`、MCP handler 和 skills 分散维护的协议与执行逻辑，重构为可验证的跨语言合同、Mac 侧 host runtime、独立 Workflow 层以及 MCP/CLI 适配器。

重构完成后必须同时满足：

1. App action 的字段、默认值、范围、稳定错误码和结果类型只有一个跨语言合同源。
2. Swift 仍可以保留 UIKit 相关的复杂语义解析，但不能再独立维护一套未验证的 wire schema。
3. MCP `tools/list` 不依赖 App 是否在线，工具名称和静态 schema 保持稳定。
4. MCP、CLI 和未来 Host SDK 复用同一个 host runtime，不复制 HTTP、错误、截图和组合流程逻辑。
5. 现有 `POST /`、JSON envelope、`call_action` 和公共 MCP 工具名称保持兼容。
6. 每个阶段都能独立编译、测试和回滚，不允许最后阶段才暴露跨语言集成问题。

## 2. 非目标

本次重构不做以下事情：

- 不改变 iPhone App 的 HTTP endpoint、请求 body 结构和基础 envelope。
- 不把 MCP 协议下沉到 Swift App；App 仍只执行 action。
- 不把 UIKit 类型放入 core public boundary。
- 不实现任意 JSON Schema 方言的通用验证器；合同只支持项目实际使用的受控子集。
- 不让 host runtime 自动启动、停止或管理 `iproxy`、XcodeBuildMCP 或设备生命周期。
- 不把 skills 变成协议事实源；skills 继续描述工作流策略和失败分诊。
- 不为未纳入公共合同的宿主扩展 action 自动生成 MCP 工具。

## 3. 设计词汇

- **DeviceActionContract**：一个 App action 的稳定 wire contract，包含输入 schema、版本、模块、结果和稳定错误码。
- **HostOperationSpec**：Mac 侧能力或跨 action Workflow 的输入输出合同，例如 `health`、`capabilities`、`wait_and_inspect`。
- **Host runtime**：在 Mac 上执行 transport、action 调用、能力探测、错误归一化和 artifact 解码的核心模块。
- **WorkflowRunner**：依赖 host runtime 组合多个 action 的模块，不绑定 MCP 或 CLI。
- **Adapter**：将 host runtime 或 Workflow 投影为某个入口的薄模块。MCP adapter 负责 MCP 内容，CLI adapter 负责命令行渲染。
- **Runtime state**：当前 App 是否在线、哪些 action 已注册、端口是否可达等动态事实，不进入静态合同。

## 4. 总体架构

```text
contracts/
  ├── definitions/
  ├── device-actions/
  ├── host-operations/
  └── errors.json
          │
          └── contract generator
                ├── Swift generated metadata / fields
                ├── TypeScript generated schemas
                └── generated documentation fragments

App device runtime
  ├── Command registry
  ├── typed parser / UIKit executor
  ├── ExploreResult envelope
  └── runtime help metadata

Host runtime
  ├── ActionTransport
  ├── DriverRuntime
  ├── CapabilityProbe
  ├── DriverError
  └── ArtifactDecoder

WorkflowRunner
  ├── waitAndInspect
  └── tapAndInspect

MCP adapter ─┐
CLI adapter ─┼──> Host runtime / WorkflowRunner
Host SDK ────┘
```

合同生成器输出稳定的构建产物，不依赖运行中的 App。App 的 `help` 只报告当前注册结果，供 host runtime 做能力探测和合同兼容性检查。

## 5. 合同源

### 5.1 文件布局

合同使用小文件组织，避免所有 action 共享一个高冲突 JSON：

```text
contracts/
  bundle.json
  errors.json
  definitions/
    locator.json
    view-snapshot.json
    wait-condition.json
  device-actions/
    core.ping.json
    core.echo.json
    core.info.json
    core.help.json
    uikit.inspect.json
    uikit.tap.json
    ...
    diagnostics.app-logs-mark.json
    diagnostics.app-logs-read.json
  host-operations/
    health.json
    capabilities.json
    call-action.json
    wait-and-inspect.json
    tap-and-inspect.json
```

`bundle.json` 只包含 `protocolVersion`、`contractVersion`、合同文件清单和生成器版本。每个文件通过相对 `$ref` 引用共享定义；生成器在输出 TypeScript 和 Swift 前必须解析并展开本地引用。

### 5.2 bundle metadata

```json
{
  "protocolVersion": "1",
  "contractVersion": "1.0.0",
  "generatorVersion": "1",
  "files": [
    "device-actions/core.ping.json",
    "host-operations/health.json"
  ]
}
```

合同版本遵循以下兼容规则：

- 新增可选字段或新增非破坏性描述：minor 版本；
- 修改默认值、必填字段、enum、范围、错误码含义或结果结构：major 版本；
- 只修正说明文字且不改变语义：patch 版本。

生成器对规范化 JSON 做 SHA-256，得到 `contractHash`。hash 用于标识精确构建产物，不单独决定兼容性；兼容性必须按字段语义比较。

### 5.3 DeviceActionContract

每个 device action 至少包含：

```json
{
  "kind": "deviceAction",
  "action": "ui.inspect",
  "description": "读取当前 UI 结构并签发 viewSnapshotID。",
  "provider": "uikit",
  "stability": "public",
  "inputSchema": {
    "type": "object",
    "properties": {},
    "required": [],
    "additionalProperties": false
  },
  "result": { "kind": "json" },
  "errors": ["invalid_data", "internal_error"],
  "idempotency": "readOnly",
  "timeoutClass": "standard"
}
```

支持的 schema 子集包括：

- `object`、`array`、`string`、`number`、`integer`、`boolean`、`null`；
- `properties`、`required`、`additionalProperties`；
- `items`、`minItems`、`maxItems`、`uniqueItems`；
- `enum`、`default`、`minimum`、`maximum`、`exclusiveMinimum`、`exclusiveMaximum`；
- `oneOf`、`allOf`、`not`；
- `description` 以及命令需要展示但无法由标准 JSON Schema 表达的 `x-iosExplore-constraints`。

合同不包含 Swift 的 `UIView`、`Date`、`IndexPath` 或具体 executor 类型。它只描述请求线上传输的 JSON 形态。

### 5.4 HostOperationSpec

Host operation 可以拥有不属于 App action 的字段。例如 `tap_and_inspect` 的 `waitForStable`、`stableTimeMs`、`inspectDepth` 和 `inspectMaxTargets` 必须由 HostOperationSpec 定义，而不是伪装成 `ui.tap` 的字段。

Host operation 至少包含：

```json
{
  "kind": "hostOperation",
  "operation": "tap_and_inspect",
  "description": "点击目标并返回操作后的 UI 状态。",
  "inputSchema": {},
  "result": { "kind": "json" },
  "errors": ["configuration", "transport", "http", "appEnvelope", "workflow"]
}
```

以下操作进入 HostOperationSpec：

- `health`：端点可达性和基础协议检查；
- `capabilities`：运行时 action、模块、版本和 schema 兼容性检查；
- `call_action`：通用 App action 调用入口；host runtime 内部方法命名为 `invoke`；
- `wait_and_inspect`：`ui.waitAny` 后读取 `ui.inspect`；
- `tap_and_inspect`：`ui.tap`、可选 `ui.wait`、再读取 `ui.inspect`。

`init`、`doctor`、`mcp` 是 CLI 生命周期命令。`doctor` 可以调用 `health` 和 `capabilities`，但 CLI 对 Node、配置文件和代理进程的检查不进入 HostOperationSpec。

### 5.5 errors.json

`errors.json` 只描述跨入口需要稳定识别的错误码及其机器语义，不保存完整动态 message：

```json
{
  "invalid_data": {
    "source": "appEnvelope",
    "retryable": false,
    "terminal": true
  },
  "stale_locator": {
    "source": "appEnvelope",
    "retryable": false,
    "terminal": true
  },
  "wait_timeout": {
    "source": "appEnvelope",
    "retryable": true,
    "terminal": false
  }
}
```

MCP `isError`、CLI exit code 和人类可读 `nextSteps` 是 adapter/workflow 的呈现策略，不写入 App envelope 合同。

## 6. 生成器

### 6.1 位置和调用

生成器放在 `iOSDriver/scripts/generate-contracts.mjs`，只使用 Node 内置模块读取、解析、规范化和写出文件。`iOSDriver/package.json` 增加：

```text
npm run contracts:generate
npm run contracts:check
```

- `contracts:generate` 根据 `contracts/` 覆盖生成文件；
- `contracts:check` 在临时目录生成并与仓库中的 generated 文件比较，发现漂移时失败；
- `npm run build` 和 `npm test` 在执行 TypeScript 编译前运行 `contracts:check`。

### 6.2 TypeScript 输出

生成到 `iOSDriver/src/generated/`：

- `deviceActionContracts.ts`：规范化 action 名、描述、输入 schema、结果和 metadata；
- `hostOperationSpecs.ts`：host operation schema 和 metadata；
- `contractBundle.ts`：protocol/contract version、hash 和完整索引。

生成文件不允许手工修改。MCP adapter 的工具名映射放在非 generated 的 `src/adapters/mcp/toolMappings.ts`，以保持历史名称兼容。

### 6.3 Swift 输出

按 target 生成：

- `Sources/iOSExploreServer/Generated/CoreActionContracts.swift`；
- `Sources/iOSExploreUIKit/Generated/UIKitActionContracts.swift`；
- `Sources/iOSExploreDiagnostics/Generated/DiagnosticsActionContracts.swift`。

生成的 Swift metadata 提供：

- action 名、description、provider、stability、result kind、错误码、timeout class 和 idempotency；
- 使用现有 `CommandFields` 工厂生成 scalar/array 字段声明；
- `CommandInputSchema` 的统一输入 schema。

生成器不生成 UIKit executor，也不生成完整 domain model。对 enum 字段生成 wire-level `String` 字段和 enum 值约束；Swift parser 再映射到 `InputMode` 等领域 enum。复杂数组和跨字段规则保留在手写 parser 中。

## 7. App device runtime 变更

### 7.1 Command metadata

新增 core public 的 `CommandContract` 值类型，至少包含：

```text
action
description
inputSchema
provider
stability
resultKind
declaredErrors
idempotency
timeoutClass
contractVersion
contractHash
```

`Command`/`AnyCommand` 不再只保存 action、description 和 `CommandInputSchema`，而是保存完整 `CommandContract`。Router metadata 和 `help` 从同一份 contract 快照读取。

### 7.2 generated input schema 接入

每个公共命令的 `Input.inputSchema` 改为返回对应 generated contract schema。现有 parser 改为读取 generated field 定义：

- scalar 字段不再在每个 Models 文件重复声明类型、默认值和范围；
- parser 继续负责把 wire scalar 转成 domain value；
- `UIInputInput`、`UIWaitAnyInput` 等需要保留 `parse(from:)`，但顶层 schema 和字段访问来自 generated contract；
- parser 仍必须调用 `assertAllDeclaredFieldsRead()`，防止生成字段未被业务读取。

生成的 field 名称按 action 和 JSON key 稳定派生，不依赖文件路径。

### 7.3 help 响应

`help` 成功 data 顶层增加：

```json
{
  "protocolVersion": "1",
  "contractVersion": "1.0.0",
  "contractHash": "sha256:...",
  "commands": [
    {
      "action": "ui.inspect",
      "description": "...",
      "inputSchema": {},
      "provider": "uikit",
      "stability": "public",
      "result": { "kind": "json" },
      "errors": ["invalid_data", "internal_error"]
    }
  ]
}
```

`commands` 只列当前 Router 已注册的 action。未注册 UIKit/Diagnostics 时仍然不出现在列表中，模块状态由 host capability probe 推断。

### 7.4 扩展 action

宿主自定义 action 使用新的 `CommandContract` 注册入口。为保持已有集成代码可迁移，旧的 `register(action:description:input:handler:)` 保留为 runtime extension 便利入口：

- 自动使用 `Input.inputSchema`；
- `provider` 为 `extension`；
- `stability` 为 `internal`；
- `contractSource` 为 `runtime`；
- 不纳入公共静态 MCP 工具生成。

需要对外发布的扩展 action 必须显式传入完整 contract，并由宿主自行提供对应合同文件或版本策略。

## 8. Host runtime

### 8.1 目录和职责

Node 代码拆分为：

```text
iOSDriver/src/runtime/
  actionTransport.ts
  httpActionTransport.ts
  driverRuntime.ts
  driverErrors.ts
  artifacts.ts
  capabilityProbe.ts
iOSDriver/src/workflows/
  waitAndInspect.ts
  tapAndInspect.ts
```

职责如下：

- `ActionTransport`：定义可注入的请求接口，测试使用 fake transport；
- `HttpActionTransport`：实现 POST `/`、HTTP status、JSON parse、abort timeout；
- `DriverRuntime`：把 transport response 转成统一 invocation result，处理 App envelope、合同 metadata、artifact 和 action policy；
- `DriverError`：分辨 configuration、transport、http、protocol、appEnvelope、workflow；
- `CapabilityProbe`：调用 `ping`/`help`，生成健康和能力报告；
- `WorkflowRunner`：只依赖 `DriverRuntime.invoke`，不导入 MCP SDK 或 CLI parser。

### 8.2 invocation result

Host runtime 对预期失败返回值对象，不用异常作为正常业务分支：

```text
InvocationResult
  ├── ok: true
  │     data: JSONObject
  │     artifacts: Artifact[]
  └── ok: false
        error: DriverError
```

编程错误或无法分类的异常仍可抛出，adapter 顶层将其转换为 `unexpected` host error。App envelope 的 `data` 必须保留，不能因为转换成 HostError 而丢失 `elapsedMs`、`attempts` 等字段。

### 8.3 transport 和 timeout

Host runtime 需要分别处理：

- HTTP connect/read timeout；
- App 命令 timeout envelope；
- `ui.wait`/`ui.waitAny` 的业务 deadline；
- Workflow 自身总预算。

`ActionTransport` 接收明确的 timeout 参数，`DriverRuntime` 根据 action contract 的 `timeoutClass` 和调用数据计算默认值。等待类 action 的 HTTP timeout 必须大于业务 deadline，并保留固定 margin。

### 8.4 retry policy

默认策略为不重试。只有以下条件同时满足时才允许 transport-only retry：

1. action contract 的 `idempotency` 是 `readOnly` 或明确标记为 `idempotent`；
2. 失败来源是连接建立、连接重置或可判定的 transport error；
3. 没有收到 App 成功或业务 envelope，避免“请求已执行但响应丢失”导致重复副作用。

`call_action` 不再对任意 action 无条件重试。UI tap、input、navigation、swipe、longPress 默认是 `sideEffecting`。

### 8.5 artifact

内部 artifact 模型至少支持：

```text
Artifact
  kind: image | text | json
  mimeType
  data/base64
  metadata
```

当前只实现 App JSON envelope 中的 PNG screenshot 到 `image` artifact 的转换。MCP adapter 将其变为 MCP image content；CLI adapter 根据 `--output` 写文件，否则输出 JSON metadata。`file` artifact 需要新的传输协议，不在本阶段伪造支持。

## 9. WorkflowRunner

### 9.1 waitAndInspect

输入由 `HostOperationSpec` 定义，顶层包含 wait 参数和 inspectOptions。执行顺序：

1. 调用 `ui.waitAny`；
2. 调用 `ui.inspect` 获取最新 observation；
3. `wait_timeout` 仍然尽量返回最新 observation，并将 wait 结果标记为非终态业务 outcome；
4. 其它失败立即返回，保留已发生的 App envelope 和 workflow timing。

### 9.2 tapAndInspect

执行顺序：

1. 调用 `ui.tap`；失败时不执行后续步骤；
2. `waitForStable=true` 时调用 `ui.wait` idle；等待失败或超时不阻止后续 inspect；
3. 调用 `ui.inspect`；
4. 返回 `{ tap, stateAfter, timing }`，不让 MCP adapter 自己拼接结果。

WorkflowRunner 的错误结果包含阶段名称（tap/wait/inspect），但不改变底层 App error code。

## 10. MCP adapter

### 10.1 工具目录

MCP adapter 目录：

```text
iOSDriver/src/adapters/mcp/
  toolMappings.ts
  toolCatalog.ts
  resultRenderer.ts
  server.ts
```

`toolMappings.ts` 明确保存历史 MCP 名称到 device action 或 host operation 的映射。它不保存 schema 字段；schema 从 generated contract 读取。

保留现有名称，包括：

- `health_check`、`check_capabilities`、`call_action`；
- `ui_inspect`、`ui_tap`、`ui_screenshot` 等公共 action 工具；
- `wait_and_inspect`、`ui_tap_and_inspect` 等 Workflow 工具。

### 10.2 tools/list

`tools/list` 只读取 generated contract 和 explicit tool mapping：

- 不发 HTTP；
- 不调用 `help`；
- App 不在线时仍返回完整静态集合；
- 不设置 `listChanged`；
- 不因为模块未注册而删除工具。

`check_capabilities` 负责报告缺少 action，而不是改变列表。

### 10.3 result rendering

MCP adapter 只做三件事：

- `InvocationResult` JSON 转 MCP text content；
- `Artifact(kind=image)` 转 MCP image content；
- 根据错误来源和稳定错误码设置 `isError`。

`nextSteps` 应来自 host/workflow 的规则映射，不允许把完整错误 message 作为隐式协议。

## 11. CLI adapter

### 11.1 命令

```bash
iosdriver init
iosdriver doctor
iosdriver call <action> --data '{}'
iosdriver mcp
```

### 11.2 配置优先级

配置优先级固定为：

```text
命令行参数 > 环境变量 > 配置文件 > 默认值
```

默认配置路径为 `$IOSDRIVER_CONFIG`，未设置时使用 `$XDG_CONFIG_HOME/iosdriver/config.json`，再回退到 `~/.config/iosdriver/config.json`。配置文件只保存 base URL、请求 timeout 和 CLI 偏好，不保存当前未启用的 auth token。

`init` 创建目录和配置文件时使用原子替换；配置已存在时保留未知字段和用户已有值，不覆盖文件。命令只打印 MCP 配置片段，不修改任何 MCP 客户端私有配置文件。

### 11.3 输出和退出码

- stdout：成功 JSON 或用户明确要求的文本结果；
- stderr：诊断、日志、警告和进度；
- `mcp` 模式 stdout 只能输出 MCP stdio 帧；
- 配置错误退出码 `2`；
- transport/HTTP/protocol 错误退出码 `3`；
- App 业务失败或 workflow 终态失败退出码 `1`；
- 成功退出码 `0`。

CLI `call` 支持 `--data @file`。带 image artifact 时，必须使用 `--output <path>` 写入文件；未指定时输出 metadata，不把大块 base64 默认写入终端。

`package.json` 增加稳定 bin `iosdriver`，并保留 `ios-explore-mcp-server` 作为兼容别名。`iosdriver mcp` 成为 MCP 配置中的稳定 command/args 入口。

## 12. 能力和兼容性

### 12.1 help runtime response

Host runtime 读取 `help` 后保存：

- protocolVersion；
- contractVersion；
- contractHash；
- 当前注册 commands；
- 每个 command 的 inputSchema、provider、stability、result 和 errors。

App 不可达时：

- `tools/list` 正常返回静态工具；
- `health` 返回端点不可达；
- `capabilities` 的 action/module 状态为 `unknown`，不能伪造为 missing。

### 12.2 schema compatibility

比较顺序如下：

1. action 是否存在；
2. schema 是否是合法 object；
3. required 字段是否被新增或删除；
4. properties 类型、enum、范围、数组边界是否收窄；
5. additionalProperties 是否从允许变为禁止；
6. 新增可选字段只报告 compatible addition；
7. contract hash 不同时报告版本和差异摘要。

兼容性检查结果不会改变 MCP tools/list，只影响 `health`/`capabilities` 的报告和具体调用时的错误建议。

## 13. 测试设计

### 13.1 合同生成测试

- 每个合同文件能通过结构校验；
- 本地 `$ref` 能展开且无循环；
- 规范化 bundle hash 稳定；
- 生成器重复执行得到字节相同的输出；
- generated 文件手工修改后 `contracts:check` 失败；
- 所有公共 action 和 host operation 都有唯一名称。

### 13.2 Swift 测试

- generated scalar field 与 `CommandInputDecoder` 类型、默认值、范围保持一致；
- `UIInputInput`、`UIWaitAnyInput`、日期、WebView 等复杂 parser 的合法/非法样例符合合同；
- parser 不读取 generated schema 字段时触发 unread guard；
- `help` 返回 protocol/contract version、hash 和 command metadata；
- runtime extension action 被标为 extension 且不改变公共合同 hash；
- 现有 `unknown_action`、`invalid_data`、timeout 和 envelope 测试全部保持。

### 13.3 Host runtime 测试

使用 fake `ActionTransport`，不依赖 App：

- connect/read timeout；
- HTTP 非 2xx 和非法 JSON；
- App success/failure envelope；
- response data 保留；
- retry policy 对 readOnly/idempotent/sideEffecting 的差异；
- screenshot PNG artifact 转换；
- capability probe 的 reachable、missing、partial、unknown 状态；
- schema compatibility 的 breaking/additive 判断。

### 13.4 Workflow 测试

- `wait_and_inspect` 成功、wait_timeout 后继续 inspect、inspect 失败；
- `tap_and_inspect` tap 失败短路、wait 超时继续 inspect、完整 timing；
- Workflow 不导入 MCP SDK 或 CLI parser。

### 13.5 MCP/CLI 测试

- App 不可达时 tools/list 完整且稳定；
- 工具名称和历史 action mapping 不变；
- schema 来自 generated contract 而非手写副本；
- screenshot MCP image content；
- CLI 配置初始化幂等且不覆盖未知字段；
- stdout/stderr 分离；
- exit code 映射；
- `mcp` stdout 没有非协议日志；
- `call --data @file` 和 artifact 输出。

### 13.6 集成测试

最后阶段使用真实 App 验证：

- `ping`、`help`、`capabilities`；
- 至少一个 UIKit read action；
- `ui.inspect` → `ui.tap` 或 `ui.control.sendAction`；
- screenshot image artifact；
- `app.logs.mark`/`app.logs.read`；
- App 未注册 UIKit/Diagnostics 时的 partial/not_registered 状态。

## 14. 迁移阶段

### Phase 1: Contract foundation

建立合同目录、受控 schema 规范、generator、generated TypeScript/Swift metadata 和合同检查。此阶段不改变 MCP 行为，先把当前 Swift `help` 和 Node 静态 schema 做成兼容性基线。

### Phase 2: App contract integration

接入 generated Swift fields 和 `CommandContract`，迁移 core、UIKit、Diagnostics command metadata；保留复杂 parser；`help` 增加版本和 hash；扩展 action 获得 runtime metadata。

### Phase 3: Host runtime extraction

实现 `ActionTransport`、`HttpActionTransport`、`DriverRuntime`、`DriverError`、`Artifact` 和 `CapabilityProbe`。先让旧 MCP adapter 通过 compatibility facade 调用新 runtime，再删除旧 HTTP/错误路径。

### Phase 4: Workflow extraction

把 `wait_and_inspect`、`tap_and_inspect` 从 `staticTools.ts` 移入 WorkflowRunner，保持输入输出和错误终态一致；增加 fake transport 单测。

### Phase 5: MCP adapter

从 generated contract 生成工具 schema，恢复历史 tool mapping，保证 App 离线静态启动；移除 `staticTools.ts` 中的 schema、transport 和 workflow 业务职责。

### Phase 6: CLI adapter

实现配置层、`init`、`doctor`、`call`、`mcp`，加入 bin 别名、输出协议和 exit code。CLI 与 MCP 只能调用 Host runtime/WorkflowRunner。

### Phase 7: Cleanup and verification

删除 compatibility facade 中已无调用者的旧实现，运行 Swift 定向测试、Node `npm test`、合同检查、MCP startup 测试和真实 App 集成验证；同步更新 CLI、architecture 和 runbook 文档。

## 15. 兼容性不变量

整个迁移期间必须保持：

- Swift App 仍接受 `POST /` 和 `{ action, data }`；
- HTTP communication failure 与 HTTP 200 business failure 的区分不变；
- `call_action` 的 MCP 工具名不变；
- 公共 MCP 工具名不变；
- App 不可达时 MCP `tools/list` 不发 HTTP 且结果稳定；
- screenshot 的 MCP image content 行为不变；
- `wait_timeout` 后 `wait_and_inspect` 仍尽量返回最新 observation；
- custom runtime action 仍可通过 `call_action` 调用；
- skills 只消费生成的稳定协议片段，不反向定义协议。

## 16. 设计取舍

### 为什么不生成完整 Swift domain model

UIKit command 的 wire JSON 和执行 domain 类型不是一一对应关系。日期字符串需要多种 ISO 解析策略，条件数组需要 mode-specific 校验，locator 在解析后才变成 Foundation-only domain value。生成完整 domain model 会把 UIKit 业务规则硬塞进跨语言 IDL，降低 locality。生成字段/schema/metadata，手写复杂 parser，并用合同测试锁定行为，能保持更深的 Swift command module。

### 为什么不建立 AdapterContract

MCP 工具名和 CLI 命令名是外部接口，但它们描述的是展示和调用方式，不是 App action 的业务协议。显式 mapping 加快照测试能保护兼容性，同时避免第三份 schema/默认值/错误事实源。HostOperationSpec 已经承接了组合 Workflow 的真正业务字段。

### 为什么保留静态 MCP tools/list

MCP 客户端在 App 尚未启动、真机代理暂时不可达或当前模块未注册时仍需要完成握手和工具发现。静态列表把“可调用的公共能力”和“当前设备是否可用”分离；`capabilities` 负责后者。

## 17. 完成标准

重构只有在以下条件同时满足时才算完成：

1. `contracts:check`、Swift 定向测试和 Node `npm test` 通过；
2. generated Swift/TypeScript schema 没有手工副本漂移；
3. MCP startup 测试证明 App 不在线时工具列表稳定；
4. Host runtime 和 WorkflowRunner 可用 fake transport 独立测试；
5. CLI `init/doctor/call/mcp` 的输出、stderr 和 exit code 有覆盖；
6. 真实 App 验证 help version/hash、UIKit action、截图和日志 action；
7. `staticTools.ts` 不再承担 schema、transport、错误归一化或 Workflow 实现；
8. 文档、skills 和 runbook 只引用合同生成结果，不再手写协议真相。
