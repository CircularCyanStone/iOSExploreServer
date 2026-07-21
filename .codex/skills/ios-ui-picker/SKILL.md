---
name: ios-ui-picker
description: iOS App 日期选择器与滚轮选择器操作(开发验证 + 自动化测试)UIDatePicker / UIPickerView / date picker, picker view, select row, set date, birthday, 生日, 预约, 地区选择, ui.datePicker.setDate, ui.picker.selectRow, call_action
---

# iOS 日期选择器与滚轮选择器操作

基于 iOSDriver MCP Server,覆盖 `UIDatePicker`(生日 / 预约 / 日程 / 倒计时)与 `UIPickerView`(地区 / 分类 / 多列选项)两类"滚轮控件"的程序化设值。两者都**不在 `ui.inspect` 的可设值能力表里**——`UIDatePicker` 虽是 `UIControl` 但只声明 `touchDown/touchUpInside`、`ui.control.sendAction` 的 `value` 不支持它;`UIPickerView` 根本不是 `UIControl`。因此无法用 `ui.tap` / `ui.control.sendAction` / `ui.scroll` 精确设值(滚 wheel 无法对应到具体日期 / 行),必须走本 skill 的两条专用命令,经 `call_action` 调用。

## 目标

解决"把 UIDatePicker 设到某个日期 / 把 UIPickerView 选到某一行,并确认设值生效"这一 iOS 自动化高频场景。关键是分清两条命令的语义边界:

- **`ui.datePicker.setDate`** 设 `UIDatePicker.date`:支持 ISO 8601 整日期,也支持只给部分分量(`year`/`month`/`day`/`hour`/`minute`,未给的分量沿用 picker 当前值)。设值后自动 `sendActions(.valueChanged)`,触发绑定在 picker 上的 target-action。
- **`ui.picker.selectRow`** 选 `UIPickerView` 某列某行:按 `row`(索引)或 `title`(读 dataSource/delegate 的 `titleForRow` 比对首个匹配)二选一。选行后手动补调 `pickerView(_:didSelectRow:inComponent:)` delegate(`selectRow` 本身不触发),覆盖挂在 didSelectRow 上的业务逻辑。
- **定位优先 `accessibilityIdentifier`**:两条命令都支持 `accessibilityIdentifier` / `path` 二选一定位,`viewSnapshotID` 可选(携带才做陈旧校验)。用 identifier 可免 `viewSnapshotID`,跨多步设值更省事。

## 何时使用

- ✅ 用户要"把生日选成 1990-01-01" / "设预约时间为某天某时"(`UIDatePicker`)
- ✅ 用户要"在地区选择器选'上海市'" / "选第 3 个选项"(`UIPickerView`)
- ✅ 用户要"把日期滚到某个年份但保留当前月日"(用 `components` 只给 `year`)
- ✅ 用户说 "日期选择" / "时间选择" / "picker" / "滚轮" / "选日期" / "选城市"
- ❌ 不要用于 `UISearchBar`(走 `ios-ui-form`,本质是文本框 + 按钮)
- ❌ 不要用于 `UISegmentedControl` / `UISlider` / `UIStepper`(走 `ios-ui-form` 的 `ui.control.sendAction`,它们在能力表里)
- ❌ 不要用于纯手势滚动(滚 wheel 到大致区域用 `ui.scroll`,但要精确到具体日期 / 行必须用本 skill)

## 工作原理

设值时序:**inspect 确认 picker 存在(可选,用 identifier 可跳过)→ call_action 设值 → 读返回的 `date`/`selectedRow` 确认 → (可选)inspect 读业务 label 确认 UI 同步**。

### 1. UIDatePicker(`ui.datePicker.setDate`)

经 `call_action` 调用,action 名 `"ui.datePicker.setDate"`。日期来源二选一:

