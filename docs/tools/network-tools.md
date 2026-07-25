# HTTP 协议与命令入口

本文给开发者和 agent 提供 curl 级别的当前协议入口。完整字段、默认值、结果类型和稳定错误索引以 `docs/generated/contracts.md` 为准。

## HTTP Envelope

请求固定为 `POST /`：

```json
{"action":"ping","data":{}}
```

成功：

```json
{"code":"ok","data":{"pong":true}}
```

业务失败：

```json
{"code":"unknown_action","message":"no handler for 'foo'"}
```

通信失败使用 HTTP 400/500；action 业务失败使用 HTTP 200 + 失败 envelope。

## Core Actions

Core actions 在 `ExploreServer.init` 中注册：

| action | 说明 |
| --- | --- |
| `ping` | 检查 server 是否可达。 |
| `echo` | 原样回显 `data`。 |
| `info` | 返回 `ProcessInfo` / `Bundle` 级系统、App、Bundle 信息。 |
| `help` | 返回当前实际已注册 action 及 metadata。 |

## UIKit Actions

UIKit actions 由 `iOSExploreUIKit` 提供，宿主必须显式调用：

```swift
server.registerUIKitCommands()
```

当前公共 `ui.*` action 以 `contracts/bundle.json` 和 `docs/generated/contracts.md` 为准，包括 inspect、tap、control、input、scroll、navigation、alert、picker、webview 等能力。未注册时 `help` 不包含 `ui.*`。

常用观察：

```bash
curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}'
curl -s -X POST http://localhost:38321/ -d '{"action":"ui.topViewHierarchy","data":{"maxDepth":2}}'
curl -s -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}'
```

交互命令必须使用当前 UI 状态下的定位信息。`ui.tap` 和 `ui.control.sendAction` 必须携带 `ui.inspect` 签发的 `viewSnapshotID`：

```bash
curl -s -X POST http://localhost:38321/ \
  -d '{"action":"ui.tap","data":{"path":"<path-from-inspect>","viewSnapshotID":"<snapshot-id>"}}'

curl -s -X POST http://localhost:38321/ \
  -d '{"action":"ui.control.sendAction","data":{"path":"<path-from-inspect>","viewSnapshotID":"<snapshot-id>","event":"touchUpInside"}}'
```

`ui.topViewHierarchy` 和 `ui.screenshot` 不签发 `viewSnapshotID`。minimal 节点不可直接操作；对 minimal 节点执行 tap/control 会返回 `not_actionable`。

## Diagnostics Actions

Diagnostics actions 由 `iOSExploreDiagnostics` 提供，宿主必须显式调用：

```swift
server.registerDiagnosticsCommands()
```

标准增量读取：

```bash
curl -s -X POST http://localhost:38321/ -d '{"action":"app.logs.mark"}'
curl -s -X POST http://localhost:38321/ -d '{"action":"ping"}'
curl -s -X POST http://localhost:38321/ \
  -d '{"action":"app.logs.read","data":{"after":{"captureSessionID":"<from-mark>","id":0},"limit":100}}'
```

`explore` 内部日志和宿主 `ESAppLogger` bridge 日志是稳定来源。stdout/stderr/NSLog/os_log 捕获默认关闭，只有宿主 Debug 配置显式打开后才可读。`capture.oslog.state="unavailable"` 表示系统或沙箱不允许读取当前进程 unified logging。

## iOSDriver CLI

同一 HTTP action 可以通过 CLI 调用：

```bash
cd iOSDriver
npm run build
node dist/adapters/cli/main.js doctor
node dist/adapters/cli/main.js call ping
node dist/adapters/cli/main.js call ui.inspect --data '{"mode":"minimal"}'
```

安装为 bin 后：

```bash
iosdriver doctor
iosdriver call ping
iosdriver mcp
```
