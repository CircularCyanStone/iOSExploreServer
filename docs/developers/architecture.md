# 项目整体架构设计

本文面向项目维护者和开发者，解释大重构后每一层负责什么、不负责什么，以及请求从 Mac 到 App 再返回的完整路径。Agent 修改规则放在根目录 `AGENTS.md`；本文只讲当前系统怎么组成、怎么扩展、边界在哪里。

## 一句话模型

iOSExploreServer 是一个 Debug-only 的 App 内 HTTP 自动化库；iOSDriver 是 Mac 侧 host，把同一套合同投影成 CLI 和 MCP 工具。

```text
Mac
  CLI / MCP
    -> iOSDriver adapter
      -> iOSDriver runtime / workflow
        -> HTTP POST /
          -> ExploreServer router
            -> Core / UIKit / Diagnostics command
              -> App runtime state
```

整套系统只有一个 App 端 HTTP endpoint：`POST /`。所有能力都通过 body 里的 `action` 区分，不新增 `/tap`、`/inspect`、`/logs` 这类路径。

## 顶层目录职责

| 目录 | 角色 | 主要内容 |
| --- | --- | --- |
| `Sources/iOSExploreServer/` | App 端 core | HTTP listener、request/response、router、envelope、内置 `ping`/`echo`/`info`/`help`。 |
| `Sources/iOSExploreUIKit/` | App 端 UIKit 扩展 | `ui.*` 命令、view 采集、locator、snapshot、控件执行器、alert/navigation/list/webview 等操作。 |
| `Sources/iOSExploreDiagnostics/` | App 端诊断扩展 | `app.logs.*`、进程内日志 store、宿主日志桥接、可选 stdout/stderr/NSLog/os_log 捕获。 |
| `Sources/CFishhook/` | C 辅助模块 | Diagnostics 捕获 NSLog 时使用的 fishhook 封装。 |
| `contracts/` | 协议事实源 | Device action、host operation、公共定义和错误索引的 JSON 合同。 |
| `iOSDriver/src/runtime/` | Mac 侧运行时 | HTTP transport、timeout、重试、envelope 校验、错误归一化、artifact 解码。 |
| `iOSDriver/src/workflows/` | Mac 侧复合操作 | `wait_and_inspect`、`tap_and_inspect` 等跨多个 device action 的工作流。 |
| `iOSDriver/src/adapters/cli/` | CLI adapter | `iosdriver init|doctor|call|mcp` 的参数、配置、输出和退出码。 |
| `iOSDriver/src/adapters/mcp/` | MCP adapter | 静态 tools/list、tools/call 映射、MCP 内容渲染。 |
| `iOSDriver/src/contracts/generator/` | 合同生成器 | 从 `contracts/` 生成 Swift metadata、TypeScript 合同和 Markdown 文档。 |
| `docs/generated/` | 生成文档 | `contracts.md`，不要手写修改。 |
| `docs/developers/` | 人类开发者文档 | 接入、架构、安装、排障入口。 |
| `docs/agents/` | Agent 文档 | 给自动化 agent 的修改路径和约束。 |

## Swift Package 分层

`Package.swift` 暴露三个 Swift library product：

| Product | Target | 用途 |
| --- | --- | --- |
| `iOSExploreServer` | `iOSExploreServer` | Core HTTP 自动化服务。 |
| `iOSExploreUIKit` | `iOSExploreUIKit` | UIKit 命令扩展，依赖 core。 |
| `iOSExploreDiagnostics` | `iOSExploreDiagnostics` | 日志诊断扩展，依赖 core 和 `CFishhook`。 |

`iOSExploreServer` 不依赖 UIKit。它可以在没有 UIKit 命令的情况下独立启动，只提供 core actions。UIKit 相关对象、UIView 树、UIAlertController、WKWebView 等只出现在 `iOSExploreUIKit`。

## App 端启动与注册

宿主 App 在 Debug 构建中显式创建 server，并按需注册扩展模块：

