# ui.webView.eval 命令设计文档

**文档版本**: v1.0  
**创建日期**: 2026-07-18  
**设计目标**: 为混合 App 提供最小化 JavaScript 执行能力，覆盖 Native ↔ WebView 交互场景  
**实现状态**: 设计阶段

---

## 1. 背景与动机

### 1.1 问题陈述

**混合 App 的典型测试场景**：

```
1. Native 首页 (UIKit) → iOSExploreServer 自动化
2. 点击 Banner → 打开 WebView 加载 H5 活动页
3. H5 页面内操作 → ❓ 当前没有能力
4. 点击"立即购买" → 触发 JSBridge → 跳转到 Native 支付页
5. 支付成功 → 返回 Native 订单页
```

**当前痛点**：
- iOSExploreServer 只能操作 Native UI，无法进入 WebView 内部
- 测试流程在 step 3 被割裂，需要手动协调 Native 工具和前端工具
- 轻交互场景（简单点击、表单填充、触发 JSBridge）需要完整的前端测试工具显得过重

### 1.2 设计定位

**`ui.webView.eval` 的定位**：

✅ **适用场景**（轻交互）：
- 触发 JSBridge 调用：`window.bridge.goPay()`
- 简单的点击操作：`document.querySelector('#btn').click()`
- 简单的表单填充：`document.querySelector('#input').value = 'text'`
- 读取状态验证：`document.title`、`localStorage.getItem('key')`

❌ **不适用场景**（复杂 Web 自动化，应使用 Puppeteer/CDP）：
- 复杂的表单验证和多步骤流程
- 等待 AJAX 完成、复杂异步状态
- Web 页面的截图对比和视觉验证
- 网络拦截、请求修改、Performance 监控

**关键原则**：
1. **职责边界清晰**：Native 自动化工具，提供 JS 执行原语，不做 Web DSL 封装
2. **保持测试流程连贯**：不需要在 Native 和 Web 工具之间来回切换
3. **明确能力边界**：文档明确说明哪些场景应该用前端工具

---

## 2. 方案选择

### 2.1 方案对比

| 方案 | 说明 | 优点 | 缺点 | 工作量 |
|-----|------|------|------|--------|
| **方案 A** | 单一命令 + 同步执行 | 简单直接、工作量小 | 不支持 Promise/async-await | 1-2 天 |
| **方案 B** | 单一命令 + 异步支持 | 支持复杂异步场景、公开 API | 需要版本适配 | 2-3 天 |
| **方案 C** | 多命令分层（tap/input/wait） | 语义清晰、降低门槛 | 重复造轮子、维护成本高 | 5-7 天 |

**选择**：**方案 B**（单一命令 + 异步支持）

**理由**：
1. ✅ 覆盖更多场景（Promise/async-await）
2. ✅ 仍然使用公开 API（`evaluateJavaScript` + `callAsyncJavaScript`）
3. ✅ iOS 14 以下自动降级到同步模式，透明处理
4. ✅ 符合"最小化"定位，不做过度封装
5. ✅ 工作量适中（2-3 天）

---

## 3. 命令接口设计

### 3.1 命令定义

```swift
action: "ui.webView.eval"
```

### 3.2 输入参数

| 参数 | 类型 | 必填 | 约束 | 说明 |
|-----|------|------|------|------|
| `accessibilityIdentifier` | String | 二选一 | 与 `path` 互斥 | WKWebView 的 accessibilityIdentifier |
| `path` | String | 二选一 | 与 `accessibilityIdentifier` 互斥 | WKWebView 的路径（如 `root/0/1`） |
| `script` | String | 二选一 | 与 `function` 互斥 | JS 代码字符串（同步模式）；最后一个表达式的值自动作为返回值，无需显式 `return` |
| `function` | String | 二选一 | 与 `script` 互斥 | JS 函数体（异步模式）；不含 `async` 包装器，会被自动包装为 `async function() { <functionBody> }` 执行 |
| `arguments` | Object | 否 | 只能与 `function` 一起 | 传递给 `function` 的参数（`[String: Any]` 字典）；作为 JS 函数的第一个参数传入，在函数体内用 `arguments[0]` 访问 |
| `timeout` | Number | 否 | 范围 1-30 | 超时时间（秒），默认 5；包含定位、校验、执行的总时长 |
| `viewSnapshotID` | String | 否 | - | 陈旧校验快照 ID（来自 `ui.inspect`）；校验在定位成功后、执行 JS 之前进行 |

