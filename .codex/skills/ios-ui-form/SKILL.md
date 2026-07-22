---
name: ios-ui-form
description: iOS App 表单填写与控件操作(开发验证 + 自动化测试)/ form filling, text input, switch, slider, stepper, segmented, keyboard, submit, manual testing, ui_input, ui_control_sendAction
---

# iOS 表单填写与控件操作

基于 iOSDriver UI action,覆盖 iOS App 表单填写的常见路径:文本输入(`UITextField` / `UITextView` / `UISearchTextField`)、UIControl 控件操作(`UISwitch` / `UISlider` / `UIStepper` / `UISegmentedControl`)、键盘管理、提交按钮触发、异步结果等待判据、屏幕外字段滚动定位。合并自原 `ios-form-filling`。

需要完整的泛化示例时读取 [references/form-examples.md](references/form-examples.md):异步提交、同步校验、注册成功 alert、UISearchBar 搜索、取消和清空按钮都放在那里。默认正文只保留必须流程和判别规则。

## 目标

解决"把一组字段填好、把控件设到期望状态、再提交并判断结果"这一 iOS 自动化高频场景。关键不是单条命令怎么调,而是:

- **输入与控件分开走**:`ui_input` 走 text input 协议,`ui_control_sendAction` 走 UIControl 事件链。两者不能互换:给 `UISwitch` 输入 `"ON"` 不会触发 target-action。
- **提交等法按同步 / 异步分流**:本地校验用 `ui_tap_and_inspect` 的稳定窗口;登录 / 注册 / 保存等异步流程用 `ui_tap` 后交给 `ios-ui-wait` 的 `ui_waitAny` 或 `wait_and_inspect`。
- **每个失败有业务码可判**:`become_first_responder_failed` / `input_rejected` / `stale_locator` / `not_actionable` / `invalid_data` 指向不同根因,不要靠重试掩盖参数或定位问题。

## 何时使用

- ✅ 用户要填写登录 / 注册 / 资料表单,包括用户名、密码、邮箱、手机号等字段
- ✅ 用户要在搜索框输入文字,或在多行文本框里输入带换行的内容
- ✅ 用户要打开 / 关闭开关,调整滑块,操作 stepper,选择 segment
- ✅ 用户要关掉键盘,或任务明确依赖 Return / Done / Search / 结束编辑语义
- ✅ 用户要点提交 / 登录 / 保存按钮,并判断提交是否成功
- ✅ 用户要填写屏幕外字段,需要先滚动定位
- ✅ 用户说 "表单" / "填写" / "输入文字" / "开关" / "滑块" / "分段控件" / "提交" / "登录"
- ❌ 不要用于纯手势,边缘 swipe、长按走 `ios-ui-gesture`
- ❌ 不要用于长时异步等待本身,loading / 网络结果走 `ios-ui-wait`
- ❌ 不要用于 `UIAlertController` 按钮响应,走 `ios-ui-alert`
- ❌ 不要用于 `UIDatePicker` / `UIPickerView`,走 `ios-ui-picker`
- ❌ 不要用于屏幕切换本身,提交成功后的导航验证走 `ios-ui-nav`

## 工作原理

表单填写的核心时序:**inspect 取字段 → 一次 ui_input 批量填文本字段 / sendAction 改控件 → 必要时重新 inspect → (可选)app.logs.mark → tap 提交 → 等并读取终态判据**。`viewSnapshotID` 必须来自当前屏幕;跨页、scroll、键盘开合或等待后继续操作时要重新 inspect。键盘关闭不是提交前默认步骤,只在目标被键盘遮挡、业务依赖结束编辑、或任务本身要求键盘状态时执行。

若本次测试需要日志证据,`app.logs.mark` 应放在字段输入和提交按钮定位都完成之后、点击提交之前。不要在进入页面或首次 `ui_inspect` 前 mark,否则日志会混入连接检查、inspect 和工具探测噪音。

### 1. 文本输入(`ui_input`)

