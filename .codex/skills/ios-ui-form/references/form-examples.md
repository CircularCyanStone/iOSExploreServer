# iOS 表单流程参考

只在需要完整流程时读取本文件。所有 identifier、文本和凭据都必须从当前 App 的 `ui_inspect` 结果与任务输入获取；下列尖括号内容仅表示占位符，不得直接发送。

## 通用异步表单

适用于认证、注册、保存等经过网络或异步任务的表单。先为当前页面选择至少一个明确成功终态和一个明确失败终态；不要只用 `snapshotChanged` 或 loading 消失判断结果。

```javascript
const snapshot = await mcp__iOSDriver__ui_inspect({
  maxDepth: 8,
  maxTargets: 120
})

await mcp__iOSDriver__ui_input({
  fields: [
    { accessibilityIdentifier: "<primary-field-id>", text: "<primary-value>", submit: false },
    { accessibilityIdentifier: "<secure-field-id>", text: "<secure-value>", submit: false }
  ],
  viewSnapshotID: snapshot.viewSnapshotID
})

await mcp__iOSDriver__ui_tap({
  accessibilityIdentifier: "<submit-button-id>",
  viewSnapshotID: snapshot.viewSnapshotID
})

const result = await mcp__iOSDriver__wait_and_inspect({
  conditions: [
    { id: "success", mode: "targetExists", accessibilityIdentifier: "<success-target-id>" },
    { id: "failure_target", mode: "targetExists", accessibilityIdentifier: "<failure-target-id>" },
    { id: "failure_text", mode: "textExists", text: "<stable-failure-text>" }
  ],
  timeoutMs: 10000,
  intervalMs: 200,
  inspectOptions: { maxDepth: 8, maxTargets: 120 }
})

if (result.wait.matchedID === "success") {
  // 从 result.observation 验证成功态的补充结构。
} else if (["failure_target", "failure_text"].includes(result.wait.matchedID)) {
  // 从 result.observation 验证错误提示、按钮和安全字段状态。
} else if (result.wait.code === "wait_timeout") {
  // result.observation 是超时时尽力取得的最新 UI，用于分诊，不代表成功。
}
```

`wait_and_inspect` 的结果固定分为 `wait` 和 `observation`：命中条件读取 `result.wait.matchedID`，最新 UI 读取 `result.observation`。等待条件和超时的完整契约归 `ios-ui-wait`。

### loading 的两段式处理

`targetGone` 对从未出现的目标也会立即满足，因此不要把 `loading_done` 与 success / failure 并列为终态。如果业务必须观察 loading 生命周期：

1. 先用 `targetExists(<loading-id>)` 确认 loading 确实出现；同时保留可能更快到达的 success / failure 分支。
2. 只有命中 loading 后，才等待 `targetGone(<loading-id>)` 推进阶段。
3. loading 消失后仍要继续等待明确的 success / failure；消失本身不表示提交成功。

## 同步校验

纯前端校验或立即发生的本地切页可使用 `ui_tap_and_inspect`：

```javascript
const result = await mcp__iOSDriver__ui_tap_and_inspect({
  accessibilityIdentifier: "<submit-button-id>",
  viewSnapshotID: snapshot.viewSnapshotID,
  waitForStable: true,
  stableTimeMs: 300,
  inspectDepth: 6,
  inspectMaxTargets: 100
})

const errorTarget = result.stateAfter.targets.find(target =>
  target.accessibilityIdentifier === "<validation-error-id>"
)
```

该工具返回 `{tap, stateAfter, timing}`，不是顶层 `targets`。一旦出现网络请求、loading 或延迟更新，改走通用异步表单流程。

## 确认 Alert 分支

危险操作或退出流程可能先出现确认框。第一段只识别“alert、直接成功、直接失败”三类分支：

```javascript
const branch = await mcp__iOSDriver__wait_and_inspect({
  conditions: [
    { id: "confirm_alert", mode: "textExists", text: "<stable-confirm-text>" },
    { id: "success", mode: "targetExists", accessibilityIdentifier: "<success-target-id>" },
    { id: "failure", mode: "targetExists", accessibilityIdentifier: "<failure-target-id>" }
  ],
  timeoutMs: 5000,
  intervalMs: 200,
  inspectOptions: { maxDepth: 8, maxTargets: 120 }
})

if (branch.wait.matchedID === "confirm_alert") {
  // 转 ios-ui-alert 选择并响应按钮，然后再等明确 success / failure。
}
```

不要在表单流程里猜 alert 按钮标题、下标或角色；这些选择规则归 `ios-ui-alert`。

## UISearchBar

`UISearchBar` 是容器，输入目标是内部 `UISearchTextField`。先 inspect 找到实际字段；以下示例只演示键盘 Search / Done 确实是业务触发方式的场景：

```javascript
const snapshot = await mcp__iOSDriver__ui_inspect({ maxDepth: 5, maxTargets: 80 })
const searchField = snapshot.targets.find(target => target.type === "UISearchTextField")

await mcp__iOSDriver__ui_input({
  fields: [{
    path: searchField.path,
    text: "<query>",
    mode: "replace",
    submit: true
  }],
  viewSnapshotID: snapshot.viewSnapshotID
})
```

若查询由独立按钮触发，保持 `submit:false`，重新 inspect 后点击按钮。搜索框获取焦点或内容变化后，取消和清空按钮可能动态出现；继续操作前重新 inspect，并以当前结构为准。
