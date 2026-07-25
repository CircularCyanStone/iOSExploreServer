# 本地 MCP 端到端测试

本说明用于在不安装到 Claude Code、Codex、TRAE Work 等 MCP 客户端的情况下，验证当前仓库构建出的 iOSDriver MCP 行为。`scripts/mcp-inspector.mjs` 会启动本地 `dist`，按 MCP stdio 协议执行 `initialize`、`tools/list` 和指定的 `tools/call`。

## 前置条件

1. 构建 iOSDriver：

```bash
cd iOSDriver
npm install
npm run build
```

2. Debug App 已启动并监听 `38321`。

模拟器：

```bash
curl -s -X POST http://localhost:38321/ -d '{"action":"ping"}'
```

真机：

```bash
iproxy 38321 38321
lsof -iTCP:38321 -sTCP:LISTEN
curl -s -X POST http://localhost:38321/ -d '{"action":"ping"}'
```

`lsof` 的 COMMAND 必须是 `iproxy`。

## 运行

```bash
cd iOSDriver

# 预置 smoke 序列
node scripts/mcp-inspector.mjs

# 指定工具与 JSON 参数
node scripts/mcp-inspector.mjs ui_inspect '{"mode":"minimal"}'
node scripts/mcp-inspector.mjs call_action '{"action":"ping","data":{}}'
```

工具名来自 `src/adapters/mcp/toolMappings.ts`，schema 来自 `src/generated/deviceActionContracts.ts` 和 `src/generated/hostOperationSpecs.ts`。App `help` 不改变 `tools/list`；私有或实验 action 使用 `call_action`。

## 常见问题

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 找不到 `dist` 入口 | 还没 build 或 build 失败 | `npm run build`。 |
| `health_check` 显示 unreachable | App 未启动、端口不可达或真机未转发 | 先 curl `ping`；真机检查 `iproxy`。 |
| 工具返回 `unknown_action` | App 未注册对应模块或 action 名错误 | 查 App `help`，确认是否调用 `registerUIKitCommands()` / `registerDiagnosticsCommands()`。 |
| `stale_locator` | 快照已变化 | 重新调用 `ui_inspect`，用新的 `path` / `viewSnapshotID`。 |
| 真机结果像旧 App | Mac 端 38321 被其他进程占用 | `lsof` 确认监听进程，清掉占用后重启 `iproxy`。 |

## 与单元测试的边界

`npm test` 覆盖 host runtime、adapter、合同生成和 workflow 的可 mock 行为；`mcp-inspector.mjs` 走真实 stdio + 真实 HTTP，用于发现客户端协议和真 App 响应下的问题。
