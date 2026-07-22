# 条件化等待套路

只在遇到多终态提交、确认 alert、loading 生命周期或服务端条件无法表达的复杂判定时读取本文件。示例中的尖括号字段必须替换为当前 App 通过 `ui_inspect` 发现的稳定 identifier 或可见文本。

## 多终态提交

把明确成功与明确失败都放入同一个等待预算。需要等待后继续操作时，优先一次取得新 snapshot：

```text
wait_and_inspect(
  conditions: [
    {id:"success", mode:"targetExists", accessibilityIdentifier:"<success-target-id>"},
    {id:"validation_error", mode:"textExists", text:"<validation-error-text>"},
    {id:"request_error", mode:"textExists", text:"<request-error-text>"}
  ],
  timeoutMs: 15000,
  intervalMs: 200
)
```

读取 `result.wait.matchedID`，不要读取顶层 `result.matchedID`。只有 `matchedID == "success"` 才按成功继续；两个错误 id 分别保留业务含义。`wait_timeout` 表示没有任何已建模终态出现，此时检查 `result.observation`，不要猜成功。

不要把 `targetGone(<loading-id>)`、`idle` 或 `snapshotChanged` 作为第四个“成功”分支：它们只描述过程变化。

## 确认 alert 的两段式等待

敏感动作可能先出现确认 alert，也可能直接到最终态。第一段等待“中间态或最终态”：

```text
wait_and_inspect(
  conditions: [
    {id:"confirmation", mode:"textExists", text:"<confirmation-text>"},
    {id:"completed", mode:"targetExists", accessibilityIdentifier:"<completed-target-id>"},
    {id:"failed", mode:"textExists", text:"<failure-text>"}
  ],
  timeoutMs: 5000,
  intervalMs: 200
)
```

- 命中 `confirmation`：用 `ios-ui-alert` 读取并响应当前 alert，然后执行第二段 `ui_waitAny`，只等待 `completed` 与 `failed`。
- 命中 `completed` 或 `failed`：直接按终态处理。
- 超时：从 `observation.alert` 与 targets 查找未建模状态。

不要尝试用等待命令点击 alert，也不要把 alert 出现本身判成业务失败。

## Loading 生命周期

`targetGone` 只判断当前不存在。按以下顺序避免“loading 从未出现也立即命中”的假阳性：

1. 动作后检查 loading 是否已被观察到存在。
2. 已观察到时，才用 `ui_wait(mode:"targetGone", ...)` 等它消失。
3. 未观察到时，跳过 `targetGone`，直接等待明确成功/失败终态。
4. loading 消失后仍等待明确终态或目标出现，再基于新的 `ui_inspect` snapshot 操作。

如果必须证明 loading 确实经历了“出现 → 消失”，先用 `targetExists` 等出现，命中后再用 `targetGone`。但很短的 loading 可能在首次轮询前已结束；此时应以最终业务终态为主，不应为了观察过程状态误报失败。

## 有界 Inspect 轮询

仅当现有五种 mode 无法表达条件时使用，例如需要计数、比较多个目标属性，或跨阶段组合状态：

1. 设置总 deadline，不无限循环。
2. 每 200...500ms 调用一次 `ui_inspect`，按当前任务计算条件。
3. 命中后立即停止；每次准备交互前使用最近一次 observation 的 snapshot。
4. deadline 到仍未命中时，保留最后一次 observation，并明确报告缺少哪个判据。

不要用固定次数替代 deadline，也不要通过高频 inspect 推断后台任务进度。
