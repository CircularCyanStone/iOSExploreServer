# 合同 runtime 仓库案例

本页是仓库级案例，不是通用 skill 规则。通用 skill 只描述跨 App 稳定的工作流、参数语义、失败分诊和终止条件；本仓库的 action 字段、默认值、错误码和工具映射以 [`../../generated/contracts.md`](../../generated/contracts.md) 为准。

## 合同源与生成

合同源位于仓库根目录 `contracts/`，分成 `device-actions/`、`host-operations/`、`definitions/` 和 `errors.json`。它只包含 `DeviceActionContract` 与 `HostOperationSpec` 两个业务命名空间。生成产物包括：

- `iOSDriver/src/generated/` 下的 TypeScript contract bundle；
- Swift wire-level metadata/fields；
- [`docs/generated/contracts.md`](../../generated/contracts.md) 文档片段。

修改合同后，在 `iOSDriver/` 运行 `npm run contracts:generate`，再运行 `npm run contracts:check` 确认没有 generated drift。generated 文件不能手写。

## HTTP 与 CLI 最小闭环

App 端点仍只接受 `POST /` 和 `{ action, data }`。仓库保留以下连通性示例：

```bash
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
# {"code":"ok","data":{"pong":true}}
```

CLI 侧对应调用为：

```bash
iosdriver call ping --data '{}'
```

`iosdriver doctor` 只探测 Node、配置、端点、`ping`、`help` 和合同兼容性；`iosdriver init` 幂等写入配置；`iosdriver mcp` 启动 stdio adapter。Host runtime 不启动或管理 `iproxy`、XcodeBuildMCP、设备和 App 生命周期。

## 能力与 artifact 判读

能力报告是运行时事实：端点或 `help` 不可达/不可解析记为 `unknown`；UIKit 或 Diagnostics 只注册部分 action 记为 `partial`；完全未注册记为 `not_registered`。这不会改变 MCP 启动时的静态工具列表；稳定工具和字段仍来自生成合同。

`ui.screenshot` 返回的 PNG 在 host runtime 中先解码为 image artifact：MCP adapter 输出 image content，CLI 只有传入 `--output <path>` 才写文件，否则 stdout 只包含 JSON metadata。当前协议不提供 stream/file artifact。

## skill 边界

本仓库的 `ios-automation` 负责入口检测和路由，`ios-mcp-setup` 负责 MCP 配置与工具可见性，`ios-connection` 负责端点、设备上下文和 USB 转发，`ios-ui-*`/`ios-logs` 负责具体 UI 或日志工作流。它们不复制合同 schema；需要字段、默认值或错误摘要时只链接 [`generated/contracts.md`](../../generated/contracts.md)。

仓库案例可以记录真实命令、目录和验收路径，但不得把这些内容写回通用 skill 正文：不要加入本仓库名称、示例 App、绝对路径、bundle ID、设备 ID、账号或历史验收结论。