```swift
#if DEBUG
import iOSExploreServer
import iOSExploreUIKit
import iOSExploreDiagnostics

let server = ExploreServer()
server.registerUIKitCommands()
server.registerDiagnosticsCommands()

Task {
    try? await server.start()
}
#endif
```

注册规则：

| 调用 | 注册内容 | 不调用时的行为 |
| --- | --- | --- |
| `ExploreServer()` | 自动注册 `ping`、`echo`、`info`、`help` | core actions 始终存在。 |
| `server.registerUIKitCommands()` | 注册 21 个 `ui.*` action | `help` 不包含 `ui.*`，调用返回 `unknown_action`。 |
| `server.registerDiagnosticsCommands()` | Debug 下注册 `app.logs.mark/read` 并安装 diagnostics runtime | `help` 不包含 `app.logs.*`，日志读取不可用。 |

这个设计让 core 保持轻量，也让宿主可以只接入需要的 Debug 能力。

## App 端请求链路

```text
HTTPListener
  -> ClientSession
    -> HTTPParser
      -> ExploreRequest(action, data)
        -> Router.route
          -> AnyCommand
            -> CommandInput.parse
              -> Command.handle
                -> ExploreResult
                  -> HTTPResponse
```

各层边界：

| 层 | 负责 | 不负责 |
| --- | --- | --- |
| `HTTPListener` | 监听端口、接收连接、管理 session 生命周期。 | 不理解业务 action。 |
| `ClientSession` | 读取请求、套用 parse/command timeout、写回 HTTP 响应。 | 不实现命令行为。 |
| `HTTPParser` | 解析 HTTP method/path/body，得到 `ExploreRequest`。 | 不校验某个 action 的业务字段。 |
| `Router` | 维护 `action -> command` 表，按 action 分发。 | 不直接访问 UIKit，不持锁执行 async handler。 |
| `AnyCommand` / `Command` | typed input 解析、handler 执行、业务错误转 envelope。 | 不处理 TCP/HTTP 传输问题。 |
| `HTTPResponse` | 把 envelope 编码成 HTTP body，处理 body size 上限。 | 不改变业务 code。 |

通信失败和业务失败分开：

| 类型 | 例子 | 响应形态 |
| --- | --- | --- |
| 通信/协议层失败 | 非 `POST /`、body 不是合法 JSON、请求过大、server 内部错误 | HTTP 400/500。 |
| action 业务失败 | `unknown_action`、locator 找不到、alert 不存在、wait 超时 | HTTP 200 + `{"code":"...","message":"..."}`。 |
| 成功 | `ping`、`ui.inspect`、`app.logs.read` 成功 | HTTP 200 + `{"code":"ok","data":...}`。 |

## Command 与输入模型

每个 App action 都应该有一个 `Command` 或等价注册：

```text
Command
  action
  contract
  Input: CommandInput
  handle(input) async throws -> ExploreResult
```

输入边界的关键点是 `CommandInput`。UIKit 命令的入参先由 Foundation-only 的 input model 解析校验，再进入 UIKit executor。这样 public wire 边界不会暴露 UIKit 类型，也便于合同生成、测试和 host adapter 复用 schema。

## UIKit 模块边界

UIKit 模块分成四类代码：

| 子目录 | 职责 |
| --- | --- |
| `Commands/*` | 每个 `ui.*` action 的 command、input、response model。 |
| `Support/Context` | 获取当前 window、root/top controller、root view。 |
| `Support/Locator` | 用 `accessibilityIdentifier`、`path`、`viewSnapshotID` 定位 view。 |
| `Support/Snapshot` | 保存 inspect 的 target fingerprint 与 availableActions，用于动作授权和陈旧防护。 |
| `Support/Action` | tap、input、scroll、navigation、alert、picker、webview 等实际执行器。 |
| `Support/Runtime` | Debug runtime hook 或私有 target-action 读取辅助。 |

UIKit 的核心工作流通常是：

```text
ui.inspect
  -> 采集当前可见 view 树
  -> 为 full 节点签发 fingerprint + availableActions
  -> 返回文本、控件类型、path、identifier、frame、能力摘要

ui.tap / ui.input / ui.control.sendAction
  -> 解析 locator
  -> 验证目标为本次动作签发，且 viewSnapshotID 未过期、fingerprint 仍匹配
  -> 执行具体 UIKit 操作
  -> 返回 action 结果或业务错误
```

