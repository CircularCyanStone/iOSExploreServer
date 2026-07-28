<!-- Generated from contracts/. Do not edit directly. -->
# iOS Driver Contracts

- Protocol version: `1`
- Contract version: `1.0.0`
- Generator version: `1`
- Contract hash: `sha256:1e7c78a9c2a9d9b632b4e50ebcd99c287a5d464217d18ef0273488198face1a0`
- Device actions: 27
- Host operations: 5

## Device Actions

### `app.logs.mark`

建立当前进程日志检查点。

- Provider: `diagnostics`
- Stability: `public`
- Idempotency: `sideEffecting`
- Timeout class: `standard`
- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `input_rejected`, `internal_error`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`

Input fields: none.

### `app.logs.read`

读取当前进程内已捕获的日志。

- Provider: `diagnostics`
- Stability: `public`
- Idempotency: `readOnly`
- Timeout class: `standard`
- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `input_rejected`, `internal_error`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `after` | `object \| null` | no | - | 增量读取起点 cursor。 |
| `after.captureSessionID` | `string` | yes | - | capture session ID。 |
| `after.id` | `integer` | yes | - | cursor id。 |
| `limit` | `integer` | no | `100` | 最多返回的日志条数。 |
| `minimumLevel` | `string \| null` | no | - | 最低日志等级。 |
| `sources` | `array \| null` | no | - | 日志来源过滤。 |

### `echo`

原样回显 data。

- Provider: `core`
- Stability: `public`
- Idempotency: `readOnly`
- Timeout class: `standard`
- Result: `json`
- Errors: `internal_error`

Input fields: none.

### `help`

列出所有已注册命令及其参数说明。

- Provider: `core`
- Stability: `public`
- Idempotency: `readOnly`
- Timeout class: `standard`
- Result: `json`
- Errors: `internal_error`

Input fields: none.

### `info`

返回系统、应用和 Bundle 信息。

- Provider: `core`
- Stability: `public`
- Idempotency: `readOnly`
- Timeout class: `standard`
- Result: `json`
- Errors: `internal_error`

Input fields: none.

### `ping`

检查 iOSExploreServer 是否可达。

- Provider: `core`
- Stability: `public`
- Idempotency: `readOnly`
- Timeout class: `standard`
- Result: `json`
- Errors: `internal_error`

Input fields: none.

### `ui.alert.respond`

按标题、下标或角色响应当前 alert。

- Provider: `uikit`
- Stability: `public`
- Idempotency: `sideEffecting`
- Timeout class: `standard`
- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `input_rejected`, `internal_error`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `buttonIndex` | `integer \| null` | no | - | 要触发的按钮下标。 |
| `buttonTitle` | `string \| null` | no | - | 要触发的按钮标题。 |
| `role` | `string \| null` | no | - | 按钮角色。 |

### `ui.control.sendAction`

向 UIControl 发送指定事件。

- Provider: `uikit`
- Stability: `public`
- Idempotency: `sideEffecting`
- Timeout class: `standard`
- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `input_rejected`, `internal_error`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `accessibilityIdentifier` | `string \| null` | no | - | 按 accessibilityIdentifier 定位。 |
| `event` | `string` | yes | - | 事件名。 |
| `path` | `string \| null` | no | - | 按 path 定位。 |
| `value` | `number \| boolean \| null` | no | - | 可选目标值；number 用于 UISlider/UISegmentedControl/UIStepper，UISwitch 同时接受 boolean 和 number 0/1。 |
| `viewSnapshotID` | `string` | yes | - | ui.inspect 签发的快照标识；目标必须声明与 event 对应的 control.* 动作。 |

### `ui.controllers`

读取当前 controller 层级。

- Provider: `uikit`
- Stability: `public`
- Idempotency: `readOnly`
- Timeout class: `standard`
- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `input_rejected`, `internal_error`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `maxDepth` | `integer \| null` | no | - | 最大递归深度。 |

### `ui.datePicker.setDate`

设置日期选择器日期。

- Provider: `uikit`
- Stability: `public`
- Idempotency: `sideEffecting`
- Timeout class: `standard`
- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `input_rejected`, `internal_error`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `accessibilityIdentifier` | `string \| null` | no | - | 按 accessibilityIdentifier 定位。 |
| `animated` | `boolean` | no | `false` | 是否动画。 |
| `date` | `string \| null` | no | - | ISO 8601 日期时间字符串（可带毫秒/时区）或 yyyy-MM-dd。 |
| `day` | `integer \| null` | no | - | 非负整数日期分量；parser 不限制为 1...31，Calendar 可规整超出常规范围的值。 |
| `hour` | `integer \| null` | no | - | 非负整数小时分量；parser 不限制为 0...23，Calendar 可规整超出常规范围的值。 |
| `minute` | `integer \| null` | no | - | 非负整数分钟分量；parser 不限制为 0...59，Calendar 可规整超出常规范围的值。 |
| `month` | `integer \| null` | no | - | 非负整数月份分量；parser 不限制为 1...12，Calendar 可规整超出常规范围的值。 |
| `path` | `string \| null` | no | - | 按 path 定位。 |
| `viewSnapshotID` | `string \| null` | no | - | ui.inspect 签发的快照标识。 |
| `year` | `integer \| null` | no | - | 非负整数年份分量。 |

### `ui.input`

按顺序向多个文本控件注入文本。

- Provider: `uikit`
- Stability: `public`
- Idempotency: `sideEffecting`
- Timeout class: `standard`
- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `input_rejected`, `internal_error`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `fields` | `object[]` | yes | - | 按顺序执行的字段数组。 |
| `fields[].accessibilityIdentifier` | `string \| null` | no | - | 按 accessibilityIdentifier 定位。 |
| `fields[].mode` | `string` | no | `"replace"` | 写入模式。 |
| `fields[].path` | `string \| null` | no | - | 按 path 定位。 |
| `fields[].submit` | `boolean` | no | `false` | 是否触发结束编辑语义。 |
| `fields[].text` | `string` | yes | - | 要输入的文本。 |
| `stopOnFailure` | `boolean` | no | `true` | 某个字段失败后是否停止执行后续字段。 |
| `viewSnapshotID` | `string \| null` | no | - | ui.inspect 签发的快照标识；提供时，每个目标必须在同次 inspect 中声明 input。 |

### `ui.inspect`

读取当前 UI 结构，并按每个 target 的 availableActions 签发 viewSnapshotID。

- Provider: `uikit`
- Stability: `public`
- Idempotency: `readOnly`
- Timeout class: `standard`
- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `input_rejected`, `internal_error`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `accessibilityIdentifier` | `string \| null` | no | - | 按 accessibilityIdentifier 精确定位。 |
| `accessibilityIdentifierPrefix` | `string \| null` | no | - | 按 accessibilityIdentifier 前缀过滤。 |
| `includeHidden` | `boolean` | no | `false` | 是否包含隐藏 view。 |
| `maxDepth` | `integer \| null` | no | - | 最大递归深度。 |
| `maxTargets` | `integer` | no | `200` | 单次响应最多返回的 full 目标数。 |
| `maxVisitedNodes` | `integer` | no | `2000` | DFS 访问节点上限。 |
| `textLimit` | `integer` | no | `80` | title/text/placeholder/value 最大字符数。 |

### `ui.keyboard.dismiss`

收起当前键盘或结束编辑状态。

- Provider: `uikit`
- Stability: `public`
- Idempotency: `sideEffecting`
- Timeout class: `standard`
- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `input_rejected`, `internal_error`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `strategy` | `string` | no | `"auto"` | 键盘收起策略。 |
| `waitAfterMs` | `integer` | no | `200` | 执行后等待毫秒数。 |

### `ui.longPress`

对目标 view 执行长按。

- Provider: `uikit`
- Stability: `public`
- Idempotency: `sideEffecting`
- Timeout class: `standard`
- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `input_rejected`, `internal_error`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `accessibilityIdentifier` | `string \| null` | no | - | 按 accessibilityIdentifier 定位。 |
| `duration` | `number \| null` | no | `0.5` | 长按持续时间（秒）；省略或传 null 时使用 0.5，范围 (0, 10]。 |
| `path` | `string \| null` | no | - | 按 path 定位。 |
| `viewSnapshotID` | `string \| null` | no | - | ui.inspect 签发的快照标识。 |

### `ui.navigation.back`

按策略返回或关闭当前页面。

- Provider: `uikit`
- Stability: `public`
- Idempotency: `sideEffecting`
- Timeout class: `standard`
- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `input_rejected`, `internal_error`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `animated` | `boolean` | no | `false` | 是否动画。 |
| `strategy` | `string` | no | `"auto"` | 返回策略。 |
| `waitAfterMs` | `integer` | no | `300` | 执行后等待毫秒数。 |

### `ui.navigation.tapBarButton`

点击导航栏指定按钮。

- Provider: `uikit`
- Stability: `public`
- Idempotency: `sideEffecting`
- Timeout class: `standard`
- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `input_rejected`, `internal_error`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `accessibilityIdentifier` | `string \| null` | no | - | 观察时看到的按钮 identifier。 |
| `index` | `integer \| null` | no | - | 按钮在当前侧的下标。 |
| `placement` | `string \| null` | no | - | 导航栏按钮位置。 |
| `title` | `string \| null` | no | - | 观察时看到的按钮标题。 |
| `waitAfterMs` | `integer` | no | `300` | 执行后等待毫秒数。 |

### `ui.picker.selectRow`

按 row 或 title 选择 picker 行。

- Provider: `uikit`
- Stability: `public`
- Idempotency: `sideEffecting`
- Timeout class: `standard`
- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `input_rejected`, `internal_error`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `accessibilityIdentifier` | `string \| null` | no | - | 按 accessibilityIdentifier 定位。 |
| `animated` | `boolean` | no | `false` | 是否动画。 |
| `component` | `integer` | yes | - | 目标列索引。 |
| `path` | `string \| null` | no | - | 按 path 定位。 |
| `row` | `integer \| null` | no | - | 目标行索引。 |
| `title` | `string \| null` | no | - | 目标行标题。 |
| `viewSnapshotID` | `string \| null` | no | - | ui.inspect 签发的快照标识。 |

### `ui.screenshot`

获取当前 UI 的 PNG 截图。

- Provider: `uikit`
- Stability: `public`
- Idempotency: `readOnly`
- Timeout class: `screenshot`
- Result: `image`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `input_rejected`, `internal_error`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `maxDimension` | `integer` | no | `1280` | 截图长边像素上限。 |

### `ui.scroll`

按方向滚动目标 UIScrollView。

- Provider: `uikit`
- Stability: `public`
- Idempotency: `sideEffecting`
- Timeout class: `standard`
- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `input_rejected`, `internal_error`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `accessibilityIdentifier` | `string \| null` | no | - | 按 accessibilityIdentifier 定位。 |
| `amount` | `number \| null` | no | - | 滚动距离（pt），必须 > 0；省略或传 null 时按目标可见区的一半计算。 |
| `animated` | `boolean` | no | `false` | 是否动画。 |
| `direction` | `string` | yes | - | 滚动方向。 |
| `path` | `string \| null` | no | - | 按 path 定位。 |
| `viewSnapshotID` | `string \| null` | no | - | ui.inspect 签发的快照标识；与定位字段同时提供时，目标必须在同次 inspect 中声明 scroll。 |

### `ui.scrollToElement`

把匹配文本或 identifier 的元素滚动到可见区域。

- Provider: `uikit`
- Stability: `public`
- Idempotency: `sideEffecting`
- Timeout class: `standard`
- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `input_rejected`, `internal_error`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `accessibilityIdentifier` | `string \| null` | no | - | 滚动容器 identifier。 |
| `animated` | `boolean` | no | `false` | 是否动画。 |
| `match` | `string` | no | `"text"` | 匹配方式。 |
| `path` | `string \| null` | no | - | 滚动容器 path。 |
| `value` | `string` | yes | - | 要滚动到的文本片段或 identifier。 |

### `ui.swipe`

对目标 view 执行方向滑动。

- Provider: `uikit`
- Stability: `public`
- Idempotency: `sideEffecting`
- Timeout class: `standard`
- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `input_rejected`, `internal_error`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `accessibilityIdentifier` | `string \| null` | no | - | 按 accessibilityIdentifier 定位。 |
| `actionTitle` | `string \| null` | no | - | 要触发的 swipe action 标题。 |
| `cellAccessibilityIdentifier` | `string \| null` | no | - | swipe action 目标 cell 的 identifier。 |
| `cellPath` | `string \| null` | no | - | swipe action 目标 cell 的 path。 |
| `direction` | `string` | yes | - | 滑动方向。 |
| `distance` | `number \| null` | no | `0.8` | 滑动距离比例；省略或传 null 时使用 0.8，范围 (0, 1]。 |
| `path` | `string \| null` | no | - | 按 path 定位。 |
| `viewSnapshotID` | `string \| null` | no | - | ui.inspect 签发的快照标识。 |

### `ui.tabBar.selectTab`

按 index 或 title 选择 tab。

- Provider: `uikit`
- Stability: `public`
- Idempotency: `sideEffecting`
- Timeout class: `standard`
- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `input_rejected`, `internal_error`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `index` | `integer \| null` | no | - | tab 索引。 |
| `tabBarControllerPath` | `string \| null` | no | - | 可选的 UITabBarController 路径。 |
| `title` | `string \| null` | no | - | tab 标题。 |
| `triggerDelegate` | `boolean` | no | `true` | 是否手动触发 delegate 回调。 |

### `ui.tap`

点击 ui.inspect 中 availableActions 包含 tap 的目标。

- Provider: `uikit`
- Stability: `public`
- Idempotency: `sideEffecting`
- Timeout class: `standard`
- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `input_rejected`, `internal_error`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `accessibilityIdentifier` | `string \| null` | no | - | 按 accessibilityIdentifier 定位。 |
| `path` | `string \| null` | no | - | 按 path 定位。 |
| `viewSnapshotID` | `string` | yes | - | ui.inspect 签发的快照标识；目标必须在同次 inspect 中声明 tap。 |

### `ui.topViewHierarchy`

读取当前最外层 controller 容器层级。

- Provider: `uikit`
- Stability: `public`
- Idempotency: `readOnly`
- Timeout class: `standard`
- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `input_rejected`, `internal_error`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `accessibilityIdentifier` | `string \| null` | no | - | 按 accessibilityIdentifier 过滤。 |
| `accessibilityIdentifierPrefix` | `string \| null` | no | - | 按 accessibilityIdentifier 前缀过滤。 |
| `controller` | `string \| null` | no | - | controller path。 |
| `detailLevel` | `string` | no | `"appearance"` | 层级详情级别。 |
| `includeHidden` | `boolean` | no | `false` | 是否包含隐藏 view。 |
| `maxDepth` | `integer \| null` | no | - | 最大递归深度。 |

### `ui.wait`

等待 UI 稳定或等待目标变化。

- Provider: `uikit`
- Stability: `public`
- Idempotency: `readOnly`
- Timeout class: `wait`
- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `input_rejected`, `internal_error`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `accessibilityIdentifier` | `string \| null` | no | - | targetExists/targetGone 模式按 identifier 定位。 |
| `includeHidden` | `boolean` | no | `false` | 是否考虑隐藏 view。 |
| `intervalMs` | `integer` | no | `100` | 轮询间隔毫秒数。 |
| `mode` | `string` | no | `"idle"` | 等待模式。 |
| `path` | `string \| null` | no | - | targetExists/targetGone 模式按 path 定位。 |
| `stableMs` | `integer` | no | `300` | idle 模式下连续稳定的毫秒数。 |
| `text` | `string \| null` | no | - | textExists 模式要等待的文本片段。 |
| `timeoutMs` | `integer` | no | `3000` | 业务超时毫秒数。 |
| `viewSnapshotID` | `string \| null` | no | - | snapshotChanged 模式参照的 viewSnapshotID。 |

### `ui.waitAny`

等待多个 UI 条件中的任意一个满足。

- Provider: `uikit`
- Stability: `public`
- Idempotency: `readOnly`
- Timeout class: `wait`
- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `input_rejected`, `internal_error`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `conditions` | `object[]` | yes | - | 等待条件数组。 |
| `conditions[].accessibilityIdentifier` | `string \| null` | no | - | targetExists/targetGone 模式按 identifier 定位。 |
| `conditions[].id` | `string` | yes | - | 条件标识。 |
| `conditions[].mode` | `string` | yes | - | 等待模式。 |
| `conditions[].path` | `string \| null` | no | - | targetExists/targetGone 模式按 path 定位。 |
| `conditions[].text` | `string \| null` | no | - | textExists 模式要等待的文本片段。 |
| `conditions[].viewSnapshotID` | `string \| null` | no | - | snapshotChanged 模式参照的 viewSnapshotID。 |
| `includeHidden` | `boolean` | no | `false` | 是否考虑隐藏 view。 |
| `intervalMs` | `integer` | no | `100` | 轮询间隔毫秒数。 |
| `stableMs` | `integer` | no | `300` | idle 条件连续稳定的毫秒数。 |
| `timeoutMs` | `integer` | no | `3000` | 业务超时毫秒数。 |

### `ui.webView.eval`

在目标 WKWebView 执行 script 或 function。

- Provider: `uikit`
- Stability: `public`
- Idempotency: `sideEffecting`
- Timeout class: `standard`
- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `input_rejected`, `internal_error`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `accessibilityIdentifier` | `string \| null` | no | - | 按 accessibilityIdentifier 定位。 |
| `arguments` | `object \| null` | no | - | 传递给 function 的参数。 |
| `function` | `string \| null` | no | - | 异步模式 JS 函数体。 |
| `path` | `string \| null` | no | - | 按 path 定位。 |
| `script` | `string \| null` | no | - | 同步模式 JS 代码。 |
| `timeout` | `number \| null` | no | `5` | 超时时间（秒）；省略或传 null 时使用 5 秒。 |
| `viewSnapshotID` | `string \| null` | no | - | ui.inspect 签发的快照标识。 |

## Host Operations

### `call_action`

调用宿主 App 的任意 action。

- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `artifact_decode_failed`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `contract_mismatch`, `http_error`, `input_rejected`, `internal_error`, `invalid_config`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `protocol_error`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `transport_timeout`, `transport_unavailable`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `action` | `string` | yes | - | 要调用的 action 名。 |
| `data` | `object` | no | - | 传给 action 的原始 data。 |

### `capabilities`

读取 App help 并报告当前注册 action。

- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `contract_mismatch`, `http_error`, `input_rejected`, `internal_error`, `invalid_config`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `protocol_error`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `transport_timeout`, `transport_unavailable`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`

