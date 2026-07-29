# iOSDriver 本地安装与更新（TRAE Work）

本文用于把当前仓库构建出的 iOSDriver 注册到 TRAE Work 的项目级 MCP 配置。

## 准备

```bash
cd <repo>/iOSDriver
npm install
npm run build
npm link
iosdriver init
iosdriver doctor
```

## 注册

TRAE 使用项目根目录下的 `.trae/mcp.json`。先预览，再执行：

```bash
iosdriver mcp setup trae \
  --project-dir <project-root> \
  --dry-run

iosdriver mcp setup trae \
  --project-dir <project-root>
```

setup 会保留 `.trae/mcp.json` 中其他 MCP server，只管理 `mcpServers.iOSDriver`。已有同名不同配置时使用：

```bash
iosdriver mcp setup trae --project-dir <project-root> --force
```

没有 link 时可直接运行构建产物：

```bash
node <repo>/iOSDriver/dist/adapters/cli/main.js mcp setup trae \
  --project-dir <project-root>
```

在 TRAE 设置中打开项目级 MCP 开关；项目文件只有在项目受信任时才应启用。

## 验证

重启或重连 TRAE Work 后，在 MCP 面板确认 `iOSDriver` 已连接，并调用 `health_check`。

App 连接检查：

```bash
curl -s -X POST http://localhost:38321/ -d '{"action":"ping"}'
iosdriver doctor
```

## 更新

```bash
cd <repo>/iOSDriver
npm run build
```

绝对路径没有变化时不需要重复 setup。重新构建后需要重启 TRAE Work 或重连 MCP Server。
