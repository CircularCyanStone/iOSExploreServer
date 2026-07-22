# MCP 客户端配置模板

只读取当前客户端对应的小节。所有路径均使用占位符，不复制本机项目路径。

## 通用 JSON 客户端

在已有 `mcpServers` 对象中合并两个 server，不覆盖其他配置，也不创建重复名称：

```json
{
  "mcpServers": {
    "iOSDriver": {
      "command": "node",
      "args": ["/path/to/iOSDriver/dist/index.js"],
      "env": {
        "IOS_EXPLORE_BASE_URL": "http://localhost:38321",
        "IOS_EXPLORE_REQUEST_TIMEOUT_MS": "10000"
      }
    },
    "XcodeBuildMCP": {
      "command": "npx",
      "args": ["-y", "xcodebuildmcp@latest", "mcp"]
    }
  }
}
```

## Codex CLI

```bash
codex mcp add iOSDriver --env IOS_EXPLORE_BASE_URL=http://localhost:38321 --env IOS_EXPLORE_REQUEST_TIMEOUT_MS=10000 -- node /path/to/iOSDriver/dist/index.js
codex mcp add XcodeBuildMCP -- npx -y xcodebuildmcp@latest mcp
```

用 `codex mcp get iOSDriver` 和 `codex mcp get XcodeBuildMCP` 检查最终注册结果。已存在同名 server 时先更新现有配置；只有客户端不支持原地更新时才删除后重建。

## Claude Code

```bash
claude mcp add iOSDriver -e IOS_EXPLORE_BASE_URL=http://localhost:38321 -e IOS_EXPLORE_REQUEST_TIMEOUT_MS=10000 -- node /path/to/iOSDriver/dist/index.js
claude mcp add XcodeBuildMCP -- npx -y xcodebuildmcp@latest mcp
```

用 `claude mcp get iOSDriver` 和 `claude mcp get XcodeBuildMCP` 检查最终注册结果。

## 工作目录

XcodeBuildMCP 应从目标 workspace 启动，才能发现 `.xcodebuildmcp/config.yaml`。客户端无法设置 server 工作目录时，为 XcodeBuildMCP 增加：

```json
{
  "env": {
    "XCODEBUILDMCP_CWD": "/path/to/workspace"
  }
}
```

这只影响 XcodeBuildMCP 的项目配置发现，不应添加到 iOSDriver server。
