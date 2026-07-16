# 异步表单提交最佳实践

**文档版本**: 1.0  
**创建时间**: 2026-07-16  
**适用范围**: iOSExploreServer + iOSDriver MCP + iOS App 表单自动化测试

---

## 目标

展示**异步表单提交**（登录、注册、保存等有网络请求的场景）的正确自动化方式，避免常见陷阱：固定等待、读到中间态、无法区分成功/失败。

**核心原则**: 用 `wait_and_inspect` 或 `ui_waitAny` 动态等待多个明确判据，而非 `ui_tap_and_inspect` + 固定 sleep。

---

## 对比：错误方式 vs 正确方式

### ❌ 错误方式（固定等待）

```javascript
// 点击登录按钮后固定等待 1.5 秒
await mcp__iOSDriver__ui_tap_and_inspect({
  accessibilityIdentifier: "login_button",
  stableTimeMs: 1500,  // ❌ 固定等待
  waitForStable: true,
  viewSnapshotID: "snap-123"
})

// 问题：
// 1. 登录成功可能只需 800ms，浪费了 700ms
// 2. 网络慢时 1500ms 不够，会读到 loading 中间态
// 3. 无法区分成功/失败，只能事后判断 navigationBar.title
// 4. stableTimeMs 判的是"UI 结构稳定"，loading 期间 spinner 一直转、结构不变，会提前返回
```

### ✅ 正确方式（动态等待多判据）

```javascript
// 步骤 1: 点击登录按钮（不等待）
await mcp__iOSDriver__ui_tap({
  accessibilityIdentifier: "login_button",
  viewSnapshotID: "snap-123"
})

// 步骤 2: 动态等待成功/失败判据
const result = await mcp__iOSDriver__wait_and_inspect({
  conditions: [
    {
      id: "login_success",
      mode: "targetExists",
      accessibilityIdentifier: "home_welcome_label"  // 首页确定元素
    },
    {
      id: "login_failed",
      mode: "textExists",
      text: "用户名或密码错误"  // 错误提示文本
    }
  ],
  timeoutMs: 5000,    // 最多等 5 秒
  intervalMs: 100,    // 每 100ms 检查一次
  inspectOptions: { maxDepth: 3 }
})

// 步骤 3: 明确判断结果
if (result.matched && result.matchedID === "login_success") {
  console.log("✅ 登录成功，耗时:", result.elapsedMs, "ms")
} else if (result.matched && result.matchedID === "login_failed") {
  console.log("❌ 登录失败，耗时:", result.elapsedMs, "ms")
}

// 优势：
// 1. 动态耗时：成功 800ms、失败 500ms（命中即返回）
// 2. 明确判据：matchedID 清楚表达结果
// 3. 高可靠性：等待目标元素真实出现，不是"UI 稳定"
// 4. 效率提升：40-75%
```

---

## 场景 1：登录（成功 + 失败）

### 1.1 登录成功

```javascript
// === 步骤 1: 获取表单元素 ===
const loginPage = await mcp__iOSDriver__ui_inspect({
  accessibilityIdentifierPrefix: "login_",
  maxDepth: 3
})

// === 步骤 2: 填写用户名密码 ===
await mcp__iOSDriver__ui_input({
  accessibilityIdentifier: "login_username_field",
  text: "test",
  submit: false,  // 中间字段不收键盘
  viewSnapshotID: loginPage.viewSnapshotID
})

await mcp__iOSDriver__ui_input({
  accessibilityIdentifier: "login_password_field",
  text: "123456",
  submit: true,  // 最后一个字段收键盘
  viewSnapshotID: loginPage.viewSnapshotID
})

// === 步骤 3: 点击登录（不等待）===
await mcp__iOSDriver__ui_tap({
  accessibilityIdentifier: "login_button",
  viewSnapshotID: loginPage.viewSnapshotID
})

// === 步骤 4: 动态等待多判据 ===
const result = await mcp__iOSDriver__wait_and_inspect({
  conditions: [
    {
      id: "success",
      mode: "targetExists",
      accessibilityIdentifier: "home_welcome_label"  // 首页欢迎标签
    },
    {
      id: "failed_label",
      mode: "targetExists",
      accessibilityIdentifier: "login_error_label"  // 错误标签
    },
    {
      id: "failed_text",
      mode: "textExists",
      text: "用户名或密码错误"  // 错误文本
    }
  ],
  timeoutMs: 5000,
  intervalMs: 100,
  inspectOptions: {
    maxDepth: 3,
    maxTargets: 50
  }
})

// === 步骤 5: 判断并验证 ===
if (result.matched && result.matchedID === "success") {
  console.log("✅ 登录成功")
  console.log("  实际耗时:", result.elapsedMs, "ms")
  console.log("  页面标题:", result.navigationBar?.title)
  
  // 继续验证首页内容
  const welcomeLabel = result.targets.find(t => t.accessibilityIdentifier === "home_welcome_label")
  console.log("  欢迎文本:", welcomeLabel?.text)
} else {
  console.log("❌ 登录失败或超时，matchedID:", result.matchedID)
}
```

