# iOSExploreServer 快速入门

## 三种使用方式

### 🎯 方式 1：Claude Code + 统一 Skill（最简单）

适合：AI 辅助的 iOS 自动化测试

```bash
# 在 Claude Code 中输入：
/ios-automation

# 自动完成：
# ✅ 检查连接状态（模拟器/真机）
# ✅ 自动启动 iproxy（真机需要）
# ✅ 诊断端口冲突（清理模拟器残留）
# ✅ 路由到专业 skills（表单/弹窗/导航...）
```

**示例对话：**

```
你：帮我测试 iPhone 上的 SPMExample

我：检查连接状态...
   → 检测到模拟器 App 残留占用端口 38321
   → 正在清理...
   → 启动 iproxy 转发到真机...
   ✅ 连接正常，真机模式
   
   需要测试什么功能？
   - 表单填写
   - 弹窗处理
   - 页面导航
   - 列表交互

你：测试弹窗能不能正常点击

我：调用 /ios-alert-handling skill...
   → ui.inspect 检查当前页面
   → 发现 alert: "确认删除？"
   → ui.alert.respond 点击"确定"按钮
   ✅ 弹窗已关闭，操作成功
```

---

### 🔧 方式 2：专业 Skills（精确控制）

适合：明确知道要测试的具体场景

**生产就绪（⭐⭐⭐⭐⭐ 96%+ 测试覆盖率）：**

| Skill | 用途 | 示例 |
|-------|------|------|
| `/ios-form-filling` | 表单填写、文本输入、开关控制 | "填写登录表单：用户名 admin，密码 123456" |
| `/ios-alert-handling` | 弹窗处理、确认对话框 | "处理删除确认弹窗，点击确定" |
| `/ios-navigation` | 页面导航、返回、导航栏按钮 | "点击导航栏右上角的设置按钮" |
| `/ios-list-interaction` | 列表滚动、查找项目 | "滚动到联系人列表的第 50 项" |
| `/ios-screenshot` | 截图、视觉验证 | "截图保存当前页面状态" |

**部分就绪（⭐⭐⭐ 部分测试覆盖率）：**

| Skill | 用途 | 限制 |
|-------|------|------|
| `/ios-gestures` | 滑动、长按手势 | ui.drag 未测试 |
| `/ios-dynamic-content` | 等待加载、动态内容 | ui.wait/waitAny 需手动轮询 |

完整索引：`docs/ios-automation-skills-index.md`

---

### 🛠️ 方式 3：手动 curl（底层调试）

适合：调试 MCP 工具或理解底层协议

#### 模拟器流程

```bash
# 1. 启动模拟器 App（自动启动 server）
session_use_defaults_profile("sim-app")
build_run_sim()
launch_app_sim(env={"IOS_EXPLORE_AUTOSTART":"1"})

# 2. 验证连接（模拟器不需要 iproxy）
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
# → {"code":"ok","data":{"pong":true}}

# 3. 发送命令
curl -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}'
```

#### 真机流程

```bash
# 1. 检查端口状态
./scripts/proxy.sh --status

# 2. 清理冲突进程（如果有）
lsof -iTCP:38321
# 如果是模拟器残留：
xcrun simctl terminate <UDID> com.coo.SPMExample

# 3. 启动 iproxy 后台转发
./scripts/proxy.sh --daemon
# ✅ iproxy 已启动 (PID 12345)
#   → PID 文件: /tmp/iproxy-38321.pid
#   → 日志文件: /tmp/iproxy-38321.log

# 4. 启动真机 App（自动启动 server）
session_use_defaults_profile("device-app")
build_run_device()
launch_app_device(env={"IOS_EXPLORE_AUTOSTART":"1"})

# 5. 验证连接
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'

# 6. 停止 iproxy（测试完成后）
./scripts/proxy.sh --stop
```

---

## 常见问题排查

### ❌ 问题 1: `curl: (7) Failed to connect to localhost:38321`

**原因：** App 未启动或端口未监听

**解决方案：**
```bash
# 检查状态
./scripts/proxy.sh --status

# 如果显示"端口未被监听"，启动 App：
launch_app_sim(env={"IOS_EXPLORE_AUTOSTART":"1"})  # 模拟器
launch_app_device(env={"IOS_EXPLORE_AUTOSTART":"1"})  # 真机
```

---

### ⚠️ 问题 2: 真机 curl 返回旧数据/模拟器数据

**原因：** 残留的模拟器 App 占用了 38321 端口

**诊断：**
```bash
./scripts/proxy.sh --status
# 输出：
# ⚠️  模拟器 App 直接监听 (模拟器模式)
#   → 如需测试真机，先清理模拟器残留
```

**解决方案：**
```bash
# 1. 查找运行中的模拟器
xcrun simctl list devices | grep Booted

# 2. 终止残留进程
xcrun simctl terminate <模拟器UDID> com.coo.SPMExample

# 3. 启动 iproxy
./scripts/proxy.sh --daemon

# 4. 验证（COMMAND 列应显示 iproxy）
lsof -iTCP:38321
```

---

### 🔄 问题 3: `iproxy: Address already in use: 38321`

**原因：** 端口被其他进程占用

