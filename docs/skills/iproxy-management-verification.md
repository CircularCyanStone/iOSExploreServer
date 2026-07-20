# iproxy 管理方案验证报告

## 执行时间
2026-07-20

## 方案概述

已完成 iproxy 转发配置优化，通过在 `ios-automation` skill 中嵌入管理脚本，实现模拟器/真机切换的规范化流程管理。

## 核心结论

**MCP 配置无需修改**。当前的单一 `localhost:38321` 配置是最优方案，因为：

1. **对 MCP Server 来说，目标永远是 `localhost:38321`**
   - 模拟器：MCP → localhost:38321 → 模拟器 App
   - 真机：MCP → localhost:38321 → iproxy → USB → 真机 App
   
2. **iproxy 是透明的路由层**，MCP Server 不需要感知背后是模拟器直连还是 USB 转发

3. **真正的问题是操作流程规范化**，不是技术架构问题

## 已完成的工作

### 1. 创建 iproxy 管理脚本

**位置**：`.claude/skills/ios-automation/scripts/iproxy-manager.sh`

**功能**：
- ✅ 一键安装 iproxy（通过 Homebrew）
- ✅ 启动/停止/重启 iproxy（后台运行）
- ✅ 自动检测并清理模拟器 App 残留
- ✅ 自动获取 USB 设备 UDID
- ✅ 智能诊断（端口占用、设备连接、服务可用性）
- ✅ 彩色输出 + 具体修复建议
- ✅ 快速 ping 验证

**命令列表**：
- `install` — 安装 iproxy
- `start` — 启动 iproxy
- `stop` — 停止 iproxy
- `restart` — 重启 iproxy（自动清理冲突）
- `status` — 详细诊断
- `clean` — 清理模拟器残留
- `check` — 快速 ping 验证

### 2. 更新 ios-automation skill 文档

**文件**：`.claude/skills/ios-automation/SKILL.md`

**更新内容**：
- ✅ 新增「iproxy 管理脚本」章节，包含命令速查表
- ✅ 新增「真机测试标准流程（30 秒）」
- ✅ 简化「常见错误与判别」，改为一键修复流程
- ✅ 简化「端口冲突排查」，改为一键诊断
- ✅ 添加命令别名建议（`alias ipm=...`）

### 3. 创建快速参考文档

**文件**：`.claude/skills/ios-automation/scripts/README.md`

**内容**：
- 快速开始指南
- 命令速查表
- 典型场景处理（端口占用、返回旧数据、连接失败）
- 高级用法（别名、自定义端口、查看日志）
- 与旧脚本的对比
- 故障排查
- 工作原理说明

## 方案对比

### 方案 A：当前方案（已采用）

**实现**：单一 MCP 配置 + skill 内嵌管理脚本

**优点**：
- ✅ 不需要改 MCP Server 代码
- ✅ 不需要改 MCP 配置
- ✅ URL 统一（localhost:38321），心智模型简单
- ✅ 通过 skill 规范化操作流程
- ✅ 一键命令处理常见问题

**缺点**：
- ⚠️ 需要手动切换（但已简化为一键命令）

### 方案 B：多端口隔离（未采用）

**实现**：两个 MCP Server 实例（sim:38321 / device:38322）

**缺点**：
- ❌ 浪费资源（两个 MCP Server）
- ❌ skill 文档需区分两套工具前缀
- ❌ 用户需记住用哪个 server

### 方案 C：动态 URL 切换（未采用）

**实现**：MCP Server 增加 `switch_target` 工具

**缺点**：
- ❌ 需改 MCP Server 代码
- ❌ iproxy 仍需手动启动
- ❌ 实际价值不大

### 方案 D：智能探测（未采用）

**实现**：MCP Server 自动探测模拟器/真机

**缺点**：
- ❌ **对 MCP Server 来说，URL 都是 localhost:38321，探测到也做不了什么**
- ❌ 不能自动启动 iproxy（需要 USB UDID 和权限）
- ❌ 只是增加复杂度，没有实际收益

## 使用示例

### 模拟器测试

```bash
# 不需要 iproxy，直接启动 App 即可
# MCP 会自动连接到 localhost:38321
```

### 真机测试

```bash
# 1. 启动 iproxy
./.claude/skills/ios-automation/scripts/iproxy-manager.sh start

# 2. 验证连接
./.claude/skills/ios-automation/scripts/iproxy-manager.sh check

# 3. 开始测试
# MCP 连接到 localhost:38321 → iproxy 自动转发到真机
```

### 遇到端口冲突

```bash
# 一键修复
./.claude/skills/ios-automation/scripts/iproxy-manager.sh restart
```

## 验证结果

### 脚本功能验证

- ✅ 脚本可执行（已添加执行权限）
- ✅ 帮助信息正常显示
- ✅ 状态检查功能正常
- ✅ 彩色输出正常
- ✅ 错误提示清晰

### 文档完整性验证

- ✅ skill 文档已更新，包含完整的 iproxy 管理流程
- ✅ 快速参考文档已创建
- ✅ 命令示例已测试
- ✅ 路径已修正（从 `~/.claude/skills/` 改为 `./.claude/skills/`）

## 用户体验改进

### 改进前

```bash
# 真机测试需要 5-6 步手动操作
lsof -iTCP:38321
xcrun simctl terminate <sim-id> <bundle-id>
./scripts/proxy.sh --stop
./scripts/proxy.sh --daemon
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
# 容易出错，需记忆多个命令
```

### 改进后

```bash
# 真机测试只需 2 步
./.claude/skills/ios-automation/scripts/iproxy-manager.sh start
./.claude/skills/ios-automation/scripts/iproxy-manager.sh check
# 一键命令，自动处理冲突
```

### 遇到问题时

**改进前**：需手动诊断 → 查文档 → 执行 4-5 个命令

**改进后**：一条命令搞定
```bash
./.claude/skills/ios-automation/scripts/iproxy-manager.sh restart
```

## 建议的后续优化

### 1. 创建命令别名（可选）

在 `~/.zshrc` 中添加：
```bash
alias ipm='/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/.claude/skills/ios-automation/scripts/iproxy-manager.sh'
```

使用：
```bash
ipm start    # 启动
ipm status   # 诊断
ipm restart  # 重启
```

### 2. 与 XcodeBuildMCP 集成（未来）

可以在 XcodeBuildMCP 的 `build_run_device` 前自动检查 iproxy 状态，但当前方案已足够简单。

### 3. CI/CD 集成（未来）

如果需要在 CI 环境中运行真机测试，可以：
- 在 CI 脚本中自动调用 `iproxy-manager.sh start`
- 测试完成后调用 `iproxy-manager.sh stop`

## 总结

**方案 A（当前方案）是最优解**：

1. **MCP 配置不需要改** — 单一 `localhost:38321` 配置适用于模拟器和真机
2. **iproxy 管理通过 skill 规范化** — 一键命令处理安装、启动、诊断、清理
3. **用户体验大幅提升** — 从 5-6 步手动操作简化为 2 步一键命令
4. **自动处理常见问题** — 端口冲突、残留进程、设备检测全部自动化

关键洞察：**iproxy 是透明的路由层，MCP Server 不需要感知它的存在**。真正需要的是操作流程的规范化，而不是技术架构的调整。
