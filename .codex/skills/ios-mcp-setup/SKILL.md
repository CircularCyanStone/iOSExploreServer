---
name: ios-mcp-setup
description: iOS 自动化工具 MCP 配置指引。当用户说"配置 MCP"、"安装 iOSDriver"、"工具不可用"、"MCP Server 连不上"、"怎么安装 XcodeBuildMCP"时使用。提供 iOSDriver MCP 与 XcodeBuildMCP 的客户端中立安装、配置、验证步骤。
---

# iOS MCP 配置指引

处理 iOS 自动化所需 MCP Server 的安装、配置与验证。把配置说明写成客户端中立流程：先识别用户使用的 MCP 客户端，再按该客户端的配置文件格式填入等价的 server 配置。

## 目标

解决"怎么让 iOS 自动化 MCP 工具可用"的问题：

- 检测当前状态：判断 iOSDriver MCP 与 XcodeBuildMCP 是否已被客户端加载。
- 提供安装步骤：安装依赖、构建 server、写入 MCP 客户端配置。
- 验证安装结果：重连 MCP 客户端后确认工具可发现、server 可启动、App HTTP API 可连通。

不做实际 App 操作、UI 自动化流程编排、连接排障或 Xcode 构建调试；这些任务应回到对应的 iOS 自动化、连接、构建调试流程。

## MCP Server 依赖

iOS 自动化通常需要两个 MCP Server：

| MCP Server | 用途 | 典型工具 |
|---|---|---|
| iOSDriver MCP | 把已接入 App 内 HTTP 自动化端点的 action 包装成 MCP tools | `health_check`、`ui_inspect`、`ui_tap`、`app_logs_read` |
| XcodeBuildMCP | 提供 Xcode 构建、模拟器/真机管理、App 启动调试能力 | `list_devices`、`build_run_sim`、`launch_app_device` |

两者配合工作：XcodeBuildMCP 负责构建和启动 App，iOSDriver MCP 负责访问 App 内的 HTTP 自动化 API。

## 配置流程

### 1. 检测当前状态

先在当前 MCP 客户端中查看已加载的 MCP server 和 tools：

- 看到 iOSDriver 的 `health_check`、`ui_inspect` 或同类工具，说明 iOSDriver MCP 已加载。
- 看到 XcodeBuildMCP 的 `list_devices`、`build_run_sim` 或同类工具，说明 XcodeBuildMCP 已加载。
- 两者都缺失时，按下文全新安装。
- 只有一个缺失时，只补齐缺失项。

如果客户端支持 MCP server 日志或工具列表刷新，先使用客户端自带能力读取真实错误；不要只根据当前聊天界面是否展示工具下结论。

### 2. 安装 iOSDriver MCP

iOSDriver MCP Server 封装目标 App 的 HTTP 自动化 API，默认访问 `POST http://localhost:38321/`。

前置要求：

- 安装 Node.js，建议使用当前 LTS 版本。
- 安装 Git。
- 准备一个可被 MCP 客户端访问的 iOSDriver 源码目录。

安装流程：

```bash
git clone https://github.com/cystone/iOSDriver.git
cd iOSDriver
npm install
npm run build
```

如果仓库没有 `build` 脚本，按仓库实际说明选择入口文件，例如 `dist/index.js`、`build/index.js`、`src/index.js` 或 `index.js`。

把 iOSDriver 注册到 MCP 客户端。不同客户端的配置文件位置和格式不同，使用客户端文档确认实际位置；下面是通用 JSON 形态示例：

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

配置要求：

- 使用真实绝对路径替换 `/path/to/iOSDriver/dist/index.js`。
- 不要在 `args` 中使用 `~` 或依赖当前工作目录的相对路径。
- 保留 `IOS_EXPLORE_BASE_URL`，除非 App 监听的 host 或端口已被显式改动。
- 修改配置后，按客户端要求重连 MCP server；多数客户端需要完全重启或重新加载 MCP 配置。

### 3. 安装 XcodeBuildMCP

XcodeBuildMCP 提供 Xcode 构建、设备管理、App 启动调试能力。

前置要求：

- 使用 macOS。
- 安装 Xcode，并用 `xcodebuild -version` 验证。
- 安装 Command Line Tools；缺失时运行 `xcode-select --install`。

安装流程：

```bash
npm install -g xcodebuildmcp@latest
```

