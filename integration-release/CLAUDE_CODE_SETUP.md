# Claude Code 配置指南

## 📦 前置条件

确保已安装 MCP Server：

```bash
npm install -g ios-explore-mcp-server
```

验证安装：

```bash
which ios-explore-mcp-server
# 应输出：/usr/local/bin/ios-explore-mcp-server（或类似路径）
```

## ⚙️ 配置步骤

### 1. 创建或编辑配置文件

配置文件位置：`~/.claude/.mcp.json`

```bash
# 创建目录（如果不存在）
mkdir -p ~/.claude

# 编辑配置文件
nano ~/.claude/.mcp.json
# 或使用其他编辑器：vim、code、open 等
```

### 2. 添加 iOSDriver 配置

将以下内容添加到 `~/.claude/.mcp.json`：

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

**如果已有其他 MCP 配置**，添加到 `mcpServers` 对象中：

```json
{
  "mcpServers": {
    "existingServer": {
      "command": "other-mcp-server"
    },
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

配置修改后，**必须重启 Claude Code** 才能生效。

## 🔧 配置详解

### 配置文件结构

```json
{
  "mcpServers": {
    "服务器名称": {
      "command": "命令",
      "args": ["参数"],
      "env": {
        "环境变量名": "值"
      }
    }
  }
}
```

### 字段详细说明

#### 1. `mcpServers`（顶层对象）

- **作用**：定义所有 MCP Server 的配置
- **类型**：对象（Object）
- **必填**：是
- **说明**：Claude Code 会读取这个对象，加载所有配置的 MCP Server

```json
{
  "mcpServers": {
    // 这里放所有 MCP Server 配置
  }
}
```

#### 2. 服务器名称（如 `"iOSDriver"`）

- **作用**：给 MCP Server 取一个标识名
- **类型**：字符串（String）
- **必填**：是
- **说明**：
  - 这是你自己定义的名字，可以随便取
  - 推荐用有意义的名字：`iOSDriver`、`GitHubMCP`、`FileSystemMCP` 等
  - Claude Code 内部用这个名字区分不同的 MCP Server
  - **不影响功能，只是个标签**

示例：

```json
{
  "mcpServers": {
    "iOSDriver": { ... },      // 第一个 MCP Server
    "AnotherServer": { ... }   // 第二个 MCP Server（如果有）
  }
}
```

#### 3. `command`（命令字段）

- **作用**：告诉 Claude Code 如何启动这个 MCP Server
- **类型**：字符串（String）
- **必填**：是
- **说明**：
  - 这是一个**可执行命令**
  - 对于 `ios-explore-mcp-server`，它是通过 `npm install -g` 安装后的全局命令
  - Claude Code 会在终端执行这个命令来启动 MCP Server
  - 必须是系统 PATH 中可找到的命令

示例：

```json
{
  "command": "ios-explore-mcp-server"
}
```

等同于你在终端执行：

```bash
ios-explore-mcp-server
```

#### 4. `args`（参数数组，可选）

- **作用**：传递给命令的参数
- **类型**：数组（Array）
- **必填**：否（通常不需要）
- **说明**：
  - 如果命令需要额外参数，在这里指定
  - 每个参数是数组中的一个字符串元素

示例 1：不使用 args（默认）

```json
{
  "command": "ios-explore-mcp-server"
}
```

示例 2：使用 npx 运行（需要 args）

```json
{
  "command": "npx",
  "args": ["-y", "ios-explore-mcp-server"]
}
```

等同于终端执行：

```bash
npx -y ios-explore-mcp-server
```

#### 5. `env`（环境变量，可选）

- **作用**：传递环境变量给 MCP Server 进程
- **类型**：对象（Object）
- **必填**：否（但推荐配置）
- **说明**：
  - 环境变量是进程运行时的配置参数
  - MCP Server 启动时会读取这些变量
  - 键（key）是变量名，值（value）是变量值
  - **所有值必须是字符串**

示例：

```json
{
  "env": {
    "IOS_EXPLORE_BASE_URL": "http://localhost:38321/",
    "IOS_EXPLORE_REQUEST_TIMEOUT_MS": "10000"
  }
}
```

等同于终端执行：

```bash
IOS_EXPLORE_BASE_URL="http://localhost:38321/" \
IOS_EXPLORE_REQUEST_TIMEOUT_MS="10000" \
ios-explore-mcp-server
```

### iOSDriver 专用环境变量

#### `IOS_EXPLORE_BASE_URL`

- **作用**：告诉 MCP Server 去哪里连接 iOSExploreServer
- **类型**：字符串（URL）
- **必填**：否（有默认值）
- **默认值**：`http://localhost:38321/`
- **说明**：
  - `localhost` = 本机
  - `38321` = iOSExploreServer 监听的端口
  - 末尾的 `/` 不能省略
  - 如果你的 App 用了其他端口，在这里修改