重要语义：

- `ui.inspect` 是主要发现入口；交互命令依赖它签发的 `viewSnapshotID`。
- `ui.topViewHierarchy` 是完整观察命令，不签发 `viewSnapshotID`。
- `ui.screenshot` 只返回 PNG artifact，不签发 `viewSnapshotID`。
- `path` 是当前 root view 树上的相对路径，UI 变化后可能失效。
- `accessibilityIdentifier` 优先用于稳定定位；没有 identifier 时才依赖 path。
- `ui.tap` 现在是“默认激活动作”，不是真实触摸注入。它按目标类型走 control、switch、input、gesture 等分支。
- action-aware snapshot 覆盖 `availableActions` 表达的通用 capability：`ui.tap`、携带 snapshot 的 `ui.input`、定向 `ui.scroll`、`ui.control.sendAction`。picker、datePicker、webView、swipe、longPress 是独立 typed executor 合同，snapshot 仅作可选 freshness guard；这不是延期项。`ui.wait(snapshotChanged)` 只读取 snapshot，不属于动作授权。
- 公开 Swift API `UIKitSnapshotStore.insert` 接收 `[String: UIKitSnapshotTarget]`。这是有意的 source-breaking 迁移：旧的 fingerprint-only 入参无法证明 inspect 当时授权了哪些动作，因此不保留兼容 overload。

## Diagnostics 模块边界

Diagnostics 的设计目标是读取当前 App 进程内的 Debug 日志，避免 agent 只能从 Xcode 控制台或系统噪音里猜。

```text
ESDiagnosticsRuntime
  -> ESAppLogStore
    -> app.logs.mark
    -> app.logs.read

Developer API
  -> ESAppLogger
  -> ESDiagnosticsConfiguration

Optional capture
  -> stdout/stderr
  -> NSLog via CFishhook
  -> os_log / Swift Logger bridge
```

边界：

- `ESAppLogger` 是宿主主动写入业务日志的推荐入口。
- stdout/stderr/NSLog/os_log 捕获默认不等于全部开启，需要宿主通过 `ESDiagnosticsConfiguration` 显式配置。
- Release 构建不应该安装 Debug 捕获路径。
- `app.logs.mark` 返回 cursor；`app.logs.read` 从 cursor 后读取增量。
- 捕获不可用时要返回状态或错误，不能把“捕获失败”伪装成“没有日志”。

## 合同层

`contracts/` 是 action 字段、默认值、错误码、幂等性和 timeout class 的事实源。

```text
contracts/
  bundle.json
  errors.json
  definitions/*.json
  device-actions/*.json
  host-operations/*.json
```

两类合同：

| 合同 | 运行位置 | 例子 |
| --- | --- | --- |
| Device action | App 内 `POST /` action | `ui.inspect`、`ui.tap`、`app.logs.read`、`ping` |
| Host operation | Mac 侧 iOSDriver 复合能力 | `health`、`capabilities`、`call_action`、`wait_and_inspect`、`tap_and_inspect` |

生成产物：

| 产物 | 用途 |
| --- | --- |
| `iOSDriver/src/generated/*.ts` | CLI/MCP/runtime 使用的合同常量。 |
| `Sources/*/Generated/*.swift` | Swift command metadata 和字段定义。 |
| `docs/generated/contracts.md` | 给人看的合同摘要。 |

合同变更流程：

```bash
cd iOSDriver
npm run contracts:generate
npm run contracts:check
```

不要在 README、skill 或 adapter 中手写复制完整 action 字段表。入口文档可以写示例，字段细节指向 generated 文档。

## iOSDriver Host 架构

iOSDriver 是 Mac 侧 Node.js 包。它不是 App server；它调用已经运行在 App 内的 `ExploreServer`。