如果客户端支持 XcodeBuildMCP 的自动安装命令，可按官方文档执行：

```bash
xcodebuildmcp install
```

如果需要手动写入 MCP 配置，使用等价 server 配置：

```json
{
  "mcpServers": {
    "XcodeBuildMCP": {
      "command": "npx",
      "args": ["-y", "xcodebuildmcp@latest", "mcp"],
      "env": {}
    }
  }
}
```

验证本地安装：

```bash
xcodebuildmcp doctor
```

完整文档与最新安装方法见 https://www.xcodebuildmcp.com/#get-started。

### 4. 合并配置

如果客户端已有其他 MCP server，在同一个 `mcpServers` 对象内并列添加。保持 JSON、TOML 或客户端专用配置格式有效，避免多余逗号、错误引号或重复 server 名。

通用 JSON 合并示例：

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
    },
    "XcodeBuildMCP": {
      "command": "npx",
      "args": ["-y", "xcodebuildmcp@latest", "mcp"],
      "env": {}
    }
  }
}
```

## 验证流程

配置完成后按顺序验证：

1. 重连或重启 MCP 客户端，让客户端重新读取 MCP 配置。
2. 查看 MCP server 状态，确认 iOSDriver 和 XcodeBuildMCP 都已启动且没有配置解析错误。
3. 查看 MCP tools 列表，确认 iOSDriver 暴露 `health_check`，XcodeBuildMCP 暴露设备或构建相关工具。
4. 对 XcodeBuildMCP 执行设备列表能力，确认能看到本机模拟器或已连接真机。
5. 在 App 已运行且目标 HTTP 自动化端点已监听后，调用 iOSDriver `health_check`；成功时再继续使用 UI、日志或截图工具。

iOSDriver 连接失败时，先直接验证 HTTP API：

```bash
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
```

预期响应：

```json
{"code":"ok","data":{"pong":true}}
```

## 常见问题

### 工具列表里看不到 iOSDriver 工具

按顺序排查：

1. 确认 MCP 客户端已重新加载配置。
2. 检查客户端 MCP 配置文件语法。
3. 检查 `args` 指向的 iOSDriver 入口文件是否存在。
4. 手动运行 `node /path/to/iOSDriver/dist/index.js`，读取启动错误。
5. 查看客户端的 MCP server 日志，确认 server 是否启动后立即退出。
6. 如果 `health_check` 已可用但部分动态 UI 工具未展示，先确认 App 是否已启动并返回 action 列表；部分客户端会在重新列出 tools 后才展示新工具。

### XcodeBuildMCP 命令不可用

按顺序排查：

1. 运行 `which xcodebuildmcp` 确认 CLI 是否在 `PATH` 内。
2. 运行 `xcodebuildmcp doctor` 读取诊断结果。
3. 检查 Node.js、Xcode、Command Line Tools 是否满足前置要求。
4. 如果使用 `npx -y xcodebuildmcp@latest mcp`，确认当前网络环境允许下载 npm 包。

### iOSDriver 能启动但连接 App 失败

按顺序排查：

1. 确认 App 已接入 App 内 HTTP 自动化端点，并在 DEBUG 或测试构建中启动 server。
2. 用 `curl` 调用 `ping` action 验证端口。
3. 模拟器场景通常可直接访问 `localhost:38321`。
4. 真机场景通常需要 USB 端口转发，例如把 Mac 的 `38321` 转发到设备的 `38321`。
5. 检查 `IOS_EXPLORE_BASE_URL` 是否指向实际可访问地址。

### 配置文件位置不明确

不要硬编码某个客户端的配置路径。先查看当前 MCP 客户端文档或设置界面，确认：

- 配置文件路径。
- 配置格式是 JSON、TOML 还是客户端专用 schema。
- 修改后需要重启客户端、重连 MCP server，还是刷新当前会话。

## 后续步骤

配置通过后，把用户带回实际任务：

- 需要启动或调试 App：使用 XcodeBuildMCP 相关流程。
- 需要操作 UI、表单、列表、弹窗或截图：使用 iOSDriver 相关流程。
- 需要排查 App HTTP 连接、端口冲突或真机 USB 转发：使用连接诊断流程。

## 参考资源

- iOSDriver MCP GitHub: https://github.com/cystone/iOSDriver
- XcodeBuildMCP 官网: https://www.xcodebuildmcp.com
- MCP 规范: https://modelcontextprotocol.io