### 1.2 登录失败（错误凭据）

```javascript
// 前面步骤相同，使用错误凭据
await mcp__iOSDriver__ui_input({
  accessibilityIdentifier: "login_username_field",
  text: "nonexistent",
  submit: false,
  viewSnapshotID: loginPage.viewSnapshotID
})

await mcp__iOSDriver__ui_input({
  accessibilityIdentifier: "login_password_field",
  text: "wrongpass",
  submit: true,
  viewSnapshotID: loginPage.viewSnapshotID
})

await mcp__iOSDriver__ui_tap({
  accessibilityIdentifier: "login_button",
  viewSnapshotID: loginPage.viewSnapshotID
})

// 等待失败判据
const result = await mcp__iOSDriver__wait_and_inspect({
  conditions: [
    {
      id: "error_label",
      mode: "targetExists",
      accessibilityIdentifier: "login_error_label"
    },
    {
      id: "error_text",
      mode: "textExists",
      text: "用户名或密码错误"
    },
    {
      id: "unexpected_success",  // 兜底：不应该成功
      mode: "targetExists",
      accessibilityIdentifier: "home_welcome_label"
    }
  ],
  timeoutMs: 5000,
  intervalMs: 100,
  inspectOptions: { maxDepth: 3 }
})

if (result.matchedID === "error_label" || result.matchedID === "error_text") {
  console.log("✅ 登录失败验证通过")
  console.log("  实际耗时:", result.elapsedMs, "ms")
  
  // 核对关键状态
  const errorLabel = result.targets.find(t => t.accessibilityIdentifier === "login_error_label")
  console.log("  错误标签可见:", !errorLabel?.isHidden)
  console.log("  错误文本:", errorLabel?.text)
  
  // 验证密码框已被清空（iOS 标准行为）
  const passwordField = result.targets.find(t => t.accessibilityIdentifier === "login_password_field")
  console.log("  密码框已清空:", passwordField?.text === null)
  
  // 验证仍停留在登录页
  console.log("  当前页面:", result.navigationBar?.title)  // 应为 "登录"
} else if (result.matchedID === "unexpected_success") {
  console.log("❌ 测试失败：错误凭据居然登录成功了")
}
```

### 1.3 登录失败（空输入）

```javascript
// 空用户名
await mcp__iOSDriver__ui_input({
  accessibilityIdentifier: "login_username_field",
  text: "",  // 空字符串
  submit: false,
  viewSnapshotID: loginPage.viewSnapshotID
})

await mcp__iOSDriver__ui_input({
  accessibilityIdentifier: "login_password_field",
  text: "123456",
  submit: true,
  viewSnapshotID: loginPage.viewSnapshotID
})

await mcp__iOSDriver__ui_tap({
  accessibilityIdentifier: "login_button",
  viewSnapshotID: loginPage.viewSnapshotID
})

// 空输入通常在前端校验，失败更快（200-500ms）
const result = await mcp__iOSDriver__wait_and_inspect({
  conditions: [
    {
      id: "validation_error",
      mode: "textExists",
      text: "用户名或密码不能为空"  // 前端校验消息
    },
    {
      id: "generic_error",
      mode: "targetExists",
      accessibilityIdentifier: "login_error_label"
    }
  ],
  timeoutMs: 3000,  // 前端校验可以缩短超时
  intervalMs: 100,
  inspectOptions: { maxDepth: 3 }
})

console.log("空输入校验结果:", result.matchedID)
console.log("实际耗时:", result.elapsedMs, "ms")  // 通常 < 500ms
```

