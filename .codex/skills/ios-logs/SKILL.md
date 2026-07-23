---
name: ios-logs
description: 读取 iOS App 当前进程内的 Debug 日志，用于增量监控、按来源或等级排查、日志断言，以及区分命令链、业务结果和系统噪音。Use for app.logs.mark/read, stdout, stderr, NSLog, os_log, Swift Logger, ExploreAppLog bridge, capture state, cursor, pagination, gap, and stale cursor troubleshooting.
---

# iOS App 进程内日志读取

使用 iOSDriver 的 `app_logs_mark` 和 `app_logs_read` 读取 App 当前进程的内存日志。该能力只适用于已注册 Diagnostics 命令的 Debug App；它不持久化日志，也不替代系统级控制台日志。

## 核心流程

严格执行以下顺序：

1. 在被测动作即将发生前调用 `app_logs_mark`，保存结果中的 `cursor`。
2. 触发被测动作。
3. 调用 `app_logs_read`，把 cursor 原样传入 `after`，只读取本次动作后的日志。
4. 先检查响应中的 `capture`，再解释空 `entries`。
5. 若 `hasMore:true`，用 `nextCursor` 继续读取，直到 `hasMore:false`。

不要在动作后 mark，也不要在增量验证中省略 `after`。省略 `after` 会返回当前可见的最近 `limit` 条，可能混入历史噪音。

cursor 只属于一个 `captureSessionID`。App 或 Diagnostics Runtime 重启后重新 mark；跨 session 使用旧 cursor 会返回 `stale_cursor`。`gap` 表示 ring buffer 已覆盖部分请求范围，不代表当前返回条目有问题，但证据已经不完整。

## 选择日志来源

| source | 实际写入路径 | 适合判断什么 |
|---|---|---|
| `explore` | core 与扩展模块经 `ExploreLogging` 写入；UIKit 命令日志也走此来源 | HTTP、路由、命令注册与执行链 |
| `bridge` | 宿主通过 `ExploreAppLog.emit(...)` 主动写入 | 高信号业务事件 |
| `stdout` | 当前进程的 `print` 或 stdout 输出 | 临时标准输出 |
| `stderr` | 当前进程的 stderr 输出，等级固定为 `error` | 错误标准流 |
| `nslog` | stderr 行识别、fishhook Objective-C/C 增强路径或 OSLogStore fallback 捕获到的 `NSLog` | Objective-C、旧代码或第三方日志 |
| `oslog` | 当前进程中可读取的 `os_log` 与 Swift `Logger` entry | Apple Unified Logging |

`explore` 与 `bridge` 默认开启且不依赖系统日志读取权限。`bridge` 不是 UIKit 命令日志来源；宿主未调用 `ExploreAppLog.emit(...)` 时，不应期待出现业务 bridge 日志。

## 先检查捕获状态

`app_logs_mark` 和 `app_logs_read` 都返回六个 source 的 `capture` 快照：

| state | 含义 | 动作 |
|---|---|---|
| `enabled` | 来源已安装并可向内存 store 写入 | 继续读取和判断 |
| `notCaptured` | 对应配置未开启，或当前构建不捕获 | 需要该来源时开启配置并重启 App |
| `unavailable` | 已请求捕获，但系统版本、权限或安装步骤不允许 | 查看 `reason`，改用可用来源或系统级日志 |

`notCaptured` 和 `unavailable` 都不能证明“日志没有发生”或“代码没有执行”。只有 source 为 `enabled`，且 cursor、过滤条件、分页和异步刷新均正确时，空结果才可作为“当前捕获范围内未观察到该日志”的证据。

需要开启或排查 `stdout`、`stderr`、`nslog`、`oslog` 时，读取 [capture-troubleshooting.md](references/capture-troubleshooting.md)。正文不按模拟器或真机写死可用性，始终以本次响应的 `capture.state` 和 `reason` 为准。

## 低噪音读取

按需逐级扩大范围：

1. 先读 `sources:["explore","bridge"]`，确认命令链和宿主主动业务日志。
2. 需要查异常时，再用 `minimumLevel:"error"` 读取所有已启用来源。
3. 只有排查捕获通道、分页或底层日志时，才读取全部 source 和 debug 级别。

每次结论分成三层：

| 层级 | 主要证据 | 判定边界 |
|---|---|---|
| 自动化命令 | `explore` | 只证明请求、路由和命令执行结果 |
| 业务结果 | 明确 UI 终态或 `bridge` | 用于判断被测功能成功或失败 |
| 系统与环境 | `oslog`、`nslog`、`stderr` | 作为诊断证据，不单独替代业务结论 |

不要因系统来源出现一条 `error` 就判业务失败；也不要仅凭 `explore` 命令成功就判业务成功。

## 读取契约

`app_logs_mark` 无入参，关键返回字段为 `cursor`、`capture`、`oldestAvailableID` 和 `latestAvailableID`。

`app_logs_read` 的稳定参数：

| 参数 | 约束 |
|---|---|
| `after` | mark 或上次 read 返回的 cursor；增量读取必传 |
| `limit` | `1...500`，默认 `100` |
| `sources` | 可选数组；合法值仅为上述六种 source |
| `minimumLevel` | `debug`、`info`、`error`、`fault`、`unknown` |

关键返回字段为 `entries`、`nextCursor`、`capturedThrough`、`hasMore`、`gap` 和 `capture`。过滤读取时，`nextCursor` 指向最后扫描的物理日志位置，不一定等于最后返回 entry 的 id；分页必须传回完整 `nextCursor`。

## 失败分诊

- 空结果：先检查 source 的 `capture.state`，再检查 mark 是否早于动作、`after` 是否正确、source 名和等级过滤是否排除了目标，最后处理分页或 oslog 异步刷新。
- `stale_cursor`：App 或 Runtime 已换 session，重新 mark 后重试，不复用旧 cursor。
- `gap` 非空：ring buffer 已覆盖部分日志；记录证据不完整，重新 mark 并缩短动作到读取的间隔。
- 参数失败：不要使用 `print`、`os_log`、`Logger` 作为 source 名；分别使用 `stdout` 或 `oslog`。
- Diagnostics action 为 `unknown_action`：宿主未注册 Diagnostics 命令；回到集成配置检查，不把它判断成日志为空。

## 边界与路由

- 需要系统级或其他进程日志时，使用构建/设备管理层的日志能力。
- 连接失败、端口或设备上下文问题路由到 `ios-connection`。
- 不确定从哪种自动化能力开始时路由到 `ios-automation`；本 skill 只负责 App 当前进程内日志。
