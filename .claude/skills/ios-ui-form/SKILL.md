---
name: ios-ui-form
description: iOS App 表单填写与控件操作(原 ios-form-filling)/ form filling, text input, switch, slider, stepper, segmented, keyboard, submit, ui_input, ui_control_sendAction
allowed-tools:
  - mcp__iOSDriver__ui_input
  - mcp__iOSDriver__ui_tap
  - mcp__iOSDriver__ui_tap_and_inspect
  - mcp__iOSDriver__ui_control_sendAction
  - mcp__iOSDriver__ui_keyboard_dismiss
  - mcp__iOSDriver__ui_inspect
  - mcp__iOSDriver__ui_scrollToElement
  - mcp__iOSDriver__ui_screenshot
---

# iOS 表单填写与控件操作

基于 iOSDriver MCP Server(`mcp__iOSDriver__*`),覆盖 iOS App 表单填写的全链路:文本输入(`UITextField` / `UITextView` / `UISearchTextField`,支持 replace / append、Unicode / emoji、安全字段)、UIControl 控件操作(`UISwitch` / `UISlider` / `UIStepper` / `UISegmentedControl`,统一走 `ui_control_sendAction`)、键盘管理、表单提交(同步 vs 异步的等法差异),以及屏幕外字段的滚动定位。合并自原 `ios-form-filling`。

## 目标

解决"把一组字段填好、把控件设到期望状态、再把表单提交掉,并在每一步都能判断到底发生了什么"这一 iOS 自动化高频场景。关键不是单个命令怎么调,而是:

- **输入与控件分开走**:`ui_input` 走 text input 协议(支持 IME / Unicode),`ui_control_sendAction` 走 UIControl 事件链(valueChanged 等真实事件)。两者不能互换 —— 直接 `ui_input` 给 `UISwitch` 填 `"ON"` 不会触发 target-action。
- **提交等法按同步 / 异步分流**:本地校验用 `ui_tap_and_inspect` 的稳定窗口;登录 / 保存等异步流程不能用固定 sleep,要把成功 / 失败判据交给 `ios-ui-wait` 的 `ui_waitAny`。
- **每个失败有业务码可判**:`become_first_responder_failed` / `input_rejected` / `stale_locator` / `not_actionable` 各指向不同根因,本 skill 给出判别矩阵。

## 何时使用

- ✅ 用户要"填写登录 / 注册 / 资料表单"(用户名、密码、邮箱、手机号等)
- ✅ 用户要"在搜索框输入文字"或"在多行文本框里输入带换行的内容"
- ✅ 用户要"打开 / 关闭某个开关"(`UISwitch`)
- ✅ 用户要"把滑块调到某个比例" / " stepper 加减一" / "选某个 segment"(`UISlider` / `UIStepper` / `UISegmentedControl`)
- ✅ 用户要"关掉键盘"或"填完最后一个字段顺手收键盘"
- ✅ 用户要"点提交 / 登录 / 保存按钮",并判断提交是否成功
- ✅ 用户要"填到屏幕底部的字段"(屏幕外,先滚动定位)
- ✅ 用户说 "表单" / "填写" / "输入文字" / "开关" / "滑块" / "分段控件" / "提交" / "登录"
- ❌ 不要用于纯手势(边缘 swipe、长按 → `ios-ui-gesture`)
- ❌ 不要用于"等异步加载 / loading 结束"本身(走 `ios-ui-wait`,本 skill 的异步提交只负责给出判据、然后委托给它)
- ❌ 不要用于 `UIAlertController` 弹窗的按钮响应(走 `ui_alert_respond`,即 `ios-ui-alert`)
- ❌ 不要用于 `UIDatePicker` / `UIPickerView`(本 skill 不覆盖,需用专门控件 skill)
- ❌ 不要用于屏幕切换本身(提交成功后的跳转验证走 `ios-ui-nav`,本 skill 只负责"点到提交按钮"和"读终态判据")

## 工作原理

表单填写的核心时序:**inspect 取字段 → 逐字段 input / sendAction → 收键盘 → inspect 取提交按钮 → tap 提交 → 读终态判据**。每个字段操作前 `viewSnapshotID` 必须有效(同屏没换页就不过期);跨页或多步流程之间要重新 inspect。

### 1. 文本输入(`ui_input`)

支持 `UITextField`(单行)/ `UITextView`(多行)/ `UISearchTextField`(搜索框)。两种模式:

- **replace(默认)**:先清空原内容,再填新文本 —— 表单填写默认用它,行为可预测
- **append**:在现有内容末尾追加 —— 仅在需要拼接时用

关键约束:

- **Unicode / emoji 全支持**(走 `UITextInput.insertText`,不是键盘码):中文、emoji、组合字符都能直接传
- **空字符串 = 清空字段**:`text:""` 等于清空,不报错
- **安全字段(密码)**:响应里不回原文,只回 `length` 和 `masked`(如 `"••••••••"`),用于核对位数
- **`\n` 换行只在 `UITextView` 有效**:发到 `UITextField` 会返回业务码 `input_rejected`(UIKit 的 return 键触发字段 action,不插入换行符)—— 传 `\n` 前先 inspect 确认目标是 `UITextView`
- **`submit` 参数默认 true**:输入完成后自动 `resignFirstResponder` 收键盘;批量填字段时建议中间几个设 `submit:false`、最后一个设 `submit:true`,避免每个字段都闪一下键盘

定位字段优先用 `accessibilityIdentifier`(最稳),其次 `path`。

### 2. 控件交互(`ui_control_sendAction`)

`UISwitch` / `UISlider` / `UIStepper` / `UISegmentedControl` 统一走 `ui_control_sendAction`,通过发 UIControl 事件驱动真实 target-action(不是反射设值)。**事件名固定 `valueChanged`**,不要写 `"action"`(那是另一套机制,会被拒)。

| 控件 | 必填 event | `value` 字段 | 行为 |
|---|---|---|---|
| `UISwitch` | `valueChanged` | 不传 | 翻转当前 on/off;响应回 `previousValue` / `currentValue` |
| `UISlider` | `valueChanged` | 0.0–1.0 浮点 | 直接跳到该比例;超范围会被拒 |
| `UIStepper` | `valueChanged` | 不传或 `±1` | 不传 = 翻转一步(系统自动判增量方向);不能直接设绝对值 |
| `UISegmentedControl` | `valueChanged` | segment 索引(0 起) | 选中该索引 |

控件动作极快(3–4ms),同屏多个控件可连续发,不需要中间 re-inspect(只要 `viewSnapshotID` 没过期)。响应统一回 `previousValue` / `currentValue` / `isEnabled` / `isSelected` / `accessibilityIdentifier`,可直接核对结果。

> 控件必须 `isEnabled == true` 才能触发,禁用态会返回业务码 `not_actionable` 或 `invalid_data`。

### 3. 键盘管理(`ui_keyboard_dismiss`)

两种收键盘方式,按场景选:

- **自动**:`ui_input(submit:true)` 输完即收,适合单字段或最后一字段
- **手动**:`ui_keyboard_dismiss(strategy:"auto"|"endEditing"|"resignFirstResponder")`,适合批量填完后再统一收

`strategy` 三选一:`auto`(默认,先试 resignFirstResponder 再试 endEditing)、`endEditing`(递归让当前 view 的整个子树结束编辑,强)、`resignFirstResponder`(只针对当前 first responder,温和)。响应回 `firstResponderBefore` / `firstResponderAfter`,可确认键盘确实收了。

### 4. 表单提交(同步 vs 异步,等法不同)

填完字段后:**收键盘 → inspect 取提交按钮 → tap → 读终态判据**。提交按钮用 `accessibilityIdentifier` 或 `path` 定位,**必须先有 fresh `viewSnapshotID`**(收键盘等动作不会让 snapshot 过期,但跨屏 re-inspect 会)。

**关键分流 —— 提交后怎么等,决定成败:**

- **同步提交**(纯前端校验、本地切页、无网络):点完 UI 几乎立即到终态 → 用 `ui_tap_and_inspect`(`waitForStable:true`, `stableTimeMs:300~500`)。它合并 tap + 等动画 + inspect,省一轮推理。
- **异步提交**(登录 / 注册 / 保存到服务器,有 loading 或网络):点完先进 loading 中间态(按钮禁用 + `UIActivityIndicatorView`),最终才跳转或报错。**不要用 `ui_tap_and_inspect` + 固定 sleep** —— `stableTimeMs` 判的是"UI 结构稳定",loading 期间 spinner 一直转、结构不变,会提前"稳定"并抓到 loading 中间态;固定 sleep 也覆盖不了网络慢。

  **正确做法**:本 skill 只负责"点到提交按钮"和"给出终态判据清单",实际等待交给 `ios-ui-wait` 的 `ui_waitAny`:
  - 成功判据:目标页确定元素(如 `targetExists:"home_welcome_label"`、`textExists:"欢迎回来"`)
  - 失败判据:`targetExists` alert(弹错误框)、`textContains:"错误"`、或提交按钮重新启用(loading 结束但没跳转)
  - 成功 / 失败两个条件塞进 `ui_waitAny.conditions`,先命中谁就是谁