**Schema 约束**：
```swift
constraints: [
    .exactlyOneOf(["accessibilityIdentifier", "path"]),
    .exactlyOneOf(["script", "function"]),
    .implies("arguments", requires: "function")
]
```

### 3.3 响应格式

**成功响应**：
```json
{
  "code": "ok",
  "data": {
    "result": <any>,        // JS 返回值（null/bool/number/string/array/object）
    "resultType": "string", // 类型：null/boolean/number/string/array/object
    "mode": "sync",         // 执行模式：sync/async
    "executionTime": 0.123, // 执行耗时（秒）
    "iosVersion": "17.5.0"  // iOS 版本（用于诊断降级）
  }
}
```

**错误响应**：

| 错误码 | 触发条件 | message 示例 |
|--------|----------|-------------|
| `target_not_found` | WKWebView 定位失败 | `webView target not found — the page view tree may have changed` |
| `invalid_data` | 目标非 WKWebView | `target is not a WKWebView (got UIView)` |
| `invalid_data` | JS 执行超时 | `JS execution timed out after 5s (elapsed 5.02s)` |
| `invalid_data` | JS 执行错误 | `JS execution failed: ReferenceError: xxx is not defined` |
| `stale_locator` | viewSnapshotID 陈旧 | `viewSnapshotID mismatch` |

---

## 4. 技术实现设计

### 4.1 架构分层

遵循 iOSExploreUIKit 的标准三层结构：

```
┌─────────────────────────────────────────┐
│  UIWebViewEvalCommand                   │  ← 薄 adapter
│  - 日志记录                              │
│  - 错误处理（catch → envelope）          │
└──────────────────┬──────────────────────┘
                   │
┌──────────────────▼──────────────────────┐
│  UIWebViewEvalExecutor (@MainActor)     │  ← 核心执行逻辑
│  - 定位 WKWebView                        │
│  - 陈旧校验                              │
│  - 判断执行模式（sync/async）            │
│  - 执行 JS（带超时）                     │
│  - 结果序列化                            │
└──────────────────┬──────────────────────┘
                   │
┌──────────────────▼──────────────────────┐
│  UIWebViewEvalInput (Foundation-only)   │  ← typed input
│  - 字段定义                              │
│  - Schema 暴露                           │
│  - Parse 逻辑                            │
└─────────────────────────────────────────┘
```

### 4.2 执行模式判断

```swift
// Executor 中的判断逻辑
if let function = input.function {
    if #available(iOS 14.0, *) {
        // 异步模式：callAsyncJavaScript
        return try await executeAsync(webView, function, input.arguments, input.timeout)
    } else {
        // 降级到同步模式：evaluateJavaScript
        UIKitCommandLogging.debug("command", "iOS < 14.0, downgrade to sync mode (expected behavior)")
        return try await executeSync(webView, function, input.timeout)
    }
} else if let script = input.script {
    // 同步模式：evaluateJavaScript
    return try await executeSync(webView, script, input.timeout)
}
```

**陈旧校验时机**：在定位成功后、执行 JS 之前进行。如果 `viewSnapshotID` 不匹配，返回 `stale_locator` 且不执行 JS。

### 4.3 底层 API 选择

| 执行模式 | API | iOS 版本 | 支持 Promise |
|---------|-----|---------|-------------|
| 同步 | `WKWebView.evaluateJavaScript(_:completionHandler:)` | iOS 10+ | ❌ |
| 异步 | `WKWebView.callAsyncJavaScript(_:arguments:in:contentWorld:)` | iOS 14+ | ✅ |

**降级策略**：
- iOS 14+ 且提供 `function` → 异步模式
- iOS 14 以下且提供 `function` → 自动降级到同步模式，记录日志
- 提供 `script` → 总是同步模式

### 4.4 超时处理

使用 Swift Concurrency 的 `withThrowingTaskGroup` 实现超时：

