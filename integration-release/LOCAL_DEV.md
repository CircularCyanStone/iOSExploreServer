# iOSDriver 本地开发与调试

## 🔧 本地开发环境

### 前置条件

- Node.js >= 20.0.0
- npm >= 9.0.0

### 安装依赖

```bash
cd iOSDriver
npm install
```

## 🚀 本地运行方式

### 方式 1：开发模式（推荐）

直接运行 TypeScript 源码，支持热重载：

```bash
npm run dev
```

### 方式 2：构建后运行

编译后运行 JavaScript：

```bash
npm run build
node dist/index.js
```

### 方式 3：本地全局链接

模拟全局安装，用于测试：

```bash
# 创建全局链接
npm link

# 现在可以全局使用命令
ios-explore-mcp-server

# 测试完成后取消链接
npm unlink -g @ios-explore/mcp-server
```

## 🧪 测试

### 运行所有测试

```bash
npm test
```

### 监视模式（开发时使用）

```bash
npm run test:watch
```

### 类型检查

```bash
npm run typecheck
```

## 🔗 配置 Claude Code 使用本地版本

### 方式 1：使用 npm link（推荐）

```bash
cd iOSDriver
npm link
```

然后在 `~/.claude/.mcp.json` 中：

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

### 方式 2：直接指向本地路径

在 `~/.claude/.mcp.json` 中：

```json
{
  "mcpServers": {
    "iOSDriver": {
      "command": "node",
      "args": ["/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/iOSDriver/dist/index.js"],
      "env": {
        "IOS_EXPLORE_BASE_URL": "http://localhost:38321/"
      }
    }
  }
}
```

### 方式 3：使用 tsx 直接运行源码

在 `~/.claude/.mcp.json` 中：

```json
{
  "mcpServers": {
    "iOSDriver": {
      "command": "npx",
      "args": ["tsx", "/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/iOSDriver/src/index.ts"],
      "env": {
        "IOS_EXPLORE_BASE_URL": "http://localhost:38321/"
      }
    }
  }
}
```

## 🐛 调试

### 启用调试日志

```bash
# 设置环境变量
export DEBUG=mcp:*
npm run dev
```

### 使用 Node.js Inspector

```bash
node --inspect dist/index.js
```

然后在 Chrome 中打开 `chrome://inspect`。

### 查看 MCP 通信日志

Claude Code 的 MCP 日志通常在：
- macOS: `~/Library/Logs/Claude/`
- Windows: `%APPDATA%\Claude\logs\`

## 📝 开发工作流

### 1. 修改代码

编辑 `src/` 下的 TypeScript 文件。

### 2. 运行测试

```bash
npm test
```

### 3. 类型检查

```bash
npm run typecheck
```

### 4. 构建

```bash
npm run build
```

### 5. 本地测试

```bash
npm link
# 在 Claude Code 中测试

# 或手动测试
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | ios-explore-mcp-server
```

### 6. 取消链接

```bash
npm unlink -g @ios-explore/mcp-server
```

## 🔍 常见问题

### Q: npm link 后命令不可用

检查：
```bash
which ios-explore-mcp-server
ls -la $(npm config get prefix)/bin/ios-explore-mcp-server
```

解决：
```bash
npm unlink -g @ios-explore/mcp-server
npm link
```

### Q: 修改代码后不生效

方式 1 的用户需要重新构建：
```bash
npm run build
```

方式 3 的用户（使用 tsx）会自动生效。

### Q: Claude Code 连接 MCP 失败

检查：
1. MCP 命令是否可执行：`ios-explore-mcp-server`
2. 配置文件语法：`cat ~/.claude/.mcp.json | jq`
3. 重启 Claude Code

### Q: 测试失败

确保依赖最新：
```bash
npm install
npm run build
npm test
```

## 🔄 从本地切换到发布版本

### 取消本地链接

```bash
npm unlink -g @ios-explore/mcp-server
```

### 安装发布版本

```bash
npm install -g @ios-explore/mcp-server
```

### 更新 Claude Code 配置

改回使用命令名：
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

## 📦 打包测试

模拟 npm publish，查看会发布哪些文件：

```bash
npm pack --dry-run
```

实际打包（生成 .tgz 文件）：

```bash
npm pack
```

从 .tgz 安装测试：

```bash
npm install -g ./ios-explore-mcp-server-1.0.0.tgz
```

## 🎯 推荐开发流程

日常开发使用 **方式 1（npm link）**：

```bash
# 初始化（只需一次）
cd iOSDriver
npm install
npm link

# 修改代码后
npm run build   # 重新构建
# Claude Code 会自动使用新版本

# 开发完成
npm unlink -g @ios-explore/mcp-server
```

快速迭代使用 **方式 3（tsx）**：

- 修改代码即时生效，无需构建
- 适合快速调试
- 重启 Claude Code 即可加载最新代码
