# iOSDriver CLI 架构判定与迁移方案

- 日期: 2026-07-24
- 状态: 架构决策记录
- 决策: 采用“contract / runtime / adapter”拆分，但不建立一份包揽所有内容的总 manifest，也不把 adapter 做成第三个业务事实源。

## 一句话结论

最终结构应为：

```text
DriverContractBundle
  ├── DeviceActionContract
  └── HostOperationSpec
          │
          ├── App device runtime
          ├── Host runtime
          ├── Workflow layer
          ├── MCP adapter
          └── CLI adapter
```

其中：

- **contract** 是跨语言稳定的输入、输出、错误和兼容性协议，不描述当前设备状态。
- **device runtime** 在 App 内执行 action、UIKit 操作和日志命令。
- **host runtime** 在 Mac 侧负责传输、调用、能力探测、错误归一化和产物解码。
- **workflow layer** 负责 `wait_and_inspect`、`tap_and_inspect` 等跨 action 组合。
- **adapter** 只是把同一套 host 能力投影成 MCP 或 CLI 入口；MCP 和 CLI 是平级适配器。

CLI 是开发者、脚本和诊断的一等入口，MCP 是 Agent 的结构化入口。不能把 CLI 定义成唯一语义入口，也不能让 MCP 自己维护另一套业务实现。

## 为什么需要调整现状

当前系统已经形成两个运行时：

1. Swift `ExploreServer` 在 App 内注册 `Command`，执行 typed 输入解析、UIKit/Diagnostics handler 和业务错误封装。
2. `iOSDriver/src/iosExploreClient.ts` 在 Mac 侧通过 HTTP 调用 App，并把 HTTP 错误和 App envelope 转换成 Node 错误。
3. `iOSDriver/src/staticTools.ts` 另外维护 MCP 工具名、action 映射、输入 schema、组合工具、截图转换和错误富化。
4. `help` 返回当前实际注册的 action；`check_capabilities` 用它检查 App 是否满足静态工具依赖，但它不应该决定 `tools/list`。

这说明真正需要收敛的是“协议和执行核心”，不是把所有逻辑机械搬到一份 IDL。当前 Swift schema 与 typed parser 已经有复杂语义：部分输入要手写嵌套数组解析、跨字段校验和日期解析，不能声称全部 typed input 都能直接生成。

## 采用与拒绝

| 方案 | 决策 | 原因 |
|---|---|---|
| 继续由 `staticTools.ts` 手写全部 schema | 拒绝 | 继续复制 Swift 字段、默认值、范围和错误语义，漂移只能靠运行时比较发现。 |
| 动态读取 `help` 生成 MCP tools | 拒绝 | App 不在线时无法发现工具，工具列表会随运行时注册状态变化，破坏 MCP 启动稳定性。 |
| 一份总 manifest 同时描述 action、宿主工作流、CLI、MCP、当前能力 | 拒绝 | 把静态协议、宿主策略和运行时状态混成一个事实源，最终会成为新的大杂烩。 |
| contract / runtime / adapter 三层拆分 | 采用 | 能把协议、执行核心和展示入口分别演进。 |
| 两个合同命名空间 + 独立 Workflow 层 | 最终方案 | 解决组合工具字段无法归属 App action、HostRuntime 过宽和 adapter 业务化问题。 |

## 合同设计

### DriverContractBundle

合同是一个版本化、可生成的机器可读 bundle，建议存放在仓库的 `contracts/` 目录。它不是运行时能力快照，也不包含 `iproxy`、端口或当前 App 是否启动。

bundle 只有两个业务命名空间：

```text
DeviceActionContract
HostOperationSpec
```

### DeviceActionContract

描述一个 App action 的稳定 wire contract：

- action 名和 contract version；
- 输入 JSON Schema、默认值、范围、enum、数组/对象结构；
- 所属模块和稳定级别（public / experimental / internal）；
- 结果类型或 artifact 类型；
- 稳定业务错误码；
- 是否幂等、是否允许 transport-only retry；
- 命令 timeout class 或可接受的执行预算；
- contract hash，用于 App 与 host 的兼容性检查。

它不描述：

- UIKit 对象、Swift 具体类型和 handler 实现；
- 当前是否调用了 `registerUIKitCommands()` 或 `registerDiagnosticsCommands()`；
- HTTP transport、MCP image content、CLI stdout；
- 每一条动态错误 message 或调试建议。

### HostOperationSpec

描述 Mac 侧 host runtime 和 Workflow 层对外提供的操作。它可以拥有自己的输入字段，因为这些字段不是 App action 的字段。

应纳入的操作包括：

