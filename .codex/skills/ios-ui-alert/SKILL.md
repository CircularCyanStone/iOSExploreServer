---
name: ios-ui-alert
description: iOS App 内 UIAlertController 与 action sheet 的查询、输入和按钮响应。用于读取 alert 标题/消息/按钮、按 role/title/index 安全确认或取消、填写 alert 文本框、处理连续弹窗；系统权限弹窗和自定义模态视图不适用。触发词包括 alert、dialog、action sheet、确认框、取消、删除确认、ui.alert.respond、ui_alert_respond。
---

# iOS 弹窗查询与响应

处理 App 进程内的 `UIAlertController`。先用 `ui_inspect` 读取结构，再用 `ui_alert_respond` 触发按钮；不要让 respond 兼任查询。

## 决策流程

1. 触发可能产生弹窗的动作后，读取最新 `ui_inspect`。
2. 检查 `alert.available`：为 `false` 时不要调用 respond。同步弹窗可短暂等待后重查；异步弹窗交给 `ios-ui-wait` 等待终态。
3. 从 `alert.buttons` 读取现场 `index`、`title`、`role`，明确选择按钮。
4. 若 `alert.textFields` 非空，先用当次 inspect 返回的 path 或 identifier 调 `ui_input`，再响应按钮。
5. 调用 `ui_alert_respond` 后重新 inspect。用新的 `alert.available/title` 判断是否关闭或出现后续弹窗，不把 `presentedAfterDismiss` 当作“新弹窗存在”。

Action sheet 与普通 alert 使用同一流程和参数。

## 选择按钮

`buttonIndex`、`buttonTitle`、`role` 至多传一个：

| 选择器 | 何时使用 | 风险 |
|---|---|---|
| `role` | `cancel` / `default` / `destructive` 语义明确且该角色唯一 | 同一角色有多个按钮时只匹配第一个 |
| `buttonTitle` | 现场文案稳定，需要精确表达意图 | 大小写敏感且受本地化影响 |
| `buttonIndex` | 按钮顺序已由本次 inspect 确认 | 跨版本和文案变化时较脆弱 |

单按钮 alert 可不传选择器；多按钮 alert 必须显式选择，否则返回 `alert_button_required`。破坏性操作不要依赖默认选择。

`default`、`cancel`、`destructive` 使用同一等值匹配逻辑；不要为 destructive 额外重试或自动降级到其他按钮。

## 输入型弹窗

使用当次 `alert.textFields[]` 中的 `path` 或 `accessibilityIdentifier` 定位输入框。path 可能很深且会随弹窗重建而变化，不要硬编码或跨弹窗复用。

```text
ui_inspect
  -> alert.textFields[].path / accessibilityIdentifier
ui_input(fields:[{path 或 accessibilityIdentifier, text:"<value>", mode:"replace"}], viewSnapshotID:<本次快照>)
ui_alert_respond(role/title/index)
```

输入模式、批量字段和安全文本响应语义由 `ios-ui-form` 负责；此处只规定 alert 的定位与提交顺序。

## 结果判读

成功响应包含：

- `performed`：按钮 handler 已触发。
- `dismissed`：已请求关闭这个 alert；不是“之后没有其他 alert”。
- `dismissWaitMs`：等待该 alert 离场的耗时。
- `presentedAfterDismiss`：被响应的同一个 alert 等待后是否仍在 presenting chain。
- `button`：实际触发的 `index/title/role`。

连续弹窗必须逐个执行 `inspect -> respond -> inspect`。新弹窗是新对象，即使 `presentedAfterDismiss=false` 也可能已经出现。

## 失败分诊

| code | 含义 | 动作 |
|---|---|---|
| `alert_unavailable` | 当前顶层不是 `UIAlertController` | 重新 inspect；若为延迟结果，使用 `ios-ui-wait` |
| `alert_button_required` | 多按钮但未提供选择器 | 按本次 `alert.buttons` 显式选择 |
| `alert_button_not_found` | index 越界、title/role 不匹配或 role 非法 | 不猜测；按本次结构修正 |
| `alert_button_trigger_failed` | runtime 无法触发所选 action handler | 检查 App handler/运行路径；更换选择器通常无效 |
| `alert_release_unsupported` | Release 构建禁用了私有触发路径 | 使用 Debug 构建 |

若 respond 成功但同一 alert 仍存在，检查 App 是否阻止 dismiss 或转场是否卡住。若出现的是不同标题的新 alert，按连续弹窗流程继续处理。

## 边界

- 系统权限弹窗不在 App 内 `UIAlertController` 路径中，本 skill 不处理。
- 自定义弹层不是 alert；关闭与导航交给 `ios-ui-nav`，手势交给 `ios-ui-gesture`。
- 长时等待和成功/失败竞态归 `ios-ui-wait`；本 skill 只做弹窗附近的短稳定检查。
- 视觉取证归 `ios-ui-shot`。

`ui_alert_respond` 的触发路径仅 Debug 可用；命令在主线程执行。