示例 1：默认端口

```json
"IOS_EXPLORE_BASE_URL": "http://localhost:38321/"
```

示例 2：自定义端口

```json
"IOS_EXPLORE_BASE_URL": "http://localhost:38322/"
```

#### `IOS_EXPLORE_REQUEST_TIMEOUT_MS`

- **作用**：设置 HTTP 请求的超时时间
- **类型**：字符串（数字）
- **必填**：否（有默认值）
- **默认值**：`10000`（10 秒）
- **单位**：毫秒（milliseconds）
- **说明**：
  - 如果 UI 操作很慢（如复杂动画），可以增加这个值
  - 太小会导致超时错误
  - 太大会让失败操作等待很久
  - **必须用字符串，不能用数字**：`"10000"` ✅  `10000` ❌

示例：

```json
"IOS_EXPLORE_REQUEST_TIMEOUT_MS": "15000"  // 15 秒
```

### 完整配置示例（带详细注释）

```json
{
  // 顶层：所有 MCP Server 的容器
  "mcpServers": {
    
    // 服务器标识名（自己定义，推荐用有意义的名字）
    "iOSDriver": {
      
      // 启动命令（全局安装后的命令名）
      "command": "ios-explore-mcp-server",
      
      // 环境变量（传递给 MCP Server 进程）
      "env": {
        
        // iOSExploreServer 的 HTTP 地址
        // localhost:38321 是默认配置
        "IOS_EXPLORE_BASE_URL": "http://localhost:38321/",
        
        // HTTP 请求超时时间（毫秒）
        // 10000 = 10 秒
        "IOS_EXPLORE_REQUEST_TIMEOUT_MS": "10000"
      }
    }
  }
}
```

### 常见配置模式

#### 模式 1：最简配置（推荐新手）

```json
{
  "mcpServers": {
    "iOSDriver": {
      "command": "ios-explore-mcp-server"
    }
  }
}
```

**说明**：使用所有默认值，99% 场景够用。

#### 模式 2：完整配置（推荐）

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

**说明**：显式指定 URL，方便日后修改。

#### 模式 3：自定义端口

```json
{
  "mcpServers": {
    "iOSDriver": {
      "command": "ios-explore-mcp-server",
      "env": {
        "IOS_EXPLORE_BASE_URL": "http://localhost:38322/",
        "IOS_EXPLORE_REQUEST_TIMEOUT_MS": "15000"
      }
    }
  }
}
```

**说明**：端口改为 38322，超时增加到 15 秒。

#### 模式 4：使用 npx（无需全局安装）

```json
{
  "mcpServers": {
    "iOSDriver": {
      "command": "npx",
      "args": ["-y", "ios-explore-mcp-server"],
      "env": {
        "IOS_EXPLORE_BASE_URL": "http://localhost:38321/"
      }
    }
  }
}
```

**说明**：
- `npx` 是 npm 自带的命令
- `-y` 表示自动确认
- 每次启动会检查并使用最新版本
- 首次运行会下载，稍慢

### 多个 MCP Server 配置

```json
{
  "mcpServers": {
    "iOSDriver": {
      "command": "ios-explore-mcp-server",
      "env": {
        "IOS_EXPLORE_BASE_URL": "http://localhost:38321/"
      }
    },
    "FileSystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/Users/yourname/Documents"]
    },
    "GitHub": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "your-token-here"
      }
    }
  }
}
```

**说明**：
- 可以配置多个 MCP Server
- 每个 Server 之间用逗号分隔
- **最后一个不要加逗号**（JSON 语法）
- Claude Code 会同时加载所有配置的 Server

### 完整配置示例

```json
{
  "mcpServers": {
    "iOSDriver": {
      "command": "ios-explore-mcp-server",
      "env": {
        "IOS_EXPLORE_BASE_URL": "http://localhost:38321/",
        "IOS_EXPLORE_REQUEST_TIMEOUT_MS": "15000"
      }
    }
  }
}
```

## ✅ 验证配置

### 1. 检查配置文件语法

```bash
cat ~/.claude/.mcp.json | jq
# 应该正常输出 JSON，无报错
```

如果提示 `jq` 未安装：