- **`date`**(ISO 8601 字符串):完整 datetime 如 `"1990-01-01T00:00:00Z"`(可带时区 / 毫秒),或仅日期 `"1990-01-01"`。最直接,适合已知完整日期。
- **`components`**(分量):`year` / `month` / `day` / `hour` / `minute` 各自可选,只给关心的分量,**未给的分量沿用 picker 当前值**。适合"只改年份保留月日"。

两者互斥(同时给或都不给返回 `invalid_data`)。

```javascript
// 整日期(最常用)
await mcp__iOSDriver__call_action({
  action: "ui.datePicker.setDate",
  data: {
    accessibilityIdentifier: "birthday_picker",
    date: "1990-01-01T00:00:00Z"
  }
})
// → { type: "UIDatePicker", mode: "date", previousDate: "...", date: "1990-01-01T00:00:00Z" }

// 只改年份,保留当前月日时分
await mcp__iOSDriver__call_action({
  action: "ui.datePicker.setDate",
  data: {
    accessibilityIdentifier: "birthday_picker",
    year: 2000
  }
})
```

返回:`type` / `mode`(`date`/`time`/`dateAndTime`/`countDownTimer`)/ `previousDate` / `date`(均为 ISO 8601 UTC)。`previousDate` 与 `date` 直接反映设值前后状态,无需额外 inspect 即可核对。

设值后命令自动 `sendActions(for: .valueChanged)`,挂在 picker 上的 target-action(如 `datePicker.addTarget(..., for: .valueChanged)`)会被触发。若业务在 valueChanged 里刷新关联 label,设值后 label 同步更新。

> `animated`(默认 `false`)控制过渡动画。设 `true` 会以动画过渡到新日期(端到端验证时读回值仍是最终值,不受动画影响)。

### 2. UIPickerView(`ui.picker.selectRow`)

经 `call_action` 调用,action 名 `"ui.picker.selectRow"`。目标行用 `row`(索引)或 `title`(标题)二选一;`component`(列索引)必填:

```javascript
// 按索引选(已知位置)
await mcp__iOSDriver__call_action({
  action: "ui.picker.selectRow",
  data: {
    accessibilityIdentifier: "city_picker",
    component: 0,
    row: 2
  }
})

// 按标题选(顺序会变时更稳)
await mcp__iOSDriver__call_action({
  action: "ui.picker.selectRow",
  data: {
    accessibilityIdentifier: "city_picker",
    component: 0,
    title: "上海市"
  }
})
// → { type: "UIPickerView", numberOfComponents: 1, component: 0,
//     numberOfRowsInComponent: 5, selectedRow: 1, selectedTitle: "上海市" }
```

返回:`numberOfComponents` / `component` / `numberOfRowsInComponent` / `selectedRow` / `selectedTitle`。`selectedTitle` 从 delegate 的 `titleForRow` 读回,既验证选中正确,也间接证明 delegate 链路可用。

选行后命令手动补调 `pickerView(_:didSelectRow:inComponent:)` delegate(`selectRow(_:inComponent:animated:)` 本身不触发 delegate,与 `ui.tabBar.selectTab` 触发 delegate 同理),覆盖挂在 didSelectRow 上的埋点 / 联动 / 刷新逻辑。

> **按 `title` 选的前提**:delegate 必须实现 `pickerView(_:titleForRow:forComponent:)`。若 App 用 `pickerView(_:viewForRow:reusingView:)` 自定义行(无 title 文本),按 title 选会返回 `target_not_found`(遍历全行 title 均为 nil)——此时改用 `row` 索引。

## 关键参数

### `ui.datePicker.setDate`

| 参数 | 含义 | 注意 |
|---|---|---|
| `accessibilityIdentifier` / `path` | 定位目标 UIDatePicker(二选一) | 优先 identifier;用 identifier 可省 `viewSnapshotID` |
| `viewSnapshotID` | `ui.inspect` 签发的快照标识 | 可选;携带才做陈旧校验 |
| `date` | ISO 8601 日期字符串 | 与 `components` 互斥;支持 `1990-01-01T00:00:00Z` / `1990-01-01` |
| `year` / `month` / `day` / `hour` / `minute` | 日期分量 | 与 `date` 互斥;未给的分量沿用 picker 当前值;超出范围由 Calendar 规整(如 month=13 → 次年 1 月) |
| `animated` | bool,默认 false | 是否动画过渡 |

