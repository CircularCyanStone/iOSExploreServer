# iOSExplore MCP Server

Mac 本机运行的 MCP stdio server。它把 App 内 `ExploreServer` 的 `POST /` action 包装成 MCP tools，默认连接 `http://localhost:38321/`。

工具架构决策（静态 MCP 工具、`help` 能力检查和 `call_action` 兜底）见仓库文档：[MCP 工具架构决策](../docs/architecture/dynamic-mcp-tools.md)。

## 启动前提

模拟器：App 启动并开启 `IOS_EXPLORE_AUTOSTART=1` 后,Mac 直接访问 `localhost:38321`。

真机：App 启动并开启 `IOS_EXPLORE_AUTOSTART=1` 后，先启动 `iproxy 38321 38321`。真机验收前运行：

```bash
lsof -iTCP:38321 -sTCP:LISTEN
```

`COMMAND` 必须是 `iproxy`，不能是残留的 `SPMExampl`。

## 开发命令

```bash
npm install
npm test
npm run typecheck
npm run build
```

`ios-explore-mcp-server` 的 `bin` 和本地调试脚本默认运行 `dist/index.js`。修改
修改 `src/staticTools.ts`、`src/server.ts` 等工具暴露层后，必须先 `npm run build`，再重连
MCP 客户端；否则客户端看到的仍是旧 `dist` 里的工具 schema。

`npm test` 会先执行 `npm run build`，用于避免源码测试通过但本地 MCP 运行产物仍停留在旧 schema。

## 配置

| 环境变量 | 默认值 | 说明 |
|---|---|---|
| `IOS_EXPLORE_BASE_URL` | `http://localhost:38321/` | iOSExplore HTTP 地址 |
| `IOS_EXPLORE_REQUEST_TIMEOUT_MS` | `10000` | 普通 action 请求超时 |

`ui.wait`、`ui.waitAny`、`wait_and_inspect` 会按业务 `timeoutMs + 5000` 自动放宽 HTTP timeout。

## 端到端测试

- 本地临时调试（不安装 iOSDriver 到任何 MCP 客户端）：[docs/local-mcp-test.md](docs/local-mcp-test.md)
