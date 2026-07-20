# iOSDriver 正式发布指南

## 📦 发布到 npm

### 前置条件

- npm 账号（https://www.npmjs.com/signup）
- 已登录：`npm login`

### 发布步骤

```bash
cd iOSDriver

# 1. 确保代码最新
git pull origin main

# 2. 构建
npm run build

# 3. 运行测试
npm test

# 4. 检查打包内容
npm pack --dry-run
# 确认只包含 dist/ 和 README.md

# 5. 发布（首次需要 --access public）
npm publish --access public

# 6. 验证发布
npm view @ios-explore/mcp-server
```

### 发布后验证

```bash
# 在另一个目录测试安装
cd /tmp
npm install -g @ios-explore/mcp-server

# 测试命令
which ios-explore-mcp-server
ios-explore-mcp-server --help

# 清理
npm uninstall -g @ios-explore/mcp-server
```

## 🔄 版本更新

### Bug 修复（1.0.0 → 1.0.1）

```bash
npm version patch
npm publish
git push --tags
```

### 新功能（1.0.0 → 1.1.0）

```bash
npm version minor
npm publish
git push --tags
```

### 破坏性变更（1.0.0 → 2.0.0）

```bash
npm version major
npm publish
git push --tags
```

## 📋 用户安装指南

发布后，用户安装：

### 1. 安装 MCP Server

```bash
npm install -g @ios-explore/mcp-server
```

### 2. 配置 Claude Code

创建或编辑 `~/.claude/.mcp.json`：

```json
{
  "mcpServers": {
    "iOSDriver": {
      "command": "ios-explore-mcp-server",
      "env": {
        "IOS_EXPLORE_BASE_URL": "http://localhost:38321/"
      }
    }
  }
}
```

### 3. 重启 Claude Code

配置生效后，在 Claude Code 中可以使用所有 MCP tools。

## 🔧 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `IOS_EXPLORE_BASE_URL` | `http://localhost:38321/` | iOSExploreServer HTTP 端点 |
| `IOS_EXPLORE_REQUEST_TIMEOUT_MS` | `10000` | 请求超时（毫秒） |

## 📚 相关文档

- npm 包地址：https://www.npmjs.com/package/@ios-explore/mcp-server
- GitHub 仓库：https://github.com/coocssweb/iOSExploreServer/tree/main/iOSDriver
- MCP 官方文档：https://modelcontextprotocol.io

## ⚠️ 注意事项

### 发布前检查

- [ ] 所有测试通过（`npm test`）
- [ ] shebang 存在（`head -1 dist/index.js`）
- [ ] package.json 元数据完整
- [ ] README.md 更新
- [ ] CHANGELOG.md 更新（如果有）

### 发布后

- [ ] 验证 npm 页面显示正确
- [ ] 测试全局安装
- [ ] 更新项目 README 中的安装说明
- [ ] 标记 Git tag

## 🆘 故障排查

### 发布失败：需要登录

```bash
npm login
# 输入用户名、密码、邮箱
```

### 发布失败：包名已存在

检查包名是否被占用：
```bash
npm view @ios-explore/mcp-server
```

如果被占用，修改 package.json 的 `name` 字段。

### 发布失败：权限不足

确保使用 `--access public` 发布 scoped package：
```bash
npm publish --access public
```

### 用户安装后命令不可用

检查：
1. 全局安装路径：`npm config get prefix`
2. PATH 包含该路径：`echo $PATH`
3. 命令存在：`ls $(npm config get prefix)/bin/ios-explore-mcp-server`
