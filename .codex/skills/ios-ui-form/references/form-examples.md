# iOS 表单示例

本文件只在需要完整流程示例时读取。示例使用泛化的 accessibilityIdentifier 和占位文本,不要把它们理解为某个本地测试 App 的真实账号、bundle id 或固定页面结构。

## 登录 / 认证模板

适合"用户名 + 密码 + 提交按钮"这一类认证表单。重点不是某个具体 App 的字段名,而是把常见判据提前整理成可复用清单。

### 建议先确认的 4 类元素

- **输入元素**:用户名字段、密码字段、提交按钮
- **成功元素**:首页标题、欢迎文案、用户信息、退出按钮中任意 1-2 个稳定标识
- **失败元素**:错误标签、错误文案、alert 标题中任意 1-2 个稳定标识
- **中间元素**:loading spinner、进度 HUD、按钮禁用态、确认弹窗

### 推荐判据模板

| 场景 | pass criteria | fail criteria | 备注 |
|---|---|---|---|
| 登录成功 | `targetExists("<home-title>")` 或 `textExists("<welcome-text>")` | `targetExists("<login-error-label>")` 或 `textExists("<login-error-text>")` | 不要只用 `snapshotChanged` 判断成功 |
| 登录失败 | `targetExists("<login-error-label>")` 或 `textExists("<login-error-text>")` | `targetExists("<home-title>")` | 可补充"安全字段被清空"做失败后检查 |
| 登录中 | `targetGone("<loading-indicator>")` 后再等 success / fail | 超时 | loading 消失本身不等于成功 |
| 退出登录 | 第一段: `textExists("<confirm-title>")` 或 `targetExists("<login-submit-button>")` | 第一段超时 | 若先命中确认框,响应后再做第二段等待 |

### 推荐执行顺序

1. `ui_inspect` 找字段与成功 / 失败判据
2. `ui_input` 填用户名和密码
3. `ui_tap` 点提交
4. `wait_and_inspect` 同时等 success / fail / loading_done
5. 若命中 alert 分支,切到 `ios-ui-alert` 响应后再做第二段等待
6. 成功后再用首页结构补一次确认,失败后补读错误文案和字段状态

### 登录模板示例

```javascript
const snapshot = await mcp__iOSDriver__ui_inspect({
  accessibilityIdentifierPrefix: "auth_",
  maxDepth: 8,
  maxTargets: 120
})

await mcp__iOSDriver__ui_input({
  fields: [
    { accessibilityIdentifier: "auth_username_field", text: "<username>", submit: false },
    { accessibilityIdentifier: "auth_password_field", text: "<password>", submit: false }
  ],
  viewSnapshotID: snapshot.viewSnapshotID
})

await mcp__iOSDriver__ui_tap({
  accessibilityIdentifier: "auth_submit_button",
  viewSnapshotID: snapshot.viewSnapshotID
})

const branch = await mcp__iOSDriver__wait_and_inspect({
  conditions: [
    { id: "success", mode: "targetExists", accessibilityIdentifier: "home_title" },
    { id: "error_label", mode: "targetExists", accessibilityIdentifier: "auth_error_label" },
    { id: "error_text", mode: "textExists", text: "<login-error-text>" },
    { id: "loading_done", mode: "targetGone", accessibilityIdentifier: "auth_loading_indicator" }
  ],
  timeoutMs: 10000,
  intervalMs: 200,
  inspectOptions: { maxDepth: 8, maxTargets: 120 }
})
```

如果登录后的下一步可能先弹确认框、协议框或二次验证弹窗,第一段等待改成:

```javascript
const branch = await mcp__iOSDriver__wait_and_inspect({
  conditions: [
    { id: "confirm_alert", mode: "textExists", text: "<confirm-title>" },
    { id: "success", mode: "targetExists", accessibilityIdentifier: "home_title" },
    { id: "error_text", mode: "textExists", text: "<login-error-text>" }
  ],
  timeoutMs: 10000,
  intervalMs: 200,
  inspectOptions: { maxDepth: 8, maxTargets: 120 }
})
```

命中 `confirm_alert` 后,转 `ios-ui-alert` 响应,再做第二段等待去等最终成功 / 失败态。

## 异步提交

适合登录、注册、保存等会经过 loading 或网络请求的流程。

