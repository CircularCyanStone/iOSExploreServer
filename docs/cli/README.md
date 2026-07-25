# iOSDriver CLI / MCP 架构

本文记录当前 iOSDriver 的合同、runtime、workflow、CLI adapter 和 MCP adapter 边界。它是当前决策说明，不是迁移待办。

## 结论

```text
contracts/
  DeviceActionContract
  HostOperationSpec
      -> DriverRuntime
      -> WorkflowRunner
          -> CLI adapter
          -> MCP adapter
```

- `contracts/` 是跨语言 wire contract 的唯一事实源。
- `DriverRuntime` 负责 HTTP transport、timeout、错误归一化、capability probe 和 artifact 解码。
- `WorkflowRunner` 负责 `wait_and_inspect`、`tap_and_inspect` 等跨 action 编排。
- CLI 与 MCP 是平级 adapter，不复制 action schema 或 handler。
- App `help` 是运行时能力观测，不驱动 MCP `tools/list`。

## 合同

合同源位于仓库根 `contracts/`：

```text
contracts/
  definitions/
  device-actions/
  host-operations/
  bundle.json
  errors.json
```

生成摘要在 `docs/generated/contracts.md`。合同变更后：

```bash
cd iOSDriver
npm run contracts:generate
npm run contracts:check
```

不要手写 generated 文件，也不要在 README、skill 或 adapter 中复制长字段表。

## CLI adapter

入口：

```bash
iosdriver init
iosdriver doctor
iosdriver call <action> --data '{}'
iosdriver mcp
```

源码：

- `iOSDriver/src/adapters/cli/main.ts`
- `iOSDriver/src/adapters/cli/commands.ts`
- `iOSDriver/src/adapters/cli/config.ts`
- `iOSDriver/src/adapters/cli/output.ts`

职责：

- 解析命令行参数和配置。
- 输出 JSON / human 文本。
- 固定退出码。
- 启动 MCP stdio adapter。

不负责：

- 启动 App。
- 管理 `iproxy`。
- 复制 action handler。
- 动态生成业务 schema。

## MCP adapter

源码：

- `iOSDriver/src/adapters/mcp/toolMappings.ts`
- `iOSDriver/src/adapters/mcp/toolCatalog.ts`
- `iOSDriver/src/adapters/mcp/server.ts`
- `iOSDriver/src/adapters/mcp/resultRenderer.ts`

MCP 工具列表是静态合同投影。工具名到 device action / host operation 的映射由 `toolMappings.ts` 显式维护；description 与 input schema 来自 generated contract。App 离线时 MCP 仍可启动并返回完整工具列表，调用时再报告 transport 或 capability 问题。

`call_action` 是调用任意 App action 的通用入口。宿主私有、Debug 或实验 action 不自动进入 MCP 工具列表。

## Runtime 与 Workflow

`DriverRuntime` 使用可注入 transport 调用 App `POST /`，保留 transport、HTTP、protocol、App envelope 和 workflow 错误分层。副作用 action 不自动重试；只对合同标记为安全且尚未收到 App response 的连接阶段失败考虑 transport-only retry。

`WorkflowRunner` 组合多个 action，并保留每一步结果和 timing。adapter 只把 workflow 结果渲染成 CLI 输出或 MCP content。

## 配置与退出码

配置优先级：

```text
命令行参数 > 环境变量 > 配置文件 > 默认值
```

环境变量：

- `IOS_EXPLORE_BASE_URL`
- `IOS_EXPLORE_REQUEST_TIMEOUT_MS`
- `IOSDRIVER_CONFIG`

退出码：

| code | 含义 |
| ---: | --- |
| `0` | 成功 |
| `1` | App 业务、workflow 或合同不兼容失败 |
| `2` | 配置、参数或 Node 版本错误 |
| `3` | transport、HTTP、protocol 或 artifact 失败 |

## 验证

```bash
cd iOSDriver
npm run contracts:check
npm run typecheck
npm test
node scripts/mcp-inspector.mjs
```

`mcp-inspector.mjs` 需要真实 App HTTP 服务可达；单元测试不需要真 App。
