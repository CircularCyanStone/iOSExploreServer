# iOSDriver 本地安装与更新（TRAE Work）

本文用于把当前仓库中的 `iOSDriver` 直接注册到 `TRAE Work`，方便测试本地修改后的 MCP 服务代码。`iOSDriver` 是 Node.js/TypeScript 服务，不是 Swift Package；`TRAE Work` 启动的是 `dist/index.js`。

## 固定本地入口

源码目录：

```text
/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/iOSDriver
```

编译产物：

```text
/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/iOSDriver/dist/index.js
```

如果你是在当前项目里使用 `TRAE Work`，优先使用项目级变量 `${workspaceFolder}`，这样仓库路径变化后不需要改配置中的绝对路径。

## 首次安装

要求 macOS、Node.js 20 或更高版本，以及已安装 `TRAE Work` 桌面版。

```bash
cd /Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/iOSDriver
npm install
npm run build
```

确认编译产物存在：

```bash
test -f /Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/iOSDriver/dist/index.js
```

## 项目级配置（推荐）

`TRAE Work` 桌面端支持项目级 MCP 配置文件：

```text
/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/.trae/mcp.json
```

在当前项目中，推荐把下面内容保存为 `./.trae/mcp.json`：

```json
{
  "mcpServers": {
    "iOSDriver": {
      "command": "bash",
      "args": [
        "-lc",
        "cd \"${workspaceFolder}/iOSDriver\" && exec node dist/index.js"
      ],
      "env": {
        "IOS_EXPLORE_BASE_URL": "http://localhost:38321",
        "IOS_EXPLORE_REQUEST_TIMEOUT_MS": "10000"
      }
    },
    "XcodeBuildMCP": {
      "command": "bash",
      "args": [
        "-lc",
        "cd \"${workspaceFolder}\" && exec npx -y xcodebuildmcp@latest mcp"
      ]
    }
  }
}
```

重点：

- 只保留一个名为 `iOSDriver` 的配置，避免同时存在旧的相对路径和新的项目级配置。
- `TRAE Work` 支持 `${workspaceFolder}`，适合当前仓库这种项目级本地 MCP。
- `iOSDriver` 与 `XcodeBuildMCP` 都建议通过 `bash -lc` 先切到 `${workspaceFolder}` 或 `${workspaceFolder}/iOSDriver` 再 `exec`。这样 `iOSDriver` 始终读取当前仓库的最新 `dist/index.js`，`XcodeBuildMCP` 也能稳定读取当前仓库下的 `.xcodebuildmcp/config.yaml`，避免进程从 `/Users/coo` 或别的工程目录启动后只暴露默认模拟器工具。
- 如果当前项目已经有其他 MCP Server，在同一个 `mcpServers` 对象里并列添加，不要覆盖整个文件。
- JSON 必须保持有效，最后一个属性后不能有多余逗号。

## 在 TRAE Work 界面中手动添加

如果你不想手动编辑 `./.trae/mcp.json`，也可以在 `TRAE Work` 里直接添加：

1. 打开 `TRAE Work`。
2. 点击左下角头像，进入 `设置`。
3. 打开左侧 `MCP`。
4. 如果是桌面版，选择运行环境为 `本地`。
5. 在 `MCP Servers 管理` 里点击 `创建 > 手动配置`。
6. 粘贴下面这段 JSON。

```json
{
  "mcpServers": {
    "iOSDriver": {
      "command": "bash",
      "args": [
        "-lc",
        "cd \"${workspaceFolder}/iOSDriver\" && exec node dist/index.js"
      ],
      "env": {
        "IOS_EXPLORE_BASE_URL": "http://localhost:38321",
        "IOS_EXPLORE_REQUEST_TIMEOUT_MS": "10000"
      }
    },
    "XcodeBuildMCP": {
      "command": "bash",
      "args": [
        "-lc",
        "cd \"${workspaceFolder}\" && exec npx -y xcodebuildmcp@latest mcp"
      ]
    }
  }
}
```

如果你是在别的工作区或空窗口里单独配置，不方便使用 `${workspaceFolder}`，可以改成绝对路径：

```json
{
  "mcpServers": {
    "iOSDriver": {
      "command": "bash",
      "args": [
        "-lc",
        "cd \"/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/iOSDriver\" && exec node dist/index.js"
      ],
      "env": {
        "IOS_EXPLORE_BASE_URL": "http://localhost:38321",
        "IOS_EXPLORE_REQUEST_TIMEOUT_MS": "10000"
      }
    },
    "XcodeBuildMCP": {
      "command": "bash",
      "args": [
        "-lc",
        "cd \"/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer\" && exec npx -y xcodebuildmcp@latest mcp"
      ]
    }
  }
}
```

## 为什么优先项目级

项目级配置只对当前仓库生效，适合本地调试 `iOSDriver`：

- 不会污染其他项目的 MCP 列表。
- 可以直接用 `${workspaceFolder}` 指向当前仓库里的 `dist/index.js`。
- 仓库切换分支或重新编译后，`TRAE Work` 仍然指向同一个项目内入口。

只有在你明确想让所有项目都共用这个本地 `iOSDriver` 时，才建议改成全局。

## 验证

先确保集成了 `iOSExploreServer` 的 App 已启动并监听 `38321`。

模拟器可直接验证：

```bash
curl -s -X POST http://localhost:38321/ \
  -H 'Content-Type: application/json' \
  -d '{"action":"ping"}'
```

预期包含：

```json
{"code":"ok","data":{"pong":true}}
```

然后回到 `TRAE Work`：

1. 打开当前项目。
2. 进入对话或工具面板中的 `/mcp` 视图。
3. 确认 `iOSDriver` 已连接，并能看到 `health_check`。

真机还需要先运行 `iproxy 38321 38321`，并确认 `lsof -iTCP:38321 -sTCP:LISTEN` 显示的监听进程是 `iproxy`。

## 本地更新

修改 `iOSDriver/src` 下的代码后，执行：

```bash
cd /Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/iOSDriver
npm run build
```

如果 `TRAE Work` 当前已经启动并加载了旧的 MCP 子进程，重新打开对应项目窗口或在 MCP 管理页重启 `iOSDriver`，让它重新加载最新的 `dist/index.js`。

如果你同时修改了 `.xcodebuildmcp/config.yaml`（例如打开 `device` workflow），也必须在 MCP 管理页重启 `XcodeBuildMCP`。否则旧进程会继续沿用之前的工作目录和工具清单，常见现象就是当前仓库明明配置了真机 profile，但 MCP tools 里仍然只有 `build_run_sim` / `launch_app_sim` / `stop_app_sim`。

## 常见问题

- `Cannot find module .../dist/index.js`：在 `iOSDriver` 目录执行 `npm run build`，并检查路径是否存在。
- `TRAE Work` 看不到 `health_check`：确认 `iOSDriver` MCP 已连接，且当前配置里没有重复的 `iOSDriver`。
- `health_check` 连接失败：先用 `curl` 验证 `38321`，再检查模拟器/真机端口转发。
- 真机没有响应：先确认 `iproxy` 在监听 `38321`，不是残留的 `SPMExample` Mac 进程占用了端口。
