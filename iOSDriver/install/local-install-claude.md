# iOSDriver 本地安装与更新（Claude Code）

本文用于把当前仓库中的 iOSDriver 直接注册到 Claude Code，方便测试本地修改后的 MCP 服务代码。iOSDriver 是 Node.js/TypeScript 服务，不是 Swift Package；Claude Code 启动的是 `dist/index.js`。

## 固定本地入口

源码目录：

```text
/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/iOSDriver
```

MCP 配置固定指向：

```text
/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/iOSDriver/dist/index.js
```

使用绝对路径，避免 Claude Code 的工作目录变化导致入口找不到。

## 首次安装

要求 macOS、Node.js 20 或更高版本，以及已安装的 Claude Code CLI。

```bash
cd /Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/iOSDriver
npm install
npm run build
```

确认编译产物存在：

```bash
test -f /Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/iOSDriver/dist/index.js
```

## 直接编辑 Claude Code 配置文件（推荐）

项目级 MCP 配置文件是当前项目根目录下的：

```text
/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/.mcp.json
```

在已有的 `mcpServers` 对象中加入或替换 `iOSDriver`，保留其他 MCP 服务，例如：

```json
{
  "mcpServers": {
    "iOSDriver": {
      "command": "node",
      "args": [
        "/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/iOSDriver/dist/index.js"
      ],
      "env": {
        "IOS_EXPLORE_BASE_URL": "http://localhost:38321",
        "IOS_EXPLORE_REQUEST_TIMEOUT_MS": "10000"
      }
    },
    "XcodeBuildMCP": {
      "command": "npx",
      "args": ["-y", "xcodebuildmcp@latest", "mcp"]
    }
  }
}
```

重点：

- 只保留一个名为 `iOSDriver` 的配置，避免同时存在旧的相对路径和新的绝对路径。
- 如果 `.mcp.json` 已经有 `XcodeBuildMCP` 或其他服务，只替换 `iOSDriver` 对象，不要覆盖整个文件。
- JSON 必须保持有效，最后一个属性后不能有多余逗号。

保存后重新启动 Claude Code。在会话中执行 `/mcp`，确认 `iOSDriver` 已连接并显示 `health_check`。

## 使用 Claude Code 命令注册（可选）

如果不想手动编辑文件，`--scope local` 也可以把同等配置写入当前项目的本地配置：

```bash
claude mcp add \
  --transport stdio \
  --scope local \
  iOSDriver \
  -e IOS_EXPLORE_BASE_URL=http://localhost:38321 \
  -e IOS_EXPLORE_REQUEST_TIMEOUT_MS=10000 \
  -- node /Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/iOSDriver/dist/index.js
```

检查注册结果：

```bash
claude mcp list
claude mcp get iOSDriver
```

如果 `iOSDriver` 已存在，先删除再注册：

```bash
claude mcp remove iOSDriver
```

## 验证

先确保集成了 iOSExploreServer 的 App 已启动并监听 `38321`。模拟器直接验证：

```bash
curl -s -X POST http://localhost:38321/ \
  -H 'Content-Type: application/json' \
  -d '{"action":"ping"}'
```

预期包含：

```json
{"code":"ok","data":{"pong":true}}
```

启动 Claude Code 后执行 `/mcp`，确认 `iOSDriver` 已连接并能看到 `health_check`。调用 `health_check` 可以验证 iOSDriver 到 App HTTP 服务的连接；App 未启动时，MCP 服务仍可能启动，但检查会报告连接失败。

真机还需要先运行 `iproxy 38321 38321`，并确认 `lsof -iTCP:38321 -sTCP:LISTEN` 显示的监听进程是 `iproxy`。

## 本地更新

修改 `iOSDriver/src` 下的代码后，执行：

```bash
cd /Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/iOSDriver
npm run build
```

因为 Claude Code 配置始终指向同一个 `dist/index.js`，不需要重新编辑 `.mcp.json`，也不需要重新 `claude mcp add`。已运行的 MCP 子进程不会自动加载新代码，编译完成后请退出当前 Claude Code 并重新启动；进入新会话后执行 `/mcp` 检查连接和工具列表。

可选地，先运行单元测试（测试命令也会先编译）：

```bash
npm test
```

## 项目配置与个人配置

上面的 `.mcp.json` 是项目级配置。它适合当前仓库的本地测试，但其中的绝对路径只对当前机器有效，不应直接提交给其他开发者使用。个人级配置应使用 Claude Code 自身支持的用户配置位置；本项目文档只推荐修改当前仓库的 `.mcp.json`，避免误改其他项目的 MCP 服务。

## 常见问题

- `Cannot find module .../dist/index.js`：在 iOSDriver 目录执行 `npm run build`，并检查上面的绝对路径。
- Claude Code 显示配置解析失败：检查 `.mcp.json` 是否为合法 JSON，尤其是逗号、引号和重复的 `iOSDriver` 配置。
- `/mcp` 中工具仍是旧版本：完全退出并重新启动 Claude Code；仅重新编译不会重启已有 MCP 子进程。
- `health_check` 连接失败：先用上面的 `curl` 验证 App 端口，再检查模拟器/真机端口转发。
- 换了电脑或目录：执行 `claude mcp remove iOSDriver` 后重新注册，把命令中的绝对路径替换为新路径。