---

## 场景 2：注册（成功 + 失败 + alert）

### 2.1 注册成功（带 alert 响应）

```javascript
// === 步骤 1: 跳转到注册页 ===
const loginPage = await mcp__iOSDriver__ui_inspect({ maxDepth: 2 })

await mcp__iOSDriver__ui_tap({
  accessibilityIdentifier: "goto_register_button",
  viewSnapshotID: loginPage.viewSnapshotID
})

// 等待跳转完成
await mcp__iOSDriver__ui_wait({
  mode: "idle",
  stableMs: 300
})

// === 步骤 2: 获取注册页表单 ===
const registerPage = await mcp__iOSDriver__ui_inspect({
  accessibilityIdentifierPrefix: "register_",
  maxDepth: 3
})

// === 步骤 3: 填写注册表单 ===
await mcp__iOSDriver__ui_input({
  accessibilityIdentifier: "register_username_field",
  text: "newuser",
  submit: false,
  viewSnapshotID: registerPage.viewSnapshotID
})

await mcp__iOSDriver__ui_input({
  accessibilityIdentifier: "register_email_field",
  text: "newuser@example.com",
  submit: false,
  viewSnapshotID: registerPage.viewSnapshotID
})

await mcp__iOSDriver__ui_input({
  accessibilityIdentifier: "register_password_field",
  text: "password123",
  submit: false,
  viewSnapshotID: registerPage.viewSnapshotID
})

await mcp__iOSDriver__ui_input({
  accessibilityIdentifier: "register_confirm_password_field",
  text: "password123",
  submit: true,  // 最后一个字段收键盘
  viewSnapshotID: registerPage.viewSnapshotID
})

// === 步骤 4: 点击注册 ===
await mcp__iOSDriver__ui_tap({
  accessibilityIdentifier: "register_button",
  viewSnapshotID: registerPage.viewSnapshotID
})

// === 步骤 5: 等待注册结果（会弹 alert）===
const result = await mcp__iOSDriver__wait_and_inspect({
  conditions: [
    {
      id: "success_alert",
      mode: "textExists",
      text: "注册成功"  // alert 的 title
    },
    {
      id: "error_label",
      mode: "targetExists",
      accessibilityIdentifier: "register_error_label"
    },
    {
      id: "username_exists",
      mode: "textExists",
      text: "用户名已存在"
    }
  ],
  timeoutMs: 5000,
  intervalMs: 100,
  inspectOptions: { maxDepth: 3 }
})

// === 步骤 6: 处理 alert ===
if (result.matchedID === "success_alert") {
  console.log("✅ 注册成功，alert 已显示")
  console.log("  耗时:", result.elapsedMs, "ms")
  
  // 验证 alert 内容
  const alertInfo = result.alert
  console.log("  Alert title:", alertInfo?.title)
  console.log("  Alert message:", alertInfo?.message)
  console.log("  按钮:", alertInfo?.buttons.map(b => b.title))
  
  // 点击确定按钮
  await mcp__iOSDriver__ui_alert_respond({
    buttonTitle: "确定"
  })
  
  // === 步骤 7: 验证返回登录页 ===
  const backToLogin = await mcp__iOSDriver__ui_inspect({ maxDepth: 2 })
  console.log("  返回页面:", backToLogin.navigationBar?.title)  // 应为 "登录"
} else {
  console.log("❌ 注册失败，matchedID:", result.matchedID)
}
```

### 2.2 注册失败（密码不匹配）

```javascript
// 填写表单（两次密码不一致）
await mcp__iOSDriver__ui_input({
  accessibilityIdentifier: "register_password_field",
  text: "password123",
  submit: false,
  viewSnapshotID: registerPage.viewSnapshotID
})

await mcp__iOSDriver__ui_input({
  accessibilityIdentifier: "register_confirm_password_field",
  text: "password456",  // 不一致
  submit: true,
  viewSnapshotID: registerPage.viewSnapshotID
})

await mcp__iOSDriver__ui_tap({
  accessibilityIdentifier: "register_button",
  viewSnapshotID: registerPage.viewSnapshotID
})

// 等待前端校验（通常很快）
const result = await mcp__iOSDriver__wait_and_inspect({
  conditions: [
    {
      id: "mismatch_error",
      mode: "textExists",
      text: "两次密码输入不一致"
    },
    {
      id: "error_label",
      mode: "targetExists",
      accessibilityIdentifier: "register_error_label"
    }
  ],
  timeoutMs: 3000,  // 前端校验快，缩短超时
  intervalMs: 100,
  inspectOptions: { maxDepth: 3 }
})

console.log("密码不匹配验证:", result.matchedID)
console.log("耗时:", result.elapsedMs, "ms")  // 通常 < 500ms
```