```swift
try await withThrowingTaskGroup(of: Any?.self) { group in
    // 操作 Task
    group.addTask {
        return try await webView.evaluateJavaScript(script)
    }
    
    // 超时 Task
    group.addTask {
        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        throw TimeoutError()
    }
    
    // 第一个完成的 Task 获胜
    guard let result = try await group.next() else {
        throw TimeoutError()
    }
    
    group.cancelAll()  // 取消另一个 Task
    return result
}
```

### 4.5 结果序列化

JS 返回值需要转换为 `JSONValue`：

| JS 类型 | Swift 类型 | JSONValue | resultType |
|---------|-----------|-----------|-----------|
| `null` / `undefined` | `NSNull` | `.null` | `"null"` |
| `boolean` | `NSNumber` (bool) | `.bool(Bool)` | `"boolean"` |
| `number` (整数) | `NSNumber` (int) | `.number(Double)` | `"number"` |
| `number` (浮点) | `NSNumber` (double) | `.number(Double)` | `"number"` |
| `string` | `String` | `.string(String)` | `"string"` |
| `Array` | `[Any]` | `.array([JSONValue])` | `"array"` |
| `Object` | `[String: Any]` | `.object([String: JSONValue])` | `"object"` |
| 其他（DOM 节点、Function、Symbol 等） | - | `.null` | `"object"` |

**说明**：
- `resultType` 是固定的 6 种枚举值：`null`、`boolean`、`number`、`string`、`array`、`object`
- 不可序列化的类型（DOM 节点、Function、Symbol 等）统一映射为 `result: null` + `resultType: "object"`，实际类型会在日志中记录

**NSNumber 类型判断**：
- 使用 `CFNumberGetType` 区分 Bool（`charType`）vs Int vs Double
- Bool 优先级最高（避免被误判为 Int）

---

## 5. 文件组织

```
Sources/iOSExploreUIKit/Commands/WebViewEval/
├── UIWebViewEvalInput.swift       (~180 行)
├── UIWebViewEvalExecutor.swift    (~280 行)
└── UIWebViewEvalCommand.swift     (~50 行)
```

所有文件整体包在 `#if canImport(UIKit)` 内。

**注册**：
```swift
// UIKitCommandRegistrar.swift
register(UIWebViewEvalCommand(), logCategory: .extensionCommand(category: "command"))
```

---

## 6. 使用示例

### 6.1 同步模式：触发 JSBridge

```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.webView.eval",
  "data": {
    "accessibilityIdentifier": "web_container",
    "script": "window.bridge.goPay(); true",
    "timeout": 5
  }
}'

# 响应
{
  "code": "ok",
  "data": {
    "result": true,
    "resultType": "boolean",
    "mode": "sync",
    "executionTime": 0.023,
    "iosVersion": "17.5.0"
  }
}
```

**说明**：最后一个表达式 `true` 自动作为返回值。如果只需要触发 JSBridge 调用而不关心返回值，可以只写 `"script": "window.bridge.goPay()"`。

### 6.2 同步模式：读取页面状态

```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.webView.eval",
  "data": {
    "path": "root/0/1",
    "script": "document.title",
    "viewSnapshotID": "snap-1"
  }
}'

# 响应
{
  "code": "ok",
  "data": {
    "result": "活动页面",
    "resultType": "string",
    "mode": "sync",
    "executionTime": 0.012,
    "iosVersion": "17.5.0"
  }
}
```

**说明**：`script` 执行后的最后一个表达式的值自动作为返回值，无需显式 `return`。

### 6.3 异步模式：等待 AJAX（iOS 14+）

```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.webView.eval",
  "data": {
    "accessibilityIdentifier": "web_container",
    "function": "const res = await fetch(\"/api/user\"); return await res.json();",
    "timeout": 10
  }
}'

# 响应
{
  "code": "ok",
  "data": {
    "result": {"id": 123, "name": "alice"},
    "resultType": "object",
    "mode": "async",
    "executionTime": 0.456,
    "iosVersion": "17.5.0"
  }
}
```

**说明**：`function` 字段是函数体（不含 `async` 包装器），会被自动包装为 `async function() { <functionBody> }` 执行。

### 6.4 异步模式：带参数（iOS 14+）