> **不用 `snapshotChanged` 判成功**:它只表达"界面变了",登录失败(弹 alert、清空密码框)界面同样会变,会被误判为成功。必须用目标页的**确定元素**。

### 5. 屏幕外字段定位(`ui_scrollToElement`)

长表单底部字段在可视区外时,先 `ui_scrollToElement({match:"text"|"accessibilityIdentifier", value:"<field-label-or-id>"})` 把它滚进可视区,再 `ui_inspect` 拿**新** `viewSnapshotID`(scroll 后旧 snapshot 立即作废),然后 input。定位语义与 `ios-ui-list` 一致,本 skill 只用到"滚到字段可见"这一步。

### 6. 截图取证(可选)

需要记录填写过程或失败证据时,`ui_screenshot` 返回 PNG base64。建议填前 / 提交后各一张。复杂的视觉对比归 `ios-ui-shot`。

## 关键参数

### `ui_input`

| 参数 | 含义 | 注意 |
|---|---|---|
| `text` | 要输入的文本(任意 Unicode,含中文 / emoji) | 必填;空字符串 = 清空字段 |
| `accessibilityIdentifier` / `path` | 定位目标字段(二选一) | 与 `viewSnapshotID` 配套;优先用 identifier |
| `viewSnapshotID` | 来自最近 `ui_inspect` 的目标指纹 | 必填;跨屏 / scroll 后必须重新 inspect |
| `mode` | `"replace"`(默认)/ `"append"` | replace 先清空,行为可预测,表单填写默认 |
| `submit` | bool,默认 true | 输入后是否 `resignFirstResponder` 收键盘;批量填字段时中间设 false |

### `ui_control_sendAction`

| 参数 | 含义 | 注意 |
|---|---|---|
| `event` | UIControl 事件名 | 必填;**固定 `"valueChanged"`**,不要写 `"action"` |
| `accessibilityIdentifier` / `path` | 定位控件(二选一) | 与 `viewSnapshotID` 配套 |
| `viewSnapshotID` | 来自最近 `ui_inspect` | 必填 |
| `value` | 控件目标值 | `UISlider` 0.0–1.0;`UISegmentedControl` segment 索引;`UISwitch` / `UIStepper` 不传 |

### `ui_keyboard_dismiss`

| 参数 | 含义 | 注意 |
|---|---|---|
| `strategy` | `"auto"`(默认)/ `"endEditing"` / `"resignFirstResponder"` | endEditing 强(递归整个子树),resignFirstResponder 温(只针对当前 first responder) |
| `waitAfterMs` | 0...3000,默认 200 | 收键盘动画后的稳定等待 |

### `ui_tap_and_inspect`(提交按钮)

| 参数 | 含义 | 注意 |
|---|---|---|
| `viewSnapshotID` | 提交按钮的目标指纹 | 必填 |
| `path` / `accessibilityIdentifier` | 定位按钮(二选一) | 与 `viewSnapshotID` 配套 |
| `waitForStable` / `stableTimeMs` | 等 UI 稳定再 inspect,默认开 | **仅同步提交用**;异步提交改走 `ios-ui-wait` |

## 常见错误与判别

### `become_first_responder_failed`(`ui_input`)

- **现象**:input 失败,业务码 `become_first_responder_failed`,字段没获得焦点
- **原因**:字段被禁用(`isEnabled == false`)、隐藏、被遮挡,或字段在可视区外
- **判别**:执行前 `ui_inspect` 看 `isEnabled`;看 `path` 是否在屏内;有 `alpha` / `hidden` 字段时确认
- **处理**:先 `ui_tap` 点一下字段再 input;屏幕外字段先 `ui_scrollToElement`;禁用字段需先走业务流程启用

### `input_rejected`(`ui_input` 发 `\n` 到 `UITextField`)

