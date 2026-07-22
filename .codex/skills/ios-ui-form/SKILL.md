---
name: ios-ui-form
description: iOS App 表单填写与控件操作（开发验证 + 自动化测试）。用于 UITextField、UITextView、UISearchTextField 文本输入，UISwitch、UISlider、UIStepper、UISegmentedControl 设值，键盘处理、表单提交和屏幕外字段定位；触发词包括 form、text input、switch、slider、stepper、segmented、keyboard、submit、ui_input、ui_control_sendAction。
---

# iOS 表单填写与控件操作

把本 skill 的职责限制为：发现字段、填写文本、设置控件、处理必要的键盘状态并触发表单提交。异步终态判定转 `ios-ui-wait`，alert 响应转 `ios-ui-alert`，提交后的导航验证转 `ios-ui-nav`。

需要完整流程时按需读取 [references/form-examples.md](references/form-examples.md)：通用异步表单、同步校验、确认 alert 和 UISearchBar 变体都在该文件中。

## 核心流程

1. 调 `ui_inspect` 发现输入字段、控件和提交目标，保存当前 `viewSnapshotID`。
2. 文本字段用一次 `ui_input` 批量填写；数值或选择控件用 `ui_control_sendAction`。
3. 仅在键盘遮挡目标、业务依赖结束编辑，或任务明确验证键盘状态时处理键盘。
4. 滚动、换屏、键盘开合或等待后继续操作前，重新 `ui_inspect`。
5. 触发提交后按同步或异步分流，不把中间态当成最终结果。

## 选择工具

| 目标 | 工具 | 关键规则 |
|---|---|---|
| `UITextField` / `UITextView` / `UISearchTextField` | `ui_input` | 顶层始终传 `fields` 数组；单字段也放入数组 |
| `UISwitch` / `UISlider` / `UIStepper` / `UISegmentedControl` | `ui_control_sendAction` | 设值使用 `event:"valueChanged"`，并检查 `currentValue` |
| 普通按钮 | `ui_tap` 或 `ui_tap_and_inspect` | 不用 `sendAction` 模拟普通点击 |
| 屏幕外字段 | `ui_scrollToElement` | 滚动后重新 inspect，再输入 |
| 键盘结束编辑 | `ui_input submit:true` 或 `ui_keyboard_dismiss` | 只在业务确实依赖该语义时使用 |

## 文本输入

`ui_input` 支持 `UITextField`、`UITextView` 和 `UISearchTextField`。

| 参数 | 规则 |
|---|---|
| `fields[].text` | 必填；空字符串表示清空 |
| `fields[].accessibilityIdentifier` / `path` | 每项二选一，优先稳定 identifier |
| `viewSnapshotID` | 使用本轮 inspect 的顶层值 |
| `fields[].mode` | `replace`（默认）或 `append` |
| `fields[].submit` | 默认 `false`；仅用于 Return / Done / Search / 结束编辑语义 |
| `stopOnFailure` | 默认 `true`；批量表单通常保持默认值 |

关键约束：

- Unicode、emoji 和中文可直接传；工具走 `UITextInput.insertText`，不是键盘码。
- 安全字段响应不返回原文。失败后 App 可能清空安全字段，重试时必须重新填写。
- 换行只用于 `UITextView`；向单行 `UITextField` 传换行会返回 `input_rejected`。
- `submit:true` 会改变输入事件语义，不要把它当作默认的“输完收键盘”。

## 控件设值

对值控件发送 `valueChanged`，并显式传目标值；省略 `value` 只派发事件，不保证控件值发生变化。

| 控件 | `value` | 行为 |
|---|---|---|
| `UISwitch` | `0` 或 `1` | 设置 off / on；若只需按用户点击语义翻转，可用 `ui_tap` |
| `UISlider` | `0.0...1.0` | 设置目标比例，最终值以 `currentValue` 为准 |
| `UIStepper` | 数值 | 设置绝对值，不是增减步数 |
| `UISegmentedControl` | 从 0 开始的整数索引 | 设置选中项 |

控件必须可用，且目标必须是 inspect 返回的 full 节点。用响应中的 `previousValue`、`currentValue`、`isEnabled` 和 `isSelected` 核对实际结果。

## 快照、滚动与键盘

- `viewSnapshotID` 必须来自当前屏幕。scroll、换屏、键盘开合和较长等待都可能让旧定位失效。
- 长表单先用 `ui_scrollToElement` 将字段滚入可见区；该命令后必须重新 inspect。
- 键盘遮挡目标时，先尝试业务要求的 `submit:true`；否则用 `ui_keyboard_dismiss(strategy:"auto")`。`auto` 先尝试当前 first responder，再回退到整棵 view 树结束编辑。
- `UISearchBar` 是容器，实际输入目标是内部 `UISearchTextField`。输入或获取焦点后动态按钮可能变化，应重新 inspect。

## 提交分流

- **同步校验或本地切页**：使用 `ui_tap_and_inspect`。结果结构是 `{tap, stateAfter, timing}`，从 `stateAfter.targets`、`stateAfter.alert` 或导航摘要读取提交后状态。
- **网络或其他异步提交**：使用 `ui_tap` 只负责触发，然后转 `ios-ui-wait`，等待明确的成功和失败终态。不要用提交后的首个 inspect、固定 sleep、`snapshotChanged` 或 loading 消失单独判成功。
- **可能出现确认 alert**：先把 alert 出现作为分支；命中后转 `ios-ui-alert` 响应，再等待最终成功或失败。表单 skill 不复制 alert 按钮选择规则。

`targetGone` 只表示当前找不到目标。若 loading 从未出现，它也会立即满足；只有先确认 loading 出现后，才能把其消失用于阶段推进，而且之后仍须验证明确成功或失败终态。

## 失败分诊

| code / 现象 | 含义 | 动作 |
|---|---|---|
| `become_first_responder_failed` | 字段不可聚焦、被遮挡或不在可视区 | inspect 可用性；必要时滚动或先 tap 字段 |
| `input_rejected` | 委托拒绝或单行字段收到换行 | 核对控件类型和输入内容，不盲目重试 |
| `stale_locator` | snapshot 已过期或 view 树变化 | 重新 inspect 后重试 |
| `not_actionable` | 目标为 minimal 节点或当前不可操作 | 改用 full 目标或先完成启用它的业务步骤 |
| `invalid_data` | 事件、值、索引或定位参数不合法 | 按控件类型修正参数 |
| 提交后只见 loading | 读取了异步中间态 | 转 `ios-ui-wait` 等明确成功 / 失败分支 |
| 失败后安全字段为空 | App 清空了敏感输入 | 重试前重新填写安全字段 |

## 边界

- `ios-ui-wait`：拥有异步等待条件、超时和结果判定规则。
- `ios-ui-alert`：拥有 `UIAlertController` 查询与响应规则。
- `ios-ui-nav`：拥有提交后的页面切换与返回验证。
- `ios-ui-picker`：拥有 `UIDatePicker` / `UIPickerView` 设值。
- `ios-ui-list`：拥有列表选择和滚动查找。

本能力仅用于启用自动化端点的 Debug 构建。控件动作在主线程执行，必须在命令超时内完成。
