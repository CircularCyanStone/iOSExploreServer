# iproxy 配置方案 - 最终完成报告

## 完成时间
2026-07-20

## 问题回顾

**原始问题**："iproxy 到底要怎么办？有时候需要转发到真机上，有时候是在模拟器上。"

## 核心结论

**MCP 配置无需修改。** 通过在 `ios-automation` skill 中嵌入管理脚本，规范化操作流程。

### 关键洞察

对 MCP Server 来说，目标永远是 `localhost:38321`：
- 模拟器：MCP → localhost:38321 → 模拟器 App（直连）
- 真机：MCP → localhost:38321 → iproxy → USB → 真机 App（转发）

**iproxy 是透明的路由层**，MCP Server 不需要感知它的存在。

## 已完成的工作

### 1. 创建 iproxy 管理脚本

**位置**：`.claude/skills/ios-automation/scripts/iproxy-manager.sh`

**功能**：
- ✅ `install` — 一键安装 iproxy（通过 Homebrew）
- ✅ `start` — 启动 iproxy（自动获取设备 UDID）
- ✅ `stop` — 停止 iproxy
- ✅ `restart` — 重启 iproxy（自动清理端口冲突）
- ✅ `status` — 详细诊断（端口占用、设备连接、服务可用性）
- ✅ `clean` — 清理模拟器 App 残留
- ✅ `check` — 快速 ping 验证

**特性**：
- 自动检测并清理模拟器 App 残留进程
- 自动获取 USB 设备 UDID
- 彩色输出 + 具体修复建议
- 一键命令解决端口冲突

### 2. 更新 skill 文档

**文件**：`.claude/skills/ios-automation/SKILL.md`

**改进**：
- ✅ 新增「iproxy 管理脚本」章节
- ✅ 简化真机测试流程（从 5-6 步变为 2 步）
- ✅ 简化常见错误处理（从手动诊断变为一键修复）
- ✅ 简化端口冲突排查（从逐步执行变为一键诊断）
- ✅ 移除硬编码路径和项目特定说明

### 3. 创建快速参考文档

**文件**：`.claude/skills/ios-automation/scripts/README.md`

**内容**：
- 快速开始指南
- 命令速查表
- 典型场景处理（端口占用、返回旧数据、连接失败）
- 高级用法（自定义端口、查看日志）
- 与旧脚本的对比
- 故障排查指南
- 工作原理说明

### 4. 创建验证文档

**文件**：
- `docs/skills/iproxy-management-verification.md` — 方案对比、使用示例
- `docs/skills/iproxy-configuration-summary.md` — 总结文档

## 使用方式

### Agent 执行（自动）

当用户通过 `ios-automation` skill 测试真机时，Agent 会自动：
1. 检查 iproxy 是否已安装
2. 启动 iproxy
3. 验证连接
4. 出现问题时自动诊断

### 用户手动执行

**测试模拟器**：
```bash
# 不需要 iproxy，直接启动 App
```

**测试真机**：
```bash
# 从项目根目录执行
./.claude/skills/ios-automation/scripts/iproxy-manager.sh start
./.claude/skills/ios-automation/scripts/iproxy-manager.sh check
```

**端口冲突时**：
```bash
./.claude/skills/ios-automation/scripts/iproxy-manager.sh restart
```

## 用户体验改进

### 改进前（5-6 步手动操作）
```bash
lsof -iTCP:38321
xcrun simctl terminate <sim-id> <bundle-id>
./scripts/proxy.sh --stop
./scripts/proxy.sh --daemon
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
```

### 改进后（2 步一键命令）
```bash
./.claude/skills/ios-automation/scripts/iproxy-manager.sh start
./.claude/skills/ios-automation/scripts/iproxy-manager.sh check
```

### 遇到问题时（1 步搞定）
```bash
./.claude/skills/ios-automation/scripts/iproxy-manager.sh restart
```

## 验证结果

### 脚本功能
- ✅ 脚本可执行（已添加执行权限）
- ✅ 帮助信息正常显示
- ✅ 状态检查功能正常
- ✅ 彩色输出正常
- ✅ 错误提示清晰

### 文档完整性
- ✅ skill 文档已更新
- ✅ 快速参考文档已创建
- ✅ 验证报告已创建
- ✅ 已移除硬编码路径
- ✅ 已移除项目特定说明

### 可移植性
- ✅ 脚本位于 skill 内部（`.claude/skills/ios-automation/scripts/`）
- ✅ 使用相对路径（`./.claude/skills/ios-automation/scripts/iproxy-manager.sh`）
- ✅ 适用于项目级和用户级 skill
- ✅ 不依赖特定项目路径

## MCP 配置（无需修改）

`.mcp.json` 保持不变：
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

## 关键文件清单

| 文件 | 说明 | 状态 |
|---|---|---|
| `.claude/skills/ios-automation/SKILL.md` | skill 主文档 | ✅ 已更新 |
| `.claude/skills/ios-automation/scripts/iproxy-manager.sh` | 管理脚本 | ✅ 已创建 |
| `.claude/skills/ios-automation/scripts/README.md` | 快速参考 | ✅ 已创建 |
| `docs/skills/iproxy-management-verification.md` | 验证报告 | ✅ 已创建 |
| `docs/skills/iproxy-configuration-summary.md` | 总结文档 | ✅ 已创建 |
| `.mcp.json` | MCP 配置 | ✅ 无需修改 |

## 方案优势

1. **无需改动 MCP 配置** — 单一配置适用于所有场景
2. **操作简化** — 从 5-6 步简化为 1-2 步
3. **自动化处理** — 端口冲突、残留进程、设备检测全自动
4. **可移植性强** — skill 内嵌脚本，适用于任何项目
5. **用户友好** — 彩色输出 + 具体修复建议

## 核心价值

把"技术架构问题"转化为"操作流程问题"：
- 不需要改 MCP Server 代码
- 不需要改 MCP 配置
- 不需要多套工具前缀
- 只需要规范化的操作流程 + 自动化脚本

## 任务完成

✅ **问题分析** — 确认 MCP 配置无需修改  
✅ **脚本开发** — 完成 iproxy 管理脚本（7 个命令）  
✅ **文档更新** — 更新 skill 文档，移除硬编码路径  
✅ **快速参考** — 创建使用手册  
✅ **验证测试** — 确认脚本可执行、文档可移植  

方案已完成并可以投入使用。
