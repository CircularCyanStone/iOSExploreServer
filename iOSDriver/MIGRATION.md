# 从 MCPServer 迁移到 iOSDriver

## 变更概述

**日期**: 2026-07-14  
**原因**: 品牌升级，准备投入生产使用

iOSDriver 是 MCPServer 的正式品牌名称，功能完全兼容，只是名称变更。

## 变更内容

### 1. 目录名称
```
MCPServer/ → iOSDriver/
```

### 2. MCP 服务器配置

**旧配置** (`~/.claude/config.json`):
```json
{
  "mcpServers": {
    "MCPServer": {
      "command": "node",
      "args": ["/path/to/MCPServer/dist/index.js"]
    }
  }
}
```

**新配置** (`~/.claude/config.json`):
```json
{
  "mcpServers": {
    "iOSDriver": {
      "command": "node",
      "args": ["/path/to/iOSDriver/dist/index.js"],
      "description": "iOS App automation driver server"
    }
  }
}
```

### 3. 文档引用

所有文档中的 "MCPServer" 已更新为 "iOSDriver"，包括：
- README.md
- 技术文档 (docs/)
- Skills 描述 (.claude/skills/)
- 测试报告 (reports/)

### 4. Skills 前置条件

**旧描述**:
```markdown
- iOSExploreServer MCP 已连接
```

**新描述**:
```markdown
- iOSDriver MCP Server 已连接
```

## 迁移步骤

### 步骤 1: 更新 MCP 配置

1. 打开 MCP 配置文件:
   ```bash
   # macOS
   code ~/.claude/config.json
   ```

2. 将 `"MCPServer"` 改为 `"iOSDriver"`

3. 更新 `args` 中的路径 (如果使用绝对路径):
   ```json
   "args": ["/path/to/iOSDriver/dist/index.js"]
   ```

### 步骤 2: 重新构建 (可选)

如果你有本地修改，重新构建：
```bash
cd iOSDriver
npm install
npm run build
```

### 步骤 3: 重启 Claude Code

1. 完全退出 Claude Code
2. 重新启动 Claude Code
3. 验证 MCP 连接状态 (应该显示 "iOSDriver")

### 步骤 4: 验证功能

测试基本连接:
```bash
# 确保示例 App 正在运行
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
```

预期响应:
```json
{
  "code": "ok",
  "data": {
    "pong": true
  }
}
```

## 向后兼容

### 完全兼容的部分
- ✅ 所有 HTTP 命令和 API
- ✅ 所有 MCP 工具定义
- ✅ 所有 Skills 功能
- ✅ 配置格式和选项
- ✅ 示例 App 集成

### 需要手动更新的部分
- ⚠️ MCP 配置文件中的服务器名称
- ⚠️ 自定义脚本中的目录路径引用
- ⚠️ 文档中的项目名称引用

## 常见问题

### Q: 是否需要重新安装依赖？
A: 不需要。如果你已经有 `node_modules/` 和 `dist/`，可以直接使用。

### Q: 旧的 MCPServer 配置会自动失效吗？
A: 是的。如果你的配置中仍然使用 `"MCPServer"`，Claude Code 会找不到对应的目录。需要手动更新为 `"iOSDriver"`。

### Q: Skills 会自动更新吗？
A: Skills 文件已经在项目中更新。重启 Claude Code 后，新的描述会自动生效。

### Q: 如何验证迁移成功？
A: 在 Claude Code 中输入 `/mcp`，应该看到 "iOSDriver" 而不是 "MCPServer"。

### Q: 可以同时保留两个配置吗？
A: 可以，但没有必要。两个配置会指向同一个实现，只是名称不同。

## 回滚方案

如果需要回滚到旧名称 (不推荐):

```bash
# 重命名目录
git mv iOSDriver MCPServer

# 恢复文档中的引用
find . -type f -name "*.md" -o -name "*.json" | \
  xargs sed -i '' 's/iOSDriver/MCPServer/g'

# 重新提交
git add .
git commit -m "Revert to MCPServer naming"
```

## 技术支持

如果迁移过程中遇到问题：

1. 检查 MCP 配置文件路径是否正确
2. 验证 `dist/index.js` 文件是否存在
3. 查看 Claude Code 的 MCP 连接日志
4. 确认示例 App 是否正在运行且端口 38321 可访问

## 相关文档

- [BRANDING.md](BRANDING.md) - 品牌定位和产品介绍
- [README.md](README.md) - 项目概述
- [docs/](docs/) - 完整技术文档
