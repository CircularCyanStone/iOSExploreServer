---
name: ios-automation
description: |
  Unified entry point for iOS app automation. Provides connection management, 
  automatic routing to specialized skills, and quick diagnostics.
  
  Use this skill when you need to:
  - Test iOS apps (simulator or physical device)
  - Handle alerts, forms, navigation, lists, or gestures
  - Check connection status or troubleshoot iproxy
  - Take screenshots or inspect UI state
  
  Automatically manages iproxy for physical devices and routes to the right sub-skill.
---

# iOS Automation - Unified Entry Point

## 功能概述

这是 iOS 自动化的统一入口 skill，提供：

1. **自动连接管理** — 自动启动/停止 iproxy，检测端口状态
2. **智能任务路由** — 根据任务类型自动调用对应的专业 skill
3. **快速诊断** — 连接检查、截图、UI 检查等常用操作

## 何时使用

当你需要：
- 测试 iOS App（模拟器或真机）
- 不确定该用哪个 skill 时，作为通用入口
- 检查连接状态或排查 iproxy 问题
- 快速截图或查看当前 UI 状态

## 前置条件

- **XcodeBuildMCP** 已连接（用于构建和运行 App）
- **iOSDriver MCP Server** 已配置在 `.mcp.json`
- iOS App 已安装（模拟器或真机）

## 核心能力

### 1. 连接管理

#### 检查连接状态
```bash
# 我会自动执行以下检查：
# 1. 检测端口 38321 是否被监听
# 2. 识别监听进程（iproxy / SPMExample / 其他）
# 3. 尝试 ping 命令验证服务可用性
# 4. 给出连接诊断建议
```

**自动诊断场景：**
- ✅ 模拟器：App 直接监听 localhost:38321
- ✅ 真机（正确）：iproxy 监听 38321，转发到设备
- ❌ 真机（错误）：残留的模拟器 App 占用 38321
- ❌ 无服务：端口未监听，需要启动 App

#### 启动 iproxy（真机）
```bash
# 我会自动：
# 1. 检测当前端口状态
# 2. 如果有冲突进程，提示清理方案
# 3. 启动 iproxy 后台守护进程
# 4. 验证转发是否成功
```

#### 停止 iproxy
```bash
# 我会自动：
# 1. 查找 iproxy 进程
# 2. 安全停止进程
# 3. 确认端口已释放
```

### 2. 任务路由

我会根据你的需求自动调用对应的专业 skill：

| 任务类型 | 自动路由到 | 可信度 |
|---------|-----------|-------|
| 表单填写、文本输入、开关控制 | `/ios-form-filling` | ⭐⭐⭐⭐⭐ |
| 弹窗处理、确认对话框 | `/ios-alert-handling` | ⭐⭐⭐⭐⭐ |
| 页面导航、返回、导航栏按钮 | `/ios-navigation` | ⭐⭐⭐⭐⭐ |
| 列表滚动、查找项目 | `/ios-list-interaction` | ⭐⭐⭐⭐⭐ |
| 截图、视觉验证 | `/ios-screenshot` | ⭐⭐⭐⭐⭐ |
| 滑动、长按手势 | `/ios-gestures` | ⭐⭐⭐ |
| 等待加载、动态内容 | `/ios-dynamic-content` | ⭐⭐⭐ |

**示例对话：**
- "帮我点击登录按钮" → 自动调用 `/ios-form-filling` 或 `/ios-navigation`
- "处理这个确认弹窗" → 自动调用 `/ios-alert-handling`
- "滚动到联系人列表的第 50 项" → 自动调用 `/ios-list-interaction`

### 3. 快速诊断

#### 健康检查（ping）
```bash
# 发送 ping 命令验证服务可用性
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
# 预期响应: {"code":"ok","data":{"pong":true}}
```

#### UI 状态检查（inspect）
```bash
# 获取当前 UI 层次结构
# - 视图树
# - 可交互元素
# - 文本内容
# - 弹窗状态
```

#### 截图（screenshot）
```bash
# 捕获当前屏幕 PNG 截图
# - 默认最大尺寸 1280px
# - Base64 编码传输
# - 包含尺寸元数据
```

## 工作流程

### 模拟器测试流程

```
1. 用户：帮我测试模拟器上的 SPMExample
2. 我：检查连接状态...
   → lsof -iTCP:38321 检测到 SPMExample 监听
   → curl ping 验证服务正常
   ✅ 连接正常，模拟器模式
3. 我：需要我做什么测试？（表单/弹窗/导航...）
4. 用户：测试表单填写
5. 我：调用 /ios-form-filling skill...
```

### 真机测试流程

```
1. 用户：帮我测试真机上的 App
2. 我：检查连接状态...
   → lsof -iTCP:38321 检测到残留 SPMExample（模拟器）
   ❌ 端口被占用，需要清理
3. 我：清理残留进程...
   → xcrun simctl terminate <UDID> com.coo.SPMExample
   ✅ 端口已释放
4. 我：启动 iproxy 转发...
   → 获取真机 USB UDID
   → ./scripts/proxy.sh --daemon
   ✅ iproxy 已启动并转发到真机
5. 我：curl ping 验证连接...
   ✅ 真机服务正常
6. 用户：测试弹窗处理
7. 我：调用 /ios-alert-handling skill...
```