- `call_action`：调用任意 App action 的通用入口；host runtime 内部方法可命名为 `invoke`，不要求改动现有外部工具名；
- `health` / `capabilities`：连接、协议和运行时能力探测；
- `wait_and_inspect`；
- `tap_and_inspect`；
- 后续确定需要跨 action 编排的工作流。

`init`、`doctor`、`mcp` 是 CLI 生命周期和配置命令，不属于 DeviceActionContract，也不必强行放进 HostOperationSpec。`doctor` 可以调用 host runtime 的 probe，但环境检查和输出格式属于 CLI 诊断层。

### 不建立 AdapterContract 事实源

MCP tool 名和 CLI 子命令名是外部兼容接口，但不需要第三份业务 manifest：

- MCP adapter 保留显式的 tool mapping，并用 `tools/list` 快照测试固定名称和 schema；
- CLI adapter 保留显式的命令 mapping，并用 JSON 输出/exit code 测试固定行为；
- adapter 不复制 App action 的字段、默认值和业务 handler；
- 组合工作流的字段由 `HostOperationSpec` 定义，adapter 只做投影和渲染。

这样既能保持 `ui_topViewHierarchy` 等历史工具名稳定，也不会把展示命名规则误当成协议事实源。

## Schema 事实源与生成边界

合同应作为跨语言 wire schema 的唯一事实源：

```text
contracts/
  -> 生成 Swift ActionSpec / 基础 validator / help metadata
  -> 生成 TypeScript MCP schema / CLI 校验
  -> 生成协议文档片段
```

生成范围必须明确：

1. 字段类型、必填、默认值、范围和结构由合同生成。
2. Swift typed parser 仍负责 UIKit 相关类型转换和复杂语义，例如条件数组、日期解析、跨字段互斥；这些实现必须通过合同测试证明符合 schema。
3. JSON Schema 能表达的互斥关系应写进合同；不能可靠表达的规则必须在 Swift parser 中校验，并在合同中留下稳定的语义说明或测试样例。
4. 不把 `CommandInputSchema` 原样当成所有宿主的公共 DSL。它是 Swift 侧实现合同的投影；生成器输出的是跨语言 JSON Schema 和 metadata。
5. MCP 客户端对 JSON Schema 方言支持不一致时，adapter 可以做兼容性投影，但不能改变字段语义、默认值或错误含义。

生成结果不应依赖运行中的 App。App 不在线时，MCP 仍必须能启动并返回完整静态工具列表。

## App device runtime

App 内的 Swift runtime 继续负责：

- `Command` 注册和 action 路由；
- typed input 解析与运行时安全校验；
- UIKit、Diagnostics 和宿主自定义 action 的执行；
- `ExploreResult` envelope；
- `help` 运行时注册表；
- 命令级 timeout、日志和资源限制。

`help` 不再是静态事实源，而是运行时观测结果。建议增加：

```json
{
  "protocolVersion": "1",
  "contractVersion": "2026-07-24",
  "contractHash": "...",
  "commands": []
}
```

`commands` 仍只列出当前实际注册的 action。宿主可以注册扩展 action，但扩展 action 必须携带自己的 metadata；未纳入公共合同的扩展 action 不自动生成 MCP 工具，只通过通用 `call_action` 调用。

## Host runtime 与 Workflow 层

Host runtime 应保持小而深的接口，隐藏 HTTP、超时、错误和 artifact 细节：

```text
ActionTransport
  -> HTTP 实现 / 测试 fake

DriverRuntime
  -> invoke(action, data)
  -> probe()
  -> capabilities()
  -> error normalization
  -> artifact decoding

WorkflowRunner
  -> wait_and_inspect
  -> tap_and_inspect
```

具体规则：

- `ActionTransport` 可注入，host runtime 单测不需要真实 App。
- Host runtime 保留 App envelope、HTTP status 和 transport source，不把所有错误压成一个字符串。
- `ui.screenshot` 在 host runtime 内转成内部 image artifact；MCP 转成 image content，CLI 转成文件或 JSON，不让 App 协议依赖 MCP 类型。
- 当前协议只有 JSON envelope 和 base64 PNG；`file` artifact 应作为后续传输能力，不应在没有协议支持时提前宣称已实现。
- `wait_and_inspect`、`tap_and_inspect` 的等待、失败后是否继续、inspect 参数和 timing 都属于 WorkflowRunner，不属于 MCP server。
- host runtime 不负责启动或管理 `iproxy`；`doctor` 可以诊断端口和代理，设备启动仍由外部设备管理工具负责。

## 错误、超时和重试

Host 错误应保持分层：

```text
configuration | transport | http | protocol | appEnvelope | workflow
```