**解决方案：**
```bash
# 1. 检查占用进程
./scripts/proxy.sh --status

# 2. 如果是旧 iproxy，停止它
./scripts/proxy.sh --stop

# 3. 如果是模拟器 App，终止它
xcrun simctl terminate <UDID> com.coo.SPMExample

# 4. 重新启动
./scripts/proxy.sh --daemon
```

---

### 🧪 问题 4: 端口显示监听但 ping 失败

**诊断：**
```bash
./scripts/proxy.sh --status
# 查看"验证服务可用性"部分的结果
```

**可能原因：**
1. **App 崩溃**：重新启动 App
2. **iproxy 转发错误**：检查设备 UDID 是否正确
3. **防火墙阻止**：检查系统防火墙设置

---

## proxy.sh 完整命令参考

| 命令 | 说明 | 适用场景 |
|------|------|---------|
| `./scripts/proxy.sh` | 前台运行 iproxy（Ctrl-C 停止） | 调试、查看实时日志 |
| `./scripts/proxy.sh --daemon` | 后台运行 iproxy | 日常测试（推荐） |
| `./scripts/proxy.sh --status` | 检查连接状态 + 诊断 | 排查连接问题 |
| `./scripts/proxy.sh --stop` | 停止后台 iproxy | 测试完成后清理 |
| `./scripts/proxy.sh --help` | 显示帮助信息 | 查看所有选项 |

**状态检查输出示例：**

```bash
$ ./scripts/proxy.sh --status

📊 iproxy 状态检查 (端口 38321):

✅ 端口 38321 正在监听:
  iproxy (PID 12345, User coo)

✅ iproxy 运行中 (真机模式)
  → PID 文件: /tmp/iproxy-38321.pid (PID 12345)
  → 日志文件: /tmp/iproxy-38321.log

最近 5 行日志:
    waiting for connection
    accepted connection
    ...

🔍 验证服务可用性:
  ✅ 服务正常响应 (ping 成功)
```

---

## MCP 配置（`.mcp.json`）

确保 MCP 服务已配置：

```json
{
  "mcpServers": {
    "iOSDriver": {
      "command": "node",
      "args": ["/path/to/iOSDriver/dist/index.js"],
      "env": {}
    }
  }
}
```

Claude Code 会自动加载 30+ MCP 工具：
- `mcp__iOSDriver__ui_inspect`
- `mcp__iOSDriver__ui_tap`
- `mcp__iOSDriver__ui_alert_respond`
- `mcp__iOSDriver__ui_screenshot`
- ...

---

## 测试验证流程

### 完整测试流程（真机）

```bash
# 步骤 1: 清理环境
./scripts/proxy.sh --stop
lsof -iTCP:38321  # 确认端口空闲

# 步骤 2: 启动 iproxy
./scripts/proxy.sh --daemon

# 步骤 3: 启动 App（XcodeBuildMCP）
session_use_defaults_profile("device-app")
build_run_device()
launch_app_device(env={"IOS_EXPLORE_AUTOSTART":"1"})

# 步骤 4: 验证连接
./scripts/proxy.sh --status
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'

# 步骤 5: 使用 Claude Code skill
/ios-automation
# 或直接调用专业 skill：
/ios-alert-handling

# 步骤 6: 清理（测试完成后）
./scripts/proxy.sh --stop
```

---

## 架构图

```
┌─────────────────────────────────────────────────────────────┐
│                     Claude Code                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ /ios-automation (统一入口 Skill)                        │ │
│  │  ├─ 连接管理 (iproxy 启动/停止/检查)                    │ │
│  │  ├─ 任务路由 → 专业 skills                              │ │
│  │  └─ 快速诊断 (ping/inspect/screenshot)                 │ │
│  └────────────────────────────────────────────────────────┘ │
│                          ↓                                   │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ MCP Tools (iOSDriver)                                   │ │
│  │  - ui.inspect  - ui.tap  - ui.alert.respond            │ │
│  │  - ui.screenshot  - ui.input  - ui.scroll              │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                          ↓ HTTP POST
┌─────────────────────────────────────────────────────────────┐
│                  Mac (localhost:38321)                       │
│  ┌──────────────────┐           ┌──────────────────┐        │
│  │  模拟器模式       │           │   真机模式        │        │
│  │  SPMExample      │           │   iproxy         │        │
│  │  直接监听 38321   │           │   USB 转发       │        │
│  └──────────────────┘           └──────────────────┘        │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│            iPhone/iPad (iOS 26.2+)                          │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ SPMExample App                                          │ │
│  │  ├─ iOSExploreServer (监听 38321)                       │ │
│  │  ├─ iOSExploreUIKit (14 个 ui.* 命令)                  │ │
│  │  └─ iOSExploreDiagnostics (日志捕获)                   │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

## 下一步

- **阅读完整文档：** `README.md`、`AGENTS.md`、`CLAUDE.md`
- **Skills 索引：** `docs/ios-automation-skills-index.md`
- **架构设计：** `docs/architecture/index.md`
- **UIKit 命令：** `docs/uikit/README.md`
- **排障指南：** `docs/runbooks/debugging.md`

**Happy Testing! 🚀**