Input fields: none.

### `health`

检查 iOS App 端点可达性和基础协议。

- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `contract_mismatch`, `http_error`, `input_rejected`, `internal_error`, `invalid_config`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `protocol_error`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `transport_timeout`, `transport_unavailable`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`

Input fields: none.

### `tap_and_inspect`

点击元素后自动检查 UI 状态。

- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `contract_mismatch`, `http_error`, `input_rejected`, `internal_error`, `invalid_config`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `protocol_error`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `transport_timeout`, `transport_unavailable`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`, `workflow_timeout`

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `accessibilityIdentifier` | `string \| null` | no | - | 按 accessibilityIdentifier 定位。 |
| `inspectDepth` | `integer` | no | `2` | inspect 的最大递归深度。 |
| `inspectMaxTargets` | `integer` | no | `20` | inspect 返回的最大目标数量。 |
| `path` | `string \| null` | no | - | 按 path 定位。 |
| `stableTimeMs` | `integer` | no | `300` | 等待 UI 稳定的时长。 |
| `viewSnapshotID` | `string` | yes | - | ui.inspect 签发的快照标识。 |
| `waitForStable` | `boolean` | no | `true` | 是否等待 UI 稳定后再 inspect。 |

### `wait_and_inspect`

先等待条件，再读取 UI 结构。

