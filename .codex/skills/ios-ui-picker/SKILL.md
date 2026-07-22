---
name: ios-ui-picker
description: iOS App 的 UIDatePicker 精确设值和 UIPickerView 选行。用于按 ISO 8601 或日期分量设置日期、按 row/title 选择 picker 行并触发 valueChanged/delegate；UISegmentedControl 等普通表单控件不适用。触发词包括 date picker、picker view、select row、set date、生日、预约、地区选择、ui_datePicker_setDate、ui_picker_selectRow。
---

# iOS 日期与滚轮选择器

使用专用静态工具，不要用手势去猜具体日期或行，也不要绕到 `call_action`：

- `ui_datePicker_setDate` 对应 `UIDatePicker`。
- `ui_picker_selectRow` 对应 `UIPickerView`。

需要调用示例时，按目标类型读取 [picker-examples.md](references/picker-examples.md)。

## 通用流程

1. 用 `ui_inspect` 确认控件类型和当前 identifier/path。
2. 优先用唯一 `accessibilityIdentifier`；没有稳定 identifier 时使用当次 path，并携带 `viewSnapshotID` 做陈旧校验。
3. 调用对应专用工具。
4. 先用工具返回值核对控件状态；业务 label 或页面联动是独立终态，必要时再 inspect/wait。

## UIDatePicker

日期来源必须二选一：

- `date`：ISO 8601 datetime（可含毫秒/时区）或 `yyyy-MM-dd`；仅日期按 UTC 00:00:00 解析。
- `year/month/day/hour/minute`：至少提供一个；未提供分量沿用 picker 当前日期。

两种来源同时提供或都不提供会返回 `invalid_data`。`animated` 默认 `false`。

设置后命令调用 `sendActions(for:.valueChanged)`。返回 `type/mode/previousDate/date`，日期统一为 ISO 8601 UTC。先核对返回的 `date`，再判断业务副作用。

当前 parser 只要求日期分量为非负整数，不对 month/day/hour/minute 做日历范围拒绝；`Calendar` 可能规整超范围组合。需要精确日期时提供正常范围，并以返回的 `date` 为准。

## UIPickerView

- `component` 必填且为 0-based。
- `row` 与 `title` 必须且只能提供一个。
- `title` 精确匹配 delegate 的 `titleForRow`，取首个匹配。
- App 使用 `viewForRow` 而没有 `titleForRow` 时，改用 `row`。
- `animated` 默认 `false`。

选行后命令补调 `pickerView(_:didSelectRow:inComponent:)`。返回 `numberOfComponents/component/numberOfRowsInComponent/selectedRow/selectedTitle`；`selectedTitle` 可能因 delegate 未提供 title 而为空。

## 失败分诊

| code/现象 | 原因 | 动作 |
|---|---|---|
| `invalid_data` 且目标类型不符 | identifier/path 指向了其他 view | 重新 inspect，确认 `UIDatePicker` 或 `UIPickerView` |
| `invalid_data` 且 component/row 越界 | 索引不在当前数据源范围 | 根据 message 或返回的计数修正 |
| `target_not_found` 且 title 未命中 | 文案不一致或只实现 `viewForRow` | 核对精确 title，或改用 row |
| `target_not_found` 且 picker 未找到 | 页面、sheet 或目标路径已变化 | 重新 inspect，必要时先等待出现 |
| `stale_locator` | 携带的快照已陈旧 | 使用新 inspect 的 path/snapshot |
| 返回日期与输入分量不同 | Calendar 规整了不合法组合 | 使用合法分量，或直接传完整 ISO 日期 |

`UISegmentedControl/UISlider/UIStepper/UISwitch` 和文本输入归 `ios-ui-form`；进入 picker 页面归 `ios-ui-nav`；异步出现或业务联动归 `ios-ui-wait`。

两个专用命令均使用公开 UIKit 设值 API，整套自动化仍只在 Debug 集成中使用。