支持 `UITextField`、`UITextView`、`UISearchTextField`。`ui_input` 只有批量形态:顶层传 `fields` 数组,单字段输入也必须放进数组。每个 field 的定位优先用 `accessibilityIdentifier`,其次用 `path`;整批共用最近一次 `ui_inspect` 的顶层 `viewSnapshotID`。

| 参数 | 含义 | 注意 |
|---|---|---|
| `fields` | 字段数组 | 顶层必填;每个元素是一个文本字段 |
| `fields[].text` | 要输入的文本 | 必填;空字符串表示清空字段 |
| `fields[].accessibilityIdentifier` / `fields[].path` | 定位目标字段 | 二选一;优先 identifier |
| `viewSnapshotID` | 当前控件树快照 | 顶层传;跨屏 / scroll / 键盘开合后重取 |
| `fields[].mode` | `"replace"`(默认)/ `"append"` | 表单填写默认 replace |
| `fields[].submit` | bool,默认 false | 只有要触发 Return / Done / Search 或结束编辑时才设 `true` |
| `stopOnFailure` | bool,默认 true | 某个字段失败后停止后续字段;批量表单默认保持 true |

关键约束:

- Unicode / emoji / 中文可直接传;内部走 `UITextInput.insertText`,不是键盘码。
- 安全字段响应不回原文,只回长度和 masked 值。
- `\n` 换行只在 `UITextView` 有效;发到 `UITextField` 会返回 `input_rejected`。
- 多字段输入时默认保持键盘状态;只有目标被键盘遮挡、业务依赖 editingDidEnd / Return / Done / Search,或任务本身要求键盘状态时,才在对应 field 使用 `submit:true` 或额外调用 `ui_keyboard_dismiss`。

### 2. 控件交互(`ui_control_sendAction`)

`UISwitch` / `UISlider` / `UIStepper` / `UISegmentedControl` 统一走 `ui_control_sendAction`,通过真实 UIControl 事件驱动 target-action。**事件名固定 `valueChanged`**,不要写 `"action"`。

| 控件 | `value` 字段 | 行为 |
|---|---|---|
| `UISwitch` | 不传 | 翻转当前 on/off |
| `UISlider` | 0.0-1.0 浮点 | 跳到指定比例 |
| `UIStepper` | 不传或 `1` / `-1` | 按一步增减;不能直接设绝对值 |
| `UISegmentedControl` | segment 索引(0 起) | 选中该索引 |

控件必须 `isEnabled == true` 才能触发。响应里的 `previousValue` / `currentValue` / `isEnabled` / `isSelected` 可直接用于核对结果。

### 3. 键盘管理(`ui_keyboard_dismiss`)

键盘管理不是提交前默认步骤。只有以下情况才处理键盘:

- 要点击的目标被键盘实际遮挡,或普通 tap 因键盘覆盖失败。
- App 业务逻辑依赖 `editingDidEnd`、Return、Done、Search 等键盘事件。
- 用户任务本身要求验证键盘出现 / 消失 / 输入焦点。

两种键盘处理方式:

- 自动:`ui_input({fields:[{..., submit:true}]})` 输入后触发提交键语义,适合搜索框、单字段提交、或明确依赖 Return / Done 的字段。
- 手动:`ui_keyboard_dismiss(strategy:"auto"|"endEditing"|"resignFirstResponder")`,适合目标被键盘遮挡或必须结束当前编辑状态的场景。

`strategy:"auto"` 默认先试 `resignFirstResponder` 再试 `endEditing`;`endEditing` 递归整个子树,更强;`resignFirstResponder` 只处理当前 first responder,更温和。响应回 `firstResponderBefore` / `firstResponderAfter`,用于确认键盘是否收起。

### 4. 提交表单

填完字段后:**必要时重新 inspect 取提交按钮 → tap → 按同步 / 异步选择等待方式**。只有键盘遮挡目标、业务依赖结束编辑、或键盘状态本身是验证目标时,才先收键盘。