- **现象**:input 返回 `input_rejected`,文本没插入
- **原因**:`UITextField` 的 return 键触发字段 action,不插入换行符(UIKit 固有行为);只有 `UITextView` 接受 `\n`
- **判别**:执行前 `ui_inspect` 看 `type` 字段 —— `UITextField` 不接受 `\n`,`UITextView` 才接受
- **处理**:多行内容改用 `UITextView`;若必须是 `UITextField`,去掉 `\n` 分多次填或换控件

### `stale_locator`(snapshot 过期)

- **现象**:input / sendAction 失败,业务码 `stale_locator`
- **原因**:`viewSnapshotID` 已过期(超过 120 秒 TTL,或中途发生了 scroll / 换屏 / 键盘开合导致 view 树变化)
- **判别**:看响应 code 与 message;通常发生在"inspect 之后做了别的动作,再用旧 ID"的场景
- **处理**:每次 input / sendAction 前若怀疑过期,重新 `ui_inspect` 拿新 `viewSnapshotID`;scroll 后必须重新 inspect

### `not_actionable`(控件禁用 / minimal 节点)

- **现象**:sendAction 或 tap 返回 `not_actionable`
- **原因**:控件 `isEnabled == false`(业务逻辑禁用),或目标在 `ui_inspect` 里是 minimal 节点(只给 path+type,不签发指纹)
- **判别**:响应 code 区分 —— `not_actionable` 指向 minimal 节点或禁用控件;`target_not_found` 指向 snapshot 过期或 path 不存在
- **处理**:minimal 节点改点其 full 父节点;禁用控件先走业务流程启用(如先勾选"同意条款"才能点亮提交按钮)

### `invalid_data`(sendAction 参数错)

- **现象**:sendAction 业务码 `invalid_data`
- **原因**:`event` 写成 `"action"`(错)、`value` 超范围(如 slider 传 1.5)、segment 索引越界、必填的 `path` / `viewSnapshotID` 缺失
- **判别**:看 message 提示哪个字段;`event` 必须是 `valueChanged`,不是 `action`
- **处理**:`event` 统一用 `valueChanged`;slider `value` 限制 0.0–1.0;segment 索引从 0 起

### 提交后读到 loading 中间态(异步误判)

- **现象**:点提交后 `ui_tap_and_inspect` 立即返回,读到按钮禁用 + spinner,被误判为"卡住"或"完成"
- **原因**:异步提交的 loading 期间 UI 结构稳定(spinner 一直转),`stableTimeMs` 提前判稳定;固定 sleep 也覆盖不了网络慢
- **判别**:看响应里是否有 `UIActivityIndicatorView` / 按钮标题变 "登录中..." / 按钮禁用 —— 任一命中就是 loading 中间态
- **处理**:异步提交不要用 `ui_tap_and_inspect` + sleep;改用 `ui_tap` 点按钮,再把成功 / 失败判据交给 `ios-ui-wait` 的 `ui_waitAny`

### 密码框被清空(登录失败后)

- **现象**:登录失败后重试,密码框是空的
- **原因**:iOS 标准行为,登录失败后系统 / App 会清空安全字段;不是本 skill 的 bug
- **判别**:`ui_inspect` 密码字段 `masked` 长度为 0
- **处理**:重试时必须重新 `ui_input` 密码,不能复用上次的填写

## 相关 skill

- `ios-ui-wait` — 异步提交(登录 / 注册 / 保存)的成功 / 失败等待归它;本 skill 只给判据清单,实际 `ui_waitAny` 轮询走它
- `ios-ui-nav` — 提交成功后的屏幕切换验证走它;本 skill 只负责"点到提交按钮"和"读终态判据"
- `ios-ui-alert` — 提交触发的 `UIAlertController`(如错误弹窗)走 `ui_alert_respond`,不是本 skill 的 input / sendAction
- `ios-ui-list` — 表单里的下拉选择 / picker 走列表或专门控件 skill;本 skill 不覆盖 `UIDatePicker` / `UIPickerView`
- `ios-ui-shot` — 复杂的填前 / 提交后视觉对比归它,本 skill 只用 `ui_screenshot` 做单张取证
- `ios-automation` — L1 总入口;不确定走哪个子 skill 时先问它

**平台约束**:iOSExploreServer 要求 iOS 15+,部署目标视宿主 App 而定。仅 Debug 集成(控件操作依赖私有 API 注入,Release 不可用)。控件动作在主线程执行,单次必须在 5 秒内完成。`viewSnapshotID` 默认 TTL 120 秒,但 scroll / 换屏 / 键盘开合会提前作废。
