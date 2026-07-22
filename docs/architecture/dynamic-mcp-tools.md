# 动态 MCP 工具设计说明

本文专门说明 iOSDriver 中“动态工具”的设计目的、适用范围和运行边界。这里的“动态工具”是项目内部术语，不是 MCP 协议中的另一种工具类型：它们最终仍通过同一个 `tools/list` 暴露、通过同一个 `tools/call` 调用。

## 为什么需要动态工具

iOSExploreServer 的 App 可以由宿主按需注册命令。除了 core 的 `ping`、`echo`、`info`、`help`，示例 App 还可以注册 `greet`、`device`、`debug.*`；UIKit 和 Diagnostics 也只有在宿主显式注册后才会出现。不同 App、不同 Debug 配置的 command 集合可能不同。

如果 iOSDriver 为每个宿主 App 的每个私有 action 都写一份 TypeScript 工具，Driver 会失去跨 App 复用能力，新增 App 命令也必须同步发布 Driver。动态工具解决的是这个扩展问题：Driver 读取 App 的 `help`，把未被静态核心工具占用的 App command 转成 MCP 工具。

动态工具**不**负责保证核心工作流可用，也不应该成为登录、UI 探索或日志排障的唯一入口。

## 三个概念必须区分

### MCP 协议能力

MCP 正式定义了：

- `tools/list`：读取当前工具列表；
- `tools/call`：调用工具；
- `tools.listChanged` 和 `notifications/tools/list_changed`：工具列表变化时通知客户端。

MCP 支持动态列表，但没有要求服务端必须从某个 HTTP `help` action 自动生成工具。列表变化通知也不能替代静态核心工具，因为客户端对通知的处理速度和完整性可能不同。

### iOSDriver 的实现

iOSDriver 的动态路径是：

```text
App help
  -> ToolRegistry.refresh()
  -> action 名转换为 MCP 名
  -> 静态名/名称冲突过滤
  -> schemaMapper 适配 schema
  -> tools/list 返回动态快照
```

`help` 是 App 的 HTTP action，不是 MCP `tools/list`。`ToolRegistry` 是 Driver 的适配层，不属于 App core 协议。

### 项目工程术语

- **静态工具**：在 `iOSDriver/src/staticTools.ts` 中写死名称、schema 和 handler 的工具。
- **动态工具**：运行时从 App `help` 生成 `ToolDefinition` 的工具。
- 两者在 MCP 线上没有不同的调用格式。

## 工具分层

### 静态核心工具

静态核心工具承担稳定、可预测和故障恢复职责，当前包括：

- `health_check`、`refresh_tools`、`call_action`；
- `app_logs_mark`、`app_logs_read`；
- `ui_inspect`、`ui_input`、`ui_tap`、`ui_control_sendAction`；
- `ui_keyboard_dismiss`、`ui_scrollToElement`、`ui_wait`；
- `wait_and_inspect`、`ui_tap_and_inspect`。

新增的稳定 UIKit/Diagnostics 公共 action 应优先进入静态核心契约，而不是依赖 App 启动后动态发现。静态工具的 schema 应与 Swift `help` schema 通过测试或单一 manifest 保持一致。

### 动态扩展工具

动态工具适合：

- 宿主 App 私有 action，例如 `greet`、`device`；
- `debug.*`、`experimental.*` 等调试或实验能力；
- 尚未承诺稳定 schema 的新命令；
- 不同 App 之间确实不同的业务命令。

动态扩展不应覆盖已有静态工具名。冲突会被过滤并通过 `refresh_tools` 的 `conflicts` 返回诊断信息。

## `help` 的职责

`help` 保留，但职责是：

1. 发现 App 当前有哪些能力；
2. 校验静态核心 action 是否存在、schema 是否兼容；
3. 诊断 App build、注册模块和 command 集合差异；
4. 为动态扩展提供候选 metadata。

`help` 不应成为核心工具可见性的前置条件。App 不可达时，MCP server 仍应先启动并暴露静态工具。

## 生命周期和失败语义

```text
MCP server 启动
  -> 立即 connect，静态工具可见
  -> 客户端 initialized
  -> 后台 refresh help
  -> 动态快照变化时发送 tools/list_changed
  -> 客户端重新 tools/list
```

当前实现约定：

- refresh 成功且工具列表实际变化时才发送 `tools/list_changed`；
- refresh 失败保留最后一次成功的动态快照；
- 初次 App 不可达不会阻塞 MCP 初始化；
- `tools/call` 找不到工具时会尝试一次 refresh，既支持 `ui_*` 也支持 App 自定义名称；
- refresh 失败返回结构化 transport/refresh 错误，不把 App 不可达误报成 `unknown_tool`；
- `call_action` 永远保留，作为动态扩展不可见、名称冲突或客户端未及时刷新时的兜底入口。

## 为什么不能全部依赖动态工具

动态列表存在以下天然不确定性：

- App 可能尚未启动或尚未注册 UIKit/Diagnostics；
- 客户端可能已经缓存旧的 `tools/list`；
- 列表变化通知可能被客户端延迟处理；
- action 名转换可能发生冲突，例如 `a.b` 和 `a_b`；
- App `help` 的嵌套 schema 可能比运行时 parser 更粗；
- schemaMapper 为兼容客户端会改写 `oneOf`、约束和数组 enum。

因此核心 UI 和日志流程必须拥有静态入口；动态工具只提供扩展便利。

## 新增 action 的决策规则

| 问题 | 结论 |
|---|---|
| 所有 App 都需要，且属于稳定测试流程？ | 静态工具 |
| 日志、观察、定位、等待或故障恢复必需？ | 静态工具 |
| 只属于某个宿主 App？ | 动态扩展 + `call_action` 兜底 |
| `debug.*` 或实验性 schema？ | 动态扩展 |
| schema 仍可能频繁变化？ | 先动态，稳定后再转静态 |
| 与静态工具名冲突？ | 不动态暴露，修正命名或使用 `call_action` |

## 调试方法

遇到“工具不存在”时按以下顺序判断：

1. 调用 `health_check`，确认 App、端口和 help 是否可达；
2. 调用 `refresh_tools`，查看动态数量、冲突和 refresh 错误；
3. 再查看客户端是否重新请求了 `tools/list`；
4. 如果仍不可见，使用 `call_action` 直接调用原始 App action；
5. 若 `call_action` 返回 `unknown_action`，才说明 App 当前确实没有注册该 action。

不要把“客户端没有显示工具”和“App 没有注册 action”当成同一个问题。

## 相关实现和测试

- 静态工具：[iOSDriver/src/staticTools.ts](../../iOSDriver/src/staticTools.ts)
- 动态注册表：[iOSDriver/src/toolRegistry.ts](../../iOSDriver/src/toolRegistry.ts)
- MCP 暴露和调用：[iOSDriver/src/server.ts](../../iOSDriver/src/server.ts)
- action 名和冲突：[iOSDriver/src/toolName.ts](../../iOSDriver/src/toolName.ts)
- 动态注册测试：[iOSDriver/tests/toolRegistry.test.ts](../../iOSDriver/tests/toolRegistry.test.ts)
- MCP handler 测试：[iOSDriver/tests/server.test.ts](../../iOSDriver/tests/server.test.ts)