## 常见问题排查

### 问题 1: `curl: (7) Failed to connect to localhost:38321`

**原因：** App 未启动或端口未监听

**解决方案：**
```bash
# 模拟器：
session_use_defaults_profile("sim-app")
build_run_sim()
launch_app_sim(env={"IOS_EXPLORE_AUTOSTART":"1"})

# 真机：
session_use_defaults_profile("device-app")
build_run_device()
launch_app_device(env={"IOS_EXPLORE_AUTOSTART":"1"})
```

### 问题 2: 真机 `curl` 返回的是旧数据/模拟器数据

**原因：** 残留的模拟器 App 占用了 38321 端口

**解决方案：**
```bash
# 1. 检查监听进程
lsof -iTCP:38321
# COMMAND 列显示 SPMExampl → 模拟器残留

# 2. 终止残留进程
xcrun simctl terminate <模拟器UDID> com.coo.SPMExample

# 3. 启动 iproxy
./scripts/proxy.sh --daemon

# 4. 验证
lsof -iTCP:38321
# COMMAND 列显示 iproxy → 正确
```

### 问题 3: `iproxy: Address already in use: 38321`

**原因：** 端口被其他进程占用

**解决方案：**
```bash
# 查看占用进程
lsof -iTCP:38321

# 如果是旧 iproxy，停止它
./scripts/proxy.sh --stop

# 如果是模拟器 App，终止它
xcrun simctl terminate <UDID> com.coo.SPMExample
```

## MCP 工具映射

| 操作 | 使用的 MCP 工具 |
|------|---------------|
| 连接检查 | `mcp__iOSDriver__ping` |
| UI 检查 | `mcp__iOSDriver__ui_inspect` |
| 截图 | `mcp__iOSDriver__ui_screenshot` |
| 点击 | `mcp__iOSDriver__ui_tap` |
| 弹窗响应 | `mcp__iOSDriver__ui_alert_respond` |
| 文本输入 | `mcp__iOSDriver__ui_input` |
| 滚动 | `mcp__iOSDriver__ui_scroll` |
| 导航返回 | `mcp__iOSDriver__ui_navigation_back` |

## 性能指标

| 操作 | 预期耗时 |
|------|---------|
| 连接检查（ping） | < 50ms |
| 端口状态检查 | < 100ms |
| 启动 iproxy | ~1-2 秒 |
| UI 检查（inspect） | 20-50ms |
| 截图（screenshot） | 200-500ms |

## 专业 Skills 索引

完整 skills 文档：`docs/ios-automation-skills-index.md`

**生产就绪（⭐⭐⭐⭐⭐）：**
- `/ios-form-filling` — 表单填写、控件操作
- `/ios-alert-handling` — 弹窗、对话框处理
- `/ios-navigation` — 页面导航、返回
- `/ios-list-interaction` — 列表滚动、查找
- `/ios-screenshot` — 截图、视觉验证

**部分就绪（⭐⭐⭐）：**
- `/ios-gestures` — 滑动、长按手势
- `/ios-dynamic-content` — 动态内容等待

**实验性（⭐）：**
- `/ios-controller-navigation` — 控制器层次检查
- `/ios-table-actions` — 表格高级操作
- `/ios-date-picker` — 日期选择器

## 技术架构

```
用户请求
    ↓
ios-automation (入口 skill)
    ↓
    ├─ 连接管理 (iproxy 启动/停止/检查)
    │   ├─ lsof 端口检测
    │   ├─ scripts/proxy.sh 守护进程
    │   └─ curl ping 验证
    ↓
    ├─ 任务路由 (根据需求调用专业 skill)
    │   ├─ /ios-form-filling
    │   ├─ /ios-alert-handling
    │   ├─ /ios-navigation
    │   └─ ...其他 skills
    ↓
    └─ MCP 工具调用 (iOSDriver)
        ├─ ui.inspect
        ├─ ui.tap
        ├─ ui.alert.respond
        └─ ...30+ 命令
```

## 最佳实践

1. **优先使用此 skill 作为入口**，让我自动路由到专业 skill
2. **真机测试前先检查连接状态**，确保 iproxy 正确运行
3. **模拟器残留问题**：定期检查 `lsof -iTCP:38321`，清理残留进程
4. **环境变量驱动自动启动**：使用 `IOS_EXPLORE_AUTOSTART=1` 让 App 自动启动服务
5. **保留截图证据**：关键操作前后截图，便于排查问题

## 相关文档

- **完整 Skills 索引**：`docs/ios-automation-skills-index.md`
- **架构设计**：`docs/architecture/index.md`
- **构建与测试**：`docs/runbooks/build-and-test.md`
- **排障指南**：`docs/runbooks/debugging.md`
- **UIKit 命令**：`docs/uikit/README.md`
- **项目规则**：`AGENTS.md`、`CLAUDE.md`

---

**版本**：1.0  
**创建日期**：2026-07-14  
**测试覆盖率**：96.3% (200+ 场景)  
**MCP 服务**：XcodeBuildMCP + iOSDriver
