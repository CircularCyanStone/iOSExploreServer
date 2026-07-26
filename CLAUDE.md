# iOSExploreServer — Claude Code Guide

Claude Code 使用本仓库时，先读根 `AGENTS.md`。所有通用工程规则、模块边界、验证策略、文档分层和任务完成汇报要求都维护在那里；本文件只保留 Claude Code 容易重复踩到的入口差异，避免双份维护。

## MCP 与 CLI

当前 Mac 侧入口是 `iOSDriver`：

- CLI bin：`iosdriver`，源码入口 `iOSDriver/src/adapters/cli/main.ts`，构建产物 `iOSDriver/dist/adapters/cli/main.js`。
- MCP 入口：`iosdriver mcp`，也可以直接用 `node <repo>/iOSDriver/dist/adapters/cli/main.js mcp`。
- 新安装说明应优先使用 CLI 的 `mcp` 子命令，不要回退到历史兼容入口。

修改 `iOSDriver/src` 后先运行 `cd iOSDriver && npm run build`，再重启 Claude Code 的 MCP 进程；已启动的 stdio 子进程不会自动加载新 `dist`。

## App 启动假设

`Examples/SPMExample` 在 Debug 构建中直接启动 server，不需要额外 autostart 环境变量。可选启动参数只用于快速进入测试页面：

- `--ios-explore-open-alert-test` 或 `IOS_EXPLORE_OPEN_ALERT_TEST=1`
- `--ios-explore-show-login` 或 `IOS_EXPLORE_SHOW_LOGIN=1`

这些参数不是 iOSExploreServer 的核心 API，不能写进通用接入说明当作必需条件。

## 真机连接

真机访问 `localhost:38321` 前必须确认 Mac 侧监听进程是 `iproxy`：

```bash
lsof -iTCP:38321 -sTCP:LISTEN
```

如果 COMMAND 是残留的示例 App 或其他进程，`curl` 打到的不是当前真机。设备 ID、模拟器 ID 和本机路径不能写入通用文档。

## 回复要求

不要只说“已打通”“已收敛”“验证完成”。最终回复按 `AGENTS.md` 的完成汇报格式说明目标、改动、效果、使用/验证方式和限制。

@AGENTS.md
