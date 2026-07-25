# iOSDriver 本地安装与更新（Claude Code）

本文用于把当前仓库里的 iOSDriver 注册到 Claude Code。它面向本地开发和验证，不是 npm 发布说明。

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

`<repo>` 替换为当前仓库绝对路径。

配置优先级：CLI 参数 > 环境变量 > 配置文件 > 默认值。默认配置文件是 `~/.config/iosdriver/config.json`；可用 `IOSDRIVER_CONFIG` 或 `--config` 指定。

## 项目级配置

如果已经 `npm link`，可以在当前项目的 `.mcp.json` 中添加或更新 `iOSDriver`：

```json
{
  "mcpServers": {
    "iOSDriver": {
      "command": "iosdriver",
      "args": ["mcp"],
      "env": {
        "IOS_EXPLORE_BASE_URL": "http://localhost:38321",
        "IOS_EXPLORE_REQUEST_TIMEOUT_MS": "10000"
      }
    }
  }
}
```

未 link 时，使用当前仓库构建产物的绝对路径。保留其他 MCP 服务：

```json
{
  "mcpServers": {
    "iOSDriver": {
      "command": "node",
      "args": [
        "<repo>/iOSDriver/dist/adapters/cli/main.js",
        "mcp"
      ],
      "env": {
        "IOS_EXPLORE_BASE_URL": "http://localhost:38321",
        "IOS_EXPLORE_REQUEST_TIMEOUT_MS": "10000"
      }
    }
  }
}
```

只保留一个名为 `iOSDriver` 的配置；如果已有其他 server，不要覆盖整个 `mcpServers` 对象。

也可以用命令注册。已 link 时：

```bash
claude mcp add \
  --transport stdio \
  --scope local \
  iOSDriver \
  -e IOS_EXPLORE_BASE_URL=http://localhost:38321 \
  -e IOS_EXPLORE_REQUEST_TIMEOUT_MS=10000 \
  -- iosdriver mcp
```

未 link 时：

```bash
claude mcp add \
  --transport stdio \
  --scope local \
  iOSDriver \
  -e IOS_EXPLORE_BASE_URL=http://localhost:38321 \
  -e IOS_EXPLORE_REQUEST_TIMEOUT_MS=10000 \
  -- node <repo>/iOSDriver/dist/adapters/cli/main.js mcp
```

## 验证

```bash
curl -s -X POST http://localhost:38321/ -d '{"action":"ping"}'
```

真机需要先启动 `iproxy 38321 38321`，并确认 `lsof -iTCP:38321 -sTCP:LISTEN` 的 COMMAND 是 `iproxy`。

重启 Claude Code 后执行 `/mcp`，确认 `iOSDriver` 已连接；调用 `health_check` 可以验证 iOSDriver 到 App HTTP 服务的连接。

如果 `health_check` 可达但 `ui.*` 工具返回 `unknown_action`，检查 App 是否调用了 `registerUIKitCommands()`。

## 更新

```bash
cd <repo>/iOSDriver
npm run build
```

编译后需要重启 Claude Code。重新编译不会重启已有 stdio MCP 子进程。

## 常见问题

- `Cannot find module`：检查 `<repo>` 路径和 `dist/adapters/cli/main.js` 是否存在。
- `/mcp` 中仍是旧工具：完全退出并重启 Claude Code。
- `health_check` 连接失败：先 curl `ping`；真机检查 `iproxy`。
- JSON 配置解析失败：检查逗号、引号和是否重复配置 `iOSDriver`。
