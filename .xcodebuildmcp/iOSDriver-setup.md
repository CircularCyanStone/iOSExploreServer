# iOSDriver MCP 服务安装说明

## 适用范围

本文说明如何把 iOSDriver MCP 与 XcodeBuildMCP 配置到任意支持 MCP 的客户端中。客户端配置文件的位置、格式和重载方式由具体客户端决定；使用前先查看该客户端的 MCP 配置文档。

## 配置示例

以下示例使用通用 JSON 形态表达 MCP server 配置。若客户端使用 TOML、YAML 或图形化设置界面，把同等字段填入对应位置。

```json
{
  "mcpServers": {
    "XcodeBuildMCP": {
      "command": "npx",
      "args": ["-y", "xcodebuildmcp@latest", "mcp"],
      "env": {}
    },
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

- 把 `/path/to/iOSDriver/dist/index.js` 替换成当前机器上的真实绝对路径。
- 不要在 MCP `args` 中使用 `~` 或依赖当前工作目录的相对路径。
- 修改配置后，按客户端要求重启、重连或刷新 MCP server。

## 服务说明

- XcodeBuildMCP：提供 Xcode 构建、运行、设备管理和调试能力。
- iOSDriver：把 iOSExploreServer 的 HTTP action 包装成 MCP tools。

iOSDriver 通过 `IOS_EXPLORE_BASE_URL` 连接 App 内的 iOSExploreServer。默认地址是 `http://localhost:38321`。

## 使用前提

### 模拟器场景

1. 使用 XcodeBuildMCP 构建并启动目标 App。
2. 确认 App 在 DEBUG 或测试构建中启动 iOSExploreServer，并监听 `localhost:38321`。
3. 使用 iOSDriver 连接 `http://localhost:38321`。

### 真机场景

1. 使用 XcodeBuildMCP 构建并安装目标 App 到真机。
2. 启动 USB 端口转发，把 Mac 的 `38321` 转发到设备的 `38321`。
3. 验证端口监听进程：

   ```bash
   lsof -iTCP:38321 -sTCP:LISTEN
   ```

   真机流程中监听进程应是端口转发工具，而不是残留的模拟器 App 进程。

4. 启动目标 App，并确认 iOSExploreServer 已 ready。
5. 使用 iOSDriver 通过转发地址连接真机。

## 可用的 MCP Tools

iOSDriver 会通过 MCP `tools/list` 声明工具。部分客户端会延迟刷新工具列表；如果 server 已启动但工具列表不完整，先重连 MCP server 或刷新当前会话。

### 静态工具

- `health_check`：检查 iOSExploreServer 连接状态。
- `refresh_tools`：刷新可用 action 列表。
- `call_action`：调用任意 action。

### 动态工具

动态工具来自 App 当前注册的 iOSExploreServer action，常见示例：

- `ui_inspect`：获取 UI 层级树。
- `ui_tap`：点击控件。
- `ui_input`：输入文本。
- `ui_control_sendAction`：发送 UIControl 动作。
- `ui_datePicker_setDate`：设置日期选择器。
- `ui_picker_selectRow`：选择 picker 行。
- `ui_table_swipeAction`：列表滑动操作。
- `ui_alert_respond`：响应弹窗。
- `ui_topViewHierarchy`：获取顶层视图控制器。
- `ui_screenshot`：截图。
- `ui_wait`：等待条件。
- `ui_waitAny`：等待任意条件满足。
- `wait_and_inspect`：等待并获取 UI 树。
- `app_logs_mark`：标记日志点。
- `app_logs_read`：读取日志。

## 验证安装

重连 MCP 客户端后，按顺序验证：

1. 查看客户端 MCP server 状态，确认 `XcodeBuildMCP` 和 `iOSDriver` 均已启动。
2. 查看 MCP tools 列表，确认两个 server 都暴露工具。
3. 调用 XcodeBuildMCP 的设备列表能力，确认能看到可用模拟器或已连接真机。
4. 启动已集成 iOSExploreServer 的目标 App。
5. 调用 iOSDriver `health_check`，确认 HTTP 连接成功。

也可以直接用 HTTP 验证 App server：

```bash
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
```

预期响应：

```json
{"code":"ok","data":{"pong":true}}
```

## 配置选项

在 iOSDriver MCP server 的 `env` 字段中设置：

| 环境变量 | 默认值 | 说明 |
|---|---|---|
| `IOS_EXPLORE_BASE_URL` | `http://localhost:38321` | iOSExploreServer 地址 |
| `IOS_EXPLORE_REQUEST_TIMEOUT_MS` | `10000` | 请求超时，单位毫秒 |

`ui.wait` 和 `ui.waitAny` 可根据业务等待时间调整请求超时。

## 重新编译 iOSDriver

修改 iOSDriver 源码后重新构建：

```bash
cd /path/to/iOSDriver
npm run build
```

构建后按客户端要求重连或重启 MCP server。

## 故障排查

### iOSDriver 连接失败

先检查 App server 是否启动：

```bash
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
```

如果 `curl` 失败，优先检查 App 是否已启动 iOSExploreServer、端口是否被其他进程占用、真机端口转发是否仍在运行。

### 真机工具调用失败

检查端口监听：

```bash
lsof -iTCP:38321 -sTCP:LISTEN
```

如果监听者不是端口转发工具，先停止占用端口的进程，再重新启动 USB 端口转发。

### MCP 工具不显示

1. 确认客户端已重新加载 MCP 配置。
2. 检查配置文件语法或图形化配置字段。
3. 检查 `args` 入口文件路径是否存在。
4. 手动运行 iOSDriver 入口文件，读取 Node.js 启动错误：

   ```bash
   node /path/to/iOSDriver/dist/index.js
   ```

5. 查看客户端提供的 MCP server 日志，确认 server 是否启动后立即退出。