```bash
# macOS
brew install jq

# 或直接查看文件
cat ~/.claude/.mcp.json
```

### 2. 在 Claude Code 中测试

重启 Claude Code 后，在对话中输入：

```
请列出可用的 MCP tools
```

应该看到 `iOSDriver` 相关的 tools：
- `health_check`
- `refresh_tools`
- `ui.inspect`
- `ui.tap`
- 等等...

### 3. 测试连接

在 Claude Code 中：

```
请检查 iOSExplore 连接状态
```

Claude 会调用 `health_check` tool。

## 🔄 不同场景的配置

### 场景 1：真机调试（默认）

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

**前提**：启动 iproxy
```bash
iproxy 38321 38321
```

### 场景 2：模拟器调试

配置相同，但**不需要 iproxy**：

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

### 场景 3：自定义端口

如果 iOSExploreServer 使用其他端口（如 38322）：

```json
{
  "mcpServers": {
    "iOSDriver": {
      "command": "ios-explore-mcp-server",
      "env": {
        "IOS_EXPLORE_BASE_URL": "http://localhost:38322/"
      }
    }
  }
}
```

### 场景 4：使用 npx（无需全局安装）

```json
{
  "mcpServers": {
    "iOSDriver": {
      "command": "npx",
      "args": ["-y", "ios-explore-mcp-server"],
      "env": {
        "IOS_EXPLORE_BASE_URL": "http://localhost:38321/"
      }
    }
  }
}
```

优点：总是使用最新版本，无需手动更新。

## 🆘 故障排查

### 问题 1：Claude Code 无法连接 MCP

**检查命令是否可用：**

```bash
which ios-explore-mcp-server
```

如果输出为空：

```bash
npm install -g ios-explore-mcp-server
```

### 问题 2：配置文件语法错误

**验证 JSON 格式：**

```bash
cat ~/.claude/.mcp.json | jq
```

常见错误：
- 缺少逗号
- 多余的逗号（最后一项后）
- 引号不匹配

### 问题 3：Tools 未出现

**解决步骤：**

1. 检查配置文件路径：`~/.claude/.mcp.json`
2. 验证 JSON 语法：`cat ~/.claude/.mcp.json | jq`
3. **完全退出并重启 Claude Code**（不是刷新）
4. 查看 Claude Code 日志（如果有报错）

### 问题 4：连接超时

**检查 iOSExploreServer 是否运行：**

```bash
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
```

应返回：

```json
{"code":"ok","data":{"pong":true}}
```

如果失败：
- 确认 App 正在运行
- 真机需启动 iproxy：`iproxy 38321 38321`
- 检查端口占用：`lsof -iTCP:38321`

### 问题 5：Tools 调用失败

**常见原因：**

1. **BASE_URL 配置错误**
   - 检查 `IOS_EXPLORE_BASE_URL` 是否正确
   - 默认：`http://localhost:38321/`

2. **超时设置过短**
   - 增加超时：`"IOS_EXPLORE_REQUEST_TIMEOUT_MS": "15000"`

3. **App 未启用 ExploreServer**
   - 确认 App 中已调用 `exploreServer.start()`

## 📚 相关文档

- MCP Server 本地开发：[LOCAL_DEV.md](LOCAL_DEV.md)
- MCP Server 发布指南：[PUBLISH.md](PUBLISH.md)
- npm 包地址：https://www.npmjs.com/package/ios-explore-mcp-server
- MCP 官方文档：https://modelcontextprotocol.io

## 🔄 更新配置

### 更新 MCP Server 版本

```bash
npm update -g ios-explore-mcp-server
```

配置文件**无需修改**，重启 Claude Code 即可使用新版本。

### 临时禁用 iOSDriver

编辑 `~/.claude/.mcp.json`，注释或删除 `iOSDriver` 配置：

```json
{
  "mcpServers": {
    // "iOSDriver": {
    //   "command": "ios-explore-mcp-server"
    // }
  }
}
```

或移除整个 `iOSDriver` 对象。

### 恢复配置

重新添加配置，重启 Claude Code。

## 💡 最佳实践

1. **使用默认配置**
   - 端口 `38321` 是标准配置
   - 超时 `10000ms` 适合大多数场景

2. **定期更新**
   ```bash
   npm update -g ios-explore-mcp-server
   ```

3. **版本锁定**（生产环境）
   ```bash
   npm install -g ios-explore-mcp-server@1.0.0
   ```

4. **备份配置**
   ```bash
   cp ~/.claude/.mcp.json ~/.claude/.mcp.json.backup
   ```
