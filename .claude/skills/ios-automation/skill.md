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
launch_app_sim()  # Server 会在 DEBUG 环境自动启动

# 真机：
session_use_defaults_profile("device-app")
build_run_device()
launch_app_device()  # Server 会在 DEBUG 环境自动启动
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
| 点击并检查状态 | `mcp__iOSDriver__ui_tap_and_inspect` |
| 弹窗响应 | `mcp__iOSDriver__ui_alert_respond` |
| 文本输入 | `mcp__iOSDriver__ui_input` |
| 控件事件（开关/滑块） | `mcp__iOSDriver__ui_control_sendAction` |
| 滚动 | `mcp__iOSDriver__ui_scroll` |
| 导航返回 | `mcp__iOSDriver__ui_navigation_back` |

> **性能优化**：优先使用 `ui_tap_and_inspect` 而非单独调用 `ui.tap` 后再 `ui.inspect`。
> 组合工具将点击、等待稳定、状态检查整合为一次调用，减少 Agent 推理次数，耗时从 4-6 秒优化到 2-3 秒。
> 
> **排障兜底**：所有 UI 命令都有对应的专用 MCP 工具（如 `ui_tap_and_inspect`、`ui_input`）。
> 如遇参数问题或工具调用失败，可使用通用工具 `mcp__iOSDriver__call_action(action:"ui.tap", data:{...})` 绕过。
> 正常情况下优先使用专用工具。

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

**离线分析型（不操作 App、不进上面的任务路由表）：**
- `/ios-test-intent` — 读业务源代码产出测试意图 + 成败判据清单（pass/fail criteria），判据用 `textExists` 等等待词汇，供执行型 skill 消费；运行时执行前可先来这拿判据

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

## 执行原则

### 1. 惰性检测（Lazy Detection）

连接检查遵循"先假设正常、失败才诊断"的原则：

```
优先级 1: 直接 ping
  ✅ 成功 → 继续任务
  ❌ 失败 → 进入优先级 2

优先级 2: 启动 App（模拟器/真机）
  - 模拟器：launch_app_sim
  - 真机：确保 iproxy 运行 + launch_app_device
  ✅ 启动后 ping 成功 → 继续任务
  ❌ 仍失败 → 进入优先级 3

优先级 3: 深度诊断
  - 端口占用检查（lsof -iTCP:38321）
  - 进程冲突排查（残留模拟器 App）
  - iproxy 状态检查（真机）
  - 给出修复建议
```

**反模式：** 每次任务前都执行完整诊断流程（端口检查、进程扫描、health check），浪费 2-3 秒。

**正确做法：** 先 ping，失败了再诊断。90% 的场景下 App 已运行，ping 直接成功。

### 2. 工具调用规则

#### 必须顺序调用的场景

1. **ui.inspect → ui_tap_and_inspect**
   - `ui.inspect` 签发 `viewSnapshotID`（陈旧校验指纹）
   - `ui_tap_and_inspect` 需要 `viewSnapshotID` 验证 UI 未变化
   - 推荐使用 `ui_tap_and_inspect` 一次性完成点击和状态检查，避免额外的 Agent 推理周期

2. **ui.wait → 后续操作**
   - 等待加载完成、动画结束、目标出现后再操作
   - 避免在过渡状态下操作元素

3. **ui.alert.respond → 后续操作**
   - 弹窗响应是阻塞性的，必须处理完才能继续
   - 处理弹窗后需重新 `ui.inspect` 获取新状态

#### 可并发调用的场景

1. **多个独立查询**
   - 同时查询多个页面的 UI 状态（不同 controller）
   - 并发截图多个测试场景

2. **批量诊断**
   - 同时检查端口状态、进程状态、连接状态
   - 并发执行多个健康检查

**反模式：** 把所有工具调用串行化，即使它们之间没有依赖关系。

**正确做法：** 识别数据依赖关系，无依赖的并发执行，有依赖的顺序执行。

### 3. 常见 UI 行为

了解 iOS 标准 UI 行为，避免误判为 Bug：

| 场景 | 标准行为 | 自动化影响 |
|------|---------|-----------|
| 登录失败 | 密码框被清空 | 重试需重新输入密码，不能复用旧值 |
| 键盘弹出 | 输入框自动滚动到可见区域 | 操作前需等待键盘动画完成 |
| Alert 响应 | 弹窗关闭后才返回响应 | 后续操作需在 alert.respond 完成后 |
| 页面跳转 | 导航动画 0.3-0.5 秒 | 跳转后需 `ui.wait` idle 等待动画完成 |
| Pull to Refresh | 刷新指示器显示 1-2 秒 | 刷新后需等待内容重新加载 |
| 网络请求 | 加载指示器（loading spinner） | 需等待 loading 消失再验证结果 |

**登录失败重试示例：**
```
1. ui.input(username="test", password="wrong")
2. ui.tap(登录按钮)
3. ui.wait(textExists="用户名或密码错误")
4. ui.input(username="test", password="123456")  ← 密码已被清空，需重新输入完整密码
5. ui.tap(登录按钮)
```

**反模式：** 登录失败后只清空密码框再输入新密码，导致用户名也丢失。

**正确做法：** 失败后重新输入完整的用户名和密码。

## 最佳实践

1. **优先使用此 skill 作为入口**，让我自动路由到专业 skill
2. **真机测试前先检查连接状态**，确保 iproxy 正确运行
3. **模拟器残留问题**：定期检查 `lsof -iTCP:38321`，清理残留进程
4. **DEBUG 自动启动服务**：SPMExample 在 DEBUG 环境下于 `viewDidAppear` 自动调用 `server.start()`，无需 `IOS_EXPLORE_AUTOSTART` 等环境变量（该旧变量已废弃，不再被读取）
5. **保留截图证据**：关键操作前后截图，便于排查问题
6. **使用 ui.wait 等待动态内容**：页面跳转、加载、动画后需等待 UI 稳定
7. **理解 iOS 标准行为**：登录失败清空密码、键盘弹出滚动等是正常行为，不是 Bug

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
**测试覆盖率**：库整体覆盖率见 `swift test --enable-code-coverage`（当前约 86.6%）；本 skill 自身的端到端场景数以仓库根 `docs/skills-test-report.json` 为准（待核实，勿沿用旧文的"96.3%/200+"等无源数字）
**MCP 服务**：XcodeBuildMCP + iOSDriver
