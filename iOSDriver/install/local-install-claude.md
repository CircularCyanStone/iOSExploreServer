# iOSDriver 本地安装与更新（Claude Code）

本文用于把当前仓库构建出的 iOSDriver 注册到 Claude Code。

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

Claude Code 默认使用 project scope，写入 `<project-root>/.mcp.json`：

```bash
iosdriver mcp setup claude \
  --project-dir <project-root> \
  --dry-run

iosdriver mcp setup claude \
  --project-dir <project-root>
```

希望所有项目共用时使用 user scope：

```bash
iosdriver mcp setup claude --scope user
```

user scope 更新 `~/.claude.json`；设置了 `CLAUDE_CONFIG_DIR` 时更新该目录中的 `.claude.json`。setup 只新增或更新 `mcpServers.iOSDriver`，保留其他配置。

已有同名不同配置时先用 `--dry-run --force` 查看计划，再执行：

```bash
iosdriver mcp setup claude --project-dir <project-root> --force
```

没有 link 时可直接运行构建产物：

```bash
node <repo>/iOSDriver/dist/adapters/cli/main.js mcp setup claude \
  --project-dir <project-root>
```

## 验证

重启 Claude Code 后执行 `/mcp`，确认 `iOSDriver` 已连接，再调用 `health_check`。

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

绝对路径没有变化时不需要重复 setup。重新构建不会重启已有 stdio 子进程，需要完全退出并重启 Claude Code。