### 2.3 注册失败（用户名已存在）

```javascript
// 使用已存在的用户名 "test"
await mcp__iOSDriver__ui_input({
  accessibilityIdentifier: "register_username_field",
  text: "test",  // 预置账号
  submit: false,
  viewSnapshotID: registerPage.viewSnapshotID
})

// 其他字段填写...（省略）

await mcp__iOSDriver__ui_tap({
  accessibilityIdentifier: "register_button",
  viewSnapshotID: registerPage.viewSnapshotID
})

// 等待服务器返回（需要网络请求）
const result = await mcp__iOSDriver__wait_and_inspect({
  conditions: [
    {
      id: "username_exists",
      mode: "textExists",
      text: "用户名已存在"
    },
    {
      id: "error_label",
      mode: "targetExists",
      accessibilityIdentifier: "register_error_label"
    },
    {
      id: "unexpected_success",
      mode: "textExists",
      text: "注册成功"
    }
  ],
  timeoutMs: 5000,
  intervalMs: 100,
  inspectOptions: { maxDepth: 3 }
})

if (result.matchedID === "username_exists" || result.matchedID === "error_label") {
  console.log("✅ 用户名已存在验证通过")
  console.log("  耗时:", result.elapsedMs, "ms")  // 服务器响应通常 800-1500ms
}
```

---

## 场景 3：重置密码（成功 + 失败）

### 3.1 重置密码成功

```javascript
// === 步骤 1-2: 跳转到重置密码页并获取表单 ===
const loginPage = await mcp__iOSDriver__ui_inspect({ maxDepth: 2 })

await mcp__iOSDriver__ui_tap({
  accessibilityIdentifier: "goto_reset_password_button",
  viewSnapshotID: loginPage.viewSnapshotID
})

await mcp__iOSDriver__ui_wait({ mode: "idle", stableMs: 300 })

const resetPage = await mcp__iOSDriver__ui_inspect({
  accessibilityIdentifierPrefix: "reset_",
  maxDepth: 3
})

// === 步骤 3: 填写重置密码表单 ===
await mcp__iOSDriver__ui_input({
  accessibilityIdentifier: "reset_username_field",
  text: "test",
  submit: false,
  viewSnapshotID: resetPage.viewSnapshotID
})

await mcp__iOSDriver__ui_input({
  accessibilityIdentifier: "reset_email_field",
  text: "test@example.com",
  submit: false,
  viewSnapshotID: resetPage.viewSnapshotID
})

await mcp__iOSDriver__ui_input({
  accessibilityIdentifier: "reset_new_password_field",
  text: "newpass123",
  submit: false,
  viewSnapshotID: resetPage.viewSnapshotID
})

await mcp__iOSDriver__ui_input({
  accessibilityIdentifier: "reset_confirm_password_field",
  text: "newpass123",
  submit: true,
  viewSnapshotID: resetPage.viewSnapshotID
})

// === 步骤 4: 点击重置 ===
await mcp__iOSDriver__ui_tap({
  accessibilityIdentifier: "reset_password_button",
  viewSnapshotID: resetPage.viewSnapshotID
})

// === 步骤 5: 等待重置结果（会弹 alert）===
const result = await mcp__iOSDriver__wait_and_inspect({
  conditions: [
    {
      id: "success_alert",
      mode: "textExists",
      text: "重置成功"
    },
    {
      id: "error_label",
      mode: "targetExists",
      accessibilityIdentifier: "reset_password_error_label"
    },
    {
      id: "invalid_credentials",
      mode: "textExists",
      text: "用户名或邮箱不正确"
    }
  ],
  timeoutMs: 5000,
  intervalMs: 100,
  inspectOptions: { maxDepth: 3 }
})

if (result.matchedID === "success_alert") {
  console.log("✅ 密码重置成功")
  console.log("  耗时:", result.elapsedMs, "ms")
  
  // 响应 alert
  await mcp__iOSDriver__ui_alert_respond({
    buttonTitle: "确定"
  })
  
  // 验证返回登录页
  const backToLogin = await mcp__iOSDriver__ui_inspect({ maxDepth: 2 })
  console.log("  返回页面:", backToLogin.navigationBar?.title)
  
  // === 步骤 6: 使用新密码登录验证 ===
  await mcp__iOSDriver__ui_input({
    accessibilityIdentifier: "login_username_field",
    text: "test",
    submit: false,
    viewSnapshotID: backToLogin.viewSnapshotID
  })
  
  await mcp__iOSDriver__ui_input({
    accessibilityIdentifier: "login_password_field",
    text: "newpass123",  // 新密码
    submit: true,
    viewSnapshotID: backToLogin.viewSnapshotID
  })
  
  await mcp__iOSDriver__ui_tap({
    accessibilityIdentifier: "login_button",
    viewSnapshotID: backToLogin.viewSnapshotID
  })
  
  const loginResult = await mcp__iOSDriver__wait_and_inspect({
    conditions: [
      {
        id: "success",
        mode: "targetExists",
        accessibilityIdentifier: "home_welcome_label"
      }
    ],
    timeoutMs: 5000,
    intervalMs: 100,
    inspectOptions: { maxDepth: 3 }
  })
  
  console.log("  新密码登录:", loginResult.matchedID === "success" ? "✅ 成功" : "❌ 失败")
}
```