```text
adapters/cli
  -> resolve config
  -> DriverRuntime
  -> output / exit code

adapters/mcp
  -> static tool catalog
  -> DriverRuntime / WorkflowRunner / CapabilityProbe
  -> MCP content result

runtime
  -> HttpActionTransport
  -> DriverRuntime
  -> CapabilityProbe
  -> ArtifactDecoder

workflows
  -> wait_and_inspect
  -> tap_and_inspect
```

### Runtime

`DriverRuntime.invoke(action, data)` 负责把一次 App action 调用变成稳定的 host 结果：

- 调用 `HttpActionTransport` 发送 `POST /`。
- 套用 request timeout。
- 根据 generated contract 读取 idempotency 和 timeout class。
- 对 readOnly/idempotent 且安全的 connect/reset 失败做有限重试。
- 校验 App envelope。
- 把 HTTP、transport、protocol、appEnvelope、artifact 错误归一化。
- 解码截图等 artifact，供 CLI `--output` 或 MCP 内容使用。

Runtime 不解析 CLI 参数，也不接触 MCP SDK。

### Workflows

`WorkflowRunner` 执行 host operation。它把多个 device action 串起来，并使用一个总 deadline 控制整条链路。

当前 workflow：

| Workflow | 做什么 |
| --- | --- |
| `wait_and_inspect` | 等待文本/目标/消失等条件后，立即执行一次 `ui.inspect`。 |
| `tap_and_inspect` | 执行 tap 后，按配置等待 UI 稳定，再执行 `ui.inspect`。 |

Workflow 返回形态与普通 action 一致，方便 CLI/MCP 统一渲染。

### CLI Adapter

CLI 入口是：

```bash
iosdriver init
iosdriver doctor
iosdriver call <action>
iosdriver mcp
```

本地源码构建入口是：

```bash
node iOSDriver/dist/adapters/cli/main.js <command>
```

CLI 只负责：

- 解析 `--base-url`、`--timeout`、`--config`、`--data`、`--output`。
- 读取环境变量和配置文件。
- 创建 runtime、capability probe、workflow runner。
- 把结果写到 stdout，把日志写到 stderr。
- 返回固定退出码。

CLI 不实现任何 App action，不维护工具列表。

### MCP Adapter

MCP 推荐启动方式是：

```bash
iosdriver mcp
```

源码构建入口是：

```bash
node iOSDriver/dist/adapters/cli/main.js mcp
```

MCP adapter 的工具列表是静态的，由 `TOOL_MAPPINGS` 加 generated contracts 构造。`tools/list` 不访问 App，也不依赖 `help`。`health_check`、`capabilities` 或具体工具调用时才访问 App。

这样做的原因是 MCP 客户端需要稳定工具 schema；如果工具列表跟随 App 当前注册状态动态变化，客户端缓存和 agent 规划都会变得不稳定。App 当前是否真的注册某个 action，由调用结果或 `health_check`/`capabilities` 报告表达。

## CLI、MCP、HTTP 的关系

三种入口调用的是同一个 App 协议：

| 入口 | 面向谁 | 调用路径 |
| --- | --- | --- |
| `curl POST /` | 最小调试 | 直接发 `{action,data}` 到 App。 |
| `iosdriver call` | 人类开发者、脚本 | CLI -> Runtime -> HTTP -> App。 |
| MCP 工具 | Agent/MCP 客户端 | MCP adapter -> Runtime/Workflow -> HTTP -> App。 |

当你怀疑问题出在哪一层，可以按这个顺序缩小范围：

1. `curl ping` 失败：App server、端口、iproxy 或网络问题。
2. `curl ping` 成功但 `iosdriver doctor` 失败：iOSDriver 配置、Node、合同兼容性或 host runtime 问题。
3. `iosdriver doctor` 成功但 MCP 工具失败：MCP 客户端配置、stdio 启动、工具参数或 workflow 问题。
4. `health_check` 显示缺少 `ui.*` 或 `app.logs.*`：App 未注册对应 Swift 扩展模块。

## 配置与端口

默认 App 端口是 `38321`。

模拟器：

```bash
curl -s -X POST http://localhost:38321/ -d '{"action":"ping"}'
```

真机：