- **同步提交**:纯前端校验、本地切页、无网络。用 `ui_tap_and_inspect(waitForStable:true, stableTimeMs:300~500)`,直接读返回的 `targets` / `navigationBar` / `alert`。
- **异步提交**:登录、注册、保存到服务器等。用 `ui_tap` 只负责触发按钮,然后用 `wait_and_inspect` 或 `ui_waitAny` 等明确的成功 / 失败判据。不要在 `ui_tap` 后立刻 `ui_inspect` 并把这次快照当终态;那通常只是提交中间态或旧帧。
- **带确认框的异步提交**:退出登录、删除、重置、危险操作提交等,不能直接只等最终页。先用 `wait_and_inspect` 等"确认 alert 或最终页"二选一;若先命中 alert,切到 `ios-ui-alert` 响应后,再做第二段等待去等最终页或错误态。

异步判据建议:

| 判据类型 | 适用场景 | 示例 |
|---|---|---|
| `targetExists` + `accessibilityIdentifier` | 目标元素有稳定 identifier | 成功页标题、错误标签、空状态 view |
| `textExists` | 元素无 identifier,但文本稳定 | "保存成功"、"用户名或密码错误" |
| `targetGone` | 等中间态消失 | loading spinner 消失;通常还要配合成功 / 失败判据 |

不要用 `snapshotChanged` 判断成功;失败弹窗、清空字段、按钮禁用也会让快照变化。不要用固定 sleep 覆盖网络等待;它既浪费时间,也无法覆盖慢请求。

最小异步形态:

```javascript
await mcp__iOSDriver__ui_tap({
  accessibilityIdentifier: "form_submit_button",
  viewSnapshotID: snapshot.viewSnapshotID
})

const result = await mcp__iOSDriver__wait_and_inspect({
  conditions: [
    { id: "success", mode: "targetExists", accessibilityIdentifier: "success_title" },
    { id: "error", mode: "targetExists", accessibilityIdentifier: "form_error_label" },
    { id: "error_text", mode: "textExists", text: "提交失败" }
  ],
  timeoutMs: 10000,
  intervalMs: 200,
  inspectOptions: { maxDepth: 8, maxTargets: 120 }
})
```

带确认框的提交形态:

```javascript
await mcp__iOSDriver__ui_tap({
  accessibilityIdentifier: "danger_submit_button",
  viewSnapshotID: snapshot.viewSnapshotID
})

const branch = await mcp__iOSDriver__wait_and_inspect({
  conditions: [
    { id: "confirm_alert", mode: "textExists", text: "确认" },
    { id: "success", mode: "targetExists", accessibilityIdentifier: "success_title" },
    { id: "error", mode: "textExists", text: "提交失败" }
  ],
  timeoutMs: 5000,
  intervalMs: 200,
  inspectOptions: { maxDepth: 8, maxTargets: 120 }
})

// 命中 confirm_alert 后，切到 ios-ui-alert 响应，再执行第二段等待。
```

### 5. 屏幕外字段定位(`ui_scrollToElement`)

长表单底部字段在可视区外时,先 `ui_scrollToElement({match:"text"|"accessibilityIdentifier", value:"<field-label-or-id>"})` 把它滚进可视区,再 `ui_inspect` 拿新 `viewSnapshotID`,然后 input。scroll 后旧 snapshot 立即作废。

### 6. UISearchBar 操作

`UISearchBar` 是容器,内部真正接收输入的是 `UISearchTextField`。没有专用 `ui.searchBar.*` 命令;搜索流程用 `ui_inspect` 找内部 `UISearchTextField`,再用 `ui_input` 输入,必要时用 `ui_tap` 点取消 / 清空按钮。

要点:

- `ui_input` 应定位内部 `UISearchTextField`,不是外层 `UISearchBar`。
- `maxDepth` 设到 4-5,避免 UISearchBar 内部结构被截断。
- 搜索语义依赖键盘 Search / Done 时用 `submit:true`;如果 App 由独立按钮触发查询,保持 `submit:false`,重新 inspect 后 `ui_tap` 搜索按钮。只有需要结束编辑或稳定取消按钮状态时才调用 `ui_keyboard_dismiss`。
- 取消按钮和清空按钮是动态出现的;点击搜索框或输入文本后必须重新 inspect。

