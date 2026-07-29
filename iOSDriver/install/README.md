# iOSDriver 安装总览

iOSDriver 包含两个本地入口：

| 入口 | 用途 | 命令 |
| --- | --- | --- |
| CLI | 给开发者和脚本直接调用 App action。 | `iosdriver init|doctor|call` |
| MCP | 给 Codex、Claude Code、TRAE Work 等 MCP 客户端暴露工具。 | `iosdriver mcp` |
| MCP setup | 把 iOSDriver 注册到指定 MCP 客户端。 | `iosdriver mcp setup <client>` |

本文说明通用安装方式；具体客户端配置见同目录的客户端文档。
CLI 的完整行为说明见 [CLI 命令参考](../docs/cli-reference.md)。

## 前提

- Node.js 20 或更高版本。
- Debug App 已接入并启动 `ExploreServer`。
- App 侧按需调用 `registerUIKitCommands()` 和 `registerDiagnosticsCommands()`。
- 模拟器可直接访问 `http://localhost:38321/`。
- 真机需要先运行 `iproxy 38321 38321`。

## 从当前仓库本地使用

```bash
cd <repo>/iOSDriver
npm install
npm run build
```

源码构建后的 CLI 入口：

```bash
node <repo>/iOSDriver/dist/adapters/cli/main.js doctor
node <repo>/iOSDriver/dist/adapters/cli/main.js call ping
node <repo>/iOSDriver/dist/adapters/cli/main.js mcp
```

如果想在本机暴露 `iosdriver` 命令：

```bash
cd <repo>/iOSDriver
npm link
iosdriver doctor
iosdriver mcp setup codex --dry-run
```

不用全局 link 时，可以直接从构建产物运行 CLI：

```bash
node <repo>/iOSDriver/dist/adapters/cli/main.js doctor
```

## CLI 配置

初始化配置：

```bash
iosdriver init
```

配置优先级：

```text
CLI 参数 > 环境变量 > 配置文件 > 默认值
```

常用环境变量：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `IOS_EXPLORE_BASE_URL` | `http://localhost:38321/` | App HTTP endpoint。 |
| `IOS_EXPLORE_REQUEST_TIMEOUT_MS` | `10000` | 请求超时，单位 ms。 |
| `IOS_EXPLORE_AUTH_TOKEN` | - | 预留 token；host 可发送 header，但当前 App 明确不校验。 |
| `IOSDRIVER_CONFIG` | - | 显式配置文件路径。 |

默认配置文件路径是 `$XDG_CONFIG_HOME/iosdriver/config.json` 或 `~/.config/iosdriver/config.json`。配置文件也可保留 `authToken`；环境变量中的 token 不会由 `iosdriver init` 写入文件。当前 App 端忽略该 token，它不提供访问控制。

## 常用 CLI 命令

```bash
iosdriver doctor
iosdriver call ping
iosdriver call ui.inspect --data '{"mode":"minimal"}'
iosdriver call ui.screenshot --output screenshot.png
```

也可以在未 link 的情况下使用源码构建产物：

```bash
node <repo>/iOSDriver/dist/adapters/cli/main.js doctor
```

## MCP 配置原则

setup 会登记当前 Node、CLI 入口和 iOSDriver 配置文件的绝对路径：

```bash
iosdriver mcp setup codex
iosdriver mcp setup claude --scope project --project-dir <repo>
iosdriver mcp setup trae --project-dir <repo>
```

从源码构建但没有 link 时，也可以执行：

```bash
node <repo>/iOSDriver/dist/adapters/cli/main.js mcp setup codex
```

先使用 `--dry-run` 检查计划；同名配置不同时使用 `--force` 更新。project scope 以 `--project-dir` 为根，不能误指向 `<repo>/iOSDriver`。

客户端支持范围：

| client | 默认 scope | 可选 scope |
| --- | --- | --- |
| Codex | `user` | `user` |
| Claude Code | `project` | `user`、`project` |
| TRAE Work | `project` | `project` |

MCP 客户端应启动 stdio 进程：

```bash
iosdriver mcp
```

或者使用当前仓库构建产物：

```bash
node <repo>/iOSDriver/dist/adapters/cli/main.js mcp
```

MCP 进程 stdout 只写协议帧，日志写 stderr。修改 `iOSDriver/src` 后必须重新 `npm run build`，并重启 MCP 客户端或重连 MCP server。

## 客户端文档

- [Codex](local-install-codex.md)
- [Claude Code](local-install-claude.md)
- [TRAE Work](local-install-trae-work.md)

## 验证顺序

```bash
curl -s -X POST http://localhost:38321/ -d '{"action":"ping"}'
iosdriver doctor
iosdriver call ping
```

如果是 MCP 客户端，再调用 `health_check`。`health_check` 成功但某个 `ui.*` 工具返回 `unknown_action`，通常说明 App 侧没有注册 UIKit 命令。
