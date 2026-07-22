# 真机登录 Skill 验证报告

## 目标与范围

在不读取业务源码、不使用源码派生测试意图的前提下，验证 iOS 自动化 skills 能否完成真机登录。测试对象为已连接的 iPhone（iOS 26.5），使用 App 运行时 UI 自动化端点和进程内日志。

本报告只覆盖一次有效凭据登录，不将结果表述为完整登录流程覆盖率。

## 结果

| 项目 | 结果 | 运行时证据 |
| --- | --- | --- |
| 真机连接 | 通过 | iOSDriver `health_check` 返回 `pong: true`，动态 action 数为 30。 |
| 登录页定位 | 通过 | `ui.inspect` 发现用户名、密码和登录按钮均有可操作的 accessibility identifier。 |
| 表单输入 | 通过 | `ui.input` 成功写入用户名（长度 4）和安全密码（长度 6，响应中已掩码）。 |
| 提交 | 通过 | `ui.tap` 通过 `control.touchUpInside` 激活登录按钮。 |
| 成功终态 | 通过 | `wait_and_inspect` 检测到视图变化，最新快照为 `HomeViewController`，导航标题为“首页”，并显示“欢迎回来！”。 |
| 日志命令链 | 通过 | 增量 `app.logs.read` 显示 `ui.input`、`ui.tap`、`ui.waitAny` 均由路由器成功执行。 |

## 执行方式

1. 使用 `ios-automation` 确认 iOSDriver 和真机可用。
2. 使用 `ios-connection` 启动已存在的 USB `iproxy` 转发，并用真机 profile 启动 App 的登录入口。
3. 使用 `ios-ui-form` 的 `ui.inspect` 和 `ui.input` 填写 `test` 及密码。
4. 使用 `ios-ui-wait` 的 `wait_and_inspect` 等待错误文本或快照变化，再以首页标题、欢迎文本和控制器类型确认成功。
5. 使用 `ios-logs` 的 `app.logs.mark` / `app.logs.read` 读取本次提交后的 `explore` 与 `bridge` 日志。

## 发现的问题

> 2026-07-22 处理状态：以下两个问题均已完成代码修复和自动化回归。固定日志工具需要重连 iOSDriver MCP 后才能在当前客户端重新暴露；`ui.input` 日志去重已通过 Swift 与 iOS 模拟器测试验证。

### 1. 日志固定工具未暴露

`ios-logs` 说明中使用的 `app_logs_mark` 和 `app_logs_read` 固定 MCP 工具在当前客户端工具列表中不存在。尽管 `health_check` 报告 30 个动态 action 已加载，实际只能通过 `call_action` 转发 `app.logs.mark` 与 `app.logs.read`。

影响：流程仍可完成，但 skill 文档中“固定工具”与当前 MCP 暴露面不一致，自动化调用方必须额外实现 fallback，否则会错误地把日志能力判为不可用。

建议：为两个日志 action 增加稳定桥接工具，或在 `ios-logs` 中把 `call_action` fallback 写为首选兼容路径并提供完整参数示例。

处理结果：iOSDriver 已新增 `app_logs_mark` / `app_logs_read` 固定桥接，并使用统一的静态工具名清单阻止动态工具重名。TypeScript 回归覆盖了工具存在性、参数 schema、action 转发和动态工具冲突。

### 2. `ui.input` 记录重复的开始日志

本次增量日志中，同一次两字段 `ui.input` 只收到一次 HTTP 请求与一次成功完成记录，但出现了两条内容相同的开始日志：`command ui.input start fields=2 stopOnFailure=true viewSnapshot=snap-1`。

影响：本次操作与登录结果不受影响；但按“开始日志次数”统计请求数的测试会把一次输入误判为两次，特别是依赖 `app.logs.read` 做次数断言时。

建议：检查 `ui.input` 命令的生命周期日志写入点，确保每次 action 只写一条开始事件，或为日志加入可关联的请求标识后再做计数。

处理结果：批量 `start / completed / failed` 生命周期统一收敛到 `InputCommand`，executor 只保留逐字段日志。回归测试断言一次 `ui.input` 只产生一条批量 start 和一条 completed。

## 限制

- 只验证了有效凭据的成功路径，未覆盖空字段、错误凭据、网络失败、连续提交和退出登录。
- `snapshotChanged` 只表示 UI 已变化，不单独作为成功判据；本次最终通过首页控制器、标题和欢迎文本确认成功。
- 本次未保存截图，因为结构化 UI 快照和日志已足以判定功能结果，未发现视觉布局问题。
