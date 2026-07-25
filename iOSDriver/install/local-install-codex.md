# iOSDriver 本地安装与更新（Codex）

本文用于把当前仓库里的 iOSDriver 注册到 Codex。它面向本地开发和验证，不是 npm 发布说明。

## 准备

```bash
cd <repo>/iOSDriver
npm install
npm run build
```

本地源码构建后的 CLI 入口：

```bash
node <repo>/iOSDriver/dist/adapters/cli/main.js init
node <repo>/iOSDriver/dist/adapters/cli/main.js doctor
node <repo>/iOSDriver/dist/adapters/cli/main.js call ping
```

如果希望直接使用 `iosdriver` 命令，可以在当前仓库 link：

```bash
cd <repo>/iOSDriver
npm link
iosdriver doctor
iosdriver call ping
```

MCP 推荐入口是同一个 CLI 的 `mcp` 子命令：

```bash
iosdriver mcp
node <repo>/iOSDriver/dist/adapters/cli/main.js mcp
```

`<repo>` 替换为当前仓库绝对路径。使用绝对路径可以避免 Codex 工作目录变化导致入口找不到。

配置优先级：CLI 参数 > 环境变量 > 配置文件 > 默认值。默认配置文件是 `~/.config/iosdriver/config.json`；可用 `IOSDRIVER_CONFIG` 或 `--config` 指定。

## 配置

如果已经 `npm link`，可以让 Codex 直接启动 `iosdriver mcp`：

```toml
[mcp_servers.iOSDriver]
command = "iosdriver"
args = ["mcp"]

[mcp_servers.iOSDriver.env]
IOS_EXPLORE_BASE_URL = "http://localhost:38321"
IOS_EXPLORE_REQUEST_TIMEOUT_MS = "10000"
```

未 link 时，编辑 `~/.codex/config.toml`，使用当前仓库构建产物的绝对路径：

```toml
[mcp_servers.iOSDriver]
command = "node"
args = ["<repo>/iOSDriver/dist/adapters/cli/main.js", "mcp"]

[mcp_servers.iOSDriver.env]
IOS_EXPLORE_BASE_URL = "http://localhost:38321"
IOS_EXPLORE_REQUEST_TIMEOUT_MS = "10000"
```

如果已经存在 `[mcp_servers.iOSDriver]`，只更新这一组，不要再添加第二组同名表。

也可以用命令注册。已 link 时：

```bash
codex mcp add iOSDriver \
  --env IOS_EXPLORE_BASE_URL=http://localhost:38321 \
  --env IOS_EXPLORE_REQUEST_TIMEOUT_MS=10000 \
  -- iosdriver mcp
```

未 link 时：

```bash
codex mcp add iOSDriver \
  --env IOS_EXPLORE_BASE_URL=http://localhost:38321 \
  --env IOS_EXPLORE_REQUEST_TIMEOUT_MS=10000 \
  -- node <repo>/iOSDriver/dist/adapters/cli/main.js mcp
```

## 验证

先确认 App HTTP 服务可达：

```bash
curl -s -X POST http://localhost:38321/ -d '{"action":"ping"}'
```

真机需要先启动 `iproxy 38321 38321`，并确认：

```bash
lsof -iTCP:38321 -sTCP:LISTEN
```

COMMAND 应为 `iproxy`。

重启 Codex 后检查：

```bash
codex mcp list
codex mcp get iOSDriver
```

再调用 MCP 工具 `health_check`。如果 `health_check` 可达但 `ui.*` 工具返回 `unknown_action`，检查 App 是否调用了 `registerUIKitCommands()`。

## 更新

修改 `iOSDriver/src` 后：

```bash
cd <repo>/iOSDriver
npm run build
```

已运行的 MCP 子进程不会自动加载新构建；需要完全退出并重启 Codex。

## 常见问题

- `Cannot find module`：检查 `<repo>` 是否是绝对路径，并重新 `npm run build`。
- 配置解析失败：检查 TOML 表名、引号和数组语法；同名表只能有一组。
- `unknown_action`：App 未注册对应模块或 action 名错误，先调用 `help` 检查。
- 连接失败：先 curl `ping`，真机再检查 `iproxy`。