App action 的稳定业务错误码属于 `DeviceActionContract`；配置、网络、HTTP、MCP 和工作流错误属于 host 层。MCP 的 `isError`、CLI exit code 和 `nextSteps` 是各 adapter 的呈现策略。

合同必须区分：

- App 命令执行 timeout；
- Host HTTP 请求 timeout；
- `ui.wait` / `ui.waitAny` 的业务 deadline；
- MCP 或 CLI 调用 timeout。

副作用 action 默认禁止自动重试。合同应至少声明 `readOnly`、`idempotent`、`sideEffecting` 三种幂等级别，host runtime 只对明确安全的 action 做 transport-only retry。

## 能力探测与兼容性

MCP 工具列表始终来自构建时合同和 HostOperationSpec，不依赖 App 是否在线。运行时能力通过 `help`、`ping` 和 capability probe 判断：

- `health`：检查端点可达、响应可解析和基础协议是否正常；
- `capabilities`：检查实际注册 action、模块状态、contract version/hash 和 schema 兼容性；
- App 不可达时不伪造“缺少 action”，应返回 `unknown` 和连接诊断。

兼容性检查不能只比较属性名。建议区分：

- action 缺失：不可用；
- 必填字段、enum 或范围收窄：破坏性变更；
- 新增可选字段：兼容；
- hash 不同：报告具体差异和版本，而不是直接隐藏工具。

## CLI 入口

稳定命令入口建议为：

```bash
iosdriver init
iosdriver doctor
iosdriver call <action> --data '{}'
iosdriver mcp
```

职责划分：

- `init`：初始化或更新本地配置，生成 MCP 配置片段；不得覆盖用户已有配置。
- `doctor`：调用 host probe，检查 Node、配置、端点、端口代理、ping、help 和合同兼容性。
- `call`：调用任意 action；默认提供稳定 JSON 输出，可支持 `--data @file`，不复制 per-action handler。
- `mcp`：启动 stdio MCP adapter。stdout 只能输出 MCP 协议帧，日志必须写 stderr。

CLI 还需要单独定义配置文件路径、权限、安装方式、JSON/人类可读输出和 exit code。仅把 `dist/index.js` 包成 `iosdriver` 命令不能解决分发问题，npm 全局安装、`npx` 或其他安装方式必须在实现文档中明确。

## 迁移顺序

1. 定义 `DriverContractBundle`，先覆盖稳定公共 action 和现有 host 工作流。
2. 为合同增加版本、hash、模块、稳定级别、结果/artifact 和幂等/重试 metadata。
3. 生成 Swift metadata、TypeScript schema 和基础 CLI 校验；保留复杂 Swift parser，并增加合同测试。
4. 在 App `help` 中返回 protocol/contract version、hash 和当前注册表。
5. 抽出可注入 `ActionTransport` 和 `DriverRuntime`，统一 transport、timeout、error、artifact 处理。
6. 将 `wait_and_inspect`、`tap_and_inspect` 移入独立 WorkflowRunner，并为它们定义 `HostOperationSpec`。
7. 将 MCP 改成静态合同投影，只保留 `tools/list`、`tools/call` 和 MCP 内容渲染。
8. 新增 CLI adapter，实现 `init`、`doctor`、`call`、`mcp`。
9. 将协议 schema 文档和稳定参数片段改为生成内容；skills 继续手写工作流策略、调用顺序和失败分诊，不把 skills 变成事实源。

## 必须具备的验证

- Swift parser 与合同 schema 的正向/反向样例测试；
- 生成的 Swift、TypeScript schema 与 `help` metadata 的合同测试；
- App 不在线时 MCP `tools/list` 的稳定性测试；
- App 版本和 host 版本的兼容性矩阵测试；
- Host runtime 使用 fake transport 的 timeout、HTTP、App envelope、重试和 artifact 测试；
- WorkflowRunner 对 wait timeout、tap 失败和 inspect 失败的终态测试；
- CLI JSON stdout、stderr、exit code、配置初始化幂等性测试；
- 真实 App 端到端验证 `ping`、`help`、截图和至少一个 UIKit action。

## 最终决策

采用：

```text
DeviceActionContract
HostOperationSpec
  -> App device runtime
  -> Host runtime
  -> Workflow layer
      -> MCP adapter
      -> CLI adapter
```

不采用：

```text
一个总 manifest
一个包揽 UI / logs / workflow / doctor 的 DriverRuntime
动态 help 驱动的 MCP tools/list
adapter 自己维护 action schema 和业务 handler
```

这个结构同时保留了静态 MCP 工具发现、CLI 的可调试性、App 运行时能力探测和宿主组合能力，并把协议漂移、HostRuntime 过宽和 adapter 业务化控制在明确的模块内。
