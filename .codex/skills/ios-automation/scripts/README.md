# iproxy 管理脚本快速参考

## 概述

`iproxy-manager.sh` 是 ios-automation skill 的配套工具，用于管理真机测试时的 USB 端口转发。

## 核心优势

- ✅ **一键安装** — 自动通过 Homebrew 安装 libimobiledevice
- ✅ **自动清理** — 检测并清理模拟器 App 残留进程
- ✅ **自动获取 UDID** — 无需手动输入设备标识符
- ✅ **智能诊断** — 彩色输出 + 具体修复建议

## 快速开始

### 首次使用（安装 iproxy）

```bash
cd /Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer
./.claude/skills/ios-automation/scripts/iproxy-manager.sh install
```

### 测试真机前的标准流程

```bash
# 1. 启动 iproxy
./.claude/skills/ios-automation/scripts/iproxy-manager.sh start

# 2. 验证连接
./.claude/skills/ios-automation/scripts/iproxy-manager.sh check

# 3. 如果连接失败，查看详细诊断
./.claude/skills/ios-automation/scripts/iproxy-manager.sh status
```

### 遇到问题时

```bash
# 万能修复：重启 iproxy（自动清理冲突）
./.claude/skills/ios-automation/scripts/iproxy-manager.sh restart
```

## 命令速查表

| 命令 | 说明 | 使用时机 |
|---|---|---|
| `install` | 安装 iproxy | 首次使用或 iproxy 未安装 |
| `start` | 启动 iproxy（后台） | 每次测试真机前 |
| `stop` | 停止 iproxy | 切换到模拟器测试 |
| `restart` | 重启 iproxy | 端口冲突或连接异常（推荐） |
| `status` | 详细状态诊断 | 连接失败时查原因 |
| `clean` | 清理模拟器残留 | 手动处理端口冲突 |
| `check` | 快速 ping 验证 | 验证连接正常 |

## 典型场景

### 场景 1：端口被占用

**现象**：启动 iproxy 报错 `Address already in use: 38321`

**解决**：
```bash
./.claude/skills/ios-automation/scripts/iproxy-manager.sh restart
```

脚本会自动：
1. 检测占用进程（iproxy / 模拟器 App）
2. 清理残留进程
3. 重新启动 iproxy
4. 验证连接

### 场景 2：真机返回模拟器数据

**现象**：curl 连接成功，但返回的是旧版本 App 的数据

**原因**：模拟器 App 残留占用了 38321 端口

**解决**：
```bash
./.claude/skills/ios-automation/scripts/iproxy-manager.sh restart
```

### 场景 3：连接失败

**现象**：`curl: (7) Failed to connect to localhost port 38321`

**诊断**：
```bash
./.claude/skills/ios-automation/scripts/iproxy-manager.sh status
```

输出示例：
```
❌ 端口 38321 未被监听

可能原因：
  1. iOS App 未启动
  2. 真机需要先启动 iproxy: ... start
  3. App 中的 server.start() 未调用
```

**解决步骤**：
1. 确认设备已通过 USB 连接
2. 启动 iproxy：`./.claude/skills/ios-automation/scripts/iproxy-manager.sh start`
3. 启动 iOS App（XcodeBuildMCP 的 `launch_app_device`）
4. 验证：`./.claude/skills/ios-automation/scripts/iproxy-manager.sh check`

## 高级用法

### 创建命令别名（推荐）

在 `~/.zshrc` 或 `~/.bashrc` 中添加：

```bash
alias ipm='/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/.claude/skills/ios-automation/scripts/iproxy-manager.sh'
```

重新加载配置：
```bash
source ~/.zshrc  # 或 source ~/.bashrc
```

使用别名：
```bash
ipm status    # 检查状态
ipm start     # 启动 iproxy
ipm restart   # 重启
ipm check     # 快速验证
```

### 自定义端口

默认端口是 38321，如需修改：

```bash
PORT=38322 ./.claude/skills/ios-automation/scripts/iproxy-manager.sh start
```

### 查看日志

iproxy 后台运行时的日志文件：

```bash
# 日志位置
cat /tmp/iproxy-38321.log

# 实时查看日志
tail -f /tmp/iproxy-38321.log
```

## 与旧脚本的对比

| 功能 | 旧脚本 (`scripts/proxy.sh`) | 新脚本 (`iproxy-manager.sh`) |
|---|---|---|
| 安装 iproxy | ❌ 手动安装 | ✅ 一键安装 |
| 启动/停止 | ✅ | ✅ |
| 状态检查 | ⚠️ 基础检查 | ✅ 详细诊断 + 修复建议 |
| 清理残留 | ✅ | ✅ 自动检测并清理 |
| 快速验证 | ❌ | ✅ `check` 命令 |
| 彩色输出 | ❌ | ✅ |
| 错误提示 | ⚠️ 简单 | ✅ 具体操作建议 |

**兼容性**：两个脚本功能互补，可以共存。推荐新用户使用 `iproxy-manager.sh`。

## 故障排查

### 问题：iproxy 安装失败

**可能原因**：Homebrew 未安装或网络问题

**解决**：
1. 确认 Homebrew 已安装：`brew --version`
2. 如未安装，访问 https://brew.sh 安装
3. 手动安装：`brew install libimobiledevice`

### 问题：检测不到设备

**现象**：`未检测到 USB 连接的设备`

**解决**：
1. 确认设备已通过 USB 连接到 Mac
2. 确认设备已解锁
3. 确认设备已"信任此电脑"（首次连接会弹窗）
4. 重新插拔 USB 线
5. 验证：`idevice_id -l`（应输出设备 UDID）

### 问题：脚本权限不足

**现象**：`Permission denied`

**解决**：
```bash
chmod +x ./.claude/skills/ios-automation/scripts/iproxy-manager.sh
```

## 工作原理

### 端口转发原理

```
Mac curl → localhost:38321 → iproxy → USB → 真机 App:38321
```

- **模拟器**：Mac 与模拟器共享 localhost，直接连接，不需要 iproxy
- **真机**：真机端口不暴露给 Mac，必须通过 iproxy USB 转发

### 自动清理机制

脚本启动时会自动：
1. 检查端口 38321 占用情况（`lsof`）
2. 如果是模拟器 App 占用：
   - 对所有 Booted 模拟器执行 `simctl terminate`
   - 等待端口释放（最多 4.5 秒）
   - 如果仍占用，兜底 `kill` 残留进程
3. 如果是 iproxy 占用：提示用户先 `stop`
4. 端口空闲后才启动新 iproxy

## 相关文档

- [ios-automation SKILL.md](../SKILL.md) — 完整使用指南
- [AGENTS.md](../../../../AGENTS.md) — 项目整体架构
- [scripts/proxy.sh](../../../../scripts/proxy.sh) — 旧版脚本（兼容）

## 贡献

脚本位置：`.claude/skills/ios-automation/scripts/iproxy-manager.sh`

改进建议请在项目 issue 中提出。
