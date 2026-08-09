# iOSDriver MCP 与 CLI 设计决策

> 状态：已实施。本文记录 iOSDriver 的对外入口、MCP 启动方式和客户端注册规则。

## 1. 对外模型

iOSDriver 是一个提供 CLI 的 MCP Server Host：

- npm 包名是 `ios-explore-mcp-server`；它只用于安装和发布；
- 唯一用户命令是 `iosdriver`；
- MCP 客户端启动 `iosdriver mcp`；
- 开发者和脚本使用 `iosdriver init|doctor|call`；
- MCP 客户端注册使用 `iosdriver mcp setup <client>`。

项目不提供 Node.js library interface。`package.json` 不声明 `main`，并用空 `exports` 阻止包名导入。源码中的 runtime、workflow 和 adapter 是内部模块，不承诺 npm import 稳定性。

## 2. 运行结构

```text
Codex / Claude Code / TRAE
        │ MCP stdio
        ▼
iOSDriver MCP adapter
iosdriver mcp
        │
        ├── device action ────────┐
        ├── capability probe ─────┤ HTTP POST /
        └── host workflow ────────┘（可能调用多个 action）
                                  ▼
                         App 内 ExploreServer
```

MCP adapter 的工具列表是静态合同投影。工具调用可能：

- 通过 `DriverRuntime` 调用一个 App action；
- 通过 `CapabilityProbe` 执行 `ping`、`help` 等能力检查；
- 通过 `WorkflowRunner` 在一个总 deadline 内执行多个 action。

因此 MCP 工具与 App action 不是全部一对一映射。

## 3. `iosdriver mcp`

`iosdriver mcp` 是供 MCP Client 启动的 stdio Server 入口，不监听 MCP HTTP 端口，也不主动寻找 IDE。

启动链为：

```text
解析 CLI 参数
  -> 读取 iOSDriver App 配置
  -> 创建 HTTP transport、DriverRuntime、CapabilityProbe、WorkflowRunner
  -> 创建 MCP Server
  -> 连接 StdioServerTransport
```

MCP 握手中的 server name 固定为 `iOSDriver`，version 来自 `package.json`，不能在 adapter 中手写另一份版本。

## 4. `iosdriver mcp setup`

命令形式：

```bash
iosdriver mcp setup codex
iosdriver mcp setup claude
iosdriver mcp setup trae
```

通用参数：

```text
--scope local|user|project
--project-dir <path>
--config <iosdriver-config-path>
--dry-run
--force
```

客户端能力：

| client | 默认 scope | 支持的 scope | 注册实现 |
| --- | --- | --- | --- |
| Codex | `user` | `user` | 调用 `codex mcp get/add` |
| Claude Code | `local` | `local`、`user`、`project` | 调用 `claude mcp get/add/remove` |
| TRAE | `project` | `project` | 原子更新 `.trae/mcp.json` |

`--project-dir` 默认为当前工作目录。Claude Code 的 `local` scope 是当前项目的个人配置，
`project` scope 以该目录为团队项目根；TRAE 的 project scope 也以该目录为项目根。从仓库的
`iOSDriver/` 子目录执行时，应传 `--project-dir ..` 或先回到仓库根。

### 注册内容

setup 默认写入确定的绝对启动链：

```json
{
  "command": "/absolute/path/to/node",
  "args": [
    "/absolute/path/to/dist/adapters/cli/main.js",
    "mcp",
    "--config",
    "/absolute/path/to/iosdriver/config.json"
  ]
}
```

不依赖 GUI 客户端是否继承终端 PATH，也不通过 `bash -lc` 拼接命令。Claude 和 Codex 的
官方 CLI 接收数组形式的参数；stdio 命令在客户端选项后使用 `--`，保证 `mcp --config` 等
子进程参数不被客户端解析。移动源码目录、Node 安装目录或全局 npm 安装位置后，需要重新执行 setup。

### 幂等与冲突

- 不存在 `iOSDriver` 时调用客户端官方 add；
- 已有配置与目标完全相同时返回 `unchanged`，不执行 add/remove；
- 已有同名但内容不同时默认失败；
- `--force` 是 iOSDriver 的包装选项：Codex 直接调用 add 覆盖，Claude 调用 remove 后 add；
- `--dry-run` 返回 `create` 或 `update` 计划，不执行修改；
- TRAE JSON 文件通过同目录临时文件加 rename 原子更新，Claude force 更新不保证原子性。

## 5. setup 与 App runtime 分离

CLI 必须先把 argv 解析为两类命令：

```text
mcp setup
  -> setupMCPClient
  -> Codex command adapter / Claude command adapter / TRAE JSON adapter

init / doctor / call / mcp
  -> resolveCLIConfig
  -> DriverRuntime / CapabilityProbe / WorkflowRunner
```

`mcp setup` 只计算并登记 App 配置文件路径，不读取该文件内容，也不创建 HTTP transport。即使 App 未启动或配置文件尚不存在，客户端注册仍可完成。

## 6. `init` 与 `setup` 的职责

`iosdriver init` 管理 iOSDriver 自己的 App 连接配置：

```text
$XDG_CONFIG_HOME/iosdriver/config.json
或 ~/.config/iosdriver/config.json
```

`iosdriver mcp setup` 管理外部 MCP Client 如何启动 iOSDriver。它在启动参数中显式传入上述配置文件路径，不把 `baseURL`、timeout 或 token 复制到客户端配置。

推荐顺序：

```bash
iosdriver init
iosdriver doctor
iosdriver mcp setup codex --dry-run
iosdriver mcp setup codex
```

## 7. 不负责的行为

- setup 不启动 iOS App；
- setup 和 `iosdriver mcp` 都不启动 `iproxy`；
- setup 不验证 App action 是否已注册；
- `iosdriver mcp` 不修改 MCP Client 配置；
- MCP Client 仍负责启动、停止和重启 stdio 子进程。

App 连接与合同一致性由 `iosdriver doctor` 检查；MCP 注册结果由对应客户端的 MCP 管理命令或界面检查。
