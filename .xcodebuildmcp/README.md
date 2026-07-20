# XcodeBuildMCP 配置说明

## 安装验证

```bash
xcodebuildmcp --version  # 应显示 2.6.2 或更高版本
```

## 三个 Profile

| Profile | 用途 | 工程 | 设备 |
|---------|------|------|------|
| `sim-app` | 模拟器跑示例 App | SPMExample | iPhone 16 Pro 模拟器 |
| `sim-fw` | 模拟器跑 framework 测试 | iOSExploreServer | iPhone 16 Pro 模拟器 |
| `device-app` | 真机跑示例 App | SPMExample | 李奇奇的iPhone (iOS 26.5) |

## 使用方法（需要重启 Claude Desktop 后 MCP 工具才会加载）

### 模拟器运行示例 App

```
session_use_defaults_profile("sim-app")
build_run_sim()
launch_app_sim()
```

验证服务：
```bash
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
# 预期响应：{"code":"ok","data":{"pong":true}}
```

### 模拟器运行 framework 测试

```
session_use_defaults_profile("sim-fw")
build_run_sim()
# 测试会自动运行
```

### 真机运行示例 App

**第一步：启动 iproxy USB 转发**

```bash
./scripts/proxy.sh --daemon
# 或手动：iproxy 38321 38321 -u 00008030-001045C136D1402E
```

**第二步：构建和启动**

```
session_use_defaults_profile("device-app")
build_run_device()
launch_app_device()
```

**第三步：验证服务**

```bash
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
```

## 传递启动参数

环境变量和启动参数**不能**通过 `build_run_*` 传递，必须用 `launch_app_*`：

```
# 错误：env 不会生效
build_run_sim(env={"IOS_EXPLORE_OPEN_ALERT_TEST": "1"})

# 正确：先停止，再用 env 启动
stop_app_sim()
launch_app_sim(env={"IOS_EXPLORE_OPEN_ALERT_TEST": "1"})
```

可用的测试参数：
- `IOS_EXPLORE_OPEN_ALERT_TEST=1` — 启动后自动进入弹窗测试页
- `IOS_EXPLORE_SHOW_LOGIN=1` — 显示登录流程测试界面

## 常见问题排查

### 问题：curl 真机时响应不对

**原因**：38321 端口被模拟器残留进程占用

**排查**：
```bash
lsof -iTCP:38321
```

如果 COMMAND 列是 `SPMExampl` 而非 `iproxy`，说明模拟器 App 残留：

**解决**：
```bash
# 找到模拟器 UDID
xcrun simctl list | grep Booted
# 终止残留 App
xcrun simctl terminate <SIMULATOR_UDID> com.coo.SPMExample
# 重启 iproxy
./scripts/proxy.sh --stop
./scripts/proxy.sh --daemon
```

### 问题：真机部署失败

**检查 iOS 版本**：SPMExample 部署目标是 iOS 26.2，低于此版本无法安装。

```bash
# 查看真机版本
xcrun xctrace list devices | grep "李奇奇"
```

### 问题：MCP 工具不可用

重启 Claude Desktop 后工具才会加载。检查配置：

```bash
cat ~/.config/claude/claude_desktop_config.json
```

应包含：
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

## 设备 ID 注意事项

- **MCP 的 deviceId**：CoreDevice identifier（`3AC0C7D6-...`，通过 `list_devices` 获取）
- **iproxy 的 -u 参数**：USB UDID（`00008030-...`，通过 `xcrun xctrace list devices` 获取）

同一台真机有两个不同的 ID，不能混用。