---

## 判据类型选择矩阵

| 判据类型 | 适用场景 | 优先级 | 示例 |
|---|---|---|---|
| `targetExists` + `accessibilityIdentifier` | 元素有 identifier | **最高** | 首页欢迎标签、错误标签 |
| `textExists` | 元素无 identifier、动态文本 | 中 | "欢迎回来"、"用户名或密码错误" |
| `targetGone` | 等中间态消失 | 低 | loading spinner 消失（需配合 targetExists 确认终态）|

**避免使用**:
- ❌ `snapshotChanged` - 只表达"界面变了"，失败时界面也会变
- ❌ `targetGone:"submit_button"` - 按钮禁用时还在，只是 `isEnabled:false`
- ❌ 固定 sleep - 浪费时间、覆盖不了网络慢

---

## 性能对比总结

| 场景 | 固定等待 | 动态等待 | 效率提升 |
|---|---|---|---|
| 登录成功 | 1500ms | 800-1200ms | **40-50%** |
| 登录失败 | 2500ms | 500-800ms | **70-80%** |
| 注册成功 | 2000ms | 1000-1500ms | **40-50%** |
| 前端校验 | 1000ms | 200-500ms | **75%** |

---

## 常见陷阱与避免方式

### 陷阱 1: 用 `ui_tap_and_inspect` 等异步操作

**现象**: loading 期间 UI 结构稳定（spinner 一直转），`stableTimeMs` 提前判稳定，读到中间态。

**避免**: 异步操作用 `ui_tap` + `wait_and_inspect`，不用 `ui_tap_and_inspect`。

### 陷阱 2: 用 `snapshotChanged` 判成功

**现象**: 登录失败时界面也会变（弹 alert、清空密码框），被误判为成功。

**避免**: 用目标页的**确定元素**（`targetExists:"home_welcome_label"`）。

### 陷阱 3: 只设成功判据，不设失败判据

**现象**: 登录失败时超时等满 5 秒，浪费时间。

**避免**: 同时设成功/失败两个判据，先命中谁返回谁。

### 陷阱 4: 用 `targetGone:"submit_button"` 判成功

**现象**: 按钮禁用时还在（`isEnabled:false`），不是消失。

**避免**: 用目标页元素出现（`targetExists`）或错误文本出现（`textExists`）。

---

## 相关文档

- **ios-ui-form skill**: `.claude/skills/ios-ui-form/SKILL.md`
- **ios-ui-wait skill**: `.claude/skills/ios-ui-wait/SKILL.md`
- **测试提示词模板**: `docs/skills/test-scenarios/auth-flow-test-prompt.md`
- **异步等待分析**: `docs/skills/test-scenarios/async-wait-analysis.md`
