# 本地临时端到端测试：不安装 iOSDriver 到任何客户端

开发期间改了 iOSDriver 后想立刻验证 MCP 工具（`ui_inspect` / `ui_tap` 等）的端到端效果，**不需要把 iOSDriver 注册到 Claude Code / Cursor / Codex 等 MCP 客户端**，也**不需要 npm link / npm publish**。仓库自带 `scripts/mcp-inspector.mjs`，它扮演一个最小 MCP 客户端：通过 stdio 跟 iOSDriver 子进程走 JSON-RPC 2.0 通信，再把每个工具调用的响应原样打到 stdout。

> 本文档只描述「怎么启动一次端到端测试」，**不规定 agent 应该按什么顺序调用工具**——探索过程中会撞到什么问题、该怎么规避，正是端到端测试要发现的东西，不要把它写成固定流程模板。

## 原理

```
┌──────────────────┐   stdin (JSON-RPC)    ┌──────────────────┐   HTTP POST /  ┌──────────────┐
│ mcp-inspector.mjs│ ───────────────────► │ dist/index.js     │ ─────────────► │ iOSExploreApp│
│  (Node 脚本)      │ ◄─────────────────── │ (iOSDriver 进程)   │ ◄──────────── │  :38321      │
└──────────────────┘   stdout (JSON-RPC)   └──────────────────┘   envelope      └──────────────┘
```

`mcp-inspector.mjs` 内部按 MCP 协议顺序发：`initialize` → `notifications/initialized` → `tools/list` → 你指定的 `tools/call ...`，每个请求带自增 id，按行解析 stdout 的 JSON-RPC 响应并打印。这与 Claude Code 内部连 MCP server 的过程等价，区别只是 driver 是个一次性 Node 脚本而不是常驻 IDE。

## 前置条件

1. iOSDriver 已编译：`npm run build`（产物在 `dist/`）。
2. iOSExploreApp 已在模拟器或真机启动，且 38321 端口可从 Mac 直接访问。
   - 模拟器：`curl -s -X POST http://localhost:38321/ -d '{"action":"ping"}'` 返回 `{"code":"ok","data":{"pong":true}}`。
   - 真机：先 `iproxy 38321 38321` 转发，再 curl 同一地址。
3. 仍在用的 SPMExample 必须用 `IOS_EXPLORE_AUTOSTART=1` 启动，确保 `server.start()` 已执行（参考根 `AGENTS.md` 的「XcodeBuildMCP 运行配置」节）。

## 命令格式

```bash
cd iOSDriver

# 模式 A：无参数 — 跑预置 smoke 序列（health_check → ui_inspect → call_action ui.waitAny → wait_and_inspect）
node scripts/mcp-inspector.mjs

# 模式 B：按顺序调用任意工具，每对参数 = 工具名 + JSON 字符串
node scripts/mcp-inspector.mjs <toolName> '<jsonArgs>' [<toolName2> '<jsonArgs2>' ...]

# 工具名就是 tools/list 里看到的静态 name
```

## 静态工具名

工具名不是运行时从 App action 推断的，而是由 `src/staticTools.ts` 的静态清单固定：

| iOSExplore action | MCP 工具名 |
|---|---|
| `ui.inspect` | `ui_inspect` |
| `ui.topViewHierarchy` | `ui_topViewHierarchy` |
| `ui.tap` | `ui_tap` |
| `ui.scrollToElement` | `ui_scrollToElement` |
| `app.logs.read` | `app_logs_read` |

静态工具清单以 `src/staticTools.ts` 导出的 `STATIC_TOOL_NAMES` 为唯一来源。私有或实验
action 使用 `call_action`，App `help` 只通过 `health_check` / `check_capabilities` 做能力检查。
完整架构说明见[静态 MCP 工具架构决策](../../docs/architecture/dynamic-mcp-tools.md)。

## 排障

| 现象 | 可能原因 | 处理 |
|---|---|---|
| `Cannot find module '.../dist/index.js'` | 没编译或路径不对 | `npm run build`；脚本里 spawn 路径必须是 `dist/index.js`（不是 `dist/src/index.js`） |
| `transport` source 错误 + `healthCheck.ok=false` | App 没起 / 38321 不可达 | 模拟器直接 curl `localhost:38321`；真机确认 `iproxy` 在监听（`lsof` COMMAND 列必须是 `iproxy`，不是 `SPMExampl`） |
| 工具响应 `isError=false` 但业务 `code` 不是 `ok` | App 端业务失败（如 `unknown_action` / `wait_timeout` / `not_found`） | 看 `content[0].text` 解出来的 JSON 里的 `code` / `message`；这是正常业务反馈，不是 MCP 协议错误 |
| `ui_tap` 返回 `stale_locator` | viewSnapshotID 陈旧 | 重新调一次 `ui_inspect` 拿新的 `viewSnapshotID` 与 path |
| `ui_tap` 返回 `not_found` 但 path 看起来对 | path 是从旧快照拷来的 | 重新调 `ui_inspect` 拿当前快照的 path / indexPath |
| 真机 curl 返回内容像旧版本 App | 残留模拟器 SPMExample 占着 Mac localhost 38321 | `xcrun simctl terminate <simulatorId> com.coo.SPMExample` 后重启 iproxy |

## 与单元测试的边界

- `npm test`（vitest）覆盖 iOSDriver 内部逻辑：静态工具集合、能力检查、transport 重试、screenshot 转 image content 等，**mock 掉真实 HTTP**，不需要真 App 跑。
- `scripts/mcp-inspector.mjs` 走真 stdio + 真 HTTP，验证 iOSDriver 在真 MCP 协议下、真 App 响应下的端到端表现。两者互补：改完内部逻辑先 `npm test`，再起 App 走 mcp-inspector 做端到端 smoke。