### `ui.picker.selectRow`

| 参数 | 含义 | 注意 |
|---|---|---|
| `accessibilityIdentifier` / `path` | 定位目标 UIPickerView(二选一) | 优先 identifier |
| `viewSnapshotID` | 快照标识 | 可选 |
| `component` | 列索引(0-based) | **必填**;越界返回 `invalid_data` |
| `row` | 目标行索引(0-based) | 与 `title` 互斥;越界返回 `invalid_data` |
| `title` | 目标行标题 | 与 `row` 互斥;读 delegate `titleForRow` 首个匹配;delegate 用 viewForRow 时改用 `row` |
| `animated` | bool,默认 false | 是否动画滚动 |

## 常见错误与判别

### `invalid_data`(目标类型不对)

- **现象**:命令返回 `invalid_data`,message 形如 `target is not a UIDatePicker (got UILabel)`
- **原因**:`accessibilityIdentifier` / `path` 定位到的不是 `UIDatePicker` / `UIPickerView`(定位错控件)
- **处理**:先 `ui_inspect` 确认目标 `type`,拿到正确的 identifier / path 再调

### `invalid_data`(分量 / 索引越界)

- **现象**:datePicker 的 `month=13` 被 Calendar 规整(不报错,但结果日期可能跨年);picker 的 `component` 或 `row` 越界返回 `invalid_data`
- **判别**:picker 返回 message 含 `out of range` + 实际总数;datePicker 分量超范围不报错而是规整(如设 day=31 在 2 月会滚到 3 月)
- **处理**:picker 先看返回的 `numberOfRowsInComponent` 确认合法范围;datePicker 设值后核对返回的 `date` 是否符合预期

### `target_not_found`(title 未匹配 / 定位失败)

- **现象**:`ui.picker.selectRow` 按 title 选返回 `target_not_found`,message 含 `row with title '...' not found`
- **原因**:该 component 没有此 title;或 delegate 用 `viewForRow`(无 title 文本)
- **处理**:先 inspect 看 picker 结构;若 delegate 用 viewForRow,改用 `row` 索引;若 title 文本不一致(如带空格 / 全半角差异),用 `row` 或核对确切文本

### `target_not_found`(定位失败)

- **现象**:message 含 `picker target not found` / `datePicker target not found`
- **原因**:identifier / path 在当前 view 树找不到(页面没进到含 picker 的页,或 picker 还没加载)
- **处理**:先 `ui_inspect` 确认 picker 已在屏;picker 常在 modal / sheet 里,确认采集根包含它(见 `ios-ui-nav` 的 inspect 采集根说明)

## 相关 skill

- `ios-ui-form` — `UISegmentedControl` / `UISlider` / `UIStepper` / `UISwitch` / 文本输入走它(这些控件在 `ui.control.sendAction` 能力表里);本 skill 只管 `UIDatePicker` / `UIPickerView`(不在能力表,需专用命令)
- `ios-ui-nav` — 进到含 picker 的页面(常在 modal / push 页)、确认 inspect 采集根覆盖 picker
- `ios-ui-shot` — 设值前后截图取证
- `ios-automation` — L1 总入口;不确定走哪个子 skill 时先问它

**平台约束**:`UIDatePicker.date` / `UIPickerView.selectRow(_:inComponent:animated:)` 均为公开 UIKit API,无私有 API 依赖。仅 Debug 集成(整套自动化能力 Debug-only)。设值在主线程执行。`viewSnapshotID` 用 `accessibilityIdentifier` 定位时可省略,用 `path` 定位时建议携带做陈旧校验。