- Result: `json`
- Errors: `alert_button_not_found`, `alert_button_required`, `alert_button_trigger_failed`, `alert_release_unsupported`, `alert_unavailable`, `bad_request`, `become_first_responder_failed`, `container_not_scrollable`, `contract_mismatch`, `http_error`, `input_rejected`, `internal_error`, `invalid_config`, `invalid_data`, `keyboard_dismiss_failed`, `navigation_back_unavailable`, `navigation_bar_item_disabled`, `navigation_bar_item_mismatch`, `navigation_bar_item_not_found`, `navigation_bar_item_unsupported`, `navigation_bar_unavailable`, `not_actionable`, `protocol_error`, `rendering_failed`, `response_too_large`, `scroll_container_unavailable`, `stale_cursor`, `stale_locator`, `target_not_found`, `timeout`, `transition_in_progress`, `transport_timeout`, `transport_unavailable`, `unknown_action`, `unsupported_target`, `unsupported_text_input_type`, `wait_timeout`, `workflow_timeout`

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `conditions` | `object[]` | yes | - | 等待条件数组。 |
| `conditions[].accessibilityIdentifier` | `string \| null` | no | - | 目标 identifier。 |
| `conditions[].id` | `string` | yes | - | 条件标识。 |
| `conditions[].mode` | `string` | yes | - | 等待模式。 |
| `conditions[].path` | `string \| null` | no | - | 目标 path。 |
| `conditions[].text` | `string \| null` | no | - | 等待的文本。 |
| `conditions[].viewSnapshotID` | `string \| null` | no | - | 参照的 viewSnapshotID。 |
| `includeHidden` | `boolean` | no | `false` | 是否考虑隐藏 view。 |
| `inspectOptions` | `object` | no | - | 传给 ui.inspect 的可选参数。 |
| `inspectOptions.accessibilityIdentifier` | `string` | no | - | 按 identifier 过滤。 |
| `inspectOptions.accessibilityIdentifierPrefix` | `string` | no | - | 按 identifier 前缀过滤。 |
| `inspectOptions.includeHidden` | `boolean` | no | - | 是否包含隐藏 view。 |
| `inspectOptions.maxDepth` | `integer` | no | - | 最大递归深度。 |
| `inspectOptions.maxTargets` | `integer` | no | `200` | 最大目标数。 |
| `inspectOptions.maxVisitedNodes` | `integer` | no | `2000` | 最大访问节点数。 |
| `inspectOptions.textLimit` | `integer` | no | `80` | 文本截断长度。 |
| `intervalMs` | `integer` | no | `100` | 轮询间隔毫秒数。 |
| `stableMs` | `integer` | no | `300` | 稳定窗口毫秒数。 |
| `timeoutMs` | `integer` | no | `3000` | 业务超时毫秒数。 |

