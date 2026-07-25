# 架构概览

本文是 agent 日常修改代码时使用的当前架构索引。历史设计背景在 `docs/superpowers/`，但当前 action、字段、错误和 host operation 以 `contracts/`、源码和测试为准。

## 总体结构

```text
contracts/
  -> Swift metadata / TypeScript schema / generated docs

iOS App
  ExploreServer (POST /)
    -> core actions
    -> UIKit actions
    -> Diagnostics actions

Mac
  iOSDriver runtime
    -> WorkflowRunner
    -> CLI adapter
    -> MCP adapter
```

合同只有两个业务命名空间：

- `DeviceActionContract`：App 内 `{ action, data }` 的输入、结果、错误、幂等和 timeout 信息。
- `HostOperationSpec`：Mac 侧连接检查、能力探测和跨 action workflow。

`init`、`doctor`、`call`、`mcp` 是 CLI 命令，不是第三个业务合同命名空间。MCP 工具名由 `iOSDriver/src/adapters/mcp/toolMappings.ts` 固定，不从 App `help` 动态生成。

## Wire 协议

HTTP endpoint 固定为 `POST /`：

```json
{"action":"ping","data":{}}
```

成功：

```json
{"code":"ok","data":{"pong":true}}
```

失败：

```json
{"code":"<business-code>","message":"<message>"}
```

通信层问题使用 HTTP 400/500；action 业务失败使用 HTTP 200 + 失败 envelope。

## Swift 模块

| 模块 | 边界 |
| --- | --- |
| `iOSExploreServer` | Core server、HTTP parser/response、router、内置 `ping`/`echo`/`info`/`help`。不依赖 UIKit。 |
| `iOSExploreUIKit` | UIKit 命令、locator、executor、snapshot store、UI 采集。宿主显式调用 `registerUIKitCommands()`。 |
| `iOSExploreDiagnostics` | `app.logs.mark/read`、进程内日志 store、Debug 日志桥接和可选捕获。宿主显式调用 `registerDiagnosticsCommands()`。 |

Core 初始化只注册 core actions。UIKit 和 Diagnostics 未注册时，`help` 不包含对应 action；这既是运行时事实，也是回归保护点。

## UIKit 关键语义

`ui.inspect` 是操作前的主要发现命令。它返回 full/minimal 两档节点，并只为 full 可操作目标签发 `viewSnapshotID`。`ui.tap` 与 `ui.control.sendAction` 必须携带 `ui.inspect` 签发的 `viewSnapshotID`；minimal 节点不可直接操作，调用交互命令会返回 `not_actionable`。

定位优先级：

1. `accessibilityIdentifier` 精确匹配。
2. `path`，来自 `ui.inspect` 或 `ui.topViewHierarchy` 的只读路径。
3. `viewSnapshotID`，用于陈旧防护，不是截图 ID。

`ui.topViewHierarchy` 是完整观察命令，不签发 `viewSnapshotID`。`ui.screenshot` 只返回图像产物，也不签发 `viewSnapshotID`。

采集根是最外层可见容器 controller 的 view，包含 navigation bar、tab bar 等 chrome。`ui.inspect`、`ui.topViewHierarchy` 和交互命令的 path 使用同一棵 root view，保证观察和操作定位一致。

## Diagnostics 关键语义

Diagnostics 默认不接管 stdout/stderr/NSLog/os_log。宿主注册 Diagnostics 后会提供 `app.logs.mark` 与 `app.logs.read`；额外捕获由 `ESDiagnosticsConfiguration` 显式打开。Release 下相关 Debug 捕获路径不应启用。

`app.logs.mark` 返回 cursor，`app.logs.read` 读取 cursor 之后的增量日志。stdout/stderr/NSLog/os_log 受系统权限、沙箱和配置限制；不可用时必须报告状态，不能伪装成“没有日志”。

## iOSDriver

`iOSDriver/src/runtime/` 负责：

- HTTP transport
- request timeout
- App envelope / HTTP / protocol 错误归一化
- capability probe
- artifact 解码

`iOSDriver/src/workflows/` 负责：

- `wait_and_inspect`
- `tap_and_inspect`

`iOSDriver/src/adapters/cli/` 只负责 CLI 参数、配置、stdout/stderr 和退出码。`iOSDriver/src/adapters/mcp/` 只负责 MCP `tools/list` / `tools/call`、工具映射和内容渲染。两者都不能复制 App action handler 或 schema。

## 生成边界

合同源变更后，在 `iOSDriver/` 运行：

```bash
npm run contracts:generate
npm run contracts:check
```

生成产物包括 TypeScript 合同、Swift metadata/fields 和 `docs/generated/contracts.md`。generated 文件不手写修改。

## 参考文档

- MCP 静态工具决策：[dynamic-mcp-tools.md](dynamic-mcp-tools.md)
- CLI / runtime / adapter 决策：[../cli/README.md](../cli/README.md)
- UIKit 阅读入口：[../uikit/README.md](../uikit/README.md)
- Diagnostics 开发者说明：[../diagnostics/README.md](../diagnostics/README.md)
- 构建与测试：[../runbooks/build-and-test.md](../runbooks/build-and-test.md)
- 端口和真机排障：[../runbooks/debugging.md](../runbooks/debugging.md)
