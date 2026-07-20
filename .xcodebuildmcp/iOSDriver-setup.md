# iOSDriver MCP 服务安装说明

## 安装状态

✅ **已安装到 Claude Code**

配置文件：`~/.config/claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "XcodeBuildMCP": {
      "command": "npx",
      "args": ["-y", "xcodebuildmcp@latest", "mcp"]
    },
    "iOSDriver": {
      "command": "node",
      "args": ["/Users/cystone/Desktop/iOSExploreServer/iOSDriver/dist/index.js"],
      "env": {
        "IOS_EXPLORE_BASE_URL": "http://localhost:38321"
      }
    }
  }
}
```

## 服务说明

- **XcodeBuildMCP**：Xcode 构建、运行、调试工具（远程 npm 包）
- **iOSDriver**：iOSExploreServer 的 MCP 包装器（本地路径）

iOSDriver 将 iOSExploreServer 的 HTTP action 包装成 MCP tools，让 Claude Code 可以直接调用 `ui.tap`、`ui.input`、`ui.inspect` 等命令。

## 使用前提

### 模拟器场景

1. 使用 XcodeBuildMCP 启动 SPMExample：
   ```
   session_use_defaults_profile("sim-app")
   build_run_sim()
   launch_app_sim()
   ```

2. App 会在 DEBUG 环境自动启动 server（监听 localhost:38321）

3. iOSDriver 自动连接到 `http://localhost:38321`

### 真机场景

1. 启动 iproxy USB 转发：
   ```bash
   ./scripts/proxy.sh --daemon
   ```

2. 使用 XcodeBuildMCP 启动 SPMExample：
   ```
   session_use_defaults_profile("device-app")
   build_run_device()
   launch_app_device()
   ```

3. **验证端口监听进程**（真机必做）：
   ```bash
   lsof -iTCP:38321 -sTCP:LISTEN
   ```
   
   COMMAND 列必须是 `iproxy`，不能是残留的 `SPMExampl`。

4. iOSDriver 通过 iproxy 转发连接到真机

## 可用的 MCP Tools

重启 Claude Code 后，以下工具会自动注册：

### 静态工具（始终可用）
- `health_check` — 检查 iOSExploreServer 连接状态
- `refresh_tools` — 刷新可用的 action 列表
- `call_action` — 调用任意 action（通用接口）

### 动态工具（从 server 自动注册）
- `ui_inspect` — 获取 UI 层级树
- `ui_tap` — 点击控件
- `ui_input` — 输入文本
- `ui_control_sendAction` — 发送控件动作（UIControl）
- `ui_datePicker_setDate` — 设置日期选择器
- `ui_picker_selectRow` — 选择 picker 行
- `ui_table_swipeAction` — 列表滑动操作
- `ui_alert_respond` — 响应弹窗
- `ui_topViewHierarchy` — 获取顶层视图控制器
- `ui_screenshot` — 截图
- `ui_wait` — 等待条件
- `ui_waitAny` — 等待任意条件满足
- `wait_and_inspect` — 等待并获取 UI 树（组合工具）
- `app_logs_mark` — 标记日志点
- `app_logs_read` — 读取日志

## 验证安装

重启 Claude Code 后，在对话中询问：

```
列出所有可用的 MCP 工具
```

应该看到 `XcodeBuildMCP` 和 `iOSDriver` 的工具列表。

## 端到端测试流程

完整的测试流程见：`docs/investigations/mcp-e2e-test.md`

简化版：

1. **启动 App**（模拟器）
   ```
   session_use_defaults_profile("sim-app")
   build_run_sim()
   launch_app_sim()
   ```

2. **健康检查**
   ```
   health_check()
   ```

3. **查看 UI 树**
   ```
   ui_inspect()
   ```

4. **点击控件**（假设找到了 path）
   ```
   ui_tap({"path": "0.0.0.1"})
   ```

5. **截图**
   ```
   ui_screenshot()
   ```

## 配置选项

修改 `~/.config/claude/claude_desktop_config.json` 中 iOSDriver 的 `env` 字段：

| 环境变量 | 默认值 | 说明 |
|---------|--------|------|
| `IOS_EXPLORE_BASE_URL` | `http://localhost:38321` | iOSExploreServer 地址 |
| `IOS_EXPLORE_REQUEST_TIMEOUT_MS` | `10000` | 请求超时（毫秒） |

注意：`ui.wait` 和 `ui.waitAny` 会根据业务超时自动调整 HTTP 超时。

## 重新编译 iOSDriver

如果修改了 iOSDriver 源码：

```bash
cd /Users/cystone/Desktop/iOSExploreServer/iOSDriver
npm run build
```

重启 Claude Code 后生效。

## 故障排查

### 问题：iOSDriver 连接失败

**检查 server 是否启动**：
```bash
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
```

预期响应：`{"code":"ok","data":{"pong":true}}`

### 问题：真机工具调用失败

**检查 iproxy 状态**：
```bash
lsof -iTCP:38321 -sTCP:LISTEN
```

COMMAND 必须是 `iproxy`。如果是 `SPMExampl`，说明模拟器 App 残留：

```bash
# 清理残留
xcrun simctl list | grep Booted
xcrun simctl terminate <SIMULATOR_UDID> com.coo.SPMExample
# 重启 iproxy
./scripts/proxy.sh --stop
./scripts/proxy.sh --daemon
```

### 问题：MCP 工具不显示

1. 确认已重启 Claude Code
2. 检查配置文件语法：
   ```bash
   cat ~/.config/claude/claude_desktop_config.json | jq .
   ```
3. 查看 Claude Code 日志（通常在 Help → View Logs）