## Error Index

| Code | Source | Retryable | Terminal |
| --- | --- | --- | --- |
| `alert_button_not_found` | `appEnvelope` | false | true |
| `alert_button_required` | `appEnvelope` | false | true |
| `alert_button_trigger_failed` | `appEnvelope` | false | true |
| `alert_release_unsupported` | `appEnvelope` | false | true |
| `alert_unavailable` | `appEnvelope` | false | true |
| `artifact_decode_failed` | `artifact` | false | true |
| `bad_request` | `appEnvelope` | false | true |
| `become_first_responder_failed` | `appEnvelope` | true | false |
| `container_not_scrollable` | `appEnvelope` | false | true |
| `contract_mismatch` | `contract` | false | true |
| `http_error` | `http` | false | true |
| `input_rejected` | `appEnvelope` | false | true |
| `internal_error` | `appEnvelope` | false | true |
| `invalid_config` | `config` | false | true |
| `invalid_data` | `appEnvelope` | false | true |
| `keyboard_dismiss_failed` | `appEnvelope` | false | true |
| `navigation_back_unavailable` | `appEnvelope` | false | true |
| `navigation_bar_item_disabled` | `appEnvelope` | false | true |
| `navigation_bar_item_mismatch` | `appEnvelope` | false | true |
| `navigation_bar_item_not_found` | `appEnvelope` | false | true |
| `navigation_bar_item_unsupported` | `appEnvelope` | false | true |
| `navigation_bar_unavailable` | `appEnvelope` | false | true |
| `not_actionable` | `appEnvelope` | false | true |
| `protocol_error` | `protocol` | false | true |
| `rendering_failed` | `appEnvelope` | true | false |
| `response_too_large` | `appEnvelope` | false | true |
| `scroll_container_unavailable` | `appEnvelope` | false | true |
| `stale_cursor` | `appEnvelope` | false | true |
| `stale_locator` | `appEnvelope` | false | true |
| `target_not_found` | `appEnvelope` | false | true |
| `timeout` | `appEnvelope` | true | false |
| `transition_in_progress` | `appEnvelope` | true | false |
| `transport_timeout` | `transport` | true | false |
| `transport_unavailable` | `transport` | true | false |
| `unknown_action` | `appEnvelope` | false | true |
| `unsupported_target` | `appEnvelope` | false | true |
| `unsupported_text_input_type` | `appEnvelope` | false | true |
| `wait_timeout` | `appEnvelope` | true | false |
| `workflow_timeout` | `workflow` | true | false |
