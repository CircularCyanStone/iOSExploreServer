# MCP 工具架构决策：静态工具与 call_action

## 决策

iOSDriver 不根据 App `help` 动态生成 MCP 工具。MCP 进程生命周期内的
`tools/list` 是稳定的静态集合，稳定的 UIKit、Diagnostics 能力各有明确工具名、描述和
schema；宿主私有、Debug、实验性或尚未稳定的 action 通过 `call_action` 调用。

App `help` 仍然保留，但只承担能力检查：报告当前 action 注册情况、静态工具依赖缺失项和
明显 schema 不兼容。能力检查的结果不会改变 MCP 工具列表。

## 为什么取消动态生成

过去动态工具把 App `help` 的 action 元数据映射为 MCP 工具，原本是为了让不同宿主 App 的
扩展 action 自动进入 Agent 工具面板。但这引入了启动时 HTTP 依赖、刷新竞态、客户端工具
缓存和 `tools/list_changed` 通知兼容性问题；action 名转换还会产生冲突，App schema 与
MCP 客户端支持的 schema 也可能不一致。工具数量和名称在 App 启动、模块注册、刷新失败
之间变化，使“工具不存在”和“App 不可达”难以区分，测试也必须覆盖多套动态状态。

稳定公共能力不应依赖这些运行时条件。静态 manifest 让 Agent 始终看到完整契约，App 未
启动时调用才返回明确 transport 错误，App 未注册模块时则返回原有 `unknown_action`。

## 当前工具集合

| MCP 工具 | App action |
|---|---|
| `health_check` | iOSDriver 自身，检查 `ping` 与 `help` |
| `check_capabilities` | iOSDriver 自身，读取 `help` 做能力诊断 |
| `call_action` | iOSDriver 自身，转发任意 action |
| `ui_topViewHierarchy` / `ui_inspect` / `ui_screenshot` | `ui.topViewHierarchy` / `ui.inspect` / `ui.screenshot` |
| `ui_control_sendAction` / `ui_tap` / `ui_input` / `ui_keyboard_dismiss` | 对应同名 `ui.*` action |
| `ui_scroll` / `ui_navigation_back` / `ui_navigation_tapBarButton` | 对应同名 `ui.*` action |
| `ui_wait` / `ui_waitAny` / `ui_scrollToElement` | 对应同名 `ui.*` action |
| `ui_alert_respond` / `ui_controllers` / `ui_swipe` / `ui_longPress` | 对应同名 `ui.*` action |
| `ui_tabBar_selectTab` / `ui_datePicker_setDate` / `ui_picker_selectRow` / `ui_webView_eval` | 对应同名 `ui.*` action |
| `app_logs_mark` / `app_logs_read` | `app.logs.mark` / `app.logs.read` |
| `wait_and_inspect` | 组合 `ui.waitAny` + `ui.inspect` |
| `ui_tap_and_inspect` | 组合 `ui.tap` + `ui.wait` + `ui.inspect` |

工具名、action 映射和 schema 集中在 `iOSDriver/src/staticTools.ts`；MCP 协议分发在
`iOSDriver/src/server.ts`。没有动态工具缓存、命名转换、冲突过滤或 schema 映射层。

## 完整调用时序

```text
MCP client
  -> initialize
  -> tools/list                         静态集合，与 App 状态无关
  -> tools/call <静态工具>
  -> iOSDriver HTTP POST / {action, data}
  -> iOS App Router
  -> HTTP status + {code, data/message}
  -> iOSDriver MCP content
```

`tools/call` 找到静态工具就执行其 handler；找不到则直接返回 MCP `unknown_tool`，不会
请求 App `help`。`ui.screenshot` 的 PNG 会转换成 MCP image content。`call_action` 保留
transport 重试、HTTP 错误和 App envelope 错误的结构化区分。

## 健康检查

`health_check` 一次检查调用 `ping` 和 `help`，结果区分 MCP server 是否正常、App ping/help
是否成功、当前 action 数量、缺失的静态依赖和 schema 不兼容。`check_capabilities` 提供
相同的能力诊断入口；两者都不刷新或改变 `tools/list`。

## 何时重新考虑动态工具

只有当宿主私有 action 具备稳定、可验证的跨客户端 schema，并且自动进入工具面板比
`call_action` 带来的不稳定性更有价值时，才应重新评估动态工具。届时必须先定义稳定的
命名、冲突、缓存和客户端通知协议，并补齐离线、刷新失败和 schema 兼容测试。
