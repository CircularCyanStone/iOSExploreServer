---
name: ios-ui-webview
description: WKWebView JavaScript 执行与轻量级 Web 自动化(开发调试 + 自动化测试)/ webview, javascript, js, eval, jsbridge, hybrid, web interaction, ui.webView.eval
allowed-tools:
  - mcp__iOSDriver__ui_inspect
  - mcp__iOSDriver__ui_webView_eval
  - mcp__iOSDriver__ui_topViewHierarchy
  - mcp__iOSDriver__ui_screenshot
---

# ios-ui-webview

在 WKWebView 中执行 JavaScript，用于混合 App 的轻量级 Web 自动化。

## 何时使用此 Skill

✅ **适用场景**（轻交互）：
- 触发 JSBridge 调用（如 `window.bridge.goPay()`）
- 简单的点击操作（如 `document.querySelector('#btn').click()`）
- 简单的表单填充（如 `document.querySelector('#input').value = 'text'`）
- 读取状态验证（如 `document.title`、`localStorage.getItem('key')`）

❌ **不适用场景**（复杂 Web 自动化，应使用 Puppeteer/CDP）：
- 复杂的表单验证和多步骤流程
- 等待 AJAX 完成、复杂异步状态
- Web 页面的截图对比和视觉验证
- 网络拦截、请求修改、Performance 监控

## 命令：ui.webView.eval

在 WKWebView 中执行 JavaScript。

### 参数

| 参数 | 类型 | 必填 | 说明 |
|-----|------|------|------|
| `accessibilityIdentifier` | String | 二选一 | WKWebView 的 accessibilityIdentifier |
| `path` | String | 二选一 | WKWebView 的路径（如 `root/0/1`） |
| `script` | String | 二选一 | JS 代码字符串（同步模式） |
| `function` | String | 二选一 | JS 函数体（异步模式，iOS 14+） |
| `arguments` | Object | 否 | 传递给 `function` 的参数 |
| `timeout` | Number | 否 | 超时时间（秒），默认 5，范围 1-30 |
| `viewSnapshotID` | String | 否 | 陈旧校验快照 ID |

### 同步模式 vs 异步模式

**同步模式（`script`）**：
- 适用于简单 JS 表达式
- 最后一个表达式的值自动作为返回值
- 不支持 `await` 和 Promise

```javascript
mcp__iOSDriver__ui_webView_eval({
  accessibilityIdentifier: "web_container",
  script: "document.title"
})
// → 返回页面标题字符串
```

**异步模式（`function`）**：
- 支持 `await` 和 Promise（iOS 14+）
- 函数体会被自动包装为 `async function() { ... }`
- iOS 14 以下自动降级到同步模式

```javascript
mcp__iOSDriver__ui_webView_eval({
  accessibilityIdentifier: "web_container",
  function: "const res = await fetch(\"/api/user\"); return await res.json();"
})
// → 返回 API 响应的 JSON 对象
```

**带参数的异步模式**：

```javascript
mcp__iOSDriver__ui_webView_eval({
  accessibilityIdentifier: "web_container",
  function: "const {userId} = arguments[0]; return document.querySelector(`#user-${userId}`).textContent;",
  arguments: {userId: 123}
})
// → 返回 #user-123 元素的文本内容
```

### 常见场景

**1. 触发 JSBridge 调用**

```javascript
mcp__iOSDriver__ui_webView_eval({
  accessibilityIdentifier: "web_container",
  script: "window.bridge.goPay(); true"
})
// → 返回 true（表示调用已执行）
```

**2. 点击 Web 元素**

```javascript
mcp__iOSDriver__ui_webView_eval({
  accessibilityIdentifier: "web_container",
  script: "document.querySelector('#submit-btn').click(); true"
})
// → 返回 true（表示点击已执行）
```

**3. 填充表单**

```javascript
mcp__iOSDriver__ui_webView_eval({
  accessibilityIdentifier: "web_container",
  script: "document.querySelector('#username').value = 'alice'; document.querySelector('#password').value = '123456'; true"
})
// → 返回 true（表示表单已填充）
```

**4. 读取页面状态**

```javascript
mcp__iOSDriver__ui_webView_eval({
  accessibilityIdentifier: "web_container",
  script: "localStorage.getItem('token')"
})
// → 返回 localStorage 中存储的 token 值
```

**5. 等待异步内容加载（iOS 14+）**

```javascript
mcp__iOSDriver__ui_webView_eval({
  accessibilityIdentifier: "web_container",
  function: `
    // 轮询等待目标元素出现
    await new Promise(resolve => {
      const check = () => {
        if (document.querySelector('#content')) {
          resolve(true);
        } else {
          setTimeout(check, 100); // 每 100ms 检查一次
        }
      };
      check();
    });
    // 元素出现后返回其文本内容
    return document.querySelector('#content').textContent;
  `,
  timeout: 10
})
// → 返回 #content 的文本内容
```

### 典型工作流

```javascript
// 1. 定位 WebView 容器
mcp__iOSDriver__ui_inspect({
  includeText: false
})
// → 返回控件树，找到 WKWebView 的 path 或 accessibilityIdentifier

// 2. 执行 JS 操作
mcp__iOSDriver__ui_webView_eval({
  path: "root/0/1",
  script: "document.querySelector('#buy-btn').click(); true"
})
// → 返回 true（表示点击已执行）

// 3. 验证跳转（Native 页面）
mcp__iOSDriver__ui_topViewHierarchy()
// → 返回跳转后的视图层级
```

### 错误处理

| 错误码 | 触发条件 | 解决方案 |
|--------|----------|---------|
| `target_not_found` | WKWebView 定位失败 | 先用 `ui.inspect` 确认路径 |
| `invalid_data` | 目标非 WKWebView | 检查定位是否正确 |
| `invalid_data` | JS 执行超时 | 增大 `timeout` 或简化 JS |
| `invalid_data` | JS 执行错误 | 检查 JS 语法和 API 可用性 |
| `stale_locator` | viewSnapshotID 陈旧 | 重新 `ui.inspect` 获取新快照 |

### 限制

1. **不深入 WebView 内部**：`ui.inspect` 只能看到 WKWebView 容器，看不到内部 DOM 结构
2. **跨域限制**：遵循 WKWebView 的同源策略，无法访问跨域 iframe
3. **结果序列化**：无法返回 DOM 节点、Function、Symbol 等不可序列化类型
4. **iOS 版本降级**：iOS 14 以下不支持异步模式，自动降级到同步

### 何时切换到专业 Web 工具

当遇到以下场景时，应使用 Puppeteer/CDP/Playwright：
- 需要等待复杂的异步状态（多个 AJAX 请求完成）
- 需要网络拦截、请求修改、响应 mock
- 需要 Web 页面截图对比和视觉回归测试
- 需要 Performance 监控和分析
- 需要复杂的 DOM 查询和遍历

`ui.webView.eval` 的定位是**最小化 JS 执行原语**，不做 Web DSL 封装。

## 相关 skill

- `ios-automation` — L1 总入口；不确定走哪个子 skill 时先问它；用户说"在 WebView 里执行 JavaScript"/"WebView DOM 操作"时路由到本 skill
- `ios-ui-nav` — WKWebView 容器的导航与返回走它
- `ios-ui-shot` — WebView 整体截图（不含内部 DOM 对比）

**平台约束**：`ui.webView.eval` 基于 WKWebView 的 `evaluateJavaScript` API，仅支持可序列化的 JS 值。异步模式依赖 iOS 14+ 的 `callAsyncJavaScript`，低版本自动降级到同步。命令在主线程执行。
