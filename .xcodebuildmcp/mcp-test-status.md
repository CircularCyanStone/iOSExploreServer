# MCP 服务测试状态

## 安装状态

### 1. XcodeBuildMCP
- ✅ 已安装（npm 全局包，版本 2.6.2）
- ✅ 已配置到 Claude Desktop Config
- ⚠️ **需要重启 Claude Code 才能加载工具**

### 2. iOSDriver
- ✅ 已编译（`/Users/cystone/Desktop/iOSExploreServer/iOSDriver/dist/`）
- ✅ 已配置到 Claude Desktop Config
- ⚠️ **需要重启 Claude Code 才能加载工具**

## 当前测试环境状态

### 模拟器
- ✅ iPhone 17 Pro 已启动（UDID: 8ECAD903-DF09-4111-A236-7ADA1F07A8E1）
- ✅ SPMExample App 已构建并运行（PID: 17126）
- ✅ iOSExploreServer 正常运行在 localhost:38321
- ✅ ping 测试通过：`{"code":"ok","data":{"pong":true}}`

### 端口状态
```
COMMAND     PID    USER   TYPE     ADDRESS
SPMExampl 17126 cystone  IPv6     *:38321 (LISTEN)
```

✅ 只有模拟器 App 在监听，iproxy 已停止（模拟器不需要 iproxy）

## 重启 Claude Code 后的测试步骤

### 步骤 1：验证 MCP 工具已加载

在新的 Claude Code 对话中执行：

```
列出所有可用的 MCP 服务器和工具
```

预期看到：
- `XcodeBuildMCP` 服务器及其工具
- `iOSDriver` 服务器及其工具

### 步骤 2：测试 iOSDriver 健康检查

```
使用 iOSDriver 的 health_check 工具检查连接状态
```

预期响应：
```json
{
  "status": "ok",
  "serverInfo": {
    "version": "...",
    "actions": [...]
  }
}
```

### 步骤 3：获取 UI 层级树

```
使用 iOSDriver 的 ui_inspect 工具获取当前 UI 树
```

预期响应包含完整的视图层级结构。

### 步骤 4：截图测试

```
使用 iOSDriver 的 ui_screenshot 工具截取当前屏幕
```

预期返回 base64 编码的 PNG 图像。

### 步骤 5：点击测试

先通过 `ui_inspect` 找到一个可点击元素的 path，然后：

```
使用 ui_tap 工具点击路径为 "0.0.0.1" 的控件（实际路径根据 inspect 结果）
```

### 步骤 6：XcodeBuildMCP 设备列表

```
使用 XcodeBuildMCP 的 list_devices 工具列出所有可用设备
```

预期看到模拟器和真机列表。

## 快速验证命令（终端）

如果重启后发现 App 已停止，可以用以下命令快速恢复：

```bash
# 检查模拟器是否还在运行
xcrun simctl list devices booted

# 如果模拟器还在，但 App 停止了，重新启动 App
xcrun simctl launch 8ECAD903-DF09-4111-A236-7ADA1F07A8E1 com.coo.SPMExample

# 验证 server
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
```

## 配置文件路径

- **Claude Desktop Config**: `~/.config/claude/claude_desktop_config.json`
- **XcodeBuildMCP Config**: `.xcodebuildmcp/config.yaml`
- **iOSDriver 源码**: `/Users/cystone/Desktop/iOSExploreServer/iOSDriver/`

## 常见问题

### Q: 重启后工具还是不可用？

A: 检查配置文件语法：
```bash
cat ~/.config/claude/claude_desktop_config.json | jq .
```

如果报错，说明 JSON 格式有问题。

### Q: iOSDriver 报连接失败？

A: 检查 App 是否还在运行：
```bash
lsof -iTCP:38321 -sTCP:LISTEN
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
```

如果 App 已停止，按上面的快速验证命令重启。

### Q: 需要测试真机怎么办？

A: 
1. 先配对真机（Xcode → Window → Devices and Simulators）
2. 启动 iproxy：`./scripts/proxy.sh --daemon`
3. 使用 XcodeBuildMCP 的 `device-app` profile 构建和启动
4. 确认端口监听进程是 `iproxy` 而非 `SPMExampl`

## 下一步

✅ **立即执行**：重启 Claude Code

✅ **重启后执行**：按上面的「步骤 1-6」验证所有 MCP 工具

✅ **长期使用**：参考 `.xcodebuildmcp/README.md` 和 `iOSDriver-setup.md`