```javascript
const snapshot = await mcp__iOSDriver__ui_inspect({
  accessibilityIdentifierPrefix: "auth_",
  maxDepth: 8,
  maxTargets: 120
})

await mcp__iOSDriver__ui_input({
  fields: [
    {
      accessibilityIdentifier: "auth_username_field",
      text: "<username>",
      submit: false
    },
    {
      accessibilityIdentifier: "auth_password_field",
      text: "<password>",
      submit: false
    }
  ],
  viewSnapshotID: snapshot.viewSnapshotID
})

await mcp__iOSDriver__ui_tap({
  accessibilityIdentifier: "auth_submit_button",
  viewSnapshotID: snapshot.viewSnapshotID
})

const result = await mcp__iOSDriver__wait_and_inspect({
  conditions: [
    { id: "success", mode: "targetExists", accessibilityIdentifier: "dashboard_title" },
    { id: "error_label", mode: "targetExists", accessibilityIdentifier: "auth_error_label" },
    { id: "error_text", mode: "textExists", text: "登录失败" }
  ],
  timeoutMs: 10000,
  intervalMs: 200,
  inspectOptions: { maxDepth: 8, maxTargets: 120 }
})

if (result.matchedID === "success") {
  // 继续验证成功页结构
} else if (result.matchedID === "error_label" || result.matchedID === "error_text") {
  // 继续验证错误提示、按钮状态、密码字段是否被清空等失败态
} else {
  // 超时:重新 inspect 并记录当前屏幕状态
}
```

异步流程不要用 `snapshotChanged` 判断成功,也不要用固定 sleep 代替条件等待。成功和失败都应有明确 UI 判据。

## 同步提交

适合纯本地校验,例如必填字段为空后立即显示错误文案。

```javascript
const result = await mcp__iOSDriver__ui_tap_and_inspect({
  accessibilityIdentifier: "profile_save_button",
  viewSnapshotID: snapshot.viewSnapshotID,
  waitForStable: true,
  stableTimeMs: 300
})

const errorLabel = result.targets.find(t =>
  t.accessibilityIdentifier === "profile_error_label"
)
```

同步流程可以直接读 `ui_tap_and_inspect` 返回的 targets;若出现 loading、按钮禁用、网络请求中等中间态,应改走异步提交流程。

## 注册成功 Alert

```javascript
const result = await mcp__iOSDriver__wait_and_inspect({
  conditions: [
    { id: "success_alert", mode: "textExists", text: "注册成功" },
    { id: "register_error", mode: "targetExists", accessibilityIdentifier: "register_error_label" }
  ],
  timeoutMs: 10000,
  intervalMs: 200,
  inspectOptions: { maxDepth: 8 }
})

if (result.matchedID === "success_alert") {
  await mcp__iOSDriver__ui_alert_respond({ role: "default" })
}
```

Alert 按钮响应归 `ios-ui-alert`;本 skill 只负责填写和触发提交。

## UISearchBar 键盘 Search 提交

`UISearchBar` 是容器,需要定位内部 `UISearchTextField`。

```javascript
const snapshot = await mcp__iOSDriver__ui_inspect({
  accessibilityIdentifierPrefix: "search_",
  maxDepth: 5,
  maxTargets: 80
})

const searchField = snapshot.targets.find(t =>
  t.type === "UISearchTextField" ||
  (t.type === "UITextField" && t.path.includes("search"))
)

await mcp__iOSDriver__ui_input({
  fields: [{
    path: searchField.path,
    text: "<query>",
    mode: "replace",
    // 仅当搜索由键盘 Search / Done 触发时才设 true。
    submit: true
  }],
  viewSnapshotID: snapshot.viewSnapshotID
})

const result = await mcp__iOSDriver__wait_and_inspect({
  conditions: [
    { id: "result", mode: "targetExists", accessibilityIdentifier: "search_result_label" },
    { id: "empty", mode: "targetExists", accessibilityIdentifier: "search_empty_state" }
  ],
  timeoutMs: 5000,
  intervalMs: 200,
  inspectOptions: { maxDepth: 8 }
})
```

如果 App 只在独立搜索按钮上触发查询,将 `submit` 设为 `false`,重新 inspect 后用 `ui_tap` 点击该按钮。只有键盘 Search / Done 是业务触发条件时才使用 `submit:true`。

## UISearchBar 取消和清空

取消按钮通常在搜索框获得焦点后才出现:

```javascript
await mcp__iOSDriver__ui_tap({
  accessibilityIdentifier: "search_container",
  viewSnapshotID: snapshot.viewSnapshotID
})

await mcp__iOSDriver__ui_wait({ mode: "idle", stableMs: 300 })

const focused = await mcp__iOSDriver__ui_inspect({
  accessibilityIdentifierPrefix: "search_",
  maxDepth: 5
})

const cancelButton = focused.targets.find(t =>
  t.type === "UIButton" && (t.text === "Cancel" || t.text === "取消")
)
```

清空按钮只在输入框有内容时出现。输入后重新 inspect,按按钮 text、accessibilityLabel 或 path 定位后用 `ui_tap`。不同 App 对取消和清空后的文本保留策略可能不同,以 inspect 后的实际字段状态为准。
