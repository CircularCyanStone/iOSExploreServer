---
name: ios-ui-wait
description: iOS App 异步等待与动态内容稳定（开发验证 + 自动化测试）。用于等待 loading、目标或文本出现/消失、转场稳定、多个成功/失败结局之一、UI snapshot 变化，或在等待后立即检查最新 UI；覆盖 ui_wait、ui_waitAny、wait_and_inspect 与有界 ui_inspect 轮询。
---

# iOS 异步等待与动态内容稳定

把动作后的异步 UI 状态收敛为可判定结果。优先等待可观察条件，不使用固定 sleep 猜时机。

## 选择工具

| 需求 | 工具 | 返回后怎么做 |
|---|---|---|
| 只等一个条件 | `ui_wait` | 条件命中后重新 `ui_inspect` |
| 等多个互斥结局中的第一个 | `ui_waitAny` | 按 `matchedID` 分支，再重新 `ui_inspect` |
| 等待后立即需要最新 UI 与新 snapshot | `wait_and_inspect` | 从 `wait` 读取判定，从 `observation` 读取 UI |
| 条件涉及计数、跨阶段状态或自定义计算 | 有界 `ui_inspect` 轮询 | 每轮自行判定，总时长必须封顶 |

遇到确认弹窗、loading 生命周期或复杂轮询时，读取 [references/wait-patterns.md](references/wait-patterns.md)。普通单条件等待不要加载该 reference。

## 判定规则

1. 优先等待明确终态。提交类动作至少覆盖成功与失败条件；不要用 `idle`、`snapshotChanged` 或 loading 消失证明业务成功。
2. 按业务优先级排列 `ui_waitAny.conditions`。同一轮多个条件都满足时，返回数组中靠前的条件。
3. 只在已观察到目标存在后，用 `targetGone` 证明它随后消失。目标首轮就不存在时也会立即满足，因此它不能证明目标曾出现或流程曾启动。
4. 把 `snapshotChanged` 只当作“UI 结构或可签发状态发生变化”。它不等价于转场完成或业务成功；需要确定结果时继续等待明确终态。
5. 把 `idle` 只当作可见文本活动连续稳定。它无法感知网络请求或后台任务是否完成。
6. 等待导致 UI 改变后，不复用旧 `viewSnapshotID` 做后续交互。重新 `ui_inspect`，或直接使用 `wait_and_inspect.observation` 签发的新 snapshot。
7. 没有 `textGone` 模式。优先为承载文本的 view 提供稳定 identifier 后使用 `targetGone`；否则执行有界 `ui_inspect` 轮询。

## 模式与必需字段

| `mode` | 判定 | 必需字段 |
|---|---|---|
| `idle` | 活动签名连续 `stableMs` 不变，首轮不判稳定 | 无 |
| `targetExists` | 定位目标存在 | `accessibilityIdentifier` 或 `path`，二选一 |
| `targetGone` | 定位目标不存在 | `accessibilityIdentifier` 或 `path`，二选一 |
| `textExists` | 可见文本包含指定片段 | 非空 `text` |
| `snapshotChanged` | 当前指纹表与参照不同 | `ui_inspect` 签发的 `viewSnapshotID` |

公共参数：`timeoutMs` 为 0...30000，默认 3000；`intervalMs` 为 50...5000，默认 100；`stableMs` 为 0...10000，默认 300；`includeHidden` 默认 false。`ui_waitAny.conditions` 为 1...16 项，每项必须有唯一、非空的 `id` 和合法 `mode`；`timeoutMs`、`intervalMs`、`stableMs`、`includeHidden` 在所有条件间共享。

`includeHidden=false` 时，隐藏目标不算存在，隐藏文本不参与匹配。只有测试本身明确关心隐藏 view 时才改为 true。

## 返回契约

通过 MCP 工具调用时，读取工具正文中的以下结构，不要期待 `matched` 或 `matchedConditionId`：

- `ui_wait` 命中：`{satisfied:true, mode, elapsedMs, attempts}`。
- `ui_waitAny` 命中：`{satisfied:true, matchedID, matchedIndex, matchedMode, elapsedMs, attempts}`。
- `ui_wait` / `ui_waitAny` 超时：App action 返回 HTTP 200 的 `wait_timeout` 失败 envelope；MCP 工具把它规范化为 `{source:"ios_envelope", code:"wait_timeout", message, ...}`，并以 `isError=false` 保留为可解析业务结果。它不是成功响应中的 `satisfied:false`。
- `wait_and_inspect` 命中：`{wait:<ui_waitAny 命中结果>, observation:<ui_inspect 结果>}`。
- `wait_and_inspect` 超时：先把 `wait_timeout` 结构放入 `wait`，再尝试检查 UI，成功时返回 `{wait:<wait_timeout>, observation:<ui_inspect 结果>}`。若随后 `ui_inspect` 自身也失败，则不能假定存在 `observation`。

`wait_timeout` 是“deadline 内条件未满足”的业务结论，不是底层工具故障。根据 `observation` 或新的 `ui_inspect` 判断是条件写错、出现未建模中间态，还是业务确实未完成。

## 失败分诊

| 现象 | 原因 | 动作 |
|---|---|---|
| `invalid_data` 指向 mode | 使用了不存在的模式，如 `textGone` | 改用上表五种模式 |
| `invalid_data` 指向定位字段 | `targetExists/targetGone` 缺定位，或 identifier 与 path 同时提供 | 从 `ui_inspect` 选择一种定位方式 |
| `invalid_data` 指向 `text` | `textExists` 缺少非空文本 | 提供稳定、可见的文本片段 |
| `snapshotChanged` 一直超时 | snapshot 未变化、未知或已过期 | 重新 `ui_inspect` 获取 snapshot；需要明确结果时改等终态 |
| `targetGone` 立即命中 | 目标首轮就不存在或被隐藏 | 先确认目标存在；不要把该命中当作流程完成 |
| loading 消失后交互报 `target_not_found` / `stale_locator` | 消失不是内容就绪，且旧 snapshot 已失效 | 等明确目标出现，并使用新 observation/snapshot |
| 最终态超时但出现 alert | 条件漏掉了中间确认态 | 按 reference 的两段式 alert 流程处理 |
| 高频轮询让 UI 变慢 | 主线程反复遍历 view 树 | 提高 `intervalMs`；自定义 inspect 轮询通常从 200...500ms 起步 |

## 职责边界

- 点按、输入和 control 事件归对应交互 skill；本 skill 负责动作之后的等待。
- alert 的出现可在等待条件中建模；读取和响应按钮归 `ios-ui-alert`。
- 截图取证归 `ios-ui-shot`；等待本身不证明视觉布局正确。
- 连接与能力检查归 `ios-automation` / `ios-connection`。

本能力用于 Debug 自动化端点。等待基于当前 view 树可观察状态，不能直接读取网络任务、数据库写入或后台队列的完成状态。
