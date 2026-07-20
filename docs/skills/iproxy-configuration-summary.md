# iproxy 配置方案总结

## 问题背景

**原始问题**："iproxy 到底要怎么办？有时候需要转发到真机上，有时候是在模拟器上。"

用户担心的核心问题：
1. MCP Server 配置是否需要区分模拟器/真机
2. iproxy 如何在两种场景下管理
3. 端口冲突如何避免

## 核心结论

**MCP 配置无需修改，通过 skill 规范化操作流程即可。**

### 关键洞察

对 MCP Server 来说，**目标永远是 `localhost:38321`**：

```
模拟器：MCP → localhost:38321 → 模拟器 App
真机：  MCP → localhost:38321 → iproxy → USB → 真机 App
```

iproxy 是**透明的路由层**，MCP Server 看不到、也不需要看到它的存在。

## 最终方案

### 1. MCP 配置（保持不变）

```json
{
  "mcpServers": {
    "iOSDriver": {
      "command": "node",
      "args": ["/path/to/iOSDriver/dist/index.js"],
      "env": {
        "IOS_EXPLORE_BASE_URL": "http://localhost:38321/"
      }
    }
  }
}
```

### 2. skill 内嵌管理脚本

**位置**：`.claude/skills/ios-automation/scripts/iproxy-manager.sh`

**功能**：
- 一键安装 iproxy
- 启动/停止/重启 iproxy
- 自动清理模拟器残留
- 智能诊断 + 彩色输出

### 3. 标准操作流程

#### 模拟器测试
```bash
# 不需要 iproxy，直接启动 App
# MCP 自动连接到 localhost:38321
```

#### 真机测试
```bash
# 1. 启动 iproxy（自动获取设备 UDID）
./.claude/skills/ios-automation/scripts/iproxy-manager.sh start

# 2. 验证连接
./.claude/skills/ios-automation/scripts/iproxy-manager.sh check

# 3. 开始测试
```

#### 遇到端口冲突
```bash
# 一键修复（自动清理 + 重启）
./.claude/skills/ios-automation/scripts/iproxy-manager.sh restart
```

## 为什么不采用其他方案

### 方案 B：多端口隔离 ❌

**实现**：两个 MCP Server（sim:38321 / device:38322）

**问题**：
- 浪费资源（两个 MCP Server 实例）
- skill 文档需区分两套工具
- 用户需记住用哪个 server

### 方案 C：动态 URL 切换 ❌

**实现**：MCP Server 增加 `switch_target` 工具

**问题**：
- 需改 MCP Server 代码
- iproxy 仍需手动启动
- 实际价值不大

### 方案 D：智能探测 ❌

**实现**：MCP Server 自动探测模拟器/真机

**致命缺陷**：
- **URL 都是 localhost:38321，探测到也做不了什么**
- 不能自动启动 iproxy（需要 UDID + 权限）
- 只是增加复杂度，没有实际收益

## 用户体验改进

### 改进前（5-6 步手动操作）

```bash
# 排查端口占用
lsof -iTCP:38321

# 清理模拟器残留
xcrun simctl terminate <sim-id> <bundle-id>

# 停止旧 iproxy
./scripts/proxy.sh --stop

# 启动新 iproxy
./scripts/proxy.sh --daemon

# 验证连接
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
```

### 改进后（2 步一键命令）

```bash
# 启动
./.claude/skills/ios-automation/scripts/iproxy-manager.sh start

# 验证
./.claude/skills/ios-automation/scripts/iproxy-manager.sh check
```

### 遇到问题时（1 步搞定）

```bash
# 万能修复
./.claude/skills/ios-automation/scripts/iproxy-manager.sh restart
```

## 已完成的工作

### 1. 创建管理脚本
- ✅ `.claude/skills/ios-automation/scripts/iproxy-manager.sh`
- ✅ 7 个命令（install/start/stop/restart/status/clean/check）
- ✅ 自动清理、智能诊断、彩色输出

### 2. 更新 skill 文档
- ✅ `.claude/skills/ios-automation/SKILL.md`
- ✅ 新增「iproxy 管理脚本」章节
- ✅ 简化「真机测试标准流程」
- ✅ 简化「常见错误与判别」

### 3. 创建快速参考
- ✅ `.claude/skills/ios-automation/scripts/README.md`
- ✅ 命令速查表、典型场景、故障排查

### 4. 创建验证报告
- ✅ `docs/skills/iproxy-management-verification.md`
- ✅ 方案对比、使用示例、用户体验改进

## 推荐的后续优化

### 创建命令别名（可选）

在 `~/.zshrc` 中添加：

```bash
alias ipm='/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/.claude/skills/ios-automation/scripts/iproxy-manager.sh'
```

使用：
```bash
ipm start    # 启动 iproxy
ipm status   # 详细诊断
ipm restart  # 重启
ipm check    # 快速验证
```

## 核心原则

1. **MCP 配置统一** — 单一 `localhost:38321`，适用于模拟器和真机
2. **iproxy 是透明的** — MCP Server 不需要感知路由细节
3. **流程规范化** — 通过 skill 脚本简化操作
4. **自动化优先** — 一键命令处理常见问题

## 关键文件

| 文件 | 说明 |
|---|---|
| `.claude/skills/ios-automation/SKILL.md` | skill 主文档（已更新） |
| `.claude/skills/ios-automation/scripts/iproxy-manager.sh` | 管理脚本（新增） |
| `.claude/skills/ios-automation/scripts/README.md` | 快速参考（新增） |
| `docs/skills/iproxy-management-verification.md` | 验证报告（新增） |
| `.mcp.json` | MCP 配置（无需修改） |

## 总结

✅ **方案确定**：保持当前 MCP 配置，通过 skill 规范化流程  
✅ **脚本完成**：一键安装、启动、诊断、修复  
✅ **文档完成**：skill 文档、快速参考、验证报告  
✅ **用户体验**：从 5-6 步简化为 1-2 步  

**核心价值**：把"技术问题"转化为"流程问题"，通过自动化脚本降低操作复杂度，而不是调整技术架构。
