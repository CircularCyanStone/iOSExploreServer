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

工具名不是运行时从 App action 推断的，而是由
`src/adapters/mcp/toolMappings.ts` 的显式映射固定：

| iOSExplore action | MCP 工具名 |
|---|---|
| `ui.inspect` | `ui_inspect` |
| `ui.topViewHierarchy` | `ui_topViewHierarchy` |
| `ui.tap` | `ui_tap` |
| `ui.scrollToElement` | `ui_scrollToElement` |
| `app.logs.read` | `app_logs_read` |

`toolMappings.ts` 只固定历史 MCP 工具名及其对应的 device action / host operation；
`src/adapters/mcp/toolCatalog.ts` 用这些映射从 `src/generated/deviceActionContracts.ts` 和
`src/generated/hostOperationSpecs.ts` 读取 description 与 input schema，构造 `tools/list`。
私有或实验 action 使用 `call_action`，App `help` 只通过 `health_check` /
`check_capabilities` 做能力检查，不改变工具目录。生成的协议文档
[`docs/generated/contracts.md`](../../docs/generated/contracts.md) 只描述 device action、host
operation 和稳定错误索引，不包含 MCP 工具名映射。完整架构说明见[静态 MCP 工具架构决策](../../docs/architecture/dynamic-mcp-tools.md)。

## 排障

| 现象 | 可能原因 | 处理 |
|---|---|---|
| `Cannot find module '.../dist/index.js'` | 没编译或路径不对 | `npm run build`；脚本里 spawn 路径必须是 `dist/index.js`（不是 `dist/src/index.js`） |
| `health_check` 的 `connection` 为 `unreachable`，且 `ping.error.code` 为 `transport_unavailable` 或 `transport_timeout` | App 没起、请求超时或 38321 不可达 | 结合 `ping.error` 保留的稳定 `source` / `code` 分诊；模拟器直接 curl `localhost:38321`，真机确认 `iproxy` 在监听（`lsof` COMMAND 列必须是 `iproxy`，不是 `SPMExampl`） |
| 工具响应带失败 payload | runtime 已按 `{source, code, message, ...}` 返回结构化错误 | 解析 `content` 中的 JSON，以稳定 `source` / `code` 为判断依据；`isError` 是 MCP adapter 的呈现策略，不能代替业务成功判断 |
| `ui_tap` 返回 `stale_locator` | viewSnapshotID 陈旧 | 重新调一次 `ui_inspect` 拿新的 `viewSnapshotID` 与 path |
| UI 工具返回 `target_not_found` | 当前快照或可见层级里找不到目标 | 重新调 `ui_inspect`；目标在屏幕外时先滚动，再从新快照选择 path / indexPath |
| 真机 curl 返回内容像旧版本 App | 残留模拟器 SPMExample 占着 Mac localhost 38321 | `xcrun simctl terminate <simulatorId> com.coo.SPMExample` 后重启 iproxy |

## 与单元测试的边界

- `npm test`（vitest）覆盖 iOSDriver 内部逻辑：静态工具集合、能力检查、transport 重试、screenshot 转 image content 等，**mock 掉真实 HTTP**，不需要真 App 跑。
- `scripts/mcp-inspector.mjs` 走真 stdio + 真 HTTP，验证 iOSDriver 在真 MCP 协议下、真 App 响应下的端到端表现。两者互补：改完内部逻辑先 `npm test`，再起 App 走 mcp-inspector 做端到端 smoke。