```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.webView.eval",
  "data": {
    "accessibilityIdentifier": "web_container",
    "function": "const {userId} = arguments[0]; return document.querySelector(`#user-${userId}`).textContent;",
    "arguments": {"userId": 123},
    "timeout": 5
  }
}'
```

**说明**：
- `arguments` 是 `[String: Any]` 字典，会作为 JS 函数的第一个参数传入
- 在函数体内用 `arguments[0]` 访问，然后解构：`const {userId} = arguments[0]`
- 或者直接访问：`arguments[0].userId`

### 6.5 错误场景：超时

```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.webView.eval",
  "data": {
    "accessibilityIdentifier": "web_container",
    "script": "while(true) {}",
    "timeout": 2
  }
}'

# 响应
{
  "code": "invalid_data",
  "message": "JS execution timed out after 2s (elapsed 2.01s)"
}
```

---

## 7. 测试策略

### 7.1 单元测试（macOS）

**文件**：`Tests/iOSExploreServerTests/UIWebViewEvalInputTests.swift`

**覆盖**：
- ✅ `script` 模式解析
- ✅ `function` 模式解析
- ✅ `arguments` 只能与 `function` 一起
- ✅ `script` 与 `function` 互斥
- ✅ `timeout` 范围校验（1-30）
- ✅ 定位字段互斥校验

### 7.2 集成测试（iOS framework）

**文件**：`Tests/iOSExploreServerTests/UIWebViewEvalTests.swift`（iOS target）

**覆盖**：
- ✅ 同步模式：执行简单 JS，返回 string/number/bool/null
- ✅ 同步模式：执行 JS 错误，返回 `invalid_data`
- ✅ 同步模式：超时，返回 `invalid_data`
- ✅ 异步模式（iOS 14+）：执行 async function，返回 object
- ✅ 异步模式降级（iOS 13 或更低）：在 iOS 13 环境下自动降级到 sync，`mode` 字段返回 `"sync"`
- ✅ 定位失败：返回 `target_not_found`
- ✅ 目标非 WKWebView：返回 `invalid_data`
- ✅ 陈旧校验：带 `viewSnapshotID` 且陈旧，返回 `stale_locator`

**说明**：iOS 13 或更低版本的降级测试需要额外的模拟器或真机环境。

### 7.3 端到端测试（SPMExample）

**文件**：`Examples/SPMExample/SPMExample/WebViewTestViewController.swift`

**场景**：
- 加载包含 JSBridge 的 H5 页面
- 用 `ui.webView.eval` 触发 JSBridge 调用
- 验证 Native 页面跳转

---

## 8. 文档与指导

### 8.1 Skill 文档

**新建**：`.claude/skills/ios-ui-webview/SKILL.md`

**内容**：
1. **何时使用 `ui.webView.eval`**（轻交互场景）
2. **何时不应该使用**（复杂 Web 自动化 → Puppeteer/CDP）
3. **同步 vs 异步模式的选择**
4. **常见 JS 代码片段**：
   - 点击元素：`document.querySelector('#btn').click()`
   - 填充表单：`document.querySelector('#input').value = 'text'`
   - 触发 JSBridge：`window.bridge.goPay()`
   - 读取状态：`document.title`、`localStorage.getItem('key')`
5. **错误处理与调试**

### 8.2 能力缺口文档更新

**文件**：`docs/superpowers/specs/2026-07-16-capability-gap-analysis.md`

**更新**：
- §3.2.2 WebView 操作：从"不实现"改为"已设计"
- §4 实现优先级矩阵：WKWebView 状态更新为"设计完成"
- §7.2 短期规划：添加"实现 `ui.webView.eval` 命令（2-3 天）"

### 8.3 agent-command-protocol 文档更新

**文件**：`docs/uikit/agent-command-protocol.md`

**新增**：
- `ui.webView.eval` 的前置条件（需先 `ui.inspect` 定位 WKWebView）
- 调用时序示例（inspect → eval → navigation.back）
- 常见错误模式（超时、JS 语法错误）

---

## 9. 风险与限制

### 9.1 技术限制

1. **跨域限制**：
   - 遵循 WKWebView 的同源策略
   - 无法访问跨域 iframe 内容
   - **缓解**：文档明确说明限制

2. **iOS 版本降级**：
   - iOS 14 以下不支持异步模式
   - **缓解**：自动降级到同步模式，记录日志，`iosVersion` 字段供诊断

3. **结果序列化限制**：
   - 无法序列化 DOM 节点、Function、Symbol 等
   - **缓解**：返回 `null` + `resultType` 描述类型

4. **ui.inspect 不深入 WebView**：
   - `ui.inspect` 只能看到 WKWebView 容器，看不到内部 DOM
   - **缓解**：定位元素靠 JS 的 CSS selector，不在 inspect 能力表内

### 9.2 使用风险

1. **JS 注入风险**：
   - 用户提供的 `script` / `function` 直接执行
   - **缓解**：Debug-only 工具，只在开发/测试环境使用

2. **超时参数滥用**：
   - 用户设置过长的 `timeout` 可能阻塞测试
   - **缓解**：上限 30 秒，文档建议 5-10 秒

3. **与前端工具的边界模糊**：
   - 用户可能误用 `ui.webView.eval` 做复杂 Web 自动化
   - **缓解**：文档明确说明适用/不适用场景，提供前端工具的推荐

---

## 10. 实现计划

### 10.1 Phase 1：核心实现（2 天）

- [x] 设计文档（本文档）
- [ ] `UIWebViewEvalInput.swift`（~180 行）
- [ ] `UIWebViewEvalExecutor.swift`（~280 行）
- [ ] `UIWebViewEvalCommand.swift`（~50 行）
- [ ] 在 `UIKitCommandRegistrar` 中注册

### 10.2 Phase 2：测试（1 天）

- [ ] 单元测试：`UIWebViewEvalInputTests.swift`（macOS）
- [ ] 集成测试：`UIWebViewEvalTests.swift`（iOS framework）
- [ ] 端到端测试：`WebViewTestViewController.swift`（SPMExample）

### 10.3 Phase 3：文档（0.5 天）

- [ ] 新建 Skill：`.claude/skills/ios-ui-webview/SKILL.md`
- [ ] 更新能力缺口文档：`2026-07-16-capability-gap-analysis.md`
- [ ] 更新调用契约文档：`agent-command-protocol.md`
- [ ] 更新文件档案：`uikit-file-reference.md`

### 10.4 总计

**预计工作量**：2-3 天

---

## 11. 未来扩展

### 11.1 可选增强（不在首版）

1. **内置等待机制**：
   ```json
   {
     "script": "return document.querySelector('#loading') === null",
     "until": true,  // 内部轮询直到 script 返回 truthy
     "timeout": 10
   }
   ```

2. **多 WebView 支持**：
   - 当前只定位单个 WKWebView
   - 未来可支持 `all: true` 返回所有匹配的 WebView 数组

3. **Content World 选择**（iOS 14+）：
   - `callAsyncJavaScript` 支持指定 `WKContentWorld`
   - 可选 `contentWorld: "page" | "defaultClient"`

### 11.2 不计划支持

1. **DOM 查询 DSL**：
   - 不封装 `querySelector` / `waitForElement`
   - 理由：重复造轮子，Puppeteer 已有成熟实现

2. **网络拦截**：
   - 不提供请求修改、响应 mock
   - 理由：属于前端测试工具职责

3. **截图对比**：
   - 不支持 WebView 内容的视觉回归
   - 理由：`ui.screenshot` 已覆盖整个 App，Web 内容截图应在前端工具完成

---

## 12. 参考资源

### 12.1 相关文档

- `docs/uikit/reading-guide.md`：iOSExploreUIKit 实现模式
- `docs/uikit/agent-command-protocol.md`：命令调用契约
- `AGENTS.md`：项目规范与设计原则

### 12.2 相关命令

- `ui.inspect`：定位 WKWebView 容器
- `ui.tap`：点击按钮打开 WebView
- `ui.navigation.back`：关闭 WebView
- `ui.wait`：等待 WebView 加载完成

### 12.3 底层 API 文档

- [WKWebView.evaluateJavaScript(_:completionHandler:)](https://developer.apple.com/documentation/webkit/wkwebview/1415017-evaluatejavascript)
- [WKWebView.callAsyncJavaScript(_:arguments:in:contentWorld:)](https://developer.apple.com/documentation/webkit/wkwebview/3656441-callasyncjavascript)

---

**文档结束**