完整搜索示例见 [references/form-examples.md](references/form-examples.md)。

### 7. 截图取证(可选)

需要记录填写过程或失败证据时,`ui_screenshot` 返回 PNG base64。建议填前 / 提交后各一张。复杂视觉对比归 `ios-ui-shot`。

## 常见错误与判别

### `become_first_responder_failed`

- **现象**:input 失败,字段没获得焦点
- **原因**:字段禁用、隐藏、被遮挡,或在可视区外
- **处理**:先 inspect 看 `isEnabled` / 可见性;屏幕外字段先 `ui_scrollToElement`;必要时先 `ui_tap` 点字段再 input

### `input_rejected`

- **现象**:输入被拒绝,文本未插入
- **原因**:最常见是把 `\n` 发给 `UITextField`;单行字段不接受换行
- **处理**:先 inspect 确认 `type`;多行内容用 `UITextView`,单行字段去掉换行

### `stale_locator`

- **现象**:input / sendAction / tap 失败,定位过期
- **原因**:`viewSnapshotID` 超过 TTL,或 scroll / 换屏 / 键盘开合 / 等待后 view 树变化
- **处理**:重新 `ui_inspect` 拿新 `viewSnapshotID`;scroll 后必须重取

### `not_actionable`

- **现象**:sendAction 或 tap 返回不可操作
- **原因**:控件禁用,或目标是 `ui_inspect` 的 minimal 节点
- **处理**:禁用控件先走业务流程启用;minimal 节点改点 full 父节点

### `invalid_data`

- **现象**:sendAction 参数被拒
- **原因**:`event` 写成 `"action"`、slider 值超出 0.0-1.0、segment 索引越界、缺定位字段
- **处理**:`event` 固定 `"valueChanged"`;按控件类型校验 `value`

### 提交后读到 loading 中间态

- **现象**:点提交后立即返回按钮禁用、spinner、"提交中"等中间状态
- **原因**:异步流程不能靠 `ui_tap_and_inspect` 的短稳定窗口判断终态
- **处理**:改为 `ui_tap` + `ui_waitAny` / `wait_and_inspect`,等待明确成功或失败判据

### 提交后误报超时,其实卡在确认弹窗

- **现象**:点退出 / 删除 / 重置后一直等不到最终页面,最终报超时
- **原因**:等待条件只覆盖了最终页面,漏掉了中间确认 alert
- **处理**:第一段等待把 alert 分支和最终页分支一起写进 `ui_waitAny`;若先命中 alert,转 `ios-ui-alert` 响应后再做第二段等待

### 安全字段重试为空

- **现象**:失败后重试,密码或安全字段为空
- **原因**:很多 App 会在失败后清空安全字段;这是常见业务行为,不是工具错误
- **处理**:重试时重新 `ui_input` 安全字段,不要假设旧值仍在

## 相关 skill

- `ios-ui-wait` — 异步提交的成功 / 失败等待归它;本 skill 只给判据清单和触发方式
- `ios-ui-nav` — 提交成功后的屏幕切换验证走它
- `ios-ui-alert` — 提交触发的 `UIAlertController` 走 `ui_alert_respond`
- `ios-ui-list` — 表单里的列表选择、滚动查找项走它
- `ios-ui-picker` — `UIDatePicker` / `UIPickerView` 精确设值走它
- `ios-ui-shot` — 复杂的填前 / 提交后视觉对比归它
- `ios-automation` — L1 总入口;不确定走哪个子 skill 时先问它

**平台约束**:本套自动化能力要求 iOS 15+,部署目标视宿主 App 而定。仅 Debug 集成,Release 下整套 `ui.*` 自动化不可用。控件动作在主线程执行,单次必须在命令超时内完成。`viewSnapshotID` 默认 TTL 120 秒,但 scroll / 换屏 / 键盘开合会提前作废。
