# iOSExploreServer

Debug 环境使用的 iOS App HTTP 自动化库。App 内启动 `ExploreServer` 后，Mac 可以通过单一 HTTP 端点 `POST /` 调用 `ping`、`ui.inspect`、`ui.tap`、`app.logs.read` 等 action；`iOSDriver` 在 Mac 侧把同一套合同投影成 CLI 与 MCP 工具。

## 适用范围

- 给 iOS App 的 Debug 构建接入远程诊断、UI 操作和进程内日志读取。
- 给开发脚本使用 `iosdriver call` / `iosdriver doctor` 做可重复检查。
- 给 MCP 客户端使用 `iosdriver mcp` 暴露稳定工具列表。

它不是线上日志 SDK，也不提供 Release 默认入口。UIKit、Diagnostics 和宿主自定义命令都需要宿主显式注册。

## 组成

| 目录 | 面向对象 | 内容 |
| --- | --- | --- |
| `Sources/iOSExploreServer/` | App 开发者 | Core HTTP server、action router、内置 `ping`/`echo`/`info`/`help`。 |
| `Sources/iOSExploreUIKit/` | App 开发者 | UIKit action：`ui.inspect`、`ui.tap`、`ui.input`、等待、导航、列表、alert 等。 |
| `Sources/iOSExploreDiagnostics/` | App 开发者 | `app.logs.mark/read`、Debug 日志桥接和可选 stdout/stderr/NSLog/os_log 捕获。 |
| `contracts/` | Host/adapter 开发者 | Device action 与 host operation 的 JSON 合同事实源。 |
| `iOSDriver/` | Mac 侧使用者 | Node.js CLI + MCP adapter，共用合同、runtime 和 workflow。 |
| `docs/developers/` | 开发者 | 接入、安装、运行和排障入口。 |
| `AGENTS.md`、`docs/agents/` | Agent | 代码修改规则、验证策略和 agent 专用背景。 |

## App 接入

Swift Package products：

- `iOSExploreServer`
- `iOSExploreUIKit`
- `iOSExploreDiagnostics`

Debug 构建中显式启动并注册需要的模块：

```swift
#if DEBUG
import iOSExploreServer
import iOSExploreUIKit
import iOSExploreDiagnostics

let server = ExploreServer()
server.registerUIKitCommands()
server.registerDiagnosticsCommands()

Task {
    try? await server.start()
}
#endif
```

Core 初始化只自动注册 `ping`、`echo`、`info`、`help`。不调用 `registerUIKitCommands()` 时 `help` 不包含 `ui.*`；不调用 `registerDiagnosticsCommands()` 时 `help` 不包含 `app.logs.*`。

当前版本明确不启用鉴权：`ExploreServer(authToken:)`、`IOS_EXPLORE_AUTH_TOKEN` 和 `X-Auth-Token` 只保留未来接线，即使配置 token 也不会校验或拒绝请求。该 Debug 服务不提供访问控制；listener 监听所有接口，真机在同一网络中可能被直接访问，因此只应在受控开发网络或 USB 转发环境中启用，不要把预留 token 当作安全机制。

## Mac 侧调用

模拟器与 Mac 共享 localhost；真机需要先通过 USB 转发：

```bash
iproxy 38321 38321
```

最小 HTTP 检查：

```bash
curl -s -X POST http://localhost:38321/ \
  -H 'Content-Type: application/json' \
  -d '{"action":"ping"}'
```

成功响应：

```json
{"code":"ok","data":{"pong":true}}
```

CLI：

```bash
cd iOSDriver
npm install
npm run build
node dist/adapters/cli/main.js doctor
node dist/adapters/cli/main.js call ui.inspect --data '{"mode":"minimal"}'
```

安装为命令后可使用：

```bash
iosdriver doctor
iosdriver call ping
iosdriver mcp
```

## 协议

HTTP endpoint 固定为 `POST /`：

```json
{"action":"<action-name>","data":{}}
```

响应 envelope 固定为：

```json
{"code":"ok","data":{}}
```

或：

```json
{"code":"<business-code>","message":"<message>"}
```

通信失败使用 HTTP 400/500；action 业务失败使用 HTTP 200 + 失败 envelope。完整 action、字段、结果和稳定错误索引由 `contracts/` 生成到 `docs/generated/contracts.md`，不要手写复制 schema。

## 继续阅读

- 开发者入口：[docs/developers/README.md](docs/developers/README.md)
- 项目整体架构：[docs/developers/architecture.md](docs/developers/architecture.md)
- iOSDriver 使用：[iOSDriver/README.md](iOSDriver/README.md)
- 合同摘要：[docs/generated/contracts.md](docs/generated/contracts.md)
- UIKit 模块：[docs/uikit/README.md](docs/uikit/README.md)
- Diagnostics 模块：[docs/diagnostics/README.md](docs/diagnostics/README.md)
- Agent 规则：[AGENTS.md](AGENTS.md)
