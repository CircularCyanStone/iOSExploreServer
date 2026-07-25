# 开发者文档

这个目录放给人类开发者看的接入、安装和排障说明。Agent 专用的修改规则、验证策略和技能治理放在根 `AGENTS.md` 与 `docs/agents/`，不要混入本目录。

## 快速路径

1. App 侧接入 `iOSExploreServer`，按需注册 `iOSExploreUIKit` 和 `iOSExploreDiagnostics`。
2. 启动 Debug App；模拟器直接访问 `localhost:38321`，真机先启动 `iproxy 38321 38321`。
3. 用 `curl` 或 `iosdriver doctor` 检查连接。
4. 用 `iosdriver call <action>`、MCP 工具或直接 HTTP 调用执行自动化。

## 文档索引

| 主题 | 文档 |
| --- | --- |
| App 接入与核心协议 | [根 README](../../README.md) |
| 项目整体架构 | [architecture.md](architecture.md) |
| 单次 action 数据流 | [action-flow.md](action-flow.md) |
| iOSDriver CLI/MCP | [iOSDriver README](../../iOSDriver/README.md) |
| 本地 CLI/MCP 安装 | [iOSDriver/install](../../iOSDriver/install/) |
| 当前 action 合同 | [generated/contracts.md](../generated/contracts.md) |
| UIKit action 设计 | [docs/uikit](../uikit/README.md) |
| Diagnostics 接入 | [docs/diagnostics](../diagnostics/README.md) |
| 构建与测试 | [runbooks/build-and-test.md](../runbooks/build-and-test.md) |
| 端口与真机排障 | [runbooks/debugging.md](../runbooks/debugging.md) |

## 维护规则

- 开发者文档写“怎么接入、怎么安装、怎么调用、失败怎么查”。
- Agent 文档写“修改代码时必须遵守什么、读哪些文件、怎么验证”。
- 合同字段以 `contracts/` 和生成的 `docs/generated/contracts.md` 为准；README 只放入口示例，不复制长 schema。
- 本机绝对路径、设备 ID、测试账号和一次性验收记录不要进入通用文档。