```bash
iproxy 38321 38321
curl -s -X POST http://localhost:38321/ -d '{"action":"ping"}'
```

iOSDriver 配置优先级：

```text
CLI 参数 > 环境变量 > 配置文件 > 默认值
```

常用配置：

| 配置 | 默认值 | 来源 |
| --- | --- | --- |
| `baseURL` | `http://localhost:38321/` | `--base-url`、`IOS_EXPLORE_BASE_URL`、配置文件。 |
| `requestTimeoutMs` | `10000` | `--timeout`、`IOS_EXPLORE_REQUEST_TIMEOUT_MS`、配置文件。 |
| `authToken` | 未设置 | 预留配置；host 可从 `IOS_EXPLORE_AUTH_TOKEN` 或配置文件读取，但当前 App 产品开关关闭，不校验。 |
| config path | `~/.config/iosdriver/config.json` | `--config`、`IOSDRIVER_CONFIG`、`XDG_CONFIG_HOME`。 |

## 扩展一个新能力时改哪里

新增 App device action：

1. 在 `contracts/device-actions/` 新增或修改合同。
2. 运行 `cd iOSDriver && npm run contracts:generate`。
3. 在对应 Swift 模块实现 `CommandInput` 和 `Command`。
4. 在模块 registrar 中显式注册命令。
5. 添加 Swift 定向测试。
6. 运行 `cd iOSDriver && npm run contracts:check`，再跑相关 Swift/Node 测试。

新增 host workflow：

1. 在 `contracts/host-operations/` 增加 operation 合同。
2. 运行合同生成。
3. 在 `iOSDriver/src/workflows/` 实现 workflow。
4. 在 `WorkflowRunner` 中注册 operation。
5. 如需 MCP 暴露，在 `toolMappings.ts` 增加工具映射。
6. 添加 vitest 覆盖成功、失败和 timeout。

新增 CLI 行为：

1. 改 `iOSDriver/src/adapters/cli/main.ts` 的参数解析。
2. 改 `commands.ts` 的命令执行。
3. 保持 stdout 为业务输出，stderr 为日志/错误。
4. 补 `tests/adapters/cli/`。

新增 MCP 工具：

1. 先确认是 device action 还是 host operation。
2. 改 `iOSDriver/src/adapters/mcp/toolMappings.ts`。
3. 不从 App `help` 动态生成工具。
4. 补 `tests/adapters/mcp/`。

## 测试分层

| 测试类型 | 主要验证 |
| --- | --- |
| Swift core tests | HTTP、router、command、envelope、合同 metadata。 |
| Swift UIKit tests | locator、snapshot、inspect、tap、input、navigation、alert、wait 等 App 端行为。 |
| Swift Diagnostics tests | 日志 store、mark/read、捕获隔离和合同兼容。 |
| Node runtime tests | HTTP transport、timeout、错误归一化、artifact、capability probe。 |
| Node adapter tests | CLI 参数/输出/退出码，MCP tool catalog/result rendering。 |
| Node workflow tests | `wait_and_inspect`、`tap_and_inspect` 的跨 action 编排。 |

常用验证：

```bash
swift build
swift test

cd iOSDriver
npm run contracts:check
npm test
```

文档或安装说明只改文字时，优先做链接、路径和过期关键词检查，不需要跑完整 Swift/Node 测试。

## 相关深读

- 单次 action 从 agent 到 App 再返回的数据流：[action-flow.md](action-flow.md)

## 当前边界速查

- Core 不 import UIKit。
- App endpoint 固定 `POST /`。
- action 字段、默认值、错误码以 `contracts/` 为准。
- UIKit 和 Diagnostics 都是显式注册扩展。
- `viewSnapshotID` 只由 `ui.inspect` 签发；full 节点是否可执行某动作以同次响应的 `availableActions` 为准。
- CLI 和 MCP 共用 runtime/workflow，不各自实现协议逻辑。
- MCP tools/list 静态，不从 App help 动态生成。
- stdout 用于机器可读结果；stderr 用于 host 日志。
- Release 不默认暴露 Debug 自动化入口。
