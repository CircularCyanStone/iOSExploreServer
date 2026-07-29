# iOSDriver

Mac 侧 iOSExplore host。它读取仓库根 `contracts/` 生成的合同，提供两类入口：

- CLI：`iosdriver init|doctor|call|mcp`
- MCP：`iosdriver mcp`
- MCP 客户端注册：`iosdriver mcp setup <codex|claude|trae>`

CLI 与 MCP 共用同一套 host runtime、workflow 和错误归一化逻辑。MCP 工具列表是静态合同投影，不从 App `help` 动态生成；`help` 只用于运行时能力检查。

## 前提

- Node.js 20 或更高版本。
- Debug App 已启动并监听 `38321`。
- 模拟器：Mac 可直接访问 `http://localhost:38321/`。
- 真机：先运行 `iproxy 38321 38321`，并确认 `lsof -iTCP:38321 -sTCP:LISTEN` 的 COMMAND 是 `iproxy`。

## 本地开发

```bash
cd iOSDriver
npm install
npm run build
```

常用命令：

```bash
node dist/adapters/cli/main.js doctor
node dist/adapters/cli/main.js call ping
node dist/adapters/cli/main.js call ui.inspect --data '{"mode":"minimal"}'
node dist/adapters/cli/main.js mcp
```

如果通过 npm 安装或 link 后暴露了 bin，可直接使用：

```bash
iosdriver doctor
iosdriver call ping
iosdriver mcp
```

## CLI

| 命令 | 职责 |
| --- | --- |
| `iosdriver init` | 初始化或更新本机配置文件，保留未知字段和已有值。 |
| `iosdriver doctor` | 检查 Node、配置、端点、`ping`、`help` 和合同兼容性。 |
| `iosdriver call <action>` | 调用任意 App action，支持 `--data JSON`、`--data @file` 和截图 `--output <path>`。 |
| `iosdriver mcp` | 启动 stdio MCP adapter。stdout 只输出 MCP 协议帧，日志写 stderr。 |
| `iosdriver mcp setup <client>` | 把绝对启动命令注册到 Codex、Claude Code 或 TRAE；不连接 App。 |

通用参数：

- `--base-url <url>`
- `--timeout <ms>`
- `--config <path>`

配置优先级：命令行参数 > 环境变量 > 配置文件 > 默认值。

MCP setup 参数：

- `--scope user|project`：Codex 仅支持 user，Claude Code 支持 user/project，TRAE 仅支持 project；
- `--project-dir <path>`：project scope 的项目根，默认当前目录；
- `--dry-run`：只输出新增或更新计划；
- `--force`：替换已有的同名不同配置；
- `--config <path>`：注册时显式交给 `iosdriver mcp` 的 App 配置文件。

环境变量：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `IOS_EXPLORE_BASE_URL` | `http://localhost:38321/` | App HTTP endpoint。 |
| `IOS_EXPLORE_REQUEST_TIMEOUT_MS` | `10000` | 普通请求超时。 |
| `IOS_EXPLORE_AUTH_TOKEN` | - | 预留 token；host 可发送 header，但当前 App 明确不校验。 |
| `IOSDRIVER_CONFIG` | - | 显式配置文件路径。 |

默认配置路径：`$XDG_CONFIG_HOME/iosdriver/config.json` 或 `~/.config/iosdriver/config.json`。配置文件也可保留 `authToken`；`iosdriver init` 不会把环境变量中的 token 写入文件。当前 App 端忽略该 token，它不提供访问控制。

退出码：

| code | 含义 |
| ---: | --- |
| `0` | 成功 |
| `1` | App 业务、workflow 或合同不兼容失败 |
| `2` | 配置、参数或 Node 版本错误 |
| `3` | transport、HTTP、protocol 或 artifact 失败 |

## MCP

先初始化并检查 App 连接配置：

```bash
iosdriver init
iosdriver doctor
```

再注册 MCP 客户端：

```bash
iosdriver mcp setup codex --dry-run
iosdriver mcp setup codex
iosdriver mcp setup claude --scope project --project-dir <project-root>
iosdriver mcp setup trae --project-dir <project-root>
```

setup 使用当前 Node 和 CLI 入口的绝对路径，保留客户端中的其他 MCP server。相同配置重复执行返回 `unchanged`；同名配置不同则需要 `--force`。

本地 MCP 客户端应启动：

```bash
iosdriver mcp
```

开发当前仓库时也可以配置为：

```bash
node <repo>/iOSDriver/dist/adapters/cli/main.js mcp
```

修改 `src/` 后必须重新 `npm run build` 并重启 MCP 客户端。已运行的 stdio 子进程不会自动加载新的 `dist`。

本地 CLI 安装、MCP 客户端配置和更新流程见 [install/](install/)。

## 合同与生成

合同事实源在仓库根 `contracts/`。生成产物包括：

- `iOSDriver/src/generated/*.ts`
- `Sources/iOSExploreServer/Generated/*.swift` 或相关 Swift metadata 输出
- `docs/generated/contracts.md`

合同变更后运行：

```bash
npm run contracts:generate
npm run contracts:check
```

不要手写修改 generated 文件。

## 测试

```bash
npm run typecheck
npm test
```

`npm test` 会先 build，再运行 vitest。真实 App 端到端 smoke 可用：

```bash
npm run build
node scripts/mcp-inspector.mjs
```

更多说明见 [docs/README.md](docs/README.md)。
