---
name: ios-mcp-setup
description: iOS 自动化工具 MCP 配置指引。当用户说"配置 MCP"、"安装 iOSDriver"、"工具不可用"、"MCP Server 连不上"、"怎么安装 XcodeBuildMCP"或真机 workflow 未加载时使用。提供 iOSDriver MCP 与 XcodeBuildMCP 的客户端中立安装、配置和工具可见性验证。MCP setup, iOSDriver install, XcodeBuildMCP install, missing tools, device workflow
---

# iOS MCP 配置指引

负责让 iOSDriver MCP 与 XcodeBuildMCP 被当前客户端加载并暴露所需工具。不处理 App 端点、`iproxy`、UI 操作或构建失败；工具已加载但 App 不可达时转 `ios-connection`。

## 先判定缺哪一层

| 观察结果 | 结论 | 动作 |
|---|---|---|
| iOSDriver 工具和 XcodeBuildMCP 工具都不存在 | 两个 server 均未加载 | 分别配置并重连客户端 |
| 缺少 `health_check` | iOSDriver 未加载或启动失败 | 检查 iOSDriver 配置和 server 日志 |
| 有 `health_check`，且 `connection.status` 是 `app_endpoint_unreachable` | iOSDriver 已加载，App 端点不可达 | 转 `ios-connection` |
| 有 XcodeBuildMCP 模拟器工具，但真机任务缺少 `launch_app_device` 等工具 | XcodeBuildMCP 已加载，`device` workflow 未生效 | 修复 workspace 配置并重连 server |
| UIKit / Diagnostics 静态工具存在，但调用返回 `unknown_action` | MCP 工具正常，App 未注册对应模块 | 检查宿主模块注册，不重装 MCP |

优先读取客户端的 MCP server 状态、工具列表和启动日志，不用聊天界面的展示状态替代诊断证据。

## 配置 iOSDriver

当前 skill 体系要求 iOSDriver 在 server 启动后静态暴露 `health_check`、`ui_inspect`、`app_logs_read` 等公共工具。使用目标 SDK 提供的当前 iOSDriver 源码或发行物，按其 `package.json` 安装依赖并构建：

```bash
cd /path/to/iOSDriver
npm install
npm run build
```

把 MCP command 指向实际构建入口，不绑定本机仓库名称：

```json
{
  "mcpServers": {
    "iOSDriver": {
      "command": "node",
      "args": ["/path/to/iOSDriver/dist/index.js"],
      "env": {
        "IOS_EXPLORE_BASE_URL": "http://localhost:38321",
        "IOS_EXPLORE_REQUEST_TIMEOUT_MS": "10000"
      }
    }
  }
}
```

不要仅凭某个同名 npm 包能启动就判定兼容。重连后必须核对上述静态工具；只有旧式 `refresh_tools`、缺少 `ui_inspect` 或缺少 `app_logs_read` 时，说明当前发行物落后于本 skill 契约，应改用目标 SDK 提供的当前构建。

不同客户端的 JSON、TOML 和 CLI 写法见 [客户端配置模板](references/client-config.md)。只在确认客户端类型后读取对应小节。

## 配置 XcodeBuildMCP

先按 [XcodeBuildMCP 官方安装文档](https://www.xcodebuildmcp.com/docs/installation) 核对当前 macOS、Xcode 和 Node.js 前置要求。MCP server 可直接使用：

```json
{
  "mcpServers": {
    "XcodeBuildMCP": {
      "command": "npx",
      "args": ["-y", "xcodebuildmcp@latest", "mcp"]
    }
  }
}
```

需要全局 CLI 时可运行 `npm install -g xcodebuildmcp@latest`，再用 `xcodebuildmcp --help` 验证。环境诊断使用独立命令 `xcodebuildmcp-doctor`；未全局安装时运行：

```bash
npx --package xcodebuildmcp@latest xcodebuildmcp-doctor
```

不要使用不存在的 `xcodebuildmcp install` 或 `xcodebuildmcp doctor` 子命令。`xcodebuildmcp init` 安装的是可选 agent skill，不是 MCP server。

## 配置 workflow

XcodeBuildMCP 从当前 workspace 发现 `.xcodebuildmcp/config.yaml`。需要生成或更新配置时，在目标 workspace 运行 `xcodebuildmcp setup`。MCP 客户端无法设置启动目录时，按官方配置说明设置 `XCODEBUILDMCP_CWD` 指向目标 workspace。

按任务启用最小 workflow 集合：

- 模拟器构建和启动：`simulator`。
- 真机构建和启动：`device`。
- UI 自动化或调试：仅在任务需要时增加 `ui-automation` 或 `debugging`。

修改 workflow、启动命令或工作目录后必须重启或重连 XcodeBuildMCP。旧进程不会自动刷新工具清单。

## 验证顺序

1. 让客户端重新读取 MCP 配置，确认两个 server 均未立即退出。
2. 查看工具列表：iOSDriver 至少有 `health_check`、`ui_inspect`、`app_logs_read`；XcodeBuildMCP 至少有本次任务所需的设备或构建工具。
3. 真机任务额外确认 `launch_app_device`、`stop_app_device`、`build_run_device` 可见。只看到 `*_sim` 时继续修复 workflow，不进入 App 连接排障。
4. 调用 XcodeBuildMCP 的设备列表能力，确认目标设备可见。
5. 在 App 已运行并监听 HTTP 端点后调用 `health_check`。返回 `ok:true` 时转 `ios-automation`；`connection.status == "app_endpoint_unreachable"` 时转 `ios-connection`；其他 `ok:false` 结果按 `app.modules`、`missingStaticActions` 和 `schemaIncompatibilities` 修复 App 集成，不重装 MCP。

需要直接区分 MCP 配置与 App 端点问题时，可调用：

```bash
curl -X POST http://localhost:38321/ -H 'Content-Type: application/json' -d '{"action":"ping"}'
```

预期 App 响应为 `{"code":"ok","data":{"pong":true}}`。curl 失败不能说明 MCP server 未加载，只说明该 URL 当前不可达。

## 失败分诊

| 现象 | 优先检查 | 不要误判为 |
|---|---|---|
| server 启动后立即退出 | 客户端日志、Node 版本、command/args、入口是否存在 | App 连接失败 |
| `npx` 找不到或无法下载 | 客户端进程 PATH、网络与包管理器 | Xcode 工程错误 |
| XcodeBuildMCP 只有模拟器工具 | `device` workflow、workspace 发现路径、server 是否重连 | iOSDriver 故障 |
| `health_check.connection.status` 是 `app_endpoint_unreachable` | App 运行状态、base URL、真机端口转发 | MCP 未安装 |
| 只有部分 iOSDriver action 返回 `unknown_action` | App 的 UIKit / Diagnostics 注册 | MCP tools 未刷新 |

## 边界

- `ios-automation`：工具和连接可用后的统一路由入口。
- `ios-connection`：App 端点、设备上下文、USB 转发和端口冲突。
- XcodeBuildMCP 官方文档：易变化的客户端配置、版本要求和 CLI 选项，以官方当前文档为准。
